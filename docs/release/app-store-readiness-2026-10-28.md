# Preparação para a App Store — 28/10/2026

**Estado: não comprovado como pronto para envio.** O objetivo permanece deixar
somente imagens, descrição e envio pendentes. Ainda existem pendências técnicas,
de privacidade e de validação externa. Este arquivo não substitui a aprovação da Apple.

## Candidato e proteção dos dados

- Candidato de código: `201a538b`; consentimento de IA: `6dee809b`; base anterior: `f65cc35f`.
- Bundle principal: `com.pedrosalles.smartkitchen.sync`; Team `44K57HQAP9`.
- Containers, nesta ordem: `iCloud.com.pedrosalles.smartkitchen.syn`,
  `iCloud.com.pedrosalles.smartkitchen.sync`.
- Não houve mudança de schema, store, URLs dos bancos, Team, capabilities ou migração.
- Os stores existentes continuam sendo `Application Support/SmartKitchen/Private.store`
  e `Shared.store`, segundo `CloudSyncService`.
- A versão atualizada foi instalada e aberta em `/Applications/Savoria.app` e no
  iPhone 17 Pro virtual. A tela inicial do Mac exibiu os dados existentes.
- O iPhone virtual abriu no onboarding. Os dois arquivos de store existem;
  existência/tamanho não provam conteúdo. Não foram restaurados nem alterados
  para contornar essa situação. Pedro confirmou que usa normalmente apenas o iPhone físico; o onboarding do simulador não comprova perda dos dados do aparelho.

## Matriz de requisitos e evidências

| Área | Evidência atual | Estado / próxima prova necessária |
| --- | --- | --- |
| 2.1 — app completo e estável | Builds Debug iOS/macOS passaram; evidências de funcionalidades em `docs/testing-*.md` | Confrontar cobertura com o candidato final, incluindo falhas de rede e permissões; não generalizar nove testes para o app inteiro |
| SDK, assinatura, Release e extensões | `project.yml` preserva identidade e zera chaves privadas dos provedores em Release | Gerar e inspecionar candidato Release atual; archive antigo de maio não serve como candidato |
| Depuração ausente em produção | Simulação Premium e credencial OpenRouter protegidas por `#if DEBUG` no código | Conferir o binário/interface Release, não apenas Debug |
| 5.1.2(i) — consentimento para IA externa | Gate local explícito em Supabase, OpenAI, OpenRouter e Exa; revogação nas Configurações; seis textos nos sete idiomas | Implementado; nove testes locais passaram e aviso nativo/recusa/receitas locais conferidos no Mac; interface iOS ainda precisa da conferência pertinente |
| 5.1.1 — política acessível e fiel | Links usados pelo app responderam HTTP 200 em 28/10 | Texto público ainda omite Supabase/OpenRouter e não explica suficientemente retenção/compartilhamento atual; atualizar com fatos verificados |
| Declaração de dados | Manifesto presente, sem tracking, com quatro categorias de Required Reason APIs | Manifesto lista somente Purchase History; confrontar conteúdo/fotos/áudio/dados nutricionais enviados à IA com retenção efetiva e corrigir declarações necessárias |
| Retenção dos provedores | Políticas oficiais OpenAI, OpenRouter e Exa localizadas | Não presumir zero retenção nem ausência de treinamento em todas as rotas; verificar configuração/contratos aplicáveis antes de prometer isso |
| Compras e restauração | StoreKit 2 observa transações, finaliza verificadas e oferece restore; catálogo local com dois IDs | Sandbox/TestFlight real, elegibilidade do trial, restauração, cancelamento e renovação ainda sem prova atual suficiente |
| Preços e grupo Premium | Relato anterior em `docs/testing-storekit-prices.md`: anual R$ 99,90, mensal R$ 49,90, ambos nível 1 | Cadastro atual não reconferido; não recriar produtos. Catálogo local não comprova produção |
| Saúde e precisão | App estima nutrientes e projeções; resultados de nutrição existentes | Promessa e comparação inventada corrigidas em `201a538b`; layout renderizado conferido. Demais alegações/fluxos ainda não recebem aprovação global por esse teste |
| Dados e iCloud | Stores/configuração preservados; evidências anteriores em `docs/testing-icloud-recovery.md` | Reutilizar provas compatíveis, separar do estado do simulador; nenhum teste destrutivo com dados de Pedro |
| Permissões e recursos do dispositivo | Descrições de câmera, fotos, microfone e fala presentes | Conferir strings localizadas e recusa; hardware real somente onde necessário |
| UGC/IA, conteúdo e direitos | Receitas locais, importação, IA e pesquisa externa são funções do app | Confirmar escopo público/privado, salvaguardas e direitos/atribuição do conteúdo usado |
| Metadados, faixa etária e privacidade ASC | Documentos locais históricos existem | Respostas atuais do ASC não comprovadas; classificação deve vir do questionário atual, não de recomendação antiga de 4+ |
| Contratos, impostos, banco, DSA e região | Nenhuma sessão ASC disponível nesta rodada | Verificação externa pendente; não aceitar contratos nem declarar dados comerciais por inferência |
| Imagens, descrição e envio | Exclusões expressas do objetivo | Permanecem fora da entrega técnica; não houve envio, compra ou publicação de build |

