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

## Receita existente e modo de cozinhar após retornar ao app

Novo teste nativo de 15/10: abriu a receita existente Wrap de frango com homus,
entrou no modo de cozinhar, conferiu Anterior desabilitado no passo 1, avançou
para 2, saiu para Home e retornou mantendo 2/4. Voltou ao passo 1, percorreu
2/3/4 e Finalizar retornou ao detalhe. Duas capturas preservadas; tela final
inspecionada. Teste aprovado. Todos os registros e hashes de imagens dos stores
Private e Shared permaneceram idênticos; zero chamadas pagas e nenhuma edição de
receita, favorito, porção ou lista. A evidência é direcionada à navegação de
cozinhar no Simulator, sem substituir testes físicos, macOS ou temporizadores
que não façam parte da receita.

Teste manual: abra uma receita com vários passos, avance até o segundo, saia e
volte ao app, confira o mesmo passo, volte ao anterior e finalize o percurso.

## Padrão de destinos e câmera física — 15/10

Por preferência explícita de Pedro, o iPhone 17 Pro no Simulator é o destino
padrão. O físico é reservado a necessidades reais de hardware, desempenho ou
CloudKit, sem bloquear o desenvolvimento comum por sua indisponibilidade.

Com o iPhone 12 Pro conectado, foi criado backup completo antes da atualização,
com quick_check aprovado nos dois stores. Bundle ID, Team, containers iCloud na
ordem original, CloudDocuments/CloudKit e App Group foram conferidos. O candidato
atual foi compilado, instalado sem desinstalação e aberto com os dados existentes.

Teste físico de câmera aprovado: controles nativos e obturador acessível foram
observados; o teste usou o botão nativo de descartar. Não houve captura de foto,
análise, registro de alimento ou chamada paga. A prévia estava escura; o teste
não certifica qualidade de imagem nem inferência. O caso é ignorado no Simulator.

Readback após a instalação e os testes: todos os registros, IDs, metadados e
hashes dos BLOBs permaneceram idênticos. Os 151 arquivos externos de mídia
mantiveram tamanho e SHA-256. A primeira cópia posterior atingiu seu timeout;
foi preservada como parcial e a comparação usa uma segunda cópia completa,
concluída com prazo maior. Não houve recuperação, restauração ou limpeza.

Teste manual físico: abra Nutrição > Câmera, confira os controles nativos e
cancele. Confira que voltou à Nutrição sem uma nova refeição ou foto registrada.

## Primeira busca web real: comunicação aprovada, qualidade reprovada

Com o acesso proprietário ao Supabase recuperado no Chrome, exa-search foi
baixada para auditoria sem editar a função nem ler secrets. O código encaminha
uma chamada upstream por requisição e não tem retry interno; o cliente também
não repete internamente. Os preços oficiais atuais permitem reserva conservadora
de US$ 0,019 por tentativa Auto/6 resultados/texto/resumo, com duas tentativas
no máximo. A reserva de US$ 0,038 foi escrita antes da execução, dentro do teto
global autorizado de US$ 3. O teste é optativo e bloqueia outros endpoints,
formatos, tipos, conteúdos e quantidades; execuções normais o ignoram.

No iPhone 17 Pro Simulator, o serviço real retornou seis URLs distintas em uma
chamada, com custo informado pela Exa de US$ 0,013. A reserva retida é US$ 0,019;
a segunda tentativa não ocorreu e não permanece duplicada no ledger. Isso não
é recibo de cobrança do fornecedor. Sete testes fechados passaram e o teste pago
foi ignorado por padrão antes da ativação explícita.

O teste nativo de comunicação passou, mas a revisão humana reprovou a qualidade:
havia bacon/bife/linguiça fora da despensa solicitada, um agrupador de várias
receitas e ingredientes principais como “uma”, “pressa” e “Jantar”. Essa resposta
é uma reprodução real do defeito e não uma aprovação do modo restrito. Não houve
expansão de receitas, geração de imagens, chamada OpenAI/OpenRouter ou alteração
de dados pessoais nessa execução. A correção e a revalidação da qualidade
continuam necessárias.

## Renderização do fundo: gargalo físico reproduzido em 15/10

O teste Release `testPagesAndForeground` percorreu cinco páginas e o retorno ao
app no iPhone 12 Pro. Após a execução, os registros de Private e Shared, seus IDs
e BLOBs e os 151 arquivos de mídia permaneceram idênticos. A comparação ordena as
linhas por chave primária; a ordem física de leitura não indica mudança de dados.

Uma captura Animation Hitches de aproximadamente 30 segundos encontrou 180
linhas atribuídas ao Savoria: duração somada de 11.852,39 ms, máximo de 317,46 ms.
Muitas linhas apontam trabalho de GPU e passes de renderização fora da tela.
Esses números não são uma razão de engasgos normalizada nem prova isolada da
causa; XCTest e espelhamento também podem interferir. Método da Apple:
https://developer.apple.com/documentation/xcode/improving-app-responsiveness.

O fundo CPPN agora é rasterizado com um quarto das dimensões e ampliado para a
tela. Relógio, animação, coordenadas proporcionais e fade da paleta permanecem;
não há congelamento do fundo. A correção reduz a resolução apenas da textura do
fundo, sem rasterizar textos ou controles. Os três builds passaram. A versão
abriu no iPhone 17 Pro Simulator, com shader visível; navegação e retorno ao app
passaram e todos os registros dos dois stores permaneceram idênticos.

