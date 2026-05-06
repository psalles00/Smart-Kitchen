# Checklist Manual Obrigatório — TestFlight e Publicação do Savoria

Este documento transforma a checklist manual de lançamento em um passo a passo para quem nunca publicou um app antes.

Objetivo: sair de um app funcionando localmente para um app testado no TestFlight e depois enviado corretamente para a App Store com assinaturas, páginas legais, testes e build de produção.

Importante: faça os passos na ordem. Se você pular etapas, o App Store Connect normalmente bloqueia o envio depois.

Fluxo recomendado para este projeto:

1. Compilar e testar localmente.
2. Enviar uma build para o App Store Connect.
3. Liberar primeiro no TestFlight para algumas pessoas testarem.
4. Corrigir o que aparecer.
5. Só depois enviar para revisão da App Store.

## 1. O que você precisa antes de começar

Você precisa ter isto em mãos:

- Uma conta ativa no Apple Developer Program.
- Acesso ao App Store Connect com permissão para criar apps e assinaturas.
- Xcode instalado no Mac.
- Este projeto abrindo e compilando localmente.
- Um lugar público para publicar duas páginas web: privacidade e termos.

Se alguma dessas peças ainda não existe, resolva isso antes de continuar.

## 2. Dados prontos deste projeto

Use estes valores exatamente como referência durante a configuração:

| Campo | Valor |
|---|---|
| Nome do app | Savoria |
| Bundle ID | `com.pedrosalles.smartkitchen.sync` |
| Scheme principal | `Savoria` |
| Team ID | `44K57HQAP9` |
| StoreKit local | `SmartKitchen/Resources/Configuration.storekit` |
| Privacy manifest | `SmartKitchen/Resources/PrivacyInfo.xcprivacy` |
| Arquivo de versão/build | `project.yml` |
| Assinatura anual | `com.pedrosalles.smartkitchen.sync.premium.annual` |
| Assinatura mensal | `com.pedrosalles.smartkitchen.sync.premium.monthly` |
| Preço anual | US$ 39,99 |
| Preço mensal | US$ 6,99 |
| Trial anual | 7 dias grátis |
| URL de privacidade esperada | `https://savoria.app/privacy` |
| URL de termos esperada | `https://savoria.app/terms` |

Arquivos úteis no repositório:

- `docs/legal/privacy-template.md`
- `docs/legal/terms-template.md`
- `SmartKitchen/Resources/PrivacyInfo.xcprivacy`
- `SmartKitchen/Resources/Configuration.storekit`
- `project.yml`

## 3. Publique as páginas legais primeiro

Antes de criar as assinaturas, publique as duas páginas legais do app. A Apple costuma exigir isso para revisão.

### Passo 3.1 — Ajuste os textos-base

Abra estes arquivos e substitua os placeholders:

1. `docs/legal/privacy-template.md`
2. `docs/legal/terms-template.md`

Você deve trocar pelo menos:

- O e-mail de suporte.
- A data da última atualização.
- Qualquer detalhe jurídico que ainda esteja como texto de exemplo.

### Passo 3.2 — Coloque esses textos em páginas públicas

Publique os dois documentos em URLs públicas, sem login.

Use exatamente este formato final:

1. `https://savoria.app/privacy`
2. `https://savoria.app/terms`

Pode ser no seu site, em um host estático ou em outro domínio seu. O importante é que a Apple consiga abrir o link sem autenticação.

### Passo 3.3 — Teste os links

Abra as duas URLs no navegador em janela anônima.

Resultado esperado:

- As páginas abrem normalmente.
- O conteúdo está legível no celular e no desktop.
- Não existe tela de login.

## 4. Deixe sua conta Apple pronta para vender assinaturas

Sem isso, o App Store Connect não libera compras dentro do app.

### Passo 4.1 — Entre no App Store Connect

Abra:

1. `https://appstoreconnect.apple.com`
2. Faça login com a conta que publica o app.

### Passo 4.2 — Resolva contratos, impostos e banco

No App Store Connect, procure a área de contratos, impostos e banco.

Você precisa:

1. Aceitar o contrato de apps pagos.
2. Preencher os dados bancários.
3. Preencher os dados fiscais.
4. Esperar tudo ficar com status ativo ou aprovado.

Resultado esperado:

- Você não vê mais nenhum aviso pendente para receber pagamentos.

## 5. Crie ou confira o registro do app

