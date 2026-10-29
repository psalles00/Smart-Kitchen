# Preparação para a App Store — 28/10/2026

**Estado: não comprovado como pronto para envio.** O objetivo permanece deixar
somente imagens, descrição e envio pendentes. Ainda existem pendências técnicas,
de privacidade e de validação externa. Este arquivo não substitui a aprovação da Apple.

## Candidato e proteção dos dados

- Candidato de produção atual: `ac6c5da3` (inclui relatos de IA `978057a2`); candidato anterior `b3e9eeeb`; projeção: `201a538b`; consentimento de IA: `6dee809b`.
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
| 2.1 — app completo e estável | Builds Debug iOS/macOS passaram; evidências de funcionalidades em `docs/testing-*.md` | Suíte atual: 194 aprovados, 11 ignorados, 1 reprovado no catálogo StoreKit. Provas de hardware, permissões e provedores reais não decorrem dos mocks |
| SDK, assinatura, Release e extensões | `project.yml` preserva identidade e zera chaves privadas dos provedores em Release | Archive final de 29/10 e IPA 3.6.2 (3) exportado com Cloud Managed Apple Distribution; sem upload e sem envio à revisão |
| Depuração ausente em produção | Simulação Premium e credencial OpenRouter protegidas por `#if DEBUG` no código | Binários e interface Release conferidos; marcadores examinados de debug ausentes |
| 5.1.2(i) — consentimento para IA externa | Gate local explícito em Supabase, OpenAI, OpenRouter e Exa; revogação nas Configurações; seis textos nos sete idiomas | Implementado; nove testes locais passaram. Aviso/recusa conferidos no Mac Release e teste nativo atual de recusa passou no iPhone virtual, sem envio de conteúdo |
| 5.1.1 — política acessível e fiel | Links usados pelo app responderam HTTP 200 em 28/10 | Texto corrigido e publicado em 28/10; conteúdo atual e acesso sem login conferidos no endereço usado pelo app |
| Declaração de dados | Manifesto presente, sem tracking, com quatro categorias de Required Reason APIs | Manifesto com sete categorias, sem tracking; formulário ASC alinhado e publicado com autorização explícita em 29/10 |
| Retenção dos provedores | Políticas oficiais OpenAI, OpenRouter e Exa localizadas | Não presumir zero retenção nem ausência de treinamento em todas as rotas; verificar configuração/contratos aplicáveis antes de prometer isso |
| Compras e restauração | StoreKit 2 observa transações, finaliza verificadas e oferece restore; catálogo local com dois IDs | Sandbox/TestFlight real, elegibilidade do trial, restauração, cancelamento e renovação ainda sem prova atual suficiente |
| Preços e grupo Premium | Relato anterior em `docs/testing-storekit-prices.md`: anual R$ 99,90, mensal R$ 49,90, ambos nível 1 | ASC reconferido em 29/10: R$ 99,90/ano e R$ 49,90/mês, nível 1, sete idiomas, 175 países; catálogo local não comprova compra Sandbox |
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
- Atualização: aviso e recusa nativos iOS conferidos na terceira rodada abaixo;
  reautorização e revogação permanecem cobertas pelos testes locais do broker.
  Isso não substitui compras reais nem todas as verificações funcionais do app.

## Ordem das próximas ações independentes do ASC

1. Estado esclarecido por Pedro: uso normal no iPhone físico. Consentimento iOS
   conferido em fixture isolada, sem restauração ou alterações nos seus dados.
2. Política e manifesto corrigidos/publicados. Ainda separar transparência da
   verificação das condições/configurações efetivas dos provedores; não prometer ZDR.
3. Revisar as demais alegações e fluxos de nutrição; a promessa do gráfico já foi corrigida e validada.
4. Archive atual gerado e inspecionado em 29/10. Exportação de distribuição
   permanece pendente; não gerar outra candidata para repetir esta prova.
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


## Privacidade publicada — terceira rodada de 28/10

- Commit `b3e9eeeb`: manifesto e política refletem conteúdo/saúde/atividade,
  fotos, áudio e identificador das avaliações, além de compras. Categorias
  empacotadas: `PurchaseHistory`, `Health`, `Fitness`, `PhotosorVideos`,
  `AudioData`, `OtherUserContent`, `DeviceID`; finalidade AppFunctionality,
  sem tracking. Não se presume anonimização de texto ou mídia pessoal.
- O UUID de `FoodCache.vote` é pseudônimo e persistido com alimento/voto para
  deduplicação, conforme o código e o SQL existentes. Foi incluído também
  no aviso e nas sete traduções. Não houve nova coleta nem mudança do payload.
- Revisão independente identificou essa omissão na primeira candidata; após
  correção, aprovou o delta. Plist/JSON e diff foram conferidos.
