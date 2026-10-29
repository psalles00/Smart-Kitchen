# Savoria — imagens da App Store em português brasileiro

Nove peças em `png/01.png` a `png/09.png`, na ordem de apresentação.
Formato: 1320 × 2868 pixels, PNG RGB sem transparência.
`preview.png` mostra o conjunto em três linhas; `sequence.png` mostra a sequência horizontal.

## Direção visual

Adaptação direta do conjunto pt-BR do Rotina de 02/10/2026: mesmas fontes
Bricolage Grotesque Bold e Inter, escala editorial, curvas claras,
telefones com capturas nativas, recortes ampliados e cartões em primeiro plano.
A iluminação azul do material de referência foi substituída por laranja
avermelhado de pôr do sol. A grade e os elementos decorativos usam alimentos.

Referência:
`/Volumes/PS-Externo/Coding/Rotina App/outputs/2026-10-02-appstore-localized/archived-delivery-folder/pt-BR`.

## Origem das telas

São capturas de views de produção do Savoria no iPhone 17 Pro / Simulator,
com configuração Release. Os dados de demonstração foram inseridos somente
em um ModelContainer em memória, sem CloudKit. As receitas da galeria vêm
do catálogo de onboarding do app; a refeição e a conversa ilustram a interface
com dados demonstrativos locais. A conversa não é prova de uma inferência
real e não gerou chamadas pagas. A foto exibida é a imagem já incluída no app.

Captura reproduzível em
`AdaptiveWorkspaceRenderingTests.testAppStoreDemonstrationCaptures`, no arquivo
`SmartKitchenTests/ReserveListTests.swift`. O teste passou e conferiu que a
renderização preservou os 13 itens, cinco receitas e duas mensagens da fixture.
Nenhum dado pessoal é incluído nas imagens.

`assets/screenshots/` contém as capturas originais e seus recortes. Cada recorte
tem origem, coordenadas e hash em `crop-sources.json`. Os painéis destacados utilizam pixels das capturas. A peça 06 usa uma simulação
minimalista de captura por foto e texto, autorizada por Pedro, com indicação
na arte; a foto vem do catálogo existente. A peça 02 é um infográfico ilustrativo
da média (não um print), com cinco dias somando 9.400 kcal: média de 1.880 kcal.
O telefone utiliza a mesma moldura da referência; todas as telas são escaladas
uniformemente. Fotos, nomes, números e controles permanecem nas capturas.

## Revisão crítica realizada

- Composição e equilíbrio: nove peças inspecionadas individualmente, além
  da sequência. As curvas da referência foram redistribuídas para a nova ordem editorial.
- Respiro e agrupamento: acrescentado espaço no recorte de ingredientes;
  tomate decorativo afastado da pergunta; removida sobra do cabeçalho da galeria.
- Hierarquia e tipografia: fontes carregadas, títulos sem corte e textos
  principais dentro da área de segurança. Quebras de linha revisadas em pt-BR.
- Fidelidade: descartadas capturas com skeletons e o modo incorreto de chat;
  usados apenas os estados completos. Ingredientes demonstrativos da galeria
  foram substituídos pelos modelos completos existentes no app.
- Destaques: ampliados com proporção uniforme, margem interna de 40–48 px e sombra suave;
  reposicionado o destaque de nutrição para preservar o calendário acima.
- Copy: diferenciais concretos, sem promessas clínicas ou de precisão absoluta.
  A peça de foto/texto/voz informa que as estimativas podem ser revistas antes de salvar.
- Exportação: nove PNGs, dimensões e ausência de alpha conferidas por script.

## Editar e renderizar

`index.html` contém a composição e a copy. `assets/sunset.glsl` contém o fundo.
As fontes e a moldura foram reaproveitadas dos materiais aprovados do Rotina;
os ícones e as fotos vêm dos recursos existentes do Savoria.

```sh
node marketing/app-store/2026-10-29-pt-BR/prepare-crops.cjs
node marketing/app-store/2026-10-29-pt-BR/render.cjs
```

O render usa as dependências locais compartilhadas e uma instância temporária
do Chrome em headless, encerrada ao terminar. Não inicia serviço permanente,
não acessa sessões pessoais e não publica no App Store Connect.

Para conferir manualmente: abrir `preview.png`, revisar `01.png` a `09.png`
em tamanho grande e comparar os destaques com as capturas em `assets/screenshots/`.
Esta entrega é a versão pt-BR; o material não foi enviado à loja.

## Revisão solicitada em 29/10 — segunda versão

Ordem: apresentação → média sem obrigação diária → Despensa/Mercado → ideias
com a despensa → preparo → foto/texto/voz → importação → nutrientes → integração.
A nona peça mantém o diferencial de integração sem comprimir as demais.

- Retirada a sombra sólida de 10 px sob os painéis claros; preservada somente
  sombra difusa. Os destaques de chat, ingredientes e galeria têm respiro interno.
- Galeria recortada após os dois cartões completos, sem receita pela metade.
- Despensa e Mercado recapturados nativamente com `showReserve = false`,
  sem alterar preferências nem dados do usuário. O teste de captura passou:
  uma execução, zero falhas; fixture com 13 itens, cinco receitas, duas mensagens.
- Diferencial da média conferido em `NutritionAveragesService.swift` e
  `SmartCountStepView.swift`: dias em branco não são incluídos como zero.
- A entrada por foto/texto é ilustrativa, não uma nova interface implementada;
  nenhum fornecedor, serviço pago ou recurso de produção foi alterado.

### Olhar crítico final

| Dimensão | Observação e correção | Resultado |
| --- | --- | --- |
| Equilíbrio | Um foco principal por peça; nova tela própria para média. | pass |
| Respiro | Margens internas ampliadas; removida extrusão preta. | pass |
| Ritmo e agrupamento | Fluxo Despensa/Mercado vem antes das sugestões; exemplos de entrada agrupados. | pass |
| Escala e leitura | Hierarquia editorial preservada; títulos e legendas sem corte nos exports. | pass |
| Consistência | Fontes compartilhadas; layouts editoriais variam conforme a referência. | pass |
| Tokens | Fontes e cores compartilhadas; tamanhos editoriais permanecem específicos por peça. | minor issue, escolha editorial preservada |

Não foi feito upload no App Store Connect. A verificação foi local; nenhuma
inferência paga ou dado pessoal foi usado.
