# Conversa e descoberta de receitas

## Validação de 15/10/2026: modo da despensa

A preferência de usar apenas a despensa agora acompanha as ideias rápidas e sua
expansão. Resultados serializados guardam a preferência usada na busca; mensagens
antigas ou com campo desconhecido continuam legíveis e usam o padrão restrito.
No modo livre, uma despensa vazia não impede sugestões. No modo restrito, o
ingrediente principal precisa corresponder à despensa, sem usar a existência de
um ícone como prova de disponibilidade. Sugestões relevantes alternam ingredientes
principais antes de repetir o mesmo ingrediente.

`RecipeIdeasPantryModeTests`, `RecipeIdeaRequestTests` e `AIServiceFallbackTests`:
30 testes passaram. Incluem sete idiomas no prompt/cabeçalho, restrição de leite,
prioridade do pedido original e reabertura de resultados legados.

`RecipeIdeasLiveProviderTests` é optativo. O teste nativo usa o cliente real e uma
reserva financeira durável preparada pelo operador, limitada a duas requisições;
a execução normal não faz chamadas pagas. O teste bloqueia fallback direto de
rede fora do backend controlado. Na execução de 15/10, os dois pedidos passaram
pelo backend e retornaram `qwen/qwen3.5-flash-02-23`. O custo informado pelo
provedor foi US$ 0,0001365; o registro conserva reservas maiores para tentativas
internas incertas. Isso não é recibo de cobrança nem prova do provedor primário.

A leitura humana encontrou sugestões triviais (tomate picado e cenoura cozida).
Portanto, o resultado acima comprova a correção dos modos, mas não encerra a
melhoria de qualidade, o fluxo da web ou a avaliação completa da conversa.

Compilações iOS e macOS aprovadas; instalação no Simulator e Mac realizada.
O snapshot do Mac permaneceu idêntico. A instalação física está pendente porque
o iPhone 12 Pro está indisponível no CoreDevice. Não houve desinstalação,
alteração de stores, iCloud, Team ou App Groups.

## Roteiro manual desta correção

1. Com ingredientes na despensa, ative a preferência de usar somente a despensa
   e peça ideias de jantar. Confira que os ingredientes principais existem nela.
2. Desative a preferência e faça um pedido que exija outros ingredientes.
   Abra uma ideia e confira que a receita completa mantém o modo livre.
3. Repita o modo livre com despensa vazia, em um destino de teste autorizado.
4. Reabra a conversa após sair do app. Abra o resultado anterior e confira que
   ele mantém a preferência da busca, mesmo após alterar a preferência atual.
5. Peça um jantar sem leite. Confira títulos, ingredientes e preparo da receita
   completa; rejeite queijo, manteiga e outros laticínios.
6. Confira diversidade, viabilidade, tempo e porções. Preparações triviais não
   devem ser aceitas como prova de boa qualidade.

Os roteiros da web, biblioteca, mídias, performance e produção continuam no
contrato E2E. Builds, mocks e este registro não substituem essas jornadas.

## Ingredientes e viabilidade: segunda etapa de 15/10/2026

As ideias agora pedem JSON Schema com ingredientes explícitos, tempo, porções e
condições de pré-cozimento. O app valida o retorno mesmo quando o provedor não
cumpre o contrato: rejeita ingredientes fora da despensa, preparações unitárias
usadas como preenchimento e dependência de itens cozidos que não estejam
identificados assim. Isso não comprova a viabilidade culinária de todo preparo.

Na chamada real com a nova estrutura, o app aceitou omelete com tomate e cenoura
com tomate e rejeitou arroz com feijão que dependia de feijão previamente cozido.
O modo livre revelou outro defeito: “frango” não correspondia a “peito de frango”
e “atum” não correspondia a “atum em lata”. A correção resolve apenas uma frase
inteira e inequívoca no modo livre; nunca usa essa aproximação para provar a
disponibilidade na despensa. Testes gratuitos cobrem também sal/salmão e nomes
ambíguos. O teste real anterior permanece registrado como falho; não foi
reclassificado após a correção nem repetido automaticamente.