## Consentimento: validação concluída nesta rodada

`consent-final-tests.xcresult`, em
`/Volumes/PS-Externo/Coding/Builds/Savoria-Nutrition-Final-20261028/`:

- iPhone 17 Pro Simulator, iOS 27.0, build com SDK 27.1.
- **9 aprovados, 0 falhas, 0 ignorados**: cinco testes de consentimento e quatro
  testes existentes de fallback.
- Cobertura: sem janela não registra uma escolha; recusa não repete prompt;
  nova autorização explícita; revogação; decisão pendente não vence revogação;
  cancelamento não libera envio; conteúdo recusado não alcança provedor.
- Respostas de rede substituídas por fixtures locais. Nenhuma inferência paga,
  nenhum envio de foto/refeição real e nenhuma chamada nova de backend por este ajuste.
- Revisão independente encontrou duas traduções de botões ausentes; corrigidas.
  O revisor não identificou bypass nos gates examinados. Não executou a UI.
- Mac instalado: Configurações → Autorizar serviços de IA abriu NSAlert com
  destinatários/dados/recusa. Após “Agora não”, receitas locais continuaram visíveis.
  A recusa permanece no Mac; o usuário pode autorizar pelas Configurações.
- Manual restante: no iOS, conferir aviso, recusa e reautorização em instalação
  de validação com estado conhecido; conferir modo local sem enviar conteúdo real.

## Ordem das próximas ações independentes do ASC

1. Esclarecer o estado do iPhone virtual sem reset/restauração; usar fixture isolada
   se necessário para concluir UI iOS sem tocar nos dados existentes.
2. Corrigir política/declarações a partir do fluxo real e das condições dos provedores.
3. Revisar as demais alegações e fluxos de nutrição; a promessa do gráfico já foi corrigida e validada.
4. Finalizar archive/exportação de distribuição após as correções restantes. Builds Release, segredos e capabilities já foram conferidos; finalizar
   matriz funcional proporcional reaproveitando evidências válidas.
5. Retomar somente as verificações do ASC quando houver sessão disponível. Pedro
   pediu expressamente continuar primeiro tudo que independe desse acesso.

## Fontes oficiais consultadas

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/):
  1 (segurança), 2 (desempenho/completude), 3 (negócios/IAP), 4 (design),
  5 (privacidade e direitos); atenção a 1.4.1, 2.1, 3.1.2, 5.1.1 e 5.1.2(i).
- [Preparação para envio](https://developer.apple.com/app-store/submitting/).
- [Definição de coleta e Privacy Nutrition Labels](https://developer.apple.com/videos/play/wwdc2022/10167/).
- [Categorias do manifesto](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatype).
- [OpenAI: controles de dados](https://developers.openai.com/api/docs/guides/your-data).
- [OpenRouter: política](https://openrouter.ai/privacy) e
  [retenção dos provedores](https://openrouter.ai/docs/guides/privacy/provider-logging).
- [Exa: política](https://exa.ai/privacy-policy): diferencia site e processamento
  por conta de clientes empresariais; a página geral não comprova o contrato da API.


## Projeção e builds Release — segunda rodada de 28/10

- `GoalProjectionStepView` deixa de prometer a conquista da meta e de comparar
  curvas inventadas “com” e “sem” Savoria. A linha de referência permanece no
  peso atual informado; a outra é identificada como trajetória ilustrativa.
- Cabeçalho apresenta meta/prazo, com explicação de que o gráfico não é previsão
  nem garantia e orientação para consultar médico/nutricionista. Novos textos
  cobrem os sete idiomas. Nenhum dado nutricional é alterado por essa tela.
- O teste existente `testNativeOnboardingRecipeGridAndProjection` passou em
  fixture em memória no iPhone 17 Pro. A imagem `native-onboarding-goal-projection`
  foi conferida: explicação completa e botão Continuar acessível.
- Builds **Release iOS e macOS passaram**, logs `appstore-ios-release.log` e
  `appstore-mac-release.log` na mesma pasta de evidências. Chaves OpenAI,
  OpenRouter e Exa vazias nos dois Info.plist; marcadores verificados de debug
  ausentes dos executáveis. Identidade/Team/ordem de containers e App Group da
  ShareExtension iOS conferidos. Isso não substitui exportação/distribuição Apple.
- A cópia Release foi instalada em `/Applications/Savoria.app` com assinatura de
  desenvolvimento para validação local; verificação `codesign --deep --strict`
  passou. A interface abriu com os dados existentes e sem o botão de debug.
- A primeira cópia por mesclagem deixou duas bibliotecas de Debug no pacote.
  A comparação encontrou apenas essas sobras; foram movidas, sem exclusão, para
  `Builds/Savoria-Agent-Mac/InstallRecovery-20261028`. A assinatura instalada foi
  conferida após essa correção. São artefatos de build, sem bancos do usuário;
  retenção somente durante esta auditoria de lançamento.
- O consentimento no Mac permanece recusado após o teste anterior. A autorização
  pode ser concedida nas Configurações; não foi concedida em nome de Pedro.