O Mac foi compilado, instalado com os entitlements existentes e aberto na tela
de boas-vindas já existente nesta instalação. Snapshot do backend idêntico antes
e depois. A primeira assinatura ad hoc não permitiu abrir o app; a instalação
foi corrigida com o certificado Apple Development do Team original e verificada.
Não se completou o onboarding nem se alterou perfil para simular paridade.

A versão também foi compilada para o teste físico específico. A execução nativa
está em andamento; a nova captura do Instruments ainda não foi obtida porque a
anexação durante a automação não encontrou o processo. A otimização ainda não
está certificada como suficiente, e nenhum percentual de melhora foi inferido.

Teste manual: observe o fundo em movimento, troque entre as páginas, confira o
fade de cor sem reiniciar a forma, role listas e receitas, saia e volte ao app.
Confira que textos continuam nítidos e o shader permanece visível. Desempenho no
Simulator não substitui a medição física que motivou esta correção.

## Validação dos ingredientes das páginas web — 15/10

A busca agora exclui coleções de receitas, lê uma seção delimitada de ingredientes
e exige um início verificável do preparo. No modo restrito, todos os ingredientes
obrigatórios devem corresponder aos nomes completos da despensa; quantidade,
cortes simples e formas plurais explícitas são tratados separadamente. Arroz cru
não comprova arroz cozido, tomate não comprova tomate seco, e sal/óleo/água nunca
são presumidos. Formatos desconhecidos ou truncados são rejeitados neste modo.

Pedidos sem leite conferem ingredientes e preparo. Um limite de minutos exige
tempo total conhecido na fonte; tempo de preparo isolado não é promovido a total.
As porções ainda podem ser ajustadas na expansão, que mantém sua validação final.
O parser conservador não é um certificado de qualidade culinária nem uma prova
de que toda página da web apresenta uma lista completa e correta.

O ingrediente principal vem dos ingredientes extraídos, sem transformar “uma”,
“pressa” ou “Jantar” em alimento. A primeira sequência alterna ingredientes antes
de repeti-los. A consulta enfatiza dois itens, prioriza os citados pelo usuário e
varia o foco ao atualizar; remove repetições de ocasião e resíduos dos limites
numéricos anteriores. Instruções e variações de busca estão nos sete idiomas.
O cache mudou de versão para não reapresentar cards anteriores à conferência.

61 testes passaram, com dois testes pagos ignorados por padrão. Cobrem as falhas
reais reproduzidas, nomes compostos, pré-cozimento, opcionais explícitos, tempo,
leite, diversidade, contexto, cabeçalhos em sete idiomas e limite de duas buscas.
Mocks positivos são fixtures sintéticas, não novos resultados reais da Exa.
Builds Simulator e macOS aprovados; Simulator instalado e aberto. Mac instalado
com assinatura Apple Development e snapshot idêntico; a abertura visual desta
iteração ficou pendente porque o Mac voltou a bloquear. A validação web real
posterior à correção continua pendente e não foi contabilizada como aprovada.

Roteiro manual: ative apenas despensa, busque receitas novas e abra um resultado.
Confira todos os ingredientes e o preparo; repita com limite de tempo e sem leite.
Atualize as ideias e confira diversidade e ausência de URLs repetidas. Com uma
despensa insuficiente, confira ausência de receitas incompatíveis; desligue a
restrição apenas por escolha explícita, não como fallback automático do app.

## Segunda correção do shader: superfície Metal delimitada

A primeira otimização não foi suficiente. Fora do XCTest, com o app em primeiro
plano, a captura posterior registrou 598 linhas de engasgo em aproximadamente
30 segundos, com muitos avisos de GPU/renderização e até 109 passes fora da tela.
Os intervalos superiores de GPU tiveram mediana de 26,68 ms. A navegação inicial
e esta captura parada não são experiências equivalentes: não se calculou uma
porcentagem de melhora nem se usou a redução do máximo como aprovação.

O shader agora usa MTKView com drawable limitado a 384 pixels na maior dimensão,
ampliado pelo compositor. A rede e seus pesos continuam os mesmos. O relógio e
o viewport são compartilhados; o renderer amostra o fade da paleta sem atualizar
a árvore SwiftUI a cada quadro. A apresentação solicita 60 quadros/s, sem afirmar
que o aparelho já os mantém. Páginas inativas, app em segundo plano e Reduzir
Movimento pausam a animação; há limite de dois comandos em voo e fallback visual
se Metal não estiver disponível. Referência de configuração:
https://developer.apple.com/documentation/metalkit/mtkview.

Builds dos três destinos aprovados. A versão abriu no iPhone 17 Pro Simulator,
com fundo visível, e `testPagesAndForeground` passou. Readback dos stores Private
e Shared: quick_check ok e todas as linhas, IDs e hashes dos BLOBs idênticos.
Mac instalado com Apple Development, entitlements preservados e snapshot
idêntico; abertura visual final aguarda desbloqueio. A versão também foi
instalada no físico, com Bundle ID, Team, containers ordenados e App Group
conferidos, mas medição e readback posteriores aguardam o código do aparelho.

A cópia física após o teste da primeira otimização falhou com socket fechado,
enquanto o aparelho voltou a exigir código. A cópia parcial foi preservada; ela
não contém todos os stores/arquivos e não foi usada para afirmar integridade.
O backup completo anterior e a comparação física anterior permanecem válidos
para seus respectivos instantes, sem serem promovidos a prova do novo candidato.