Se o app ainda não existe no App Store Connect, crie agora. Se já existe, apenas confira os dados.

### Passo 5.1 — Criar o app

No App Store Connect:

1. Vá em `My Apps`.
2. Clique no botão `+`.
3. Escolha `New App`.

### Passo 5.2 — Preencher os campos principais

Use estes dados:

1. Platform: `iOS`
2. Name: `Savoria`
3. Primary Language: escolha o idioma principal que você quer manter no App Store Connect
4. Bundle ID: `com.pedrosalles.smartkitchen.sync`
5. SKU: crie um identificador interno, por exemplo `savoria-ios-main`

Resultado esperado:

- O app aparece na lista de apps do App Store Connect.

## 6. Preencha a base da ficha do app

Agora preencha o básico da página do app na App Store.

### Passo 6.1 — Informações gerais

Na tela do app, preencha:

1. Descrição.
2. Keywords.
3. URL de suporte.
4. URL de marketing, se tiver.
5. Copyright.
6. Categoria.

### Passo 6.2 — Classificação etária

Configure a classificação etária.

Recomendação atual deste projeto:

1. Age Rating: `4+`

### Passo 6.3 — Screenshots

Prepare e envie screenshots reais do app.

Tamanhos mínimos que você deve cobrir:

1. iPhone 6.9"
2. iPhone 6.5"

Resultado esperado:

- A versão do app no App Store Connect não mostra erro por falta de metadados básicos.

## 7. Configure App Privacy com calma

Não responda esse questionário no chute. Use o que já está declarado no projeto como ponto de partida.

Arquivo de referência:

1. `SmartKitchen/Resources/PrivacyInfo.xcprivacy`

### Passo 7.1 — Abra App Privacy

Dentro do app no App Store Connect, abra a seção `App Privacy`.

### Passo 7.2 — Preencha a parte de monetização

Para a parte de compras, este projeto já declara:

1. `Purchase History`
2. Dados vinculados ao usuário: `Yes`
3. Tracking: `No`
4. Finalidade: `App Functionality`

### Passo 7.3 — Revise antes de salvar

Leia cada pergunta e confirme se a resposta bate com o comportamento real do app.

Resultado esperado:

- O App Store Connect não mostra pendência em `App Privacy`.

## 8. Crie as assinaturas

Esta é a etapa principal da monetização.

### Passo 8.1 — Criar um grupo de assinaturas

No App Store Connect, abra a área de monetização/assinaturas do app.

Crie um grupo de assinaturas para o Premium.

Sugestão de nome interno:

1. `Savoria Premium`

Observação importante:

- O arquivo local `SmartKitchen/Resources/Configuration.storekit` já possui um grupo de teste. Se o grupo criado no App Store Connect ficar diferente, ajuste depois o arquivo local para manter os testes coerentes com a produção.

### Passo 8.2 — Criar a assinatura anual

Crie a primeira assinatura com estes dados:

1. Product ID: `com.pedrosalles.smartkitchen.sync.premium.annual`
2. Reference Name: `Savoria Premium Annual`
3. Duração: `1 year`
4. Preço: equivalente ao tier de US$ 39,99

Depois configure a oferta introdutória:

1. Tipo: `Free Trial`
2. Duração: `7 days`
3. Elegibilidade: novos assinantes

### Passo 8.3 — Criar a assinatura mensal

Crie a segunda assinatura com estes dados:

1. Product ID: `com.pedrosalles.smartkitchen.sync.premium.monthly`
2. Reference Name: `Savoria Premium Monthly`
3. Duração: `1 month`
4. Preço: equivalente ao tier de US$ 6,99

### Passo 8.4 — Preencher metadados de cada assinatura

Para cada produto, você deve adicionar:

1. Display Name
2. Description
3. Localizações
4. Review Screenshot

Para o screenshot de revisão, use uma imagem simples do paywall ou da tela de plano, no tamanho aproximado de `640 x 920`.

### Passo 8.5 — Salvar tudo e revisar status

Resultado esperado:

- As duas assinaturas existem.
- Nenhuma delas está com campo obrigatório vazio.
- O App Store Connect não mostra erro de metadata nessas IAPs.

## 9. Crie um Sandbox Tester

Você precisa disso para testar compras reais da App Store antes de enviar o app.

### Passo 9.1 — Criar a conta de teste

No App Store Connect:

