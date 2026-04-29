# Runbook — Adicionar um novo idioma ao Smart Kitchen

Este documento descreve, passo a passo, como traduzir o Smart Kitchen para um novo idioma. Foi escrito após a adição do **Espanhol (es)** em 2026 e cobre todos os pontos onde tradução é necessária.

> **Antes de começar:** sempre seguir as regras de proteção de dados em `.github/copilot-instructions.md` e `/memories/repo/xcodegen-entitlements-hazard.md`.

---

## 0. Premissas do projeto

- Idioma fonte: **pt-BR** (definido em `Shared/Localization/Localizable.xcstrings → sourceLanguage`).
- O catálogo de strings é compartilhado por 3 targets: `SmartKitchen`, `SmartKitchenShareExtension`, `SmartKitchenWidgets`.
- Idiomas suportados estão declarados em:
  1. `project.yml` → cada target → `info.plist.CFBundleLocalizations`.
  2. `Shared/Localization/AppLocalization.swift` → `enum AppLanguage` + mapa `itemMetadataResourceName`.
  3. `SmartKitchen.xcodeproj/project.pbxproj` → `knownRegions` (gerado por xcodegen — nunca editar à mão).
- A Info.plist tem 4 chaves de permissão (`NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`) cujos valores em pt-BR vêm do `project.yml`. Traduções adicionais ficam em `Shared/Localization/InfoPlist.xcstrings`.
- Itens (1.882 entradas) ficam em `icons/meta-{lang}.json` — o registry em runtime (`ItemLocalizationRegistry` em `SmartKitchen/Models/ItemEntry+Display.swift`) faz fallback EN → legado se faltar uma chave.

---

## 1. Declarar o idioma no código

Seja `<LANG>` o código BCP-47 (ex.: `es`, `fr`, `de`, `it`, `ja`).

1. **`project.yml`** — adicionar `<LANG>` em `info.plist.CFBundleLocalizations` dos três targets.
2. **`Shared/Localization/AppLocalization.swift`**:
   - Adicionar caso ao `enum AppLanguage`.
   - Adicionar mapeamento em `itemMetadataResourceName` apontando para `meta-<lang>`.
   - Garantir nome exibível em `displayName` (no idioma nativo).
3. Não rodar `xcodegen` ainda — fazer todas as alterações primeiro.

---

## 2. Traduzir UI (Localizable.xcstrings)

`Shared/Localization/Localizable.xcstrings` tem ~1.068 chaves. Para gerar todas em uma rodada:

1. Backup: `cp Shared/Localization/Localizable.xcstrings /tmp/Localizable.xcstrings.bak`
2. Extrair chaves: `jq -r '.strings | to_entries[] | "\(.key)\t\(.value.localizations.en.stringUnit.value // .key)"' Shared/Localization/Localizable.xcstrings > /tmp/all_pairs.tsv`
3. Escrever script Python que monta dicionário `pt-BR → <LANG>` e injeta `{ "stringUnit": { "state": "translated", "value": "<traducao>" } }` em `localizations.<LANG>` para cada chave (ver `/tmp/skl10n/translate.py` deste workspace como referência da última execução em ES).
4. Validar JSON: `jq empty Shared/Localization/Localizable.xcstrings`.
5. Conferir cobertura: `jq --arg L "<LANG>" '[.strings[] | select(.localizations[$L])] | length' Shared/Localization/Localizable.xcstrings` deve retornar 1068.

**Glossário (manter consistência ao longo do app):**
- Despensa, Mercado, Receita, Refeição, Modo de Preparo, Validade, Cancelar, Salvar, Adicionar, Excluir, Configurações, Almoço, Lanche, Jantar.

---

## 3. Traduzir InfoPlist.xcstrings

Apenas as 4 `NS*UsageDescription` precisam de tradução. `CFBundleDisplayName` e `CFBundleName` permanecem em pt-BR (nome do app não muda).

1. Editar `Shared/Localization/InfoPlist.xcstrings` adicionando `localizations.<LANG>` para cada chave.
2. Validar: `jq empty Shared/Localization/InfoPlist.xcstrings`.

> ⚠️ **NÃO** remova as chaves `NS*UsageDescription` do `project.yml`. Elas precisam continuar no `Info.plist` base como valor pt-BR fonte; o catálogo só fornece traduções por idioma.

---

## 4. Traduzir meta-{lang}.json (catálogo de itens)

1. Carregar `icons/meta-en.json` (1.882 itens).
2. Construir dicionários:
   - `CATEGORIES` — 20 categorias EN → `<LANG>`.
   - `TITLES` — EN → `<LANG>` para cada título único (1.838 únicos no momento).
