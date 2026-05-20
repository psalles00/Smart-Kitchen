# TestFlight do Savoria - etapas restantes

Atualizado em: 2026-05-20.

Este guia parte do estado atual deste repositório depois da preparação local feita para a build `3.6.2 (1)`.

## 1\. O que ja esta pronto localmente

Valores confirmados:

| Item | Valor |
| --- | --- |
| App | Savoria |
| Scheme | `Savoria` |
| Bundle ID | `com.pedrosalles.smartkitchen.sync` |
| Team ID | `44K57HQAP9` |
| Versao | `3.6.2` |
| Build | `1` |
| Archive local | `build-savoria-release/Savoria-3.6.2-1.xcarchive` |

Comandos executados com sucesso:

```
xcodebuild -project SmartKitchen.xcodeproj -scheme Savoria -configuration Release -destination generic/platform=iOS build
xcodebuild -project SmartKitchen.xcodeproj -scheme Savoria -configuration Release -destination generic/platform=iOS -archivePath build-savoria-release/Savoria-3.6.2-1.xcarchive archive
```

O archive foi gerado com sucesso, mas ainda precisa ser enviado para o App Store Connect para aparecer no TestFlight.

## 2\. Antes de tentar subir

Abra o Xcode e confirme que voce esta logado:

1.  Abra o Xcode.
2.  Va em `Xcode > Settings... > Accounts`.
3.  Confirme que a sua conta Apple Developer aparece ali.
4.  Se aparecer algum aviso de certificado, aceite a correcao automatica do Xcode.

Se o Xcode pedir senha, sessao Apple ID ou permissao de chaveiro, aceite. Isso e normal na primeira distribuicao.

## 3\. Enviar o archive para o App Store Connect

Use o Organizer do Xcode:

1.  Abra `SmartKitchen.xcodeproj`.
2.  No menu, va em `Window > Organizer`.
3.  Abra a aba `Archives`.
4.  Selecione o archive `Savoria 3.6.2 (1)`.
5.  Clique em `Distribute App`.
6.  Escolha `App Store Connect`.
7.  Escolha `Upload`.
8.  Mantenha as opcoes padrao, a menos que o Xcode mostre uma correcao automatica de signing.
9.  Clique em `Upload` no final.

Resultado esperado:

1.  O upload termina sem erro.
2.  O App Store Connect processa a build.
3.  Depois de alguns minutos, a build aparece na aba `TestFlight`.

Se aparecer erro de signing, o problema mais provavel e certificado/perfil de distribuicao. Nesse caso, volte em `Xcode > Settings... > Accounts`, selecione o time `44K57HQAP9`, e tente `Download Manual Profiles` ou deixe o Xcode gerenciar automaticamente.

## 4\. Criar ou conferir o app no App Store Connect

No navegador:

1.  Abra `https://appstoreconnect.apple.com`.
2.  Entre com a conta Apple Developer.
3.  Clique em `My Apps`.
4.  Procure `Savoria`.

Se o app ainda nao existir:

1.  Clique no botao `+`.
2.  Escolha `New App`.
3.  Preencha:
    *   Platform: `iOS`
    *   Name: `Savoria`
    *   Primary Language: o idioma principal desejado
    *   Bundle ID: `com.pedrosalles.smartkitchen.sync`
    *   SKU: `savoria-ios-main`
4.  Salve.

## 5\. Resolver pendencias que bloqueiam TestFlight

Antes de liberar a build, confira estas areas no App Store Connect:

1.  `Agreements, Tax, and Banking`: contratos, impostos e banco precisam estar sem pendencias se o app tiver assinaturas.
2.  `App Privacy`: responda o questionario de privacidade.
3.  `TestFlight > Builds`: espere o processamento da build terminar.
4.  `Compliance`: se a Apple perguntar sobre criptografia/export compliance, use como referencia que o projeto declara `ITSAppUsesNonExemptEncryption = false`.

Para privacidade, use como ponto de partida:

1.  `SmartKitchen/Resources/PrivacyInfo.xcprivacy`
2.  Historico de compra: coletado, vinculado ao usuario, sem tracking, finalidade `App Functionality`.
3.  APIs declaradas: UserDefaults, file timestamp, system boot time e disk space.

## 6\. Liberar para testers internos

Use teste interno primeiro, porque normalmente e o caminho mais rapido.

1.  No App Store Connect, abra `Savoria`.
2.  Va em `TestFlight`.
3.  Espere a build `3.6.2 (1)` aparecer como processada.
4.  Va em `Internal Testing`.
5.  Crie ou escolha um grupo interno.
6.  Adicione usuarios que ja fazem parte da equipe no App Store Connect.
7.  Associe a build `3.6.2 (1)` ao grupo.

No iPhone do tester:

1.  Instale o app `TestFlight` pela App Store.
2.  Abra o convite recebido por email.
3.  Toque em `Accept`.
4.  Instale o Savoria pelo TestFlight.

## 7\. Liberar para testers externos

Use este caminho para pessoas que nao estao na equipe Apple Developer.

1.  No App Store Connect, abra `Savoria`.
2.  Va em `TestFlight`.
3.  Em `External Testing`, crie um grupo, por exemplo `Beta Inicial`.
4.  Adicione a build `3.6.2 (1)`.
5.  Preencha as informacoes de Beta App Review.
6.  Adicione emails de testers ou crie um link publico.
7.  Envie para revisao beta.

Texto sugerido para `What to Test`:

```
Testar onboarding, paywall, compra via TestFlight, restore de assinatura, limites do plano Free, importacao de receitas, IA nutricional, iCloud Sync e backup.
```

Observacoes:

1.  Testers externos podem exigir Beta App Review antes de receber acesso.
2.  Compras feitas em TestFlight usam ambiente de teste e nao cobram dinheiro real.
3.  A aprovacao de TestFlight nao e a mesma coisa que aprovacao para publicar na App Store.

## 8\. Testes minimos antes de chamar mais gente

Faca estes testes em um iPhone real:

1.  Abrir o app pela primeira vez.
2.  Concluir onboarding.
3.  Abrir paywall.
4.  Comprar plano anual em ambiente TestFlight.
5.  Comprar ou simular plano mensal, se disponivel.
6.  Usar `Restore Purchases`.
7.  Verificar limites do plano Free.
8.  Testar importacao de receita.
9.  Testar camera/galeria/microfone.
10.  Testar iCloud Sync e backup.

Se algo quebrar:

1.  Corrija no codigo.
2.  Aumente `CURRENT_PROJECT_VERSION` de `1` para `2`.
3.  Gere novo archive.
4.  Faca novo upload.
5.  Troque a build do grupo no TestFlight.

## 9\. Referencias oficiais

1.  Upload de builds no App Store Connect: https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds
2.  Upload pelo Xcode: https://help.apple.com/xcode/mac/current/en.lproj/dev442d7f2ca.html
3.  Visao geral do TestFlight: https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/
4.  Testers externos: https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers