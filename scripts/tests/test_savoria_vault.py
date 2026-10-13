import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('vault', Path(__file__).parents[1] / 'savoria_vault.py')
vault = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vault)

NOTE = '---\ntype: receita\nsummary: Original\n---\n## Ingredientes\n### Massa\n- 100g farinha\n- Sal a gosto\n## Preparo\n1. Misture.\n2. Asse.\n## Dicas\nGuarde na geladeira.\n'

class VaultImportTests(unittest.TestCase):
    def test_explicit_quantities_no_estimates(self):
        self.assertEqual(vault.parse_ingredient('100g arroz cozido'), ('arroz cozido',100.,'g'))
        self.assertEqual(vault.parse_ingredient('🧅 ½ cebola picada'), ('cebola picada',.5,''))
        self.assertEqual(vault.parse_ingredient('1/2 cenoura'), ('cenoura',.5,''))
        self.assertEqual(vault.parse_ingredient('Sal a gosto'), ('Sal a gosto',None,''))
        self.assertEqual(vault.parse_ingredient('1 ovo'), ('ovo',1.,''))

    def test_structure_keeps_sections_order_and_literal_unknowns(self):
        result, _, _ = vault.parse_note(NOTE, 'Receita.md')
        self.assertEqual(len(result['ingredients']),2)
        self.assertEqual(result['ingredients'][0]['sectionID'],result['sections'][0]['id'])
        self.assertEqual([s['instruction'] for s in result['steps']],['Misture.','Asse.'])
        self.assertIsNone(result['ingredients'][1]['quantity'])
        self.assertEqual(result,vault.parse_note(NOTE,'Receita.md')[0])

    def test_legacy_note_and_source_capture_additive_noop_reimport(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); folder=root/'Alimentação/Receitas/Fáceis';folder.mkdir(parents=True)
            p=folder/'Bolo.md';p.write_text(NOTE)
            (folder/'Contexto.md').write_text('Not a recipe')
            m,c=vault.manifest_from_vault(root,{'recipes':[]})
            self.assertEqual(m['mode'],'upsert');self.assertEqual(m['items'],[])
            self.assertEqual(len(m['recipes']),1);self.assertEqual(c['notes'][0]['text'],NOTE)
            previous=m['recipes'][0];previous['isFavorite']=True
            again,_=vault.manifest_from_vault(root,{'recipes':[previous]})
            self.assertEqual(again['recipes'],[])
            p.write_text(NOTE+'\nNovo detalhe')
            with self.assertRaisesRegex(ValueError,'Source changed'):
                vault.manifest_from_vault(root,{'recipes':[previous]})

    def test_missing_or_ambiguous_cover_stops_instead_of_skipping(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);folder=root/'Alimentação/Receitas';folder.mkdir(parents=True)
            note=folder/'A.md';note.write_text(NOTE.replace('type: receita','type: receita\nbanner: absent.png'))
            with self.assertRaisesRegex(ValueError,'missing or ambiguous'):
                vault.manifest_from_vault(root,{'recipes':[]})
            with self.assertRaises(ValueError):
                vault.resolve_asset(root,note,'../../../../etc/passwd')

    def test_empty_recipe_is_not_silently_ignored(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);folder=root/'Alimentação/Receitas';folder.mkdir(parents=True)
            (folder/'A.md').write_text('## Nada\n')
            with self.assertRaisesRegex(ValueError,'lacks recipe structure'):
                vault.manifest_from_vault(root,{'recipes':[]})

if __name__ == '__main__': unittest.main()
