# Extremamente importante
- Nunca, jamais, restaure uma versão antiga sem meu consentimento explícito. Se precisar restaurar, me avise e confirme comigo antes de executar a ação.
- NUNCA execute comandos destrutivos ou de reversão sem meu consentimento explícito no mesmo turno. Isso inclui `git reset --hard`, `git checkout --`, `git restore`, `git clean`, `git revert`, `rm -rf`, `xcrun simctl uninstall` e qualquer comando equivalente que descarte trabalho, reinstale uma versão antiga ou apague dados locais.
- Build quebrado, diff inesperado, árvore suja ou falha de ferramenta NUNCA são motivo para restaurar, resetar ou limpar automaticamente. Primeiro diagnostique a causa; se a única saída parecer destrutiva, pare e peça confirmação explícita.
- Se você aplicar uma mudança importante, deixe claro quando ela ainda estiver sem commit antes de qualquer validação que possa motivar rollback manual.

# Importante
- REGRA INEGOCIÁVEL: NUNCA realize mudanças que possam quebrar, sobrescrever, resetar ou tornar inacessíveis os dados do usuário. Proteção de dados > qualquer outro objetivo.
- SwiftData/CloudKit: JAMAIS remova a capability iCloud ou altere o layout de ModelContainer/ModelConfiguration (nome, URL ou divisão de stores) sem migração validada e backup real. Trocar configurações de store com CloudKit ativo torna dados antigos inacessíveis.
- Risco: Alterações em persistência, schemas, migrations e flags de sync exigem: 1) Identificação exata de stores/URLs; 2) Plano de backup/rollback; 3) Validação em device real (simulador não garante migração CloudKit).
- Recuperação: Se o app abrir "vazio" ou houver falha de persistência, PARE. Priorize a recuperação dos dados.
- Sempre busque a documentação oficial da SwiftUI e do Xcode pra entender o que fazer.
- NUNCA remova ou altere o "Team" em Signing & Capabilities dos Targets.
- NUNCA remova ou altere a Capability "App Groups" em SmartKitchenShareExtension.
- Se for necessário passar por cima de alguma das regras deste documento, o agente deve perguntar ao usuário e obter confirmação explícita ANTES de executar a ação. Isso é inegociável.
- Sempre que editar a versão de um app pra macOS, se restrinja a editar apenas essa versão. Não altere absolutamente nada da versão original do app, a menos que seja solicitado especificamente por isso.

# Procedimento e Build
- Antes de editar: Leia containers, schemas e fluxos de bootstrap.
- Após finalizar: Valide a integridade dos dados e garanta a capability iCloud (Documents, CloudKit e container iCloud.com.pedrosalles.smartkitchen.sync).
- Build: Use o simulador iPhone 17 Pro. O app deve abrir automaticamente.
- Cuidado com Bundle IDs ao rodar comandos no simulador: O Bundle ID CORRETO do app principal (Savoria) é `com.pedrosalles.smartkitchen.sync`. Existe uma versão antiga fantasma instalada com o bundle ID `com.pedrosalles.smartkitchen`. NUNCA use `com.pedrosalles.smartkitchen` nos comandos `xcrun simctl launch` ou `terminate`, pois isso abrirá a versão velha e estragará os testes do usuário!!
- Não use `git` como mecanismo de recuperação de build, validação ou troubleshooting.
- Nunca desinstale o app do simulador para “resolver” problemas sem minha confirmação explícita.
- Testes: Forneça uma lista de etapas para teste manual após implementar funções.

# Proteção de Dados iCloud/CloudKit
- Nunca alterar a ordem de `com.apple.developer.icloud-container-identifiers` no entitlements.
- Sempre verificar `git diff` após rodar `xcodegen generate`.
- Restaurar entitlements imediatamente se houver mudanças não intencionais.
- Confirmar manualmente o container correto antes de instalar builds.

# Tradução
- Sempre que adicionar ou modificar um texto, faça com que essas mudanças sejam traduzidas e aplicadas em todos os idiomas disponíveis no app.