Para a medição controlada, os argumentos explícitos `-SavoriaActionTrace` e
`-SavoriaKeepAwakeForValidation` mantêm a tela acesa somente no processo de teste,
sem gravar preferência de Auto-Lock ou outro dado pessoal. Execuções normais não
ativam esse comportamento. Não houve chamada paga nesta etapa.

Roteiro físico pendente: abrir a versão instalada com esses argumentos, conferir
o fundo animado e o fade em cada página, medir Animation Hitches em repouso e em
navegação e após retorno ao app; comparar cargas equivalentes e fazer readback
completo. A nova arquitetura ainda não é uma certificação de fluidez ou produção.

### Ligação Metal e movimento efetivo

A conferência adicional encontrou uma falha que a compilação e a navegação não
detectavam: a primeira pipeline nativa referenciava diretamente a função
`stitchable`, e a criação em runtime falhava com `unresolved visible function
reference`. O fundo observado nessa tentativa era o fallback estático. Assim,
seus screenshots e a navegação aprovada não comprovavam animação Metal.

A rede agora está numa função auxiliar comum; o fragmento nativo e o wrapper
SwiftUI a chamam diretamente, sem alterar seus pesos ou o relógio. A criação da
pipeline passou na GPU Apple M4 Pro e o app no Simulator registrou explicitamente
`Backdrop Metal pipeline ready`. Um teste nativo adicional abre a biblioteca do
próprio app e exige que a pipeline seja ligada numa GPU Metal, para detectar essa
classe de regressão antes de confiar no fallback.

A navegação e o retorno ao app passaram novamente com a pipeline corrigida.
Capturas sucessivas da mesma Home, sem interação, confirmaram movimento: 1.152
de 1.170 pontos amostrados numa faixa só de fundo mudaram. É evidência de animação,
sem ser medição de FPS ou garantia de continuidade em todas as transições.
Os stores do Simulator passaram quick_check e mantiveram todas as linhas, IDs e
hashes de BLOBs. Mac instalado com snapshot idêntico e físico atualizado novamente;
abertura visual do Mac, medição física e readback físico completo seguem pendentes
dos desbloqueios. Não houve restauração, exclusão ou escrita direta nos stores.

## Restrição explícita na consulta web

Pedro autorizou elevar o teto acumulado de testes de US$ 3 para US$ 4. A repetição
real do caso original fez duas buscas, com US$ 0,026 informados e US$ 0,038 retidos
conservadoramente. Não encontrou receitas compatíveis: os resultados exigiam
ingredientes ausentes ou arroz previamente cozido. O caso permanece reprovado;
rejeitar resultados errados não equivale a oferecer boas receitas.

A consulta agora explicita a lista permitida e que não é preciso usar todos os
itens. A ênfase de dois alimentos é distinta do inventário autorizado. Para
pedidos de até 30 minutos, alimentos citados pelo usuário continuam prioritários;
grãos/feijões sem indicação de pré-cozimento deixam de dominar a ênfase quando
há outros itens. Isso é ranking de busca, nunca prova de disponibilidade ou
tempo. A restrição está traduzida nos sete idiomas, e o cache foi atualizado.

59 testes passaram. Simulator e Mac foram compilados, instalados e abertos;
snapshot do Mac idêntico. A nova consulta ainda não foi revalidada no provedor.
No físico, o candidato Metal corrigido foi aberto, e a cópia completa confirmou
111 itens, 64 receitas, 8 alimentos, 62 conversas, 107 mensagens e os mesmos 151
arquivos de mídia. A captura parada apresentou tabelas vazias e um aviso CoreData
do Instruments; não se usou isso como prova de zero engasgos. A próxima medição
deve capturar ações reais com a métrica de hitches do XCTest.

Teste manual: com modo restrito, peça jantar em 20 minutos e confira que não
pressupõe arroz/feijão já cozidos. Cite explicitamente um alimento e confira sua
prioridade. Repita em modo livre e confirme que não impõe o inventário restrito.

### Repetição real e coleta de métricas

A consulta explícita foi repetida com o mesmo pedido e a mesma despensa sintética,
sem enfraquecer as restrições. Duas respostas Exa não trouxeram receitas completas
compatíveis; o teste terminou com `empty`. US$ 0,026 foram informados pelo provedor,
com US$ 0,038 conservadoramente retidos. O caso de qualidade web segue reprovado.

Há agora cinco testes de ações com `XCTHitchMetric`, rolagem quando aplicável e
retorno do segundo plano, três amostras por página. O teste da Home no Simulator
passou; a coleta adicional confirmou amostras de relógio e duração de rolagem,
mas não apresentou métricas de hitches/FPS. Duração inclui esperas da automação
e não representa latência de resposta nem fluidez. Referência oficial:
https://developer.apple.com/documentation/xctest/xcthitchmetric.

O build físico Release passou usando os certificados e profiles locais, sem
`-allowProvisioningUpdates`. A execução não iniciou: o iPhone exibiu a autorização
separada “Digite o código do iPhone para XCTest / Enable UI Automation” e o runner
expirou esperando essa autorização. Nenhuma página física foi aprovada nessa
tentativa. A medição aguarda o código digitado pelo proprietário no aparelho.

