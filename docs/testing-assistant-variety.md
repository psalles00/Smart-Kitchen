# Ideias variadas e disponibilidade de receitas

## Comportamento

O indicador de resposta usa `ProgressView` nativo compartilhado entre iOS e
macOS. A animação existe enquanto há uma resposta pendente; em segundo plano
o componente mostra reticências estáticas. Não há temporizador próprio no chat.

As novas respostas de ideias podem conter três seções:

- **Ideias Rápidas**: preparos simples e curtos.
- **Ideias únicas**: técnicas, combinações e cozinhas diferentes, respeitando o pedido.
- **Aproveite a despensa**: combinações com maior aproveitamento do estoque real.

A classificação vem na mesma resposta estruturada do modelo. Não se faz uma
chamada por seção. Se não houver uma opção viável para uma seção, ela não é
preenchida artificialmente. Conversas antigas sem categoria continuam exibindo
suas opções em Ideias Rápidas. Selecionar uma opção conserva o pedido original
e a mesma validação de ingredientes, tempo, porções e restrições alimentares.

Receitas salvas incluem opções parciais e até opções sem ingredientes disponíveis.
A ordem é pelo **número de ingredientes disponíveis**, seguido da proporção em
caso de empate e do nome. O cartão mostra disponíveis/total e quais ingredientes
faltam. Ingredientes repetidos não inflam o total. A disponibilidade considera
nomes completos normalizados, sem inferir estoque por substring ou imagem.
Um item com quantidade zero, somente no mercado ou em Para depois não conta
como estoque. Os cartões são carregados horizontalmente conforme aparecem.

Um pedido explícito para usar somente ingredientes da despensa continua sendo
restritivo; o filtro de ideias novas das configurações permanece preservado.
Consultar receitas salvas abre a biblioteca local e tem prioridade sobre o
histórico de registro de alimento ao ordenar a ação principal. Criar ou editar
receitas continua sendo uma intenção distinta.

## Proteção de dados

Não foram alterados modelos persistidos, schemas, containers, stores, flags de
sincronização, Team ou capabilities. O campo opcional de categoria pertence
somente ao JSON dos novos resultados de conversa. Os testes de geração e
restrições usam respostas controladas e stores isolados, sem enviar chamadas
pagas por teste.

## Conferências manuais

1. No assistente, peça **Mostre minhas receitas salvas** e envie. Confira a
   entrada na conversa e cartões em ordem decrescente de ingredientes disponíveis,
   incluindo receitas parciais com indicação do que falta.
2. Peça ideias para uma refeição. Confira o indicador animado durante a espera,
   as três seções quando houver opções viáveis e o conteúdo completo ao selecionar
   uma opção. Confira a retomada após sair e voltar ao app.
3. Repita com **Só com o que tenho**, restrição alimentar, tempo ou porções.
   Confirme que a flexibilidade de estoque não ignora essas restrições explícitas.
4. Abra uma conversa antiga e confira que suas ideias e receitas continuam visíveis.

## Referência Apple

- [ProgressView](https://developer.apple.com/documentation/swiftui/progressview)

## Resultado em 17/10/2026

- 89 testes finais aprovados: categorias, contrato estruturado do provedor,
  aproveitamento da despensa antes do limite de seção, ordenação das receitas,
  ingredientes faltantes, conversas antigas, restrições e encaminhamento da
  biblioteca nos sete idiomas mesmo com histórico de 200 registros de alimento.
- Renderização nativa com store em memória conferida: três seções e cartão de
  receita com 2/3 ingredientes disponíveis e indicação de queijo faltante.
- Biblioteca real do Mac conferida: receitas parciais aparecem com contadores
  5/10, 5/18, 5/26 e depois 4/6, conforme a ordem solicitada. A consulta é local.
- No iPhone 17 Pro no Simulator, a instalação final foi aberta e o botão Enviar
  encaminhou o pedido de receitas salvas corretamente; as três receitas locais
  apareceram mesmo com zero ingredientes correspondentes.
- A primeira conferência manual da busca geral abriu análise de alimento pelo
  encaminhamento antigo; ela foi cancelada sem salvar. A prioridade da biblioteca
  foi corrigida e retestada. Uma rodada também identificou a flexão alemã
  “gespeicherten Rezepte”; o caso foi corrigido antes dos 89 testes finais.
- Os dados originais do Simulator permaneceram iguais (IDs, campos e hashes),
  sem novo registro de alimento; somente as conversas das consultas de validação
  foram acrescentadas. Os dois stores passaram no `quick_check`.
- Os snapshots completos de 111 itens, 64 receitas e 69 categorias do Mac
  permaneceram idênticos, incluindo metadados e mídias. Configurações de store,
  Team e capabilities não foram alteradas.
- As sete novas mensagens possuem tradução em en/es/fr/de/it/ja e fonte pt-BR,
  no catálogo compartilhado. A geração automática foi validada com respostas
  controladas; não se apresenta esse resultado como avaliação da qualidade de
  respostas novas do provedor real.
