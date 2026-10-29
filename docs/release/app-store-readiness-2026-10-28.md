# Preparação para a App Store — fechamento em 29/10/2026

**Preparação técnica ainda pendente da investigação do valor decimal StoreKit.**
A conclusão anterior foi prematura: compra anual e restauração Sandbox não
explicam nem resolvem a falha numérica do teste local. Imagens, descrição,
upload/seleção e envio continuam fora do escopo autorizado. O pacote existe,
mas não deve ser apresentado como liberado tecnicamente sem resolver essa
falha ou comprovar e delimitar sua causa externa. Não houve upload ou revisão Apple.

## Pacote final

- Fonte de produção: `38d6034d8c407b50e716053ff02df1a60a715903`, incluindo
  compartilhamento `e658b95b`, relatos de IA `978057a2` e remoção da alegação
  de velocidade sem comprovação `ac6c5da3`.
- IPA: `/Volumes/PS-Externo/Coding/Builds/Savoria-AppStore-20261029/ManifestFinal/Export/Savoria.ipa`.
- Versão **3.6.2 (3)** nos três bundles; 64.155.941 bytes; SHA-256
  `64322f284bac26c04213fe3ebfecec68a13dbfabe60f408ea6a1c9fb0c079f42`.
- Archive e exportação App Store Connect passaram pelo Xcode 27.1, sem upload.
  Assinatura Cloud Managed Apple Distribution; Team `44K57HQAP9`;
  `get-task-allow=false` nos executáveis principal e das duas extensões.
- Bundle principal `com.pedrosalles.smartkitchen.sync`; containers assinados,
  nesta ordem: `iCloud.com.pedrosalles.smartkitchen.syn`,
  `iCloud.com.pedrosalles.smartkitchen.sync`; CloudKit **Production**.
- ShareExtension preserva `group.com.pedrosalles.smartkitchen.sync`.
  Widgets preserva seu conjunto original de permissões. Nenhuma mudança de
  schema, store, URLs, Team, capability ou migração foi necessária.
- Chaves privadas OpenAI, OpenRouter e Exa vazias no Info.plist final; nenhuma
  `.debug.dylib`; integridade ZIP conferida. Manifesto principal presente,
  sete categorias de dados, sem tracking. Extensão agora empacota seu próprio
  manifesto para UserDefaults do App Group, motivo Apple `1C8F.1`.
- Verificação extraída do IPA, incluindo entitlements reais dos Mach-O:
  `Builds/Savoria-AppStore-20261029/ManifestFinal/package-verification.json`.
  Os perfis podem autorizar mais containers do que o app efetivamente usa;
  não foram confundidos com os entitlements assinados do app.

## App Store Connect conferido e salvo

| Área | Resultado |
| --- | --- |
| Registro | App `6771525885`, versão 3.6.2 em Preparar para envio; lançamento manual; nenhum build enviado/selecionado |
| Identificação | Categorias Food & Drink / Health & Fitness, copyright 2026 Pedro Salles, suporte público e contato de revisão autorizado salvos; app não exige login |
| Classificação e direitos | Questionário atual: 13+ global, com exceções regionais; direitos comerciais confirmados por Pedro; declaração de não ser dispositivo médico |
| Contratos | Apple Developer LYL260 aceito com autorização; Paid Apps e banco ativos; informações fiscais Brasil e W-8BEN ativas; situação DSA existente conferida |
| Disponibilidade | App gratuito e dois planos em todos os 175 países/regiões permitidos pela Apple |
| Assinaturas | Grupo `22478308`, ambos nível 1; anual `6822917042` R$ 99,90/ano e mensal `6822949625` R$ 49,90/mês; sete idiomas; sem oferta introdutória cadastrada |
| Material IAP | Captura nativa 1206×2622 aceita e persistida para ambos os planos; mensal terminou o processamento. Fixture local sem trial, identificada como referência visual, não como prova de compra |
| Privacidade | Sete categorias publicadas com autorização específica; todas declaradas vinculadas, sem tracking; URL pública e finalidades conferidas |
| Comprovação | PDF adaptado do Rotina anexado uma vez ao contato de revisão; notas de revisão salvas |