36 testes direcionados passaram após a correção. Cards antigos continuam
legíveis sem os novos campos opcionais. O código é compartilhado entre iOS e
macOS. Não houve alteração nos stores, schemas SwiftData ou capabilities.

Teste manual adicional: no modo livre, abra sugestões com cortes/embalagens
específicos; no modo restrito, confirme que esses mesmos nomes não passam como
itens disponíveis quando a despensa não os contém. Confira também a receita
completa: a validação ponta a ponta da expansão ainda está em andamento.

## Conferência da receita completa e da biblioteca

A preferência capturada no resultado agora acompanha a estruturação de uma
receita da web e a expansão de uma ideia rápida. Antes de exibir o card completo,
o app confere os ingredientes reais contra a despensa no modo restrito. Nomes
são comparados por inteiro, ignorando apenas caixa, acentos e espaços externos;
ícones, correspondências parciais e similaridade não provam disponibilidade.

A biblioteca aplica as restrições do pedido a ingredientes, passos, tempo e
porções. O modo livre mantém receitas com ingredientes externos; o modo restrito
não recorre silenciosamente a receitas abaixo da disponibilidade exigida. A
compatibilidade geral configurável da página inicial permanece independente.

Roteiro manual: abra tanto uma sugestão da web como uma ideia rápida com a
restrição ativa. Confira a receita completa; um óleo ou tempero acrescentado que
não esteja na despensa deve impedir o card e mostrar o erro já traduzido.
Repita com a restrição desativada e verifique que ingredientes externos são
permitidos. Na biblioteca, peça uma receita sem leite e confirme que receitas
com laticínios não reaparecem como fallback. Esses roteiros ainda precisam da
validação visual completa; testes do comparador não a substituem.

## Busca web: consulta, variedade e custo

A consulta de atualização passa a alternar os ingredientes priorizados na
pesquisa, em vez de anexar “v2”, “v3” ao texto. O nome do ingrediente principal
vem do título do próprio resultado, não da primeira palavra do pedido nem do
primeiro item da despensa. URLs repetidas (incluindo parâmetros de campanha) e
títulos equivalentes não ocupam vários cards. O limite solicitado faz parte da
chave do cache e da requisição ao serviço.

Uma despensa vazia, ou esvaziada pelas restrições alimentares, encerra a busca
restrita sem chamada web. Tentativas alternativas nesse modo mantêm os mesmos
ingredientes e o pedido original. A pesquisa web continua sendo uma descoberta
de fontes; a confirmação de ingredientes acontece ao estruturar a receita e
não deve ser inferida apenas do título/trecho da página.

Os testes de consulta e resposta usam um backend injetado sem rede, incluindo
os sete idiomas. Não são prova de qualidade das páginas atualmente retornadas
pela Exa. A validação web real permanece pendente no contrato E2E e não deve
ultrapassar o teto de gastos vigente.

Roteiro manual: atualize as sugestões com mais de seis itens disponíveis e
confira combinações diferentes; abra fontes distintas, confirme seus títulos,
verifique que o ingrediente não aparece como “Quero” e que links com rastreio
não duplicam cards. Abra a receita completa e repita a verificação da despensa.

A versão final desta etapa passou em 43 testes direcionados e compilou nos três
destinos. Instalada e aberta no Simulator. O Mac recebeu o app assinado e o
snapshot permaneceu idêntico, mas a abertura visual final foi bloqueada pela
sessão do macOS bloqueada. O iPhone físico continuou indisponível. Essas duas
validações não estão concluídas. A busca também deixou de fazer uma terceira
chamada idêntica; atualizar o modo livre varia o enfoque sem palavras de versão.

## Cancelamento de análise de alimentos

