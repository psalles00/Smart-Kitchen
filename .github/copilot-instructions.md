# Importante
- REGRA INEGOCIÁVEL: NUNCA realize mudanças que possam quebrar, sobrescrever, resetar ou tornar inacessíveis os dados do usuário. Proteção de dados > qualquer outro objetivo.
- SwiftData/CloudKit: JAMAIS remova a capability iCloud ou altere o layout de ModelContainer/ModelConfiguration (nome, URL ou divisão de stores) sem migração validada e backup real. Trocar configurações de store com CloudKit ativo torna dados antigos inacessíveis.
- Risco: Alterações em persistência, schemas, migrations e flags de sync exigem: 1) Identificação exata de stores/URLs; 2) Plano de backup/rollback; 3) Validação em device real (simulador não garante migração CloudKit).
- Recuperação: Se o app abrir "vazio" ou houver falha de persistência, PARE. Priorize a recuperação dos dados.
- Sempre busque a documentação oficial da SwiftUI e do Xcode pra entender o que fazer.
- NUNCA remova ou altere o "Team" em Signing & Capabilities dos Targets.
- NUNCA remova ou altere a Capability "App Groups" em SmartKitchenShareExtension.
- Se for necessário passar por cima de alguma das regras deste documento, o agente deve perguntar ao usuário e obter confirmação explícita ANTES de executar a ação. Isso é inegociável.

# Procedimento e Build
- Antes de editar: Leia containers, schemas e fluxos de bootstrap.
- Após finalizar: Valide a integridade dos dados e garanta a capability iCloud (Documents, CloudKit e container iCloud.com.pedrosalles.smartkitchen.sync).
- Build: Use o simulador iPhone 17 Pro. O app deve abrir automaticamente.
- Testes: Forneça uma lista de etapas para teste manual após implementar funções.

# Proteção de Dados iCloud/CloudKit
- Nunca alterar a ordem de `com.apple.developer.icloud-container-identifiers` no entitlements.
- Sempre verificar `git diff` após rodar `xcodegen generate`.
- Restaurar entitlements imediatamente se houver mudanças não intencionais.
- Confirmar manualmente o container correto antes de instalar builds.

# Tradução
- Sempre que adicionar ou modificar um texto, faça com que essas mudanças sejam traduzidas e aplicadas em todos os idiomas disponíveis no app.