- `privacy-native-ios.xcresult`: teste nativo de recusa **aprovado** no iPhone
  17 Pro, fixture em memória. O aviso foi observado pelo Device Hub e o botão
  “Agora não” acionado por automação. Permaneceram seis itens sintéticos e zero
  mensagens; nenhum conteúdo foi enviado a provedor. Capture Keyboard desligado.
- macOS Release instalado: aviso novo conferido, incluindo a frase do identificador;
  recusa mantida. A assinatura da cópia em `/Applications/Savoria.app` foi validada.
- Builds atualizadas `privacy-build.log`, `privacy-mac-release.log` e
  `privacy-ios-release.log` passaram. O manifesto empacotado no Release iOS
  foi lido e confrontado com as sete categorias esperadas.
- Política publicada: https://psalles00.github.io/Smart-Kitchen/privacy/
  respondeu HTTP 200, sem login; data 28/10, Supabase, OpenRouter, identificador,
  revogação e texto de retenção foram conferidos no conteúdo entregue e no Chrome.
  O endpoint legado de histórico de builds do Pages retornou um registro antigo;
  prevaleceu a prova do conteúdo público atual. Não foi disparado build extra.
- A política diferencia dados locais/iCloud de envios opcionais, esclarece que
  desinstalar não exclui iCloud, e fornece o caminho existente de exclusão e
  contato para pedidos sem exigir Premium. Nenhuma exclusão foi executada.
- O formulário App Privacy no ASC continua **pendente**. Esta publicação e o
  manifesto não preenchem o formulário nem comprovam condições contratuais ou
  configurações de retenção de todas as rotas. Não houve inferência paga nesta rodada.

## Archive e suíte final local — 29/10

- `appstore-local-suite.xcresult`: **206 testes: 194 aprovados, 11 ignorados,
  1 reprovado**. Falha única: `testBrazilSubscriptionCatalogueMatchesAnnualAndMonthlyPlans`.
  Não classificamos a suíte como aprovada. Testes optativos de inferência real,
  migração física e interação manual não foram habilitados. Nenhuma chamada
  paga foi feita nesta rodada; os testes de rede usam respostas locais.
- O reteste `storefront-explicit.xcresult` fixou Brasil explicitamente: moeda e
  períodos passaram, mas a API retornou 99 / 49. A diferença de centavos já
  documentada em 14/10 permanece. Expectativas 99,90 / 49,90 preservadas.
  Ver `docs/testing-storekit-prices.md`; Sandbox real continua pendente.
- `Builds/Savoria-AppStore-20261028/Savoria.xcarchive`: **ARCHIVE SUCCEEDED**,
  versão 3.6.2 (1), arm64, SDK iphoneos27.1, mínimo iOS 17.0.
  Fonte de produção `b3e9eeeb` (commits seguintes até `d86b64e1` só documentação).
- Principal, ShareExtension e Widgets passaram `codesign --verify --deep --strict`.
  Bundle/Team corretos; containers iCloud na ordem existente, App Groups do
  principal e ShareExtension preservados. Chaves OpenAI/OpenRouter/Exa vazias
  no Info.plist do archive; sete categorias de privacidade empacotadas.
- Assinado com **Apple Development**, sem certificado Apple Distribution local.
  Archive local válido não equivale a exportação App Store nem aceitação do
  servidor Apple. Não houve upload ou nova tentativa de login. Retenção: este
  único candidato até finalizar a auditoria/envio; reutilizar em vez de recriar.

## Limites da conclusão local

- A suíte atual aprovou renderização nativa das cinco páginas em fixture em
  memória, superfícies inferiores, onboarding/projeção e seções de receitas.
  Não houve alteração de listas, refeições ou mídia de Pedro nesses testes.
- Dos 11 ignorados: sete são consultas reais protegidas por reserva financeira,
  um exige snapshot físico de migração, um é diagnóstico decimal optativo e
  dois exigem interação manual. Consentimento e gesto têm provas separadas
  registradas acima; os skips não são contados como aprovação.
- Evidências anteriores compatíveis foram reaproveitadas em
  `docs/testing-assistant-variety.md`, `docs/testing-recipe-discovery.md` e
  `docs/testing-icloud-recovery.md`. Não repetimos inferências ou migrações
  somente para aumentar a contagem. Nenhuma prova como administrador de
  Supabase foi usada para afirmar que o caminho do cliente funciona.
- O assistente contém regras médicas explícitas em `AssistantChatManager` e
  `InlineChatView`: não diagnosticar/prescrever; não prometer resultado e
  encaminhar situações clínicas a profissional. Regras de prompt são defesa
  implementada, não prova de que o modelo sempre as cumpre.