O modal mantém a tarefa da análise e a cancela quando sai da tela. A seleção
de foto usa uma tarefa vinculada ao ciclo da view; uma seleção antiga cancelada
não publica resultado por cima da nova. A análise não inicia outro provedor
quando recebe CancellationError ou URLError.cancelled. O pipeline de nutrição
confere o cancelamento entre extração, cache, USDA, Exa e estimativa, impedindo
que ele seja tratado como falha comum que justifique novas chamadas.

A espera artificial de 620 ms antes do resultado foi removida. Isso elimina esse
atraso imposto pelo app; não mede a latência da rede nem prova ausência de
engasgos nas demais páginas. Respostas de tarefas canceladas não consomem a
cota local nem atualizam a tela fechada. Chamadas já recebidas pelo servidor
podem continuar lá; o cancelamento não promete desfazer cobrança ou execução.

Se a rede cancelar uma tarefa ainda visível, o botão volta a permitir tentativa.
Roteiro manual: iniciar análise de texto/foto/rótulo, fechar o modal durante o
carregamento, reabrir e confirmar botão utilizável e ausência de resultado antigo.
Repetir com seleção de foto rapidamente trocada. O teste UI real desse roteiro
continua pendente; os testes de cancelamento usam doubles sem inferência paga.

O registro por texto recebeu Cancelar, reutilizando as traduções existentes nos
sete idiomas. A entrada de texto fica indisponível durante a análise; trocar a
foto cancela a análise antiga. A carga de foto confere a identidade da seleção
antes de publicar. O início automático atrasado também verifica se a tela ainda
está ativa, para não disparar após o fechamento.

55 testes direcionados passaram na versão com essas proteções. O XCTest nativo
aprovou três aberturas/fechamentos e texto só com espaços, seguido de retorno do
segundo plano. Outro teste aprovou a apresentação e Cancelar em pt-BR, inglês,
alemão, espanhol, francês, italiano e japonês. Capturas alemã e japonesa foram
inspecionadas; título, botão e campos ficam visíveis. O simulador foi devolvido
a pt-BR. O readback não encontrou alimentos registrados. Essa evidência cobre
entrada vazia e navegação, não o cancelamento visual de uma inferência real.

Na repetição final, o XCTest registrou esperas de 60 segundos pela notificação
de fim de animações após digitar espaços. Uma captura durante a espera já
mostrava a Nutrição após Cancelar. Amostragem de cinco segundos: 2648/2970
amostras da thread principal aguardavam o RunLoop (~89%). Não foi demonstrado
um hotspot de CPU do app nesse intervalo, nem medida de GPU ou ausência de
hitches. O shader e as animações não foram desativados para ocultar essa espera.
O resultado terminal dessa repetição deve ser consultado no xcresult; os
resultados funcionais anteriores não certificam performance.

## Câmera indisponível e seleção de foto

O host verifica a disponibilidade antes de apresentar a câmera; o representable
verifica novamente antes de configurar a fonte UIKit. Sem câmera, o aviso nativo
oferece a galeria ou Cancelar. O título e o botão reutilizam o catálogo existente;
a nova explicação foi traduzida nos sete idiomas, preservando todas as entradas
anteriores. Ao carregar uma imagem, a prévia abre expandida no iOS para deixar
Analisar visível sem arrastar. A seleção e o cancelamento usam o mesmo host
compartilhado; a galeria existente do Mac permanece disponível.

O XCTest nativo passou no iPhone 17 Pro simulado: câmera indisponível → Cancelar;
câmera indisponível → galeria carregada → foto padrão do simulador → prévia →
Analisar habilitado e acessível → Cancelar. Captura final inspecionada. Nenhuma
inferência foi disparada e nenhum alimento foi salvo. Todas as linhas dos
stores de teste e hashes de mídia permaneceram idênticos. Builds assinados iOS e
Mac Release aprovados; Mac instalado com snapshot idêntico, abertura visual
bloqueada pela sessão bloqueada. Instalação física pendente: iPhone ausente do USB.