3. Para cada item, copiar campos preservando schema (`title`, `file_name`, `added_on`, `slug`, `category`, `tags`, `volume`, etc.). Substituir `title` e `category`. Se faltar tradução, manter EN — runtime cai de volta em EN graciosamente.
4. Escrever em `icons/meta-<lang>.json` com indentação 2 e UTF-8.
5. Validar: `jq '.items | length' icons/meta-<lang>.json` deve retornar 1882.
6. Os PNGs em `icons/images-128/` são **language-agnostic** (id estável pelo `file_name`). Não precisam ser duplicados.

Referência da execução em ES: `/tmp/skl10n/translate_items.py`.

---

## 5. Refatorar Swift hardcoded (se ainda houver)

Buscar regressões com:

```bash
grep -nR --include="*.swift" -E '\b(Cancelar|Salvar|Despensa|Mercado|Receita|Excluir|Adicionar|Configurações)\b' SmartKitchen
```

Regras:
- `Button("Texto")`, `Text("Texto")`, `Label("Texto", ...)`, `.navigationTitle("Texto")` — Swift cria `LocalizedStringKey` automaticamente, **já é localizado** se a chave existir no catálogo.
- Funções que retornam `String` puro (ex.: `var typeLabel: String { ... }`) precisam usar `String(localized: "Texto")` explicitamente.
- Heurísticas NLP em `AssistantChatManager`, `InlineChatView`, `AssistantView`: adicionar sinônimos do novo idioma aos arrays de cues (ex.: `receita` → `receta` → `recipe`).

---

## 6. Regenerar projeto (xcodegen) — COM SALVAGUARDA

> ⚠️ **CRÍTICO**: `xcodegen generate` pode zerar `SmartKitchen.entitlements` (apaga iCloud, app groups). Sempre fazer backup e validar.

```bash
# 1. Snapshot
cp SmartKitchen/SmartKitchen.entitlements /tmp/entitlements-before.plist

# 2. Regerar
xcodegen generate

# 3. Validar
diff -q /tmp/entitlements-before.plist SmartKitchen/SmartKitchen.entitlements || cp /tmp/entitlements-before.plist SmartKitchen/SmartKitchen.entitlements

# 4. Conferir
git --no-pager diff -- SmartKitchen/SmartKitchen.entitlements SmartKitchenShareExtension/SmartKitchenShareExtension.entitlements
```

O diff deve estar **vazio**. Se houver qualquer alteração, restaurar do backup antes de continuar.

`project.pbxproj` deve ganhar:
- `meta-<lang>.json` registrado em PBXBuildFile/PBXFileReference (Resources/icons).
- `<LANG>` em `knownRegions`.

---

## 7. Build + verificação no simulador

```bash
FILES_DIR="/Users/pedrosalles/Documents/Coding/Smart Kitchen - Files"
BUILD_DIR="$FILES_DIR/build-copilot-<lang>-l10n"
mkdir -p "$BUILD_DIR"
xcodebuild -project SmartKitchen.xcodeproj -scheme SmartKitchen \
  -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath "$BUILD_DIR" -quiet build

APP="$BUILD_DIR/Build/Products/Release-iphonesimulator/SmartKitchen.app"

# Conferir bundles localizados
ls "$APP/<LANG>.lproj"  # deve listar Localizable.strings + InfoPlist.strings
ls "$APP" | grep meta-  # deve incluir meta-<lang>.json

# Lançar com locale forçado
xcrun simctl boot 'iPhone 17 Pro' 2>/dev/null; open -a Simulator
xcrun simctl install booted "$APP"
xcrun simctl launch booted com.pedrosalles.smartkitchen.sync \
  -AppleLanguages "(<LANG>)" -AppleLocale <lang_REGION>
```

Smoke test obrigatório:
1. Tela inicial em `<LANG>`.
2. Pantry/Despensa: nome dos itens vem do `meta-<lang>.json`.
3. Permissão de câmera: prompt em `<LANG>`.
4. Repetir com `pt-BR` e `en` para garantir não regressão.

---

## 8. Atualizar documentação e memórias

- Atualizar `/memories/repo/localization-foundation-multilang.md` com status do novo idioma.
- Confirmar README/changelog se aplicável.
- Não esquecer de garantir entitlements intactos (rodar `git diff -- SmartKitchen/SmartKitchen.entitlements` antes de qualquer commit).

---

## Status atual dos idiomas (snapshot do último build)

- ✅ **pt-BR** — fonte (100%).
- ✅ **en** — completo (UI + InfoPlist + meta-en.json).
- ✅ **es** — completo (UI + InfoPlist + meta-es.json, 1.882 itens).
- ⏸️ **fr, de, it, ja** — declarados em `AppLanguage` mas sem catálogo. Aguardando aplicação deste runbook.
