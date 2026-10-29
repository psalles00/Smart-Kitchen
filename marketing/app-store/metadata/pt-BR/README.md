# Metadados da App Store — Savoria / pt-BR

Preparados em 29/10/2026, salvos e conferidos no App Store Connect. A submissão completa à revisão ainda depende das capturas de iPad; acompanhar `docs/release/app-store-submission-2026-10-29.md`.

- `description.txt`: texto simples para o campo Descrição.
- `metadata.json`: proposta de nome, subtítulo, texto promocional e palavras-chave.

## Estratégia de ASO

O nome cobre receitas e calorias; o subtítulo acrescenta despensa, compras e nutrição sem repetir os termos principais. O campo de palavras-chave complementa essas intenções com contador, alimentação, macros, proteína, cardápio, cozinhar, ingredientes, refeições e peso. Todos se relacionam a recursos existentes. Não foram utilizados dados pagos de volume ou concorrência; a seleção é uma hipótese por relevância, sem promessa de posicionamento. Antes de aplicar, deduplicar também contra a categoria principal efetivamente selecionada no App Store Connect.

A descrição foca conversão e leitura, com termos naturais. A abertura e o texto promocional apresentam o Savoria como gerenciador inteligente de cozinha, resumindo despensa, compras conectadas, receitas com IA, importação das redes sociais e calorias por foto/texto/voz com incentivo ao uso diário e continuidade quando houver esquecimentos pontuais. A mensagem incentiva registros cotidianos, sem sugerir uso apenas quando houver vontade: esquecimentos pontuais não apagam o histórico, e dias em branco não entram como zero. Depois desse resumo, o diferencial das médias inteligentes aparece primeiro; o fluxo automático despensa/mercado antecede as ideias com os ingredientes disponíveis, acompanhando a narrativa das imagens. Não há preços regionais, avaliações inventadas, garantia de emagrecimento nem alegação de precisão nutricional absoluta.

O texto diferencia média de dias registrados de registro real de dias em branco. Explica a etapa opcional “Para depois”, a revisão de estimativas e as condições da importação. Inclui referências a receitas, porções, cadernos, favoritos, preparo, IA, registros por foto/texto/voz, macros, peso, validades, ações em lote, compartilhamento, widgets e iCloud no iPhone, iPad e Mac.

## Evidências do produto

- `SmartKitchen/Services/Nutrition/NutritionAveragesService.swift`: médias de dias registrados/comparáveis.
- `SmartKitchen/Views/Onboarding/OnboardingStep.swift`: pilares e diferenciais apresentados no app.
- `SmartKitchen/Services/RecipeImport/Pipelines/SocialURLPipeline.swift`: importação de redes sociais.
- `SmartKitchen/Views/Recipes/CookingModeView.swift` e `RecipeDetailView.swift`: preparo e porções.
- `SmartKitchen/Services/NotificationService.swift`: notificações de validade.
- `SmartKitchenWidgets/AssistantWidget.swift`: acesso ao assistente por widget.
- Imagens já revisadas: `marketing/app-store/2026-10-29-localized/pt-BR/copy.md`.

## Referências consultadas

- [Apple — App Store search](https://developer.apple.com/app-store/search/): relevância textual em nome, subtítulo, palavras-chave e categoria principal; outros sinais incluem downloads, avaliações e resenhas.
- [Apple — Product page](https://developer.apple.com/app-store/product-page/): benefícios claros e descrição legível; evitar palavras-chave desnecessárias e preços específicos.
- [Apple — Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/): descrição até 4.000 caracteres, promoção até 170 e palavras-chave até 100 bytes, com termos maiores que dois caracteres.
- [Skill App Store Optimization](https://github.com/dpearson2699/swift-ios-skills/blob/main/skills/app-store-optimization/SKILL.md): estrutura de conversão e distribuição dos termos entre os campos.
- Skill local: `/Users/pedrosalles/.agents/skills/axiom-shipping/SKILL.md`.

Próxima avaliação de desempenho, após publicação autorizada: comparar impressões, visitas e downloads no App Analytics. Este pedido não inclui publicação, experimento ou alteração da categoria.
