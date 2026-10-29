# Catálogo de assinaturas no teste local

O catálogo `SmartKitchen/Resources/Configuration.storekit` usa valores numéricos
com ponto decimal: `99.90` no anual e `49.90` no mensal. A configuração brasileira
permanece `pt_BR` / `BRA`. A apresentação localizada deve vir de
`Product.displayPrice`. Os valores esperados são R$ 99,90 por ano e R$ 49,90 por mês.

Não use a formatação localizada nos campos numéricos do arquivo.
Na investigação de 13/10/2026, a API de teste retornou 99 / 49 mesmo depois de
o catálogo correto estar presente no app e no serviço StoreKit. O paywall
aberto manualmente mostrou R$ 99,90 / R$ 49,90. Esse resultado visual, sozinho,
não prova os preços carregados pela API ou a configuração de produção.

Valide `SavoriaDebugTests.testBrazilSubscriptionCatalogueMatchesAnnualAndMonthlyPlans`
para conferir preço, moeda BRL e períodos anual/mensal por meio de `Product.products`.
Depois abra o paywall na Central de Debug e confira ambos os planos sem comprar.

Esta configuração e o teste local não alteram nem comprovam os preços publicados
no App Store Connect. Confira os produtos correspondentes antes de enviar o app.

## Evidência de 14/10/2026 no Xcode 27 beta

O teste do catálogo real carregou os dois produtos, mas `Product.price` continuou
retornando `99` e `49`, inclusive com idioma de teste inglês e região EUA.
O teste original mantém as expectativas `99.90` / `49.90` e permanece reprovado
nesse ambiente; os dois testes de simulação Básico/Premium passaram.

`testStoreKitDecimalParsingWithIsolatedCatalogues` é um diagnóstico optativo,
ativado com `SAVORIA_STOREKIT_DECIMAL_PROBE=1` no ambiente do processo de teste,
configurado no Test action do scheme. Ele usa IDs e arquivos
temporários próprios, sem comprar nem limpar transações.

Com catálogo `en_US` e ponto decimal, a resposta bruta continha
`priceFormatted: "R$99.90"` e `priceString: "99,9"`; `displayPrice` mostrava
`R$99.90`, enquanto `price` era `99`. O plano mensal apresentou o mesmo padrão:
`R$49.90`, `49,9` e `49`. Com `pt_BR` e vírgula no campo numérico, ambos os campos
já vinham truncados. Portanto, não troque os valores do catálogo por vírgulas.
Essa diferença sugere um problema de serialização ou interpretação no ambiente
StoreKit de testes; não comprova um defeito da API de produção.

Resultados preservados fora do repositório:
`basic-label-storekit-retry-20261014.xcresult`,
`storekit-us-test-region-20261014.xcresult` e
`storekit-decimal-probes-v3-20261014.xcresult`.

O cadastro de produção foi conferido no App Store Connect: app `6771525885`,
Bundle ID `com.pedrosalles.smartkitchen.sync`. Não havia grupos ou produtos de
assinatura cadastrados. O grupo `Savoria Premium` (`22478308`) foi criado;
os dois produtos foram criados com os mesmos identificadores usados pelo app:

| Plano | ID Apple | Duração | Preço inicial no Brasil |
| --- | --- | --- | --- |
| `com.pedrosalles.smartkitchen.sync.premium.annual` | `6822917042` | 1 ano | R$ 99,90 |
| `com.pedrosalles.smartkitchen.sync.premium.monthly` | `6822949625` | 1 mês | R$ 49,90 |

Após salvar cada preço, a tabela de preço inicial foi reaberta e os valores
brasileiros foram conferidos novamente. Os preços dos outros territórios foram
calculados automaticamente pela Apple a partir do preço brasileiro.
Ambos os produtos estão em **Preparar para envio**. Essa configuração não
significa que foram enviados para revisão, aprovados ou publicados, nem comprova
que `Product.products` já os retorna no ambiente Sandbox. A divergência de
centavos no SDK de testes local continua pendente, sem alterar as expectativas.
Em 15/10/2026, anual e mensal foram salvos no mesmo nível 1, pois oferecem o
mesmo serviço Premium. O grupo foi recarregado para conferir a persistência.
Disponibilidade, metadados localizados e envio para revisão não foram concluídos
nesta configuração dos preços.

Referências oficiais: [StoreKit Testing](https://developer.apple.com/documentation/storekittest/sktestsession)
e [Product.displayPrice](https://developer.apple.com/documentation/storekit/product/displayprice).

## Reteste de 29/10/2026 — storefront explícito

A suíte local completa terminou com 194 aprovados, 11 ignorados e um teste
reprovado: o catálogo brasileiro retornou USD 14,99 / 7,99. O arquivo fonte e
o catálogo empacotado continham os valores corretos e `_storefront: BRA`.

O teste agora fixa `SKTestSession.storefront = "BRA"` e `locale = pt_BR`,
restaurando os overrides anteriores ao terminar. A Apple documenta ambiente
compartilhado entre sessões e storefront padrão USA. Nenhuma transação é
comprada, excluída ou limpa. Os preços do app não foram alterados.

Em `storefront-explicit.xcresult`, moeda BRL e períodos passaram; os preços
numéricos retornaram **99 / 49**, mantendo a reprovação por centavos observada
em 14/10. Reutilizamos aquela investigação de serialização; não repetimos
consultas pagas ou diagnósticos equivalentes. Este reteste separa a região
incorreta do problema decimal, mas não comprova preços nem compras Sandbox.

Logs/resultados: pasta `Builds/Savoria-Nutrition-Final-20261028`, arquivos
`appstore-local-suite.xcresult`, `storefront-build.log` e
`storefront-explicit.xcresult`. SDK 27.1, iPhone 17 Pro virtual iOS 27.0.
[Documentação oficial de storefront](https://developer.apple.com/documentation/storekittest/sktestsession/storefront).
