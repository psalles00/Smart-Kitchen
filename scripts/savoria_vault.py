"""Deterministic additive import of local Obsidian recipes. No AI/network/database writes."""
import hashlib
from pathlib import Path
import re
import unicodedata
import urllib.parse
import uuid

NAMESPACE = uuid.UUID('a8e15e40-f015-4a1b-915e-271821390ae0')


def identity(source, kind, index=0):
    return str(uuid.uuid5(NAMESPACE, f'{source}:{kind}:{index}'))


def plain(text):
    return re.sub(r'[*`_]', '', text).strip()


def parse_ingredient(value):
    # Read only explicitly written leading amounts. Keep ambiguous descriptions intact.
    cleaned = ''.join(c for c in value if not (unicodedata.category(c) == 'So' and 0x2300 <= ord(c) <= 0x1FAFF) and c not in '\ufe0f\ufe0e\u200d').strip()
    if ':' in cleaned:
        name, amount = cleaned.split(':', 1)
        if re.match(r'^\s*(?:\d|[½¼¾])', amount):
            cleaned = amount.strip() + ' ' + name.strip()
    amount = re.match(r'^(\d+\s*/\s*\d+|\d+(?:[.,]\d+)?|[½¼¾])\s*(.*)$', cleaned)
    if not amount:
        return cleaned, None, ''
    raw, rest = amount.groups()
    if not rest or rest.startswith('='):
        return cleaned, None, ''
    if raw in {'½', '¼', '¾'}:
        quantity = {'½': .5, '¼': .25, '¾': .75}[raw]
    elif '/' in raw:
        a, b = raw.split('/')
        if float(b) == 0:
            return cleaned, None, ''
        quantity = float(a) / float(b)
    else:
        quantity = float(raw.replace(',', '.'))
    unit = re.match(r'^(kg|g|ml|mL|l|L|xícaras?|colheres? de sopa|colheres? de chá|col de sopa|dentes?|latas?|unidades?|ovos?)(?:\b|(?=\s))\s*(.*)$', rest)
    # Ovo is the ingredient, not a unit.
    if unit and not unit[1].startswith('ovo'):
        name = re.sub(r'^de\s+', '', unit[2]).strip()
        if name:
            return name, quantity, unit[1]
    return rest.strip(), quantity, ''


def heading(text):
    return ''.join(c for c in unicodedata.normalize('NFKD', plain(text).casefold()) if c.isalnum())


def resolve_asset(vault, note, reference):
    reference = reference.strip().strip('"\'').split('|')[0]
    for candidate in [note.parent / reference, vault / reference]:
        path = candidate.resolve()
        if path.is_relative_to(vault.resolve()) and path.is_file():
            return path
    matches = [p for p in (vault / 'Alimentação/Receitas').rglob(Path(reference).name) if p.is_file()]
    if len(matches) == 1:
        return matches[0].resolve()
    raise ValueError(f'Asset missing or ambiguous for {note.name}: {reference}')


def parse_note(text, source):
    front = ''
    body = text
    if text.startswith('---\n'):
        parts = text.split('---', 2)
        if len(parts) == 3:
            front, body = parts[1], parts[2]
    ingredients, sections, steps = [], [], []
    mode = None
    section_id = None
    # Preserve every original line in descriptionText; only explicit ingredient/preparation
    # sections become structured entries. Never estimate quantities, times or nutrients.
    for raw in body.splitlines():
        line = raw.strip()
        match = re.match(r'^(#{1,6})\s+(.+)', line)
        if match:
            level, title = len(match[1]), plain(match[2])
            key = heading(title)
            if level <= 2:
                mode = 'ingredients' if key.startswith('ingrediente') else 'steps' if key in ('preparo', 'mododepreparo', 'preparacao') else None
                section_id = None
            elif mode == 'ingredients':
                section_id = identity(source, 'section', len(sections))
                sections.append({'id': section_id, 'title': title, 'subtitle': '', 'sortOrder': len(sections)})
            continue
        if not line or line.startswith(('>', '![[', '<!--')):
            continue
        if mode == 'ingredients':
            value = plain(re.sub(r'^[-*+]\s+', '', line))
            if not value:
                continue
            name, quantity, unit = parse_ingredient(value)
            ingredients.append({'id': identity(source, 'ingredient', len(ingredients)), 'name': name,
                                'quantity': quantity, 'unit': unit, 'preparationState': '',
                                'sortOrder': len(ingredients), 'sectionID': section_id})
        elif mode == 'steps':
            value = plain(re.sub(r'^(?:\d+[.)]|[-*+])\s+', '', line))
            if value:
                steps.append({'id': identity(source, 'step', len(steps)), 'order': len(steps) + 1, 'instruction': value, 'durationMinutes': None})
    banner = re.search(r'^banner:\s*(.+)$', front, re.M)
    summary = re.search(r'^summary:\s*(.+)$', front, re.M)
    return {'ingredients': ingredients, 'sections': sections, 'steps': steps}, banner[1] if banner else None, summary[1] if summary else None


