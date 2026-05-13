Passos exatos para publicar no TestFlight e App Store (resumido)

Antes de começar
- Tenha uma conta Apple Developer ativa.
- Tenha acesso ao App Store Connect (Admin ou App Manager).
- Tenha Xcode instalado e seu projeto abrindo localmente.

1) Publicar Privacy Policy e Terms
- Escreva páginas públicas: /privacy e /terms (ex.: https://savoria.app/privacy).
- Hospede em GitHub Pages, Vercel ou no seu domínio.
- No texto, seja explícito sobre: dados enviados a LLMs, Supabase, CloudKit, e como o usuário apaga dados.

2) Remover segredos do app (crítico)
- Não deixe chaves de API embarcadas no bundle (Info.plist / Secrets.xcconfig).
- Passo mínimo: remover chaves reais do repo e colocar placeholders.
- Ideal: criar um servidor proxy (Vercel/Heroku/Cloud Run) com as chaves e um endpoint que encaminha chamadas LLM.
  - Atualize `AIService` para usar o endpoint do seu servidor (sem chaves no app).

3) Corrigir falhas que podem travar o app
- Procure instâncias de `try!` e `fatalError(` no projeto (use Xcode Find ou `rg "try!|fatalError\(" -n`).
- Substitua por tratamento seguro: `do/catch`, `guard let` com fallback, ou exiba erro amigável ao usuário.
- Prioridade: `SmartKitchen/Services/CloudSyncService.swift` e `RecipeDetailView.swift`.

4) Legal + UX do Paywall
- No paywall e em Settings adicione links visíveis para Privacy e Terms.
- Inclua um texto curto sobre assinaturas e restauração de compras.

5) Corrigir AppIcon e assets
- Em Xcode abra `Assets.xcassets` > `AppIcon` e preencha todos os tamanhos obrigatórios.
- Verifique `Contents.json` para entradas ausentes.

6) Verificar entitlements e assinatura
- Em Xcode: Target > Signing & Capabilities:
  - Confirme iCloud containers corretos e App Groups.
  - Não altere o Team sem coordenação.

7) Atualizar versão e build
- Em Xcode: Target > General -> Version (ex: 1.0.0) e Build (incrementar).
- Cada upload ao App Store Connect precisa de `build` único.

8) Gerar Archive e enviar
- Método GUI (recomendado): Product > Archive → Organizer → Distribute App → App Store Connect → Upload.
- Aguarde processamento no App Store Connect (pode demorar alguns minutos).

9) TestFlight (testes antes da App Store)
- App Store Connect > My Apps > selecione app > TestFlight.
- Aguarde processamento do build e adicione Internal Testers primeiro.
- Teste em dispositivos reais: assinaturas (compra/restore), iCloud sync, widgets, share extension.
- Para testar compras localmente: use StoreKit sandbox ou StoreKit configuration em Xcode.

10) Preencher metadados do App Store
- Em App Store Connect preencha:
  - Nome, Subtitle, Description, Keywords, Support URL, Marketing URL.
  - Privacy Policy URL (obrigatório).
  - Screenshots (iPhone 6.7" obrigatório para iPhone-first apps). Gere em dispositivos reais ou Simulator.
  - Categoria, faixa etária e contato.

11) Submeter para revisão
- Em App Store Connect > Prepare for Submission: selecione o build processado, responda export compliance e outras perguntas.
- Clique em Submit for Review.
- Para TestFlight externo, aguarde a revisão beta.

12) Pós-submissão
- Monitore status e mensagens do App Review no App Store Connect.
- Se necessário, responda às solicitações de revisão rapidamente.

13) Checklist mínimo (marcar antes de enviar)
- [ ] Privacy Policy pública e URL configurada
- [ ] Segredos removidos do bundle
- [ ] `try!`/`fatalError` substituídos por fallback
- [ ] AppIcon completo
- [ ] Entitlements corretos (iCloud, App Groups)
- [ ] Build arquivado e enviado
- [ ] TestFlight interno funcionando (assinaturas testadas)
- [ ] Metadados e screenshots preenchidos
- [ ] Formulários de privacidade respondidos

Se quiser, eu posso:
- Gerar um exemplo de proxy server (Node.js) para proteger chaves.
- Criar as páginas de Privacy/Terms em GitHub Pages.
- Fazer o checklist item-a-item com commits e mudanças no repo.

Boa prática final: faça um commit antes de qualquer alteração grande e um backup do projeto.
