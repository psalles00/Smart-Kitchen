# Capturas de iPad — Savoria

21 capturas nativas, três telas em cada um dos sete idiomas do app: listas com despensa/mercado, receitas com cadernos e nutrição. Dados de demonstração somente em memória; nenhum registro pessoal foi usado ou alterado.

- Dispositivo: iPad Pro 13-inch (M5), Simulator iOS 27.0.
- Dimensões: 2064×2752, PNG RGB sem alpha, aceitas no campo de iPad de 13 polegadas.
- Views originais renderizadas por UIKit/SwiftUI pelo teste `AdaptiveWorkspaceRenderingTests/testAppStoreDemonstrationCaptures`. Não se apresenta esse teste como prova de compra, hardware físico ou migração CloudKit.
- O processo e a janela usam o mesmo idioma: `-AppleLanguages`, `-AppleLocale`, `TestLanguage`/`TestRegion` e `SAVORIA_TEST_LOCALE` foram alinhados. A primeira captura parcial misturou idiomas e não foi enviada.
- Os três recursos escolhidos não exibem o botão de desenvolvimento da página inicial. As capturas da página inicial do build Debug não foram usadas.
- `review.png`: conjunto para revisão visual.
- `verification.json`: título esperado de cada tela, verificado por OCR local, e SHA-256 dos arquivos. O reconhecedor japonês recebeu a chave `ja` prevista pelo utilitário, sem alterar expectativas ou respostas.
- `manifest.json`: origem, dimensões, idiomas e correspondência entre os dez idiomas da loja e os sete idiomas de interface.
- Coreano, chinês simplificado e árabe herdam as três capturas em inglês pelo App Store Connect. As três descrições informam a ausência dessas traduções na interface.

Fonte de captura: produtos atuais em `Builds/Savoria-2-Simulator/Build/Products`, gerados por `build-for-testing`. O caminho antigo `Builds/Savoria-2-Simulator/Products` continha executáveis incompatíveis; não é usado. Os resultados finais estão em `Builds/Savoria-AppStore-20261029/SubmissionFinal/iPad-localized-<idioma>.xcresult`.