A investigação do login Apple encontrou HTTP 503 também no caminho público de
recuperação, sem conta, cookies ou credenciais. O status público do App Store
Connect não listava incidente, o que não exclui falha no serviço de recuperação.
Nos logs locais e unificados, houve uma falha de leitura de metadados do Keychain
(`missing Xcode-Username`), sem prova de envio de senha incorreta à Apple. A causa
do bloqueio da conta permanece indeterminada. Tentativas de login foram suspensas;
nenhuma senha, conta, certificado ou item do Keychain foi removido ou redefinido.

## Receita completa: ingredientes escondidos no preparo

O novo teste real das ideias passou nos dois modos: duas opções restritas e
quatro pratos diferentes em modo livre. O feijão que exigia pré-cozimento foi
rejeitado. Isso não aprovou a expansão: uma chamada posterior retornou apenas
ovos e tomate na lista, mas adicionou sal no preparo. O teste inicialmente passou
porque conferia disponibilidade só na lista; a leitura humana reprovou o caso.

O leitor do card e o montador do pedido agora são compartilhados com os testes.
Seções invertidas são rejeitadas antes de formar um intervalo inválido de texto.
A conferência da despensa também examina os passos para um vocabulário explícito
de ingredientes comuns, nos sete idiomas, respeitando negações e nomes completos.
É uma proteção adicional contra extras conhecidos, sem prometer compreensão
semântica completa de qualquer ingrediente ou frase. Receitas salvas e fontes
web passam pela mesma conferência quando o modo restrito é solicitado.

O primeiro teste com essa proteção rejeitou corretamente sal e óleo ainda
introduzidos pelo modelo. A expansão agora permite uma única correção de resposta
incompatível, com as restrições originais e a lista permitida. Há no máximo duas
chamadas, limitadas a 2.048 tokens cada; falhas de transporte e cancelamento não
disparam essa correção. Uma segunda resposta incompatível é rejeitada.

68 testes locais passaram e dois testes pagos foram ignorados por padrão. O
teste nativo real seguinte, usando uma ideia do recibo real anterior, rejeitou
uma receita com azeite/sal/pimenta e aceitou sua correção: ovos e tomate, 15 minutos,
uma porção, frigideira antiaderente sem gordura. Foram duas chamadas; não se
registrou receita nem alimento. É validação do cliente real, pedido, parser e
conferência compartilhados, sem afirmar execução visual completa da conversa.
O total conservador acumulado ficou em US$ 3,244497 do teto autorizado de US$ 4.

Builds Simulator e macOS aprovados e instalados. Os dois stores do Simulator
passaram quick_check; todas as linhas, IDs e hashes de BLOBs ficaram idênticos.
O snapshot do backend Mac também permaneceu idêntico. A busca web restrita do
caso anterior continua reprovada, sem ser substituída por este teste de expansão.

Teste manual: selecione uma ideia com modo restrito, confira lista e preparo e
confirme que não surgem sal/óleo fora da despensa; confira tempo e porções. Repita
em modo livre e sem leite. Cancele durante a busca e confira que a operação para.
Não salve uma receita apenas para validar a tela; o salvamento exige uma escolha
explícita no fluxo normal.

## Diagnóstico físico da renderização

As cinco páginas concluíram as ações e o retorno ao app no iPhone 12 Pro. A
primeira coleta gerou dados de rolagem apenas para Home e Nutrição: médias de
11,44 e 10,43 quadros/s, respectivamente. Os valores `sync` ficaram em zero,
mas não anulam os engasgos registrados pela métrica específica de rolagem. Os
contadores de quadros também vieram zerados, uma limitação a conservar no relato.
Listas e Receitas não haviam exercitado a rolagem nesse primeiro teste; o sucesso
funcional não foi usado como aprovação de desempenho dessas páginas.

A repetição sem janela de espelhamento registrou 16,14 quadros/s na Home, ainda
insuficiente. O teste de Listas passou a rejeitar a ausência de uma área exercitada:
UICollectionView existe, mas seu contêiner reporta `isHittable == false`. O harness
agora usa a área visível do viewport para reconhecer também esse contêiner; a
validação dessa última seleção está pendente.

Uma coleta optativa lê `gpuEndTime - gpuStartTime` somente após completar comandos
Metal, descarta 30 amostras de aquecimento e grava no máximo 180 amostras válidas,
com limite de 300 tentativas. Não há gravação nem logging por quadro em uso normal.
No físico, com drawable 177 × 384, mediana 0,269 ms, p95 0,511 ms e máximo 0,937 ms.
São tempos do passe do shader em repouso, não FPS da interface nem custo total
do compositor. A resolução de produção permaneceu em 384; não se justificou
reduzi-la como correção para os engasgos medidos. Documentação da Apple:
https://developer.apple.com/documentation/metal/mtlcommandbuffer/gpuendtime.

Após os testes das cinco páginas, quick_check dos dois stores físicos passou.
Todas as linhas, IDs, hashes de BLOBs e os mesmos 151 arquivos de mídia permaneceram
idênticos ao backup completo anterior. O diagnóstico não executou chamadas de IA.

### Composição obsoleta da coluna

Não havia produtores de `ContentPanelCutoutKey` no app. O recorte de calorias já
removido ainda mantinha um overlay, GeometryReader, preferência e compositingGroup
envolvendo toda a coluna. Esse caminho sem uso foi retirado; clip, superfície,
borda luminosa, shader, relógio e fade continuam existentes.