Roteiro manual:
1. Sem câmera disponível, abra Câmera e confira o aviso, Galeria e Cancelar.
2. Escolha uma foto: confira prévia expandida, controles e Analisar visível.
3. Troque a foto ou cancele; confirme que não aparece resultado de seleção antiga.
4. No iPhone físico, confira captura real e permissões. Análise de imagem/áudio,
   exatidão nutricional e validação física continuam pendentes no contrato E2E.

## Pedidos somente da biblioteca

Pedidos explícitos de receitas salvas agora usam a biblioteca local antes do
gate de IA, sem gerar ideias, buscar na web ou consumir a cota local de IA.
Os próprios serviços de geração e web também rejeitam esse escopo. A origem é
preservada no payload existente da conversa, sem mudança em schemas ou stores.
Comandos de criação/edição e pedidos mistos não são confundidos com essa busca.
Termos de roteamento e restrições conhecidas não viram palavras positivas de
busca; nomes de ingredientes também podem corresponder às receitas existentes.

Um pedido explícito para não restringir à despensa, ou para usar só seus itens,
tem prioridade sobre a preferência geral e acompanha o resultado e sua expansão.
O estado recente da conversa reconhece um resultado de biblioteca reaberto.
A interpretação natural é delimitada pelas expressões cobertas; isso não prova
compreensão irrestrita de toda frase ou de toda restrição alimentar.

54 testes direcionados passaram, incluindo escopo/termos nos sete idiomas,
comandos/pedidos mistos, override de despensa, payload legado e zero chamadas aos
backends injetados. O teste nativo pediu “Me mostre apenas receitas salvas da
minha biblioteca, sem restringir à despensa.”, exibiu só Suas Receitas e abriu
Mingau Simples na aba Receitas. Readback: os três IDs do payload correspondem
exatamente às três receitas já existentes, sem ideias geradas ou da web.
Somente a conversa de teste foi acrescentada; listas, receitas, metadados e
hashes das capas permaneceram idênticos, com zero alimentos registrados.
Mac instalado e snapshot idêntico; abertura visual bloqueada pela sessão
bloqueada, instalação física pendente porque o iPhone está ausente do USB.

Teste manual: peça sugestões somente da biblioteca; confira origem/nomes e abra
um card. Repita acrescentando “sem restringir à despensa”. Depois reabra a
conversa e confira o escopo. A variação de contexto/tempo/porções em follow-ups
continua sendo uma etapa separada da auditoria da conversa.

## Continuação da conversa, prioridade e diversidade

O texto mais recente agora acompanha os pedidos anteriores em ordem de
prioridade. Tempo, porções, leite e escopo da despensa explícitos no pedido
recente substituem as mesmas preferências antigas, mantendo as demais. O payload
opcional guarda esse histórico para reabrir e expandir resultados; mensagens
antigas continuam legíveis. A consulta web remove limites numéricos superados.
“Mais opções” e o botão equivalente excluem IDs locais, títulos de ideias e URLs
canônicas já mostrados. Exclusões entram também na chave do cache da web.

59 testes gratuitos passaram, incluindo sete idiomas, conflitos com refinamentos
antigos, histórico serializado, exclusão de títulos/URLs e zero despacho para os
serviços quando o histórico exige biblioteca. O teste nativo passou após sair e
voltar do app: a busca inicial trouxe os três IDs existentes; “Agora em até 5
minutos.” retornou apenas o Smoothie de morango e aveia; “Mais opções.” retornou
vazio, sem resultados repetidos, geração ou web. Readback confirmou os três
payloads. Somente a conversa de teste mudou; todos os registros compartilhados,
IDs, metadados e hashes das imagens permaneceram iguais. A comparação ordena
linhas pelo conteúdo para não confundir ordem de leitura SQLite com alterações.