- **Relatos de IA implementados e validados:** `978057a2` adiciona relato no
  nível da resposta, incluindo cartões e opções. A prévia começa sem anexar a
  resposta; envio depende do usuário no app de e-mail. Quatro testes locais
  passaram; interface nativa iOS/macOS e revisão independente aprovadas.
  Ver `docs/testing-ai-content-reporting.md`. Regras de segurança de prompt não
  são prova de que qualquer modelo sempre as cumprirá.
- Pedro confirmou em 29/10 os direitos comerciais das imagens/receitas e do
  conteúdo de terceiros. O comprovante Thiings adaptado foi anexado ao ASC;
  cobre somente ícones e conserva as limitações do fornecedor (incluindo
  receita anual de até US$ 200 mil e proibição de revenda avulsa). Não houve
  nova auditoria de elegibilidade financeira ou da conta Thiings. Retenção
  dos provedores não é demonstrada por build ou HTTP 200 da política.

## Fechamento atualizado — 29/10/2026

- Contrato Apple Developer LYL260 aceito com autorização expressa; acesso a
  certificados liberado. Xcode autenticado na equipe `44K57HQAP9`.
- IPA exportado **sem upload**, via Custom > App Store Connect > Export:
  `/Volumes/PS-Externo/Coding/Builds/Savoria-AppStore-20261029/Savoria-AppStore-3.6.2-3/Savoria.ipa`.
  64.091.821 bytes; SHA-256
  `530e3371c2c7ad3f7e68d28d5193f245df539d4f83112c582523a9ef7a0e37c6`.
  O Xcode incrementou o build de 1 para 3 porque informou que 1 não atendia ao
  registro existente. Archive fonte `ac6c5da3`; alterações posteriores de testes
  e documentação não mudam esse binário.
- Assinatura: Cloud Managed Apple Distribution, validade 20/05/2027. IPA e ZIP
  conferidos; principal e duas extensões são 3.6.2 (3), Team correto,
  `get-task-allow=false`. Entitlements reais extraídos do Mach-O principal
  mantêm os dois containers na ordem original e CloudKit Production.
  ShareExtension mantém App Group; Widgets preserva seu conjunto original.
  Perfis podem autorizar um conjunto maior de containers; a conferência do app
  usou os entitlements efetivamente assinados, não só a lista do perfil.
- Metadados ASC: versão 3.6.2 em preparação, lançamento manual, sem login de app
  exigido; contato autorizado, suporte público, copyright e comprovante de
  ícones anexados. Categorias, classificação 13+ global (exceções regionais),
  declaração de direitos e de não ser dispositivo médico salvas.
- App e planos disponíveis em todos os 175 países/regiões permitidos. Download
  gratuito; Premium anual/mensal mantém os preços brasileiros acima. Não foi
  habilitado o novo modelo de mensalidade com compromisso de 12 meses.
  Grupo e planos localizados nos sete idiomas. Nenhuma oferta introdutória
  está cadastrada; paywall de produção depende da oferta e elegibilidade
  retornadas pelo StoreKit, sem promessa fixa de trial.
- Privacidade: sete categorias publicadas após confirmação específica do
  proprietário. Política de 29/10 publicada e conferida na URL pública, com
  personalização e tratamento dos relatos voluntários; não promete retenção zero.
- Paywall: removida a alegação sem comprovação “4.3x mais rápido” em `ac6c5da3`,
  nos sete idiomas. Builds iOS e macOS passaram. Mac instalado e aberto em
  `/Applications/Savoria.app`; dados existentes visíveis, preços corretos e
  título novo conferidos. Simulador iPhone 17 Pro atualizado e aberto; não
  foi preenchida uma despensa fictícia nos stores reais do simulador.
- Material de revisão IAP: captura nativa 1206×2622 gerada em cena isolada,
  fixture em memória e catálogo local sem trial (igual ao cadastro ASC atual).
  Teste `testNativePaywallReviewLayoutWithoutWritingUserData` passou; nenhum
  toque em comprar/restaurar, nenhuma inferência de IA ou alteração nos dados
  reais. A captura é prova visual, **não comprova compra Sandbox**. A tentativa
  de anexar a captura macOS foi recusada por dimensões e não foi reaproveitada.
- Evidências atuais em `Builds/Savoria-Nutrition-Final-20261028/`; verificações
  do IPA em `Builds/Savoria-AppStore-20261029/package-verification.json`.

**Ainda pendente:** compra/restauração/renovação Sandbox real e reconciliação
com a falha decimal do catálogo local. A autenticação Sandbox depende do
proprietário. Imagens e descrição de marketing permanecem fora deste recorte.
Não houve upload de build nem envio para revisão; não declarar que o app está
100% pronto enquanto a prova de compras e as pendências acima não forem fechadas.
