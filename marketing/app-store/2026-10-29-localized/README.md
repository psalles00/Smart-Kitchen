# Savoria — App Store em 10 idiomas

90 imagens finais: nove por idioma, 1320 × 2868, PNG RGB/sRGB sem alpha.
Abra `index.html` para navegar, `overview.png` para comparar as capas e
`<idioma>/preview.png` para revisar as nove peças. Os arquivos para envio
estão em `<idioma>/png/01.png` a `09.png`.

## Idiomas e telas internas

Mesma seleção do material multilíngue do Rotina de 02/10/2026:

| Publicidade | Código | Interface dentro dos mockups |
| --- | --- | --- |
| Português brasileiro | pt-BR | Português, conjunto aprovado reutilizado |
| Inglês | en-US | Inglês |
| Espanhol | es-ES | Espanhol |
| Francês | fr-FR | Francês |
| Alemão | de-DE | Alemão |
| Italiano | it | Italiano |
| Japonês | ja | Japonês |
| Coreano | ko | Inglês |
| Chinês simplificado | zh-Hans | Inglês |
| Árabe | ar-SA | Inglês |

A escolha da interface segue `AppLanguage` em `Shared/Localization/AppLocalization.swift`,
com sete idiomas. Para ko/zh-Hans/ar-SA, tanto as capturas nativas quanto as
interfaces ilustrativas usam inglês. A publicidade externa usa o idioma de destino.
Árabe: texto promocional da direita para a esquerda; interface inglesa preservada
na direção original. Japonês, coreano e chinês usam fontes de sistema compatíveis.

## Fidelidade visual

A fonte de composição é `../2026-10-29-pt-BR/index.html`. O gerador injeta somente
os textos, as capturas correspondentes e ajustes de tipografia/encaixe.
O panorama, a divisão na segunda peça e a grade central permanecem compartilhados.
Não há uma cópia independente do fundo por idioma. O português foi copiado dos
PNGs aprovados, sem uma renderização extra.

`locales.cjs` contém os nove conjuntos de textos promocionais e seis dicionários
para as interfaces ilustrativas. `design.cjs` aplica as traduções e ajusta o
texto à composição; números usam a formatação da interface correspondente.
Na peça árabe 02, o texto foi afastado da curva clara para manter o contraste.

## Capturas reais e demonstrações

`captures/<idioma>/` contém capturas reais das views de produção em Release,
no iPhone 17 Pro / Simulator. Apenas a fixture foi traduzida; dados pessoais não
foram usados. A fixture usa ModelContainer em memória, sem CloudKit, compras
ou inferências. O teste preserva 13 itens, cinco receitas e duas mensagens.
As categorias demonstrativas têm ordem explícita para preservar os dois cartões
completos no recorte da galeria em todos os idiomas.

Os seis idiomas novos têm sete capturas cada: início, despensa, mercado, galeria,
receita, ingredientes após rolagem e nutrição. A galeria foi recapturada de forma
isolada após a revisão visual. `capture-manifest.json` registra hashes e resultados
XCTest; `native-text-checks.json` registra a conferência de textos.

As peças 02 (média), 04 (assistente) e 07 (foto/texto/voz) mantêm os exemplos
ilustrativos autorizados na versão original; não são evidência de inferências
reais. Os exemplos 04/07 são identificados como simplificados nas próprias artes.
Imagens de alimentos, ícones, moldura e fontes comuns vêm dos recursos já aprovados.
A foto pode conter texto impresso originalmente no cenário: isso não é um rótulo
traduzível da interface.

Os recortes de ingredientes usam as posições reais do título e do último item,
lidas com Vision, para acomodar textos longos. Recortes, coordenadas e hashes estão
em `crop-sources.json`. O OCR é local, serial e reutiliza resultados não alterados.
Capturas em inglês são compartilhadas pelos três idiomas sem suporte, sem duplicação.

## Correção encontrada durante a produção

As capturas revelaram que “Todos”, o título dos grupos e duas formas de contagem de ingredientes eram
Strings exibidas sem consulta ao catálogo. Corrigidos no código compartilhado:
`RecipesView`, `RecipeCardView`, `RecipeCompatibility` e `Localizable.xcstrings`.
Os grupos usam o resolvedor de nomes já existente, preservando nomes personalizados.
Os formatos têm tradução para os sete idiomas, incluindo a ordem dos números no japonês.
A documentação da Apple explica a diferença entre uma String e uma chave localizada:
[Preparar views para localização](https://developer.apple.com/documentation/swiftui/preparing-views-for-localization).

As capturas finais passaram no XCTest. O app macOS também compilou e foi instalado
em `/Applications/Savoria.app`, com assinatura verificada. Os recursos compilados
contêm as sete traduções. Snapshot antes/depois idêntico: 111 itens, 64 receitas,
69 categorias; nenhuma alteração nos dados. Bundle, Team e ordem dos contêineres
iCloud foram preservados. A versão modificada foi aberta no iPhone 17 Pro virtual.
Não foi necessário usar o aparelho físico.

## Verificação e revisão

Cada idioma tem `checks.json`, `manifest.json`, `copy.md`, `preview.png` e `sequence.png`.
A verificação confere limites dos textos/painéis, fontes, proporção e idioma das
capturas, dimensões, cores, alpha e hashes. Foram revisadas as nove peças de cada
idioma em visão geral, com conferência ampliada dos casos longos e dos caracteres
não latinos. A revisão corrigiu contraste na peça árabe e a composição da galeria.

Não houve upload no App Store Connect, mudança de preços, nova assinatura de serviço
ou chamada paga de IA. Os arquivos desta pasta são os fontes e resultados da entrega,
não cópias de builds ou bancos pessoais. Resultados XCTest e snapshots privados
permanecem no diretório de evidências externo, fora do Git.

## Reprodução

Com o Release testável já compilado e o iPhone 17 Pro configurado:

```sh
python3 marketing/app-store/2026-10-29-localized/capture-locales.py
# Recaptura pontual da galeria, se necessária:
SAVORIA_CAPTURE_GALLERY_ONLY=1 python3 marketing/app-store/2026-10-29-localized/capture-locales.py
# Compilar recognize.swift no caminho definido em prepare.cjs, se ainda ausente.
node marketing/app-store/2026-10-29-localized/prepare.cjs
node marketing/app-store/2026-10-29-localized/render.cjs
node marketing/app-store/2026-10-29-localized/verify.cjs
```

O renderer usa Chrome headless local, uma página por vez, e fecha servidor e navegador.
Para alteração pontual: `LOCALES=fr-FR PAGES=8 node .../render.cjs`.
Cada compilação/teste deve preservar os dados e as identidades do app; nunca desinstalar.
