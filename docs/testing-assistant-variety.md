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
dois modelos permitidos. Para ideias, tenta Gemini e depois Qwen explicitamente;
para outros pedidos, o roteamento existente permanece em uma requisição. O
fallback compartilha 45 segundos, com até 30 para Gemini. Nada disso é
multiplicado pelo número de cartões.
Abrir/reler cartões já serializados e manter o app ocioso não introduz chamadas.

O teto acumulado de testes foi ampliado por Pedro para **US$ 5 em 25/10/2026**.
O operador temporário reserva o custo antes de cada envio; tentativas antigas sem
reconciliação continuam reservadas. O limite operacional de 30 invocações desta
investigação é adicional ao teto financeiro, nunca autorização para ultrapassá-lo.
Bloqueia endpoints não previstos e requisições acima de 64 KiB; não é um limite
financeiro do produto em produção. Não houve plano, recarga ou assinatura nova.

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
1.000 chats + 1.000–2.000 buscas web no caso normal; com correção em todos,
até 2.000 chats + 2.000 buscas. Com 6 mil tokens de entrada e 2,5 mil de saída,
o chat primário custa cerca de US$ 0,0064/chamada; o Gemini cerca de US$ 0,00525.
Somado à reserva web de US$ 0,019 por busca, isso representa aproximadamente
US$ 25,40–44,40/1.000 pedidos com um chat primário, ou US$ 24,25–43,25 com
um Gemini bem-sucedido, além do plano existente, egress e eventuais tentativas
anteriores/fallback. O máximo de 4.096 tokens inclui raciocínio do Gemini; o
perfil de ideias usa esforço baixo. Uma falha pode consumir tokens mesmo sem
resposta aproveitável e não é tratada como custo zero.

Não é orçamento total da organização: consumo compartilhado, saldo, quotas
efetivas e histórico não foram auditados. O dashboard KitchenApp mostrava plano
Free, banco 29/500 MB, egress arredondado 0/5 GB e logs 0,01/1 GB; isso não
comprova folga em todas as quotas. Créditos, bloqueios e excedentes dependem do
plano; alertas não são tetos. Não há novo polling, Realtime, banco, storage,
backup contratado ou processo de monitoramento permanente por esta correção.

## Evidências de 25/10/2026

- **73 testes fechados passaram na versão final**, iPhone 17 Pro
  `EagleVault Validation`: restrições, despensa completa/atualizada, ingredientes
  indisponíveis, expansão, categorias, redistribuição e conversas antigas.
- iOS Debug, iOS Release físico e macOS Debug compilaram. Team, stores e
  capabilities permaneceram iguais. A cópia do Mac foi assinada, instalada em
  `/Applications/Savoria.app` e aberta. O Simulator foi atualizado e aberto;
  o iPhone 12 Pro recebeu a instalação final, sem abertura para testes rotineiros.
- Os E2Es iniciais com Qwen retornaram 11/12 cartões, mas falharam na variedade:
  muitas coberturas de pão, classificação artificial e café com Gatorade. A
  investigação posterior também detectou respostas sem categoria e um número
  no lugar de JSON. Esses resultados não foram aprovados só pela contagem.
- A tentativa explícita do Gemini isolou um erro HTTP 400 no formato estruturado.
  A comparação conservando o pedido e usando JSON simples resolveu o bloqueio:
  Gemini retornou **10 ideias**, nas três seções (4/4/2), em cerca de seis segundos,
  usando os ingredientes reais. Revisão independente aprovou variedade e estoque,
  registrando limitações menores (banana com açúcar e algum parentesco entre ovos).
- No fallback Gemini, o modo JSON garante sintaxe; a mesma validação local continua
  conferindo categorias, despensa, tempo, porções e restrições antes de exibir.
  OpenAI conserva o schema original; Qwen conserva o schema equivalente com as
  referências de ingredientes expandidas. O exemplo no prompt agora inclui a
  categoria quando ela é obrigatória.
- **22 testes do gateway** passam com fetch/segredos injetados e nenhuma chamada
  externa. Incluem modelos explícitos limitados, formatos, ausência de vazamento
  e erros. O limite total de 45 s do fallback foi revisado em código; não foi
  medido com uma espera artificial de 45 s.
- CLI oficial 2.122.0 conectado à conta proprietária e ao projeto
  `yfcmvdijvgeaihvwyssb`. Somente os seis tokens antigos expressamente autorizados
  foram revogados; `CLI Visual Studio Code` e os demais foram preservados. Deploy
  e download/readback usam `--use-api`, sem Docker e com JWT ativo.
- Snapshots completos antes/depois permaneceram idênticos: 49 itens de despensa,
  43 em Para depois, cinco no mercado, nove utensílios, 64 receitas, incluindo
  identidades, notas e hashes de mídias. Só foram criadas conversas de validação.
- Não há nova mensagem de interface: títulos e traduções continuam no catálogo
  compartilhado; a geração respeita o idioma escolhido.

O perfil final com raciocínio baixo passou no E2E independente: **12 ideias,
4 por seção**, incluindo panqueca de banana, crepe de queijo, mingau e ovos com
linguiça. Ainda há algum parentesco entre opções com pão/ovos; diversidade de IA
não é uma garantia determinística para toda consulta. A abertura de **Panqueca
de Banana** mostrou 15 minutos, duas porções, seis ingredientes existentes e
quatro passos coerentes. Houve uma correção automática delimitada: o primeiro
preparo usava gordura não declarada na lista; o segundo passou a listar a
Margarina da despensa. Nenhuma receita foi salva.

Na consulta final houve **um chat e duas buscas**, sem correção de ideias;
19.166 bytes no chat, 1.314/1.117 bytes nas buscas. O chat levou cerca de dez
segundos incluindo gateway/fallback, com 5.059 tokens de entrada, 2.786 de saída
(dos quais 1.527 de raciocínio), custo reportado US$ 0,00544375. Cada busca
reportou US$ 0,013. A expansão usou dois chats (18.762/21.556 bytes), custos
reportados US$ 0,000412555 e US$ 0,000461175. Não houve chamada por cartão.
Depois das ações, **140 segundos observados sem nova invocação do gateway**;
isso não é uma auditoria de toda a organização ou de todo o tráfego CloudKit.

A investigação inteira usou 29 invocações classificadas, custo reportado de
respostas US$ 0,221006015 e reserva conservadora desta tarefa US$ 0,677422415.
O teto conservador acumulado ficou em **US$ 4,46498087 de US$ 5**. Reservas de
tentativas anteriores/falhas não foram descartadas nem declaradas custo zero.
O operador temporário será desanexado ao encerrar; não é componente do produto.

O modo debug foi restaurado ao estado anterior: App Store, contadores reais,
sem Premium simulado. Snapshot completo final continuou exatamente igual ao
inicial, revisão `9260c35fe134792ba2d5176824ef515dbd5d2ffca31a1b5619120d59a48a8b88`.
O gateway final foi publicado pelo CLI e baixado novamente para comparação exata;
SHA-256 `5997893632858b3ddae5a3e873c3c5f5e645a7a236528c73b4cc3abb1de22c4a`, JWT ativo.
Evidências mínimas e recuperação do fonte anterior ficam em
`/Volumes/PS-Externo/Coding/Builds/Savoria-Variety-20261025`; caches de instalação
CLI e downloads intermediários próprios são descartados ao concluir.

Referências de compatibilidade:
[OpenRouter reasoning](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens),
[Google structured output](https://ai.google.dev/gemini-api/docs/structured-output),
[Google thinking](https://ai.google.dev/gemini-api/docs/generate-content/thinking).

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
