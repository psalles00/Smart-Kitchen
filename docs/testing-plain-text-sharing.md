# Compartilhar listas e receitas — 29/10/2026

- Listas: menu de filtro → Compartilhar lista atual. A prévia usa os IDs e a
  ordem do snapshot exibido, incluindo a busca/filtro atual. Uma leitura local
  por ação obtém valores atuais; não há nova Query, polling ou escrita.
- Receita: botão de compartilhar no painel do detalhe. Inclui descrição,
  porções exibidas, tempo, seções/ingredientes, preparo, fonte HTTP(S) e
  atribuição “Compartilhado com Savoria”. Alterar porções só escala o texto.
- A prévia permite compartilhar pelo menu nativo ou copiar, com confirmação
  visual. Nada é enviado automaticamente. Código e dez textos novos são
  compartilhados por iOS/macOS e traduzidos nos sete idiomas.
- `text-sharing-final-tests.xcresult`: quatro aprovados, zero falhas. Três
  testes de exportação cobrem ordem, quantidade/notas, seções, escala,
  ingredientes sem seção válida, fonte local excluída e ausência de mutação.
  Um teste renderiza a prévia e o acesso pelo detalhe no iPhone 17 Pro, com
  container em memória; screenshots inspecionados.
- Builds Debug iOS e Release macOS passaram. Mac instalado em
  `/Applications/Savoria.app`. Interface real: despensa completa → copiar
  confirmou “Texto copiado”; menu nativo abriu e foi fechado sem escolher
  destinatário. Busca “Arroz” → exportação continha somente Arroz. Receita
  Sushi de Preguiçoso → prévia com preparo e fonte aberta pelo botão do detalhe.
- Snapshot local antes/depois da instalação: 111 itens, 64 receitas e 69
  categorias, hash idêntico. Sem alteração de stores, schemas, Team ou capabilities.
- Custo incremental: nenhuma chamada remota, inferência ou cobrança nova por
  abrir/gerar/copiar a prévia; uma leitura local sob demanda para listas.
  Escolher um destino externo no menu nativo é uma ação posterior do usuário.

Evidências: `/Volumes/PS-Externo/Coding/Builds/Savoria-Nutrition-Final-20261028/`
(`text-sharing-*.png`, `text-sharing-final-preview/` e resultados acima).

## Teste manual

1. Filtre uma lista, abra Compartilhar lista atual e confira ordem, quantidades,
   notas e atribuição; copie ou abra o menu nativo sem enviar se estiver só testando.
2. Abra uma receita, ajuste porções e toque em compartilhar; confira que apenas
   o texto exportado foi escalado e que ingredientes/preparo/fonte estão completos.
3. Feche a prévia e confira que a lista/receita original permanece igual.