Builds iOS físico, Simulator e macOS aprovados. Mac instalado com assinatura,
Team, containers iCloud ordenados e App Group conferidos; snapshot igual antes e
depois. A sessão do Mac continua bloqueada e o iPhone 12 Pro indisponível; a
validação visual no Mac e instalação física permanecem pendentes. Não houve
chamada paga, compra, alteração de stores ou exclusão de dados nesta etapa.

Roteiro manual:
1. Peça receitas salvas e depois “Agora em até 5 minutos”; confira que continuam
   sendo da biblioteca e que receitas sem tempo conhecido não entram nesse limite.
2. Altere porções, restrição de leite ou escopo da despensa; confira que a nova
   escolha prevalece e que as outras restrições são preservadas.
3. Saia e volte ao app, reabra os resultados e confira o mesmo contexto.
4. Peça “Mais opções” ou use o botão: confira ausência dos resultados anteriores.
5. Em uma validação de rede com orçamento reservado, confira também as receitas
   novas e da web; os mocks desta etapa não comprovam qualidade do provedor real.

## Registro local de suco e confirmação repetida

O parser real e o pipeline de nutrição foram exercitados com exatamente
“suco de limao com 6cs de acucar”. Um teste fechado prova zero chamadas de IA,
USDA e Exa: bebida mais açúcar, seis colheres equivalentes à estimativa de 90 g,
porção total estimada de 290 g e 393 kcal. A quantidade da bebida não foi
informada; a interface avisa que estimou 200 g de suco sem diluição. Esses valores
não representam uma medição da bebida de Pedro nem um rótulo certificado.

O teste nativo digitou o texto exato, conferiu nome e calorias, capturou o aviso,
fez toque duplo em Registrar e relançou o app. Readback: exatamente um novo
FoodEntry, com nome completo, 393 kcal, 290 g e 90 g de açúcar adicionado.
Somente Private/ZFOODENTRY mudou; todos os demais registros e hashes de imagens
permaneceram idênticos. O alimento é sintético e fica preservado no Simulator
isolado, com sync desligado; não foi registrado nos dados pessoais de Pedro.
Não houve mudança no código do app nesta etapa, apenas testes e documentação.
A validação física e a interface macOS continuam bloqueadas conforme acima.

Teste manual: registre a frase exata num destino de teste, revise o aviso de
porção/preparo, confirme uma vez e confira a mesma linha após sair e voltar.
Não trate a ausência de quantidade do suco como uma porção exata conhecida.

## Prévias em sete idiomas

O teste nativo abriu e fechou onboarding e paywall em pt-BR, en, de, es, fr, it e
ja: 14 capturas, sem compra, restauração de assinatura ou IA paga. Retornou a
pt-BR; todos os registros e hashes de imagens permaneceram iguais. Isso comprova
navegação das prévias, não disponibilidade comercial ou conclusão integral do
onboarding em cada idioma. A inspeção das capturas identificou pouco espaço no
rodapé do paywall em traduções longas; essa diferença exige ajuste de layout.

## Rodapé do paywall em traduções longas

O aviso e Restaurar compras passaram a ocupar linhas separadas, permitindo
quebra natural do aviso, sem o limite de uma linha e a redução de texto que os
comprimiam. O layout é compartilhado por iOS e macOS e reutiliza as traduções
existentes. Não altera preços, ofertas, assinatura ou restauração.

Nova rodada nativa: onboarding e paywall nos sete idiomas, 14 capturas, com
asserções de aviso dentro da tela, sem sobrepor Restaurar compras, e botão de
restauração acessível ao toque. Teste aprovado; capturas pt-BR, de e ja
inspecionadas. Todos os registros e hashes permaneceram iguais. Builds dos três
destinos aprovados; Mac instalado e snapshot idêntico. Mac visual bloqueado e
iPhone físico indisponível, sem substituir essas verificações pelo Simulator.

Roteiro manual: abra o paywall em alemão e japonês, confira os dois preços,
leia o aviso completo e confira Restaurar compras abaixo dele. Role até o fim
para conferir o restante do conteúdo; não faça uma compra para testar layout.
