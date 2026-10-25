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

Pedidos abertos, como **“o que fazer no cafe da manha”**, agora orientam o modelo
a explorar aproximadamente 9–12 ideias distintas quando a despensa comporta
essa variedade, com cerca de quatro por seção. Isso é uma meta contextual, não
uma obrigação de inventar ingredientes ou pratos para completar uma quantidade.
Um número menor pedido explicitamente, uma dúvida de preparo ou uma despensa
limitada continuam podendo gerar poucas ideias ou somente uma explicação.
A introdução deve ser breve, deixando a variedade nos cartões.

A seleção reserva espaço entre as três seções e redistribui os lugares restantes.
Antes, uma resposta com dez ideias rápidas, uma única e uma de aproveitamento
exibia apenas seis cartões. Agora, as doze opções válidas podem aparecer; a
categoria vazia não impõe um teto artificial às demais. Os filtros de ingredientes,
tempo, porções, refeição e exclusão de títulos já mostrados continuam aplicados.

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

## Consumo da correção de 25/10/2026

Não há serviço novo, migração ou mudança de plano. A geração mantém uma chamada
normal ao gateway e, somente quando há ideias inválidas, uma correção de conteúdo;
resposta válida curta não dispara novas chamadas para preencher uma meta. Cada
resposta mantém o máximo de 4.096 tokens. A busca web existente usa até duas
consultas Auto de seis resultados (texto até 6.000 caracteres por página e resumo).
Cada gateway de chat tenta OpenAI uma vez e, em falha elegível, OpenRouter com
dois modelos permitidos. Nada disso é multiplicado pelo número de cartões.
Abrir/reler cartões já serializados e manter o app ocioso não introduz chamadas.

Orçamento estimado para as duas rodadas: até oito invocações classificadas, com
reserva durável anterior ao envio, mantendo o teto acumulado autorizado de US$ 4.
O saldo conservador anterior era US$ 0,212441545; tentativas antigas não
reconciliadas continuam reservadas. O operador bloqueia endpoints não previstos
e requisições acima de 64 KiB; não é um limite financeiro do produto em produção.

Referências oficiais consultadas em 25/10/2026, USD, sem câmbio/impostos:

| Componente existente | Cobrança e limite relevante |
| --- | --- |
| [GPT-4.1 mini](https://developers.openai.com/api/docs/models/gpt-4.1-mini) | US$ 0,40/1,60 por milhão de tokens de entrada/saída; rate limits dependem da conta. |
| [Qwen Flash](https://openrouter.ai/qwen/qwen3.5-flash-02-23) / [Gemini Flash Lite](https://openrouter.ai/google/gemini-3.1-flash-lite) | US$ 0,065/0,26 e US$ 0,25/1,50 por milhão de tokens; disponibilidade e limites dependem do provedor e saldo. Taxas de compra de créditos são separadas da inferência. |
| [Exa](https://exa.ai/pricing) | Auto até dez resultados: US$ 0,007/consulta; conteúdos/resumos têm cobrança por página. Reserva conservadora de US$ 0,019 por consulta deste fluxo. Free anuncia US$ 10/mês, 10 QPS; saldo/plano da conta não foi confirmado. |
| [Supabase Edge](https://supabase.com/docs/guides/functions/pricing) | Free: 500 mil invocações/mês; Pro: 2 milhões, depois US$ 2/milhão. Franquia compartilhada com o restante da organização. |
| [Supabase plano/egress](https://supabase.com/pricing) | Free: US$ 0, 5 GB egress e 500 MB banco; Pro desde US$ 25/mês, 250 GB egress, depois US$ 0,09/GB. Configuração de banco, storage, backups, Realtime e logs não é alterada por este ajuste. |
| Dados locais/iCloud e recursos do Mac | Mesmos stores e sincronização; sem novo armazenamento remoto contratado, polling ou processo permanente. Compilações reutilizam caches existentes. |

Como cenário proporcional (projeção, não medição), 1.000 pedidos em um ciclo usam
1.000 chats + 1.000 buscas web no caso normal; no caso de correção e segunda
busca em todos os pedidos, até 2.000 + 2.000 invocações. Com 6 mil tokens de
entrada e 2,5 mil de saída, o chat primário custa cerca de US$ 0,0064 por chamada;
somado à reserva web, cerca de US$ 25,40/1.000 pedidos normais, além do plano
existente, egress e eventuais tentativas de fallback. Isso não é orçamento total
da organização: consumo compartilhado, saldo, quotas efetivas, logs e histórico
não foram auditados nesta correção. Créditos, bloqueios e excedentes dependem
do plano; alertas não são tetos. Nenhum plano ou recarga foi ativado.

## Evidências de 25/10/2026 — validação ainda incompleta

- 73 testes fechados passaram, novamente na versão final, no iPhone 17 Pro
  `EagleVault Validation`: restrições, despensa completa/atualizada, ingredientes
  indisponíveis, expansão, categorias, redistribuição e conversas antigas.
- iOS Debug, iOS Release físico e macOS Debug compilaram. Team, stores e
  capabilities permaneceram iguais. A cópia do Mac foi assinada, instalada em
  `/Applications/Savoria.app` e aberta.
- Dois E2Es independentes no Mac instalado, em conversas novas, enviaram a
  pergunta exata com a despensa real. Retornaram 11 e depois 12 cartões nas três
  seções. **Ambos falharam na qualidade**: muitas coberturas de pão, classificação
  artificial como “únicas” e, no segundo, café com Gatorade no conteúdo gerado.
  O teste não aprovou variedade apenas por contar cartões.
- A segunda rodada usou um chat (sem correção) e duas buscas web; a primeira
  usou dois chats (uma correção) e duas buscas. Não houve chamada por cartão.
  Os chats capturados tinham 18.187/22.606/19.141 bytes de entrada; buscas,
  aproximadamente 1,1–1,3 KiB. Respostas capturadas usaram Qwen. A correção
  mantém o teto de tokens e a seleção é toda local.
- O registro conservador acumulado chegou a **US$ 3,9861621**, dentro dos US$ 4
  autorizados. Há reservas antigas e uma primeira resposta desta rodada sem
  reconciliação; não são declaradas custo zero. Novas inferências dependem de
  ampliação explícita do teto. O monitor temporário foi desligado após os testes.
- Snapshots completos antes/depois ficaram idênticos: 49 itens de despensa,
  43 em Para depois, cinco no mercado, nove utensílios, 64 receitas, incluindo
  identidades, notas e hashes de mídias. Só foram criadas conversas de validação.
- Não há nova mensagem de interface: os títulos de seção e suas traduções
  continuam no catálogo compartilhado; as instruções de geração respeitam o
  idioma escolhido.

Próxima etapa: avaliar encaminhamento do fallback de receitas para o Gemini já
permitido, com o mesmo número de chamadas. Em 6 mil tokens de entrada e 2,5 mil
de saída, o custo de inferência estimado é US$ 0,00525, contra US$ 0,00104 do
Qwen, além dos demais componentes acima. A troca ainda não foi publicada nem
validada; acesso proprietário ao projeto Supabase e orçamento são bloqueios
reais. O aumento de quantidade está implementado, mas o pedido completo **não
está concluído** enquanto o E2E de qualidade não passar.

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