1. Vá em `Users and Access`.
2. Abra a aba `Sandbox` ou `Sandbox Testers`.
3. Clique em adicionar novo tester.

Preencha com um e-mail que nunca tenha sido usado como Apple ID real.

### Passo 9.2 — Guarde os dados com segurança

Anote:

1. E-mail do sandbox tester
2. Senha
3. País/região da conta

Resultado esperado:

- Você consegue usar essa conta depois em um iPhone real para testar assinaturas.

## 10. Teste a monetização antes de subir a build final

Faça testes locais e testes próximos do ambiente real.

### Passo 10.1 — Teste local no simulador

O projeto já tem StoreKit local:

1. `SmartKitchen/Resources/Configuration.storekit`

Use o simulador para validar o fluxo da interface:

1. Plano Free aparece corretamente.
2. Paywall abre nos bloqueios.
3. Compra simulada destrava recursos.
4. Restore funciona.

### Passo 10.2 — Teste em dispositivo real com sandbox

Use um iPhone real para validar o que depende da App Store de verdade.

Teste pelo menos:

1. Compra anual.
2. Compra mensal.
3. Restore Purchases.
4. Volta para Free após expiração ou cancelamento em sandbox.
5. iCloud Sync já ligado continua ligado mesmo se o usuário perder Premium.

### Passo 10.3 — Teste os bloqueios do plano Free

Confirme estes comportamentos:

1. IA: 2 usos por dia.
2. IA Nutricional: 2 usos por dia.
3. Importação de receitas: 3 por dia.
4. Fazer backup agora: Premium.
5. Backup automático diário: Premium.
6. Exportar backup: Premium.
7. Compartilhamento Familiar: Premium.
8. Ligar iCloud Sync pela primeira vez: Premium.

Resultado esperado:

- Os limites e bloqueios batem com a estratégia comercial do app.

## 11. Atualize versão e build com segurança

Esta etapa é crítica neste projeto porque `xcodegen generate` já causou problemas reais nos entitlements do iCloud.

### Passo 11.1 — Atualize a versão

Abra `project.yml` e ajuste:

1. `MARKETING_VERSION`
2. `CURRENT_PROJECT_VERSION`, se necessário

### Passo 11.2 — Faça backup dos entitlements antes do XcodeGen

Rode no Terminal:

```bash
cp SmartKitchen/SmartKitchen.entitlements /tmp/smk-entitlements-before.plist
```

### Passo 11.3 — Gere o projeto

Rode:

```bash
xcodegen generate
```

### Passo 11.4 — Confira se o XcodeGen não quebrou os entitlements

Rode:

```bash
git diff -- SmartKitchen/SmartKitchen.entitlements SmartKitchenShareExtension/SmartKitchenShareExtension.entitlements
```

Se houver qualquer mudança inesperada em `SmartKitchen/SmartKitchen.entitlements`, restaure imediatamente:

```bash
cp /tmp/smk-entitlements-before.plist SmartKitchen/SmartKitchen.entitlements
```

### Passo 11.5 — Verificação visual obrigatória

Confirme que a ordem do container iCloud continua assim:

1. `iCloud.com.pedrosalles.smartkitchen.syn`
2. `iCloud.com.pedrosalles.smartkitchen.sync`

Essa ordem importa neste projeto.

Resultado esperado:

- O arquivo de entitlements não foi zerado.
- O container correto continua sendo o primeiro.

## 12. Gere um Archive no Xcode

Agora você vai gerar a build que sobe para a Apple.

### Passo 12.1 — Abra o projeto no Xcode

Abra `SmartKitchen.xcodeproj`.

### Passo 12.2 — Escolha um destino de archive

No topo do Xcode:

1. Selecione o scheme `Savoria`.
2. Escolha `Any iOS Device (arm64)` ou um dispositivo físico compatível.

### Passo 12.3 — Criar o archive

No menu do Xcode:

1. `Product`
2. `Archive`

Espere abrir o Organizer.

Resultado esperado:

- O archive termina sem erro.
- O Organizer mostra a nova build.

## 13. Envie a build para o App Store Connect

Esta mesma build serve tanto para TestFlight quanto para a App Store. O caminho se separa só depois do upload.

No Organizer:

1. Selecione o archive recém-criado.
2. Clique em `Distribute App`.
3. Escolha `App Store Connect`.
4. Escolha `Upload`.
5. Continue com as opções padrão, a menos que você tenha motivo claro para mudar.