Os três builds passaram, e as cinco páginas/retorno ao app passaram novamente
no Simulator. Na primeira comparação física sem espelhamento, a Home registrou
39,97 quadros/s (três amostras: 45,36/37,17/37,37), contra 16,14 da rodada anterior.
É uma melhora no cenário medido, sem certificar 60 quadros/s ou fluidez geral.
As outras páginas físicas ainda estão em execução nesta etapa.

Time Profiler físico em repouso também obteve 4.408 linhas de amostragem em
16,216 s. A pilha da thread principal ficou dominada por espera de drawable:
`_dispatch_semaphore_wait_slow → CAMetalLayerPrivateNextDrawableLocked →
MTKView.currentDrawable → SavoriaMetalBackdrop.Coordinator.draw(in:)`.
O perfil inclui threads em espera: esses pesos não representam CPU ocupada.
Isso identifica um bloqueio da interface apesar do custo baixo do passe na GPU.
A próxima correção deve retirar essa aquisição de drawable da thread principal,
preservando a animação e usando um autoreleasepool por frame, conforme a Apple:
https://developer.apple.com/documentation/quartzcore/cametallayer.

Teste manual: conferir o painel e a borda em Home/Nutrição/Listas/Receitas, rolar,
abrir e fechar a busca, sair e voltar ao app e confirmar o fundo em movimento.

### Aquisição de drawable fora da interface

O callback principal do MTKView agora só captura dimensões, cor e relógio e
entrega o valor mais recente a uma fila serial. `CAMetalLayer.nextDrawable`,
criação do render pass, encoding e commit ficam nessa fila. Nenhuma propriedade
de UIView é consultada fora da thread principal. Uma trava curta protege somente
o snapshot e a sinalização; ela nunca envolve aquisição de drawable ou trabalho
Metal. Há no máximo um trabalho pendente, dois comandos em voo e descarte de
snapshots antigos. Uma atualização estática final não é perdida; saída da tela,
pausa e desmontagem cancelam valores pendentes sem esperar a fila.

Cada trabalho usa autoreleasepool para liberar drawables prontamente, seguindo
a documentação da Apple. Rede do shader, resolução de 384, relógio compartilhado,
viewport e fade continuam iguais. Não se reduziu FPS nem se congelou o fundo.

Os três builds passaram. No Simulator, as cinco páginas e o retorno ao app
passaram; 737 de 756 pontos de uma faixa só de fundo mudaram em capturas da mesma
Home, sem interação. Um novo arquivo GPU confirmou 180 comandos completados.
São evidências de movimento, não desempenho físico. Os dois stores permaneceram
idênticos e passaram quick_check. Mac atualizado, assinatura original preservada,
snapshot idêntico e tela conhecida de boas-vindas conferida.

Após a rodada física da composição, os bancos, BLOBs e os mesmos 151 arquivos
de mídia ficaram idênticos. Uma cópia geral falhou num snapshot temporário do
SplashBoard protegido pelo iOS; a parcial foi preservada e não usada como prova
completa. Cópias bem-sucedidas de Application Support, RecipeThumbnails e
tmp/RecipeMediaCache forneceram a comparação dos dados reais.

A versão com o worker foi instalada no físico, mas o aparelho voltou a bloquear
antes da abertura, pois a instalação encerrou o processo com o argumento de tela
acesa. O Device Hub foi reaberto e o desbloqueio solicitado. Time Profiler e
métricas físicas dessa correção seguem pendentes; não se afirma que o bloqueio
foi eliminado no aparelho até obter essa evidência.

### Listas: atualizar somente ao atravessar o limite do título

A rolagem de Listas guardava cada pixel em @State, embora os consumidores só
precisem saber se a posição atravessou -24 pontos. Agora apenas a mudança desse
limite atualiza o estado. O comportamento de título e toque repetido na aba
continua equivalente; dados, textos e persistência não mudam.

Builds iOS físico/Simulator e macOS passaram. O teste de rolagem e retorno ao
app em Listas passou no iPhone 17 Pro virtual. Os dois stores continuam idênticos
em todas as linhas, IDs e hashes de BLOBs, com quick_check ok. Mac instalado e
assinado com o certificado original; snapshot antes/depois idêntico e janela
real de boas-vindas conferida (estado vazio pós-formatação já conhecido).
A medição física da combinação com o worker Metal ainda está em andamento.

Teste manual: rolar Listas para ocultar/exibir o título; tocar na aba perto do
topo para alternar a categoria e longe do topo para voltar ao início; sair e
retornar ao app.

### Worker Metal: confirmação física e limite da medição

A versão 32370c6b abriu no iPhone 12 Pro após o desbloqueio. Uma captura
Time Profiler de 16,246 s, abrangendo todos os processos e depois filtrada
para Savoria, encontrou 1.004 amostras da thread principal e nenhuma aquisição
de drawable nela. As 641 amostras com aquisição ficaram no worker. A principal
passou a ficar predominantemente no run loop em repouso. Pesos incluem esperas,
não representam CPU ocupada, e repouso não comprova desempenho de rolagem.

As cinco páginas/retorno passaram (5 testes, zero falhas), com as superfícies
verticais reais. As médias OS de rolagem foram Home 27,21 fps; Listas 13,47;
Nutrição 19,94; Receitas 18,20. Continuam baixas e não certificam fluidez. Busca
só recebeu teste funcional/retorno; o zero de sync hitch não prova ausência
de engasgos. Os resultados anteriores permanecem preservados.

