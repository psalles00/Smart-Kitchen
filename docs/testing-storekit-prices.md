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

Referências oficiais: [StoreKit Testing](https://developer.apple.com/documentation/storekittest/sktestsession)
e [Product.displayPrice](https://developer.apple.com/documentation/storekit/product/displayprice).