Depois do upload, espere o processamento do App Store Connect.

Resultado esperado:

- A build aparece no App Store Connect após o processamento.

## 14. Publique primeiro no TestFlight

Se você quer que algumas pessoas testem antes do lançamento oficial, este é o próximo passo.

O TestFlight é a plataforma da Apple para distribuir versões beta do app.

Existem dois tipos de teste:

1. `Internal Testing`: para pessoas da sua equipe dentro do App Store Connect.
2. `External Testing`: para usuários convidados fora da equipe.

Se você quer testar com alguns usuários reais, normalmente o que você quer é `External Testing`.

### Passo 14.1 — Entenda a diferença entre teste interno e externo

Use esta regra simples:

1. Se a pessoa já faz parte da equipe no App Store Connect, use `Internal Testing`.
2. Se a pessoa é um usuário convidado comum, use `External Testing`.

Diferença prática importante:

1. Teste interno não precisa de Beta App Review da Apple.
2. Teste externo precisa de aprovação de beta da Apple antes de liberar a build.

### Passo 14.2 — Liberar para teste interno

No App Store Connect:

1. Abra o app `Savoria`.
2. Abra a aba `TestFlight`.
3. Espere a build enviada aparecer e terminar de processar.
4. Vá para a área de `Internal Testing`.
5. Adicione os usuários internos que vão testar.
6. Associe a build mais recente a esses testers.

No iPhone de cada tester interno:

1. Instale o app `TestFlight` pela App Store.
2. Aceite o convite.
3. Instale a build beta do Savoria.

Resultado esperado:

- Os membros da equipe conseguem instalar o app beta sem esperar revisão beta da Apple.

### Passo 14.3 — Liberar para teste externo

Se você quer chamar alguns usuários reais, faça isso.

No App Store Connect:

1. Abra o app `Savoria`.
2. Abra a aba `TestFlight`.
3. Crie um grupo de testers externos, por exemplo `Beta Inicial`.
4. Adicione os e-mails dos testers ou prepare um link público.
5. Selecione a build que será testada.

### Passo 14.4 — Preencha os dados exigidos para Beta App Review

Para `External Testing`, a Apple normalmente pede algumas informações antes de aprovar a build beta.

Preencha com cuidado:

1. Nome da pessoa de contato.
2. E-mail.
3. Telefone.
4. O que deve ser testado.
5. Instruções para usar o app.
6. Se necessário, credenciais ou observações para testar assinatura.

Exemplo de texto útil em `What to Test`:

`Testar onboarding, paywall, compra via TestFlight, limites do plano Free, importação de receitas e tela de backup.`

Observação importante:

1. Compras feitas em build do TestFlight usam ambiente de teste.
2. O usuário não é cobrado de verdade.
3. Isso é ideal para validar o fluxo de assinatura antes do lançamento oficial.

### Passo 14.5 — Envie a build para Beta App Review

Ainda no TestFlight:

1. Clique para enviar a build para revisão beta.
2. Aguarde a Apple aprovar a build para testers externos.

Resultado esperado:

- A build fica disponível para os usuários externos convidados.

### Passo 14.6 — Convide os testers e acompanhe o uso

Depois que a build beta for aprovada:

1. Envie os convites por e-mail ou compartilhe o link público.
2. Peça para os testers instalarem o app `TestFlight`.
3. Peça que instalem a build do Savoria.
4. Reúna feedback por mensagem, formulário ou e-mail.

Peça que eles testem pelo menos:

1. Fluxo de onboarding.
2. Compra e restore de assinatura.
3. Limites do modo Free.
4. Importação de receitas.
5. IA e IA Nutricional.
6. iCloud Sync e backup.

### Passo 14.7 — Saiba quando subir outra build

Se algum problema importante aparecer:

1. Corrija no código.
2. Aumente o build/versionamento se necessário.
3. Gere novo archive.
4. Faça novo upload.
5. Troque a build do grupo no TestFlight.

Observações úteis:

1. Builds do TestFlight expiram em 90 dias.
2. Você pode repetir esse ciclo quantas vezes precisar antes da App Store.

### Passo 14.8 — Decida quando sair do TestFlight e ir para a App Store

Você deve avançar para a App Store apenas quando:

1. O app estiver estável.
2. O paywall e as assinaturas estiverem funcionando.
3. Os testers não estiverem mais encontrando bugs críticos.
4. Os textos e metadados finais estiverem prontos.