def recipe_description(text, url, digest, summary=None):
    intro = (summary or '').strip().strip('"\'')
    if not intro:
        quotes = [line[1:].strip() for line in text.splitlines() if line.startswith('> ') and not line.startswith('> [')]
        intro = next((plain(line) for line in quotes if line), 'Receita da sua biblioteca pessoal.')
    return f'{intro}\n\n{text}\n\nOrigem: {url}\nVault SHA256: {digest}'


def manifest_from_vault(vault, snapshot):
    vault = vault.resolve()
    root = vault / 'Alimentação/Receitas'
    if not root.is_dir():
        raise ValueError('Recipe folder unavailable; no fallback vault')
    recipes, captured, warnings = [], [], []
    existing = snapshot.get('recipes', [])
    for note in sorted(root.rglob('*.md')):
        if note.name in ('Contexto.md', 'AGENTS.md') or 'anexos' in note.relative_to(root).parts:
            continue
        text = note.read_text(encoding='utf-8')
        source = note.relative_to(vault).as_posix()
        structure, banner, summary = parse_note(text, source)
        if not structure['ingredients'] and not structure['steps']:
            raise ValueError(f'Note lacks recipe structure; review instead of silently skipping: {source}')
        url = 'obsidian://open?vault=' + urllib.parse.quote(vault.name) + '&file=' + urllib.parse.quote(source, safe='')
        matches = [r for r in existing if r.get('externalURLString') == url]
        if len(matches) > 1:
            raise ValueError(f'Ambiguous existing recipe source: {source}')
        target = matches[0]['id'] if matches else identity(source, 'recipe')
        # Already-imported identical source is a no-op, retaining user edits/child IDs.
        digest = hashlib.sha256(text.encode()).hexdigest()
        if matches and f'Vault SHA256: {digest}' in matches[0].get('descriptionText', ''):
            captured.append({'path': source, 'sha256': digest, 'recipeID': target, 'unchanged': True, 'text': text})
            continue
        if matches:
            raise ValueError(f'Source changed after import: {source}. Review existing child IDs and merge explicitly.')
        entry = {'id': target, 'name': note.stem,
                 'descriptionText': recipe_description(text, url, digest, summary),
                 'externalURLString': url, 'category': note.relative_to(root).parts[0],
                 'tags': ['PS Vault'], **structure}
        if banner:
            cover = resolve_asset(vault, note, banner)
            if cover.stat().st_size > 20 * 1024 * 1024:
                raise ValueError(f'Cover exceeds 20MiB: {cover}')
            entry['coverPath'] = str(cover)
            entry['coverSHA256'] = hashlib.sha256(cover.read_bytes()).hexdigest()
        else:
            warnings.append(f'Sem capa declarada: {source}')
        recipes.append(entry)
        captured.append({'path': source, 'sha256': digest, 'recipeID': target, 'text': text,
                         'coverPath': entry.get('coverPath'), 'coverSHA256': entry.get('coverSHA256')})
    if not captured:
        raise ValueError('No recipe notes found')
    return {'mode': 'upsert', 'source': 'PS Vault: Alimentação/Receitas, pedido direto de Pedro',
            'items': [], 'categories': [], 'showReserve': False, 'recipes': recipes}, {
                'vault': str(vault), 'notes': captured, 'warnings': warnings,
                'mediaPolicy': 'Local covers embedded; original Markdown/embeds preserved, videos kept in source Vault'}