A inspeção do xctestrun encontrou o verificador de antipadrões ativo, injeção
libRPAC/PERFC e captura automática em vídeo. Uma cópia privada do executor está
preparada para comparação sem essas opções, sem alterar o app, assinatura ou
dados. A Apple recomenda desativar diagnósticos e captura automática para medir
desempenho: https://developer.apple.com/videos/play/wwdc2020/10077/. Nenhum
resultado antigo foi reclassificado; o efeito dessas opções ainda será medido.
Uma captura separada Animation Hitches durante Listas está sendo salva para
atribuir o custo restante; seus números não entram no benchmark sem profiler.

### Fluxo de medição: foreground e executor separado

O teste finalizava pressionando Home e deixava o iPhone sujeito ao bloqueio
enquanto o Xcode exportava os resultados. Agora termina com o app em primeiro
plano. O argumento de validação continua restrito ao processo e não altera
as preferências de bloqueio automático. Os builds dos dois executores passaram
e o teste de Listas/foreground passou no iPhone 17 Pro virtual.

`scripts/prepare-performance-run.py ORIGINAL.xctestrun COPIA.xctestrun` cria
exclusivamente um arquivo novo, no mesmo diretório, preservando __TESTROOT__
e os caminhos do app/teste. Desativa o checker no executor copiado, retira
somente a injeção libRPAC e variáveis PERFC/asserções SQLite de diagnóstico,
e evita retenção de captura automática. Não altera o executor original,
assinatura, app ou dados. Rode a cópia com `test-without-building`,
`-enableCodeCoverage NO -enablePerformanceTestsDiagnostics NO
-collect-test-diagnostics never`, escolhendo o iPhone 17 Pro no Simulator por
padrão. O físico é necessário para medir seu desempenho real.

A captura Animation Hitches não concluiu a exportação: permaneceu em stopping,
com espera DTX observada num sample do processo da ferramenta. Após SIGINT
sem conclusão, só esse processo de diagnóstico foi encerrado. O artefato
parcial permanece preservado e excluído das evidências. O teste funcional
separado sob profiler passou, mas seus FPS não são comparados ao benchmark.
A tentativa de comparação física sem checker não iniciou, pois o iOS exige
novo desbloqueio. Não se concluiu que o checker seja a causa da lentidão.

Após os testes do worker, cópias bem-sucedidas de Application Support,
RecipeThumbnails e RecipeMediaCache confirmaram todos os registros, IDs, BLOBs
e os mesmos 151 arquivos de mídia idênticos ao baseline, com quick_check ok
nos dois stores. Nenhuma mudança de schema, container ou capability.

A conferência por screenshot após a sessão mostrou que o XCTest também encerra
o app automaticamente. Portanto, app.activate no final do método mantém apenas
o foreground dentro do teste e não garante a tela acesa após o teardown.
`scripts/run-performance-tests.py` acompanha a saída do executor: reabre o app
com os argumentos temporários de validação ao receber a conclusão da suíte,
antes da exportação do Xcode, e confere nova abertura ao término do comando.
Ele só oferece os cinco testes de páginas sem mutações/IA, exige um executor
preparado, preserva arquivos existentes e registra falhas de abertura.