## 15. Monte a versão que será enviada para revisão na App Store

Agora você vai associar a build e as assinaturas à versão do app.

### Passo 15.1 — Crie ou abra a versão

Dentro do app no App Store Connect:

1. Abra a aba da versão iOS.
2. Crie uma nova versão, se necessário.

### Passo 15.2 — Selecione a build processada

Escolha a build que acabou de ser enviada.

### Passo 15.3 — Associe as assinaturas

Na mesma tela da versão, adicione as IAPs/subscriptions relacionadas para revisão junto com o app.

Se você esquecer isso, a Apple pode revisar o app sem revisar as assinaturas.

### Passo 15.4 — Preencha App Review Information

Inclua:

1. Nome da pessoa de contato.
2. E-mail.
3. Telefone.
4. Instruções curtas para a Apple testar o paywall.
5. Credenciais de sandbox, se a Apple precisar testar compras.

Exemplo de instrução útil:

`Abra Settings > Plano, toque em Premium e faça a compra com a conta sandbox informada.`

Resultado esperado:

- A versão não mostra campos obrigatórios faltando.

## 16. Envie para revisão da App Store

Quando tudo estiver verde:

1. Clique em `Submit for Review`.
2. Responda o questionário final da Apple.
3. Confirme o envio.

Resultado esperado:

- A versão fica com status semelhante a `Waiting For Review` ou equivalente.

## 17. Checklist final de confirmação

Antes de considerar a tarefa concluída, confirme item por item:

1. As páginas `privacy` e `terms` estão públicas.
2. Paid Applications Agreement foi aceito.
3. Banco e impostos estão ativos.
4. O app `Savoria` existe no App Store Connect com bundle ID correto.
5. `App Privacy` foi preenchido.
6. Screenshots foram enviados.
7. As duas assinaturas existem com IDs corretos.
8. O plano anual tem trial de 7 dias.
9. Existe um sandbox tester funcional.
10. O paywall foi testado no simulador.
11. A compra foi testada em sandbox.
12. Pelo menos uma build foi distribuída no TestFlight.
13. Testers internos ou externos conseguiram instalar a build.
14. O feedback do TestFlight foi revisado.
15. `project.yml` foi atualizado com a nova versão.
16. Os entitlements foram conferidos após `xcodegen generate`.
17. A build foi arquivada e enviada.
18. A build correta foi anexada à versão.
19. As assinaturas foram anexadas à revisão.
20. A versão foi enviada para review.

## 18. Problemas comuns e como reconhecer

### Problema: não consigo criar assinatura

Causa mais comum:

1. Contratos, banco ou impostos ainda não estão ativos.

### Problema: a assinatura existe, mas não aparece para anexar na versão

Causas comuns:

1. Faltam metadados obrigatórios na assinatura.
2. A assinatura não foi salva corretamente.
3. Você ainda não selecionou a build da versão.

### Problema: depois do `xcodegen generate` o app abre sem dados

Causa mais comum:

1. O arquivo `SmartKitchen.entitlements` foi alterado ou zerado.

O que fazer:

1. Restaurar o backup do entitlements.
2. Recompilar.
3. Instalar a build por cima.
4. Não desinstalar o app para tentar resolver.

### Problema: funciona no simulador, mas a compra falha no iPhone

Causas comuns:

1. Você está testando sem sandbox tester.
2. A conta sandbox não está configurada corretamente.
3. A IAP ainda não está pronta no App Store Connect.

### Problema: a build aparece no App Store Connect, mas não no TestFlight

Causas comuns:

1. A build ainda está processando.
2. Faltam respostas de compliance no App Store Connect.
3. A build ainda não foi associada a testers ou a um grupo de teste.

### Problema: testers externos não conseguem instalar

Causas comuns:

1. A build ainda não foi aprovada no Beta App Review.
2. O convite não foi aceito.
3. O usuário não instalou o app `TestFlight`.
4. O limite do grupo ou do link público foi atingido.

## 19. Resultado final esperado

Quando este documento estiver concluído do começo ao fim, você terá:

1. O app registrado no App Store Connect.
2. As assinaturas criadas corretamente.
3. Páginas legais públicas.
4. Testes locais e sandbox concluídos.
5. Uma build validada no TestFlight com usuários reais ou equipe interna.
6. Uma build enviada para a Apple.
7. Uma versão pronta para revisão.