As categorias publicadas são Health, Fitness, Other User Content, Photos or
Videos, Audio, Device ID e Purchase History. Saúde, atividade e conteúdo têm
App Functionality + Product Personalization; demais têm App Functionality.
A prévia resumida da Apple ainda mostrou Health também na coluna não vinculada,
embora os sete formulários detalhados salvos indiquem vinculados. Não foi
apresentada essa prévia contraditória como confirmação integral dos formulários.

O comprovante Thiings cobre ícones, não fotos, receitas, áudio ou fontes. Mantém
os limites do fornecedor (incluindo receita anual até US$ 200 mil e proibição
de revenda avulsa); não houve nova auditoria financeira da conta. Pedro confirmou
separadamente os demais direitos comerciais. O PDF contém dados privados de
faturamento e não integra o repositório público.

## Compra e restauração reais no Sandbox

- Apple mostrou o plano anual **R$ 99,90/ano** e informou que a operação era
  apenas para teste, sem cobrança. Pedro acionou Assinar.
- Confirmação fornecida pelo usuário: **Processo completo / Sua compra foi
  realizada com sucesso / [Environment: Sandbox]**. Isso foi uma compra no
  ambiente Apple; não foi o teste local SKTestSession nem uma simulação Premium.
- Mac instalado mostrou **Premium Anual** e renovação em 30/10/2026, compatível
  com calendário acelerado do Sandbox.
- Restaurar compras retornou **Sua assinatura já estava ativa**; captura
  `sandbox-restore-active.png`. Não houve segunda compra nem limpeza de histórico.
- O login Apple existente bastou nesse fluxo. Não foi exigido novo login de
  tester depois da confirmação, nem iniciada recuperação de senha.
- Esta prova cobre compra anual e restore da assinatura ativa. Não comprova
  uma renovação/cancelamento futuro observado nem uma compra mensal separada.
  Observação e finalização de transações verificadas usam StoreKit 2 existente.

## Validação funcional e limites

- Suíte ampla: `appstore-local-suite.xcresult`, **206 testes: 194 aprovados,
  11 ignorados, 1 reprovado**. O reteste Brasil explícito aprovou moeda e
  períodos, mas `Product.price` local retornou 99/49 em vez de 99,90/49,90.
  Não foram reduzidas as expectativas. A discrepância de serialização do
  ambiente local já foi investigada em 14/10; ver `docs/testing-storekit-prices.md`.
  Cadastro ASC e compra anual Apple a R$ 99,90 são provas separadas dos preços
  reais; não transformam esse teste local reprovado em aprovado.
- Skips: sete consultas reais protegidas por reserva financeira, um snapshot
  físico de migração, um diagnóstico decimal optativo e dois testes manuais.
  Não contam como sucesso. Nenhuma inferência paga nova nesta rodada.
- Consentimento IA: nove testes locais aprovados; gate explícito para serviços
  externos, recusa e revogação. Aviso e recusa renderizados/acionados no iOS e
  macOS; recusa não enviou conteúdo. Fixture em memória no simulador.
- Relatos voluntários de IA: quatro testes aprovados; UI nativa nas duas
  plataformas e revisão independente aprovadas. A prévia começa sem anexar
  resposta; usuário decide enviar pelo app de e-mail.
- Projeção nutricional deixou de prometer conquista da meta ou comparar curvas
  inventadas; interface nativa conferida. Regras médicas de prompt não garantem
  que qualquer modelo sempre as cumpra. Não promete diagnóstico ou prescrição.
- Compartilhamento: quatro testes aprovados; lista filtrada e ordem atual,
  receita com porções/ingredientes/preparo/fonte e referência ao Savoria.
  Copiar e menu nativo conferidos no Mac com dados reais do proprietário;
  receita e prévia renderizadas no iPhone 17 Pro com dados em memória.
  Nenhuma mensagem enviada nem dado do usuário alterado. Sete idiomas.