Uso: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer python3
scripts/run-performance-tests.py --xctestrun COPIA.xctestrun --simulator UUID
--page Lists --result CAMINHO_NOVO.xcresult`. Use `--device UUID` somente para
validação que exija hardware real. Omita --page para as cinco páginas.

Os dois helpers foram exercitados juntos no iPhone 17 Pro virtual: teste de
Listas/foreground passou, as duas reaberturas retornaram sucesso e screenshot
após a exportação mostrou o Savoria efetivamente aberto. Os stores do Simulator
continuaram idênticos e quick_check ok. O usuário desbloqueou novamente o físico;
a comparação de Listas sem checker está em execução, com o novo wrapper.

### Captura exclusiva e condições do dispositivo

Listas sem checker/captura em vídeo mediu 39,19 fps (46,28/37,50/33,80),
com razão de hitch 336,62 ms/s. Isso difere da rodada de 13,47 fps com opções
extras, mas não isola qual opção causou a diferença nem certifica 60 fps.
O wrapper reabriu o app com sucesso nas duas fases também no físico.

Capturas simultâneas ao teste com XCTHitchMetric não finalizaram; as parciais
foram preservadas e excluídas. O novo testProfileListsForInstruments usa seis
pares de gestos e retorno ao app, sem abrir gravação de métricas do XCTest.
`--profile-lists` no wrapper seleciona esse caso. Os builds físico/Simulator
e os dois testes de gestos passaram. Uma captura exclusiva Time Profiler de
15 s, iniciada após o primeiro swipe, finalizou e foi exportada. Não se afirma
que a concorrência seja a causa comprovada da falha das outras capturas.

O UITest runner no iPhone registrou thermalBefore=2 e thermalAfter=2 (serious),
com Low Power Mode false. A Apple documenta redução de desempenho nesse estado:
https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum/serious.
Não é possível inferir retroativamente a temperatura das rodadas anteriores.

No perfil de rolagem, a thread principal teve 5.454 amostras de CPU e nenhuma
aquisição de drawable. A maior parte do peso ficou em layout/commit do UIKit
e coleta AX da automação; código próprio da linha PantryItemRow teve apenas
7 ms inclusivos. O compositor apresentou custo elevado em render_shape e
render_lines. sharingd e pkd também tiveram carga substancial no mesmo período;
isso não prova origem no app. O Device Hub foi encerrado normalmente para
retirar o espelhamento da próxima comparação, preservando preferências.

### Separadores pontilhados estáticos

ItemListDivider agora compõe seus dois traços pontilhados numa textura pequena
com drawingGroup, preservando o espaço de cor não linear. Mudanças de largura
ou aparência redesenham a imagem; deslocamento de rolagem pode reutilizá-la.
O objetivo é reduzir a tesselação repetida das formas observada no compositor,
sem alterar os traços, cores, layout, fundo ou dados. Código compartilhado iOS/macOS.

Os três builds passaram. No Simulator, navegação/retorno nas cinco páginas
passou em três ciclos e os bancos continuam idênticos, com quick_check ok.
A comparação visual de Listas antes/depois preserva a aparência do pontilhado;
a faixa estreita do divisor teve delta RGB médio 0,49/255, com pequenas diferenças
de antialiasing nas bordas (máximo local 16,12/255). Mac instalado/assinado com
Team/containers originais; UUIDs dos binários conferem com o build, snapshot
idêntico e GUI de boas-vindas conhecida aberta. Um guard por nome de processo
confundiu o Savoria do Simulator com o Mac; a conferência pelo caminho exato
confirmou o encerramento do backend Mac e permitiu a abertura correta da GUI.

No físico, assinatura/Team/containers e App Group foram conferidos antes da
instalação, que terminou com sucesso. A abertura imediatamente seguinte foi
negada pelo iOS com Locked; o processo que mantinha a tela acesa é encerrado
pela instalação. A versão nova está instalada e o Device Hub preparado, com
novo desbloqueio solicitado. Naquele ponto, a medição física dos separadores
estava pendente; a rodada posterior está registrada abaixo. Não se atribui
ganho causal isolado de FPS a esta mudança.

Teste manual: conferir o pontilhado entre itens em Listas e em ingredientes
de receitas, nos dois temas; rolar, alternar páginas e voltar ao app.

### Testar o app instalado sem reinstalação no físico

O manual local de xcodebuild.xctestrun documenta UseDestinationArtifacts: o
executor usa o app e o runner já instalados. `prepare-performance-run.py`
aceita --use-installed, verifica IDs/caminhos do runner e produz essa cópia
sem paths de instalação. Verifique antes se o app e o runner instalados
correspondem à versão que deseja testar; esse modo não os atualiza.

O Xcode recusou esse modo no Simulator com a mensagem explícita de que o
destino deve ser um aparelho iOS. A tentativa não executou testes e não é
falha do app. O helper agora rejeita essa combinação antes de criar arquivos;
a validação normal do Simulator continua aprovada. A cópia para o iPhone
foi preparada; a execução após o desbloqueio está registrada abaixo.

Após a instalação dos separadores, as novas cópias físicas dos dois stores
e das mídias confirmaram novamente todos os registros/IDs/BLOBs e os 151
arquivos idênticos, com quick_check ok. Isso comprova a preservação após
instalar; a abertura e a medição posteriores estão registradas abaixo.

Etapas para teste manual dos separadores:

1. Na Despensa e no Mercado, conferir o pontilhado entre itens e rolar a lista.
2. Abrir uma receita e conferir os divisores entre ingredientes nos dois temas.
3. Alternar as cinco páginas, sair e voltar ao app, conferindo a seleção e o fundo.

### Ativação do app instalado — limitação do Xcode 27 beta

Após o desbloqueio, devicectl abriu a versão nova corretamente. O primeiro
UseDestinationArtifacts iniciou o runner instalado, mas XCUIApplication.launch()
acionou IDEInstallCoreDeviceWorker e falhou com Application Bundle Not Found,
apesar de o app estar instalado e ter acabado de abrir. As cinco falhas ocorreram
antes das medições; não representam cinco falhas funcionais do Savoria.

O modo instalado agora usa um runner atualizado, com a variável de teste
SAVORIA_USE_INSTALLED_TARGET=1. O helper abre o app com os argumentos de validação
e idioma antes do XCTest. O teste exige que ele esteja em execução e usa activate()
em vez de launch(). Cada invocação mede somente uma página, pois o XCTest pode
encerrar o app ao terminar a sessão; a próxima invocação o abre novamente.
Não use esse modo com um runner antigo: atualize somente o app do runner no
aparelho, sem reinstalar o Savoria principal. O fluxo normal do Simulator mantém
launch(). A API de ativação está documentada em:
https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/activate().

A primeira rodada de Listas nesse modo passou com swipes no UICollectionView
real e retorno do segundo plano, sem reinstalar o app. FPS de rolagem:
45,20 / 45,33 / 42,96 (média 44,50), hitch ratio médio 251,53 ms/s.
Temperatura serious antes e depois; Low Power Mode false. A medição anterior
com diagnósticos reduzidos teve média 39,19 fps, mas sem temperatura registrada:
essa comparação não isola o efeito dos separadores nem comprova fluidez plena.

### Cinco páginas físicas após os separadores

As cinco invocações instaladas passaram, incluindo seleção da página após
sair/voltar. O app principal não foi reinstalado; somente o runner foi atualizado.
O Device Hub estava encerrado, sem espelhamento durante as medidas.

| Página | FPS médio da rolagem | Hitch ratio médio (ms/s) |
| --- | ---: | ---: |
| Inicial | 56,61 | 28,91 |
| Listas | 44,50 | 251,53 |
| Nutrição | 51,86 | 94,84 |
| Receitas | 46,49 | 213,49 |
| Busca | Sem métrica de rolagem | Sem métrica de rolagem |

Cada página registrou thermalBefore=2/thermalAfter=2 (serious), sem Low Power Mode.
Busca valida navegação/retorno; o sync hitch zero não prova fluidez nem FPS.
Os resultados ainda apresentam engasgos e não certificam 60 fps em uso normal.
É necessária uma comparação com o aparelho sem limitação térmica.

As cópias físicas após essa rodada preservam todos os registros, IDs, BLOBs
e 151 mídias, com quick_check ok nos dois stores. O fluxo normal de Listas
no iPhone 17 Pro do Simulator também passou com o runner novo e os mesmos
registros/IDs/BLOBs nos dois stores. Nenhuma chamada paga ou registro de
alimento foi realizado por estes testes.

Uma captura Animation Hitches exclusiva de 15 s, alimentada pelo caso sem
XCTHitchMetric, também ficou presa na finalização. Após o prazo limitado,
recebeu SIGINT e o processo próprio foi encerrado; o artefato parcial foi
preservado e excluído das conclusões. Os gestos passaram. Essa nova falha
não permite atribuir o problema apenas a coletores de métricas concorrentes.

O perfil adicional de CPU não chegou a iniciar: o preflight retornou Locked
antes de abrir o app, sem criar trace nem executar gestos. A lista de processos
depois desse bloqueio não continha Savoria ou o runner. O índice de diagnósticos
consultado não apresentava crash/jetsam novo correspondente ao horário desta
rodada; isso não determina a causa do encerramento nem exclui relatório tardio.
O Device Hub foi deixado no iPhone físico e foi solicitado esfriar/desbloquear
para a comparação térmica. Não houve reinstalação do aplicativo principal.

### Retestes após intervalo e perfil de CPU finalizado

Após novo desbloqueio, Listas passou com 59,42 / 59,42 / 58,61 fps
(média 59,15), hitch ratio médio 2,27 ms/s. O estado térmico inicial foi fair,
e o final serious; não se trata de uma rodada inteiramente nominal. O app
principal permaneceu instalado e o Device Hub foi encerrado durante a medição.

O Time Profiler exclusivo de rolagem finalizou e foi exportado: intervalo
amostrado de 15,92 s, 5.306 amostras da thread principal e nenhuma aquisição
de drawable nessa thread. As 26 amostras de aquisição ficaram em outras
threads. O trabalho próprio de PantryItemRow continuou pequeno no perfil.

Com o mesmo parser nos dois perfis, o peso estatístico inclusivo de render_shape
no backboardd passou de 2.256 para 225 ms, e render_lines de 1.240 para 90 ms.
Não são tempos de GPU nem percentuais de CPU; símbolos inclusivos se sobrepõem.
A carga de sharingd também caiu de 25.820 para 21 ms somando suas threads.
Portanto, a comparação é compatível com menos trabalho nas formas, mas não
isola causalmente o efeito dos separadores da mudança na carga do sistema.

Os retestes seguintes de seleção/rolagem/retorno também passaram:

| Página | FPS médio da rolagem | Hitch ratio médio (ms/s) |
| --- | ---: | ---: |
| Inicial | 56,77 | 9,28 |
| Listas | 59,15 | 2,27 |
| Nutrição | 56,19 | 27,70 |
| Receitas | 59,17 | 2,29 |

Inicial/Nutrição/Receitas e o perfil de CPU registraram serious antes/depois,
sem Low Power Mode. Busca mantém a aprovação funcional da rodada anterior;
não possui métrica de rolagem neste roteiro. As cópias físicas posteriores
preservaram todos os registros/IDs/BLOBs e as 151 mídias, com quick_check ok.

### Isolar intervalos na retomada

Os ActionTraces dessa rodada contêm intervalos entre callbacks de até 447 ms
em sequências de retomada quentes, excluindo os eventos de lançamento inicial.
Esses intervalos incluem a interferência da automação e não são quadros de GPU
nem prova isolada de congelamento visível. A rolagem perto de 60 fps não os
invalida e não aprova automaticamente toda a retomada.

O novo testProfileForegroundForInstruments percorre duas vezes as cinco páginas,
pressiona Home e reativa o app, conferindo a seleção preservada. Após cada
ativação, deixa o app por dois segundos sem consultas AX, dormindo apenas o
processo separado do executor. Não cria sessão XCTHitchMetric, faz chamadas
de IA ou modifica dados. O helper expõe --profile-foreground.

Os builds do runner para físico e Simulator passaram. Somente o runner físico
foi atualizado. O preflight da captura adicional retornou Locked antes de
iniciar os testes ou o profiler; esse perfil de retomada ainda não é evidência
física. Os índices consultados não mostraram crash/jetsam novo do horário
correspondente; a causa do encerramento anterior continua não comprovada.
O Device Hub está preparado e foi solicitado novo desbloqueio.

O teste novo passou no iPhone 17 Pro do Simulator: dois ciclos completos pelas
cinco páginas, seleção retida após cada retomada e zero falhas. O readback
posterior preservou todos os registros/IDs/BLOBs dos dois stores, quick_check
ok. Isso valida o roteiro e sua execução normal; não substitui a atribuição
dos intervalos observados no iPhone físico.
