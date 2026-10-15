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