- Snapshot Mac antes/depois da instalação: **111 itens, 64 receitas,
  69 categorias**, hash de conteúdo idêntico. App Release instalado e aberto
  em `/Applications/Savoria.app`. iOS atualizado, instalado e aberto no
  iPhone 17 Pro virtual, preservando stores. O simulador está no onboarding;
  Pedro confirmou uso normal no aparelho físico, não foi inferida perda de dados.
- Provas compatíveis de IA/receitas/iCloud reaproveitadas em
  `docs/testing-assistant-variety.md`, `docs/testing-recipe-discovery.md` e
  `docs/testing-icloud-recovery.md`, sem repetir inferências/migrações por rotina.
  Não foi usado acesso administrador Supabase como prova do caminho do cliente.
- Não houve mudança de persistência que exigisse nova migração física. O
  hardware não foi usado para testes rotineiros desta entrega.
- Câmera, fotos, microfone e fala mantêm descrições de uso no IPA e sete
  localizações. Produção não inclui funções de debug. Builds iOS/macOS passaram.

## Privacidade, custos e entrega

Política pública de 29/10 e termos acessíveis pelo app foram conferidos sem
login; informações de consentimento, personalização, relatos e exclusão foram
alinhadas. Não se promete retenção zero/tratamento sem treinamento em todas as
rotas dos provedores sem confirmação contratual/configuração correspondente.

Compartilhar/copiar adiciona **zero chamadas remotas** para gerar a prévia:
listas fazem uma leitura local sob demanda; nenhuma escrita, polling, nova
inferência ou serviço foi ativado. Escolher um destino externo é ação posterior
do usuário. Orçamento de IA não foi ampliado ou consumido por esta entrega.

Evidências e screenshots: `Builds/Savoria-Nutrition-Final-20261028/`.
Teste manual de compartilhamento: `docs/testing-plain-text-sharing.md`.

**Fora deste fechamento:** imagens e texto comercial da loja (incluir links de
privacidade e Terms/EULA na descrição), upload/seleção do IPA e envio para
revisão. A Apple ainda realizará validação e revisão próprias. Nada foi enviado
para revisão nem lançado.

## Fontes oficiais

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).
- [Preparação para envio](https://developer.apple.com/app-store/submitting/).
- [Required Reason APIs e motivo UserDefaults App Group](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).
- [StoreKit Testing](https://developer.apple.com/documentation/storekittest/sktestsession).
- [Product.displayPrice](https://developer.apple.com/documentation/storekit/product/displayprice).
- [OpenAI: controles de dados](https://developers.openai.com/api/docs/guides/your-data).
- [OpenRouter: privacidade](https://openrouter.ai/privacy) e [retenção](https://openrouter.ai/docs/guides/privacy/provider-logging).
- [Exa: política](https://exa.ai/privacy-policy).

## Reabertura da ressalva — 29/10/2026

Após o questionamento de Pedro, o teste original foi repetido sem alterar
as expectativas. `decimal-current-runtime.xcresult`: reprovação confirmada
no iPhone 17 Pro / iOS 27.0, valores 99 e 49 em vez de 99,90 e 49,90.
O app exibe `Product.displayPrice`; não foi localizada conversão própria de
preços que explique a perda dos centavos. Isso delimita o sintoma, mas não
comprova sozinho defeito exclusivo da Apple.

A comparação no runtime 27.1 existente (Duo) não executou o teste: o simulador
ficou aguardando BackBoard; Xcode registrou `invalidDigitCount` para o build
do runtime. A tentativa foi interrompida e somente esse simulador, iniciado
para a comparação, foi desligado. Não houve reset, exclusão de dados, compra,
nova compilação ou alteração do código de produção. Resultado **inconclusivo**,
não contado como aprovação. Evidências `decimal-runtime-27-1.log` e resultado
correspondente na pasta de testes acima.

Não foi usado `XCTSkip`/`XCTExpectFailure`, preço inteiro como expectativa,
correção artificial do valor recebido, nem comparação somente da string para
transformar essa falha em sucesso. A discrepância permanece aberta.
