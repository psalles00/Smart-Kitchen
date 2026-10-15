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
