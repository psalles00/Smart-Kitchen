# Regras pra adicionar novos ícones
Pra todo ícone que eu solicitar a inclusão, busque o mesmo em '/Users/pedrosalles/Documents/Temas/3D Icons/size-128', e adicione na nossa plataforma: items_database, pasta de images-128, etc. Além disso, adicione sempre suas versões traduzidas, nomes alternativos, categorias, etc.


# NÃO altere capabilities automaticamente.
Regras rápidas:
- Nunca modificar diretamente sem revisão humana:
  - `project.yml`
  - `SmartKitchen/SmartKitchen.entitlements`
  - arquivos dentro de `SmartKitchen.xcodeproj`

- Se for necessário mudar uma capability (ex.: iCloud, Push, Background Modes):
  1) Abra uma *issue* explicando o motivo e os passos de provisioning.
  2) Abra um *pull request* com as mudanças em `project.yml` e/ou `SmartKitchen/SmartKitchen.entitlements` — inclua checklist (CI green, revisão humana, verificação de provisioning).

Permissões do agente (apenas leitura):
- Verificar e reportar se `project.yml` e `SmartKitchen/SmartKitchen.entitlements` contêm as chaves esperadas. Não editar.

Recomendação de proteção (humana/CI):
- Adicione um script de verificação e rode-o em pre-commit e CI; use proteção de branches e revisão obrigatória.

Por que: capabilities e entitlements impactam provisioning e distribuição; alterações automáticas podem quebrar builds ou bloquear releases.
