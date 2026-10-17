# Recuperação do iCloud na tela de boas-vindas

## Comportamento

iOS e macOS oferecem **Já uso o Savoria**, separado de **Restaurar compras**.
O fluxo explica a necessidade da mesma Conta Apple e de dados previamente
sincronizados. Ele não chama a restauração de compras, não cria seleções de
despensa/mercado/receitas e não preenche novamente metas nutricionais.

Se já existe conteúdo local utilizável, o app permite abri-lo. Caso contrário,
confere a conta, preserva um checkpoint e ativa o método de sincronização já
existente. A importação é automática pelo SwiftData/CloudKit. A interface
consulta o container atual depois de sua troca, acompanha os primeiros dados
e mantém a ação **Abrir Savoria** explícita. O texto informa que a sincronização
pode continuar em segundo plano; os contadores são atualizados com os eventos
de importação. Uma espera sem registros não é apresentada como conta vazia.

O estado pendente sobrevive à recriação da interface e à reabertura do app.
Concluir a recuperação registra somente a escolha local de pular o onboarding;
não sobrescreve AppSettings ou NutritionProfile que ainda podem estar chegando.
As configurações já concluídas têm prioridade sobre configurações provisórias
na raiz da interface.

## Integridade

Os stores continuam em `<Application Support>/SmartKitchen/Private.store` e
`Shared.store`, com os mesmos schemas e configurações. O container explícito
continua `iCloud.com.pedrosalles.smartkitchen.sync`; a configuração automática
do store compartilhado e a ordem dos entitlements permanecem iguais.

Antes de ativar a sincronização, o app salva as alterações pendentes, confirma
as URLs reais e copia os stores, WAL/SHM, blobs externos, cache de mídia original
e preferências para um diretório privado e único em `iCloudRecoveryCheckpoints`.
Os dois bancos copiados precisam passar no `PRAGMA quick_check`. Checkpoints
não são podados nem restaurados automaticamente. Falhas interrompem a ativação;
cancelar o fluxo não desliga a sincronização nem reverte dados.

Instalações novas podem ter categorias padrão com UUIDs diferentes das
categorias recuperadas. Igualdade de nome não autoriza apagar esses registros:
a reconciliação automática de categorias agora considera somente UUIDs iguais.
Home, listas, seletores e receitas apresentam um rótulo por nome/tipo, mantendo
todos os IDs, ícones e posições nos stores e nos backups. A consulta completa
pelo backend continua incluindo os registros preservados.

## Verificação em 17/10/2026

- 82 testes locais passaram, incluindo troca de container, dados chegando em
  lotes, falha de conta, repetição, demora sem falsa conclusão, estado pendente
  após recriação e preservação de categorias com nomes iguais e UUIDs distintos.
- No Mac real, a opção foi acionada a partir da instalação após formatação,
  antes vazia. O iCloud trouxe os 111 itens e as 64 receitas existentes.
  Todos os IDs de itens/receitas foram conferidos contra uma cópia de leitura
  do iPhone 12 Pro. As 64 capas têm os mesmos hashes.
- Também foram conferidos os 691 ingredientes, 94 seções, 714 passos e 18
  mídias: IDs e metadados preservados; os 18 conteúdos de mídia têm os mesmos
  hashes. As 41 categorias originais mantiveram IDs, nomes, ícones e ordem.
- A importação também trouxe 28 categorias padrão locais da instalação nova.
  Seus registros são preservados e seus rótulos equivalentes são agrupados na
  interface, sem eliminar as categorias originais.
- **Abrir Savoria** entrou na interface principal do Mac sem o questionário.
  A confirmação local não alterou os modelos de configuração da conta.
- A primeira rodada de UI encontrou o botão durante sua animação de entrada,
  antes de estar utilizável. O teste foi ajustado para aguardar `isHittable`;
  essa rodada reprovada permanece separada dos resultados finais.
- A interface final passou no iPhone 17 Pro no Simulator nos sete idiomas,
  incluindo ida/volta da recuperação e retorno do segundo plano. A comparação
  final dos dois stores do Simulator confirmou todos os registros, IDs e hashes
  de blobs iguais ao baseline.
- As versões finais para Simulator, iPhone físico e macOS compilaram. O Mac
  atualizado foi instalado, assinado e reaberto sem onboarding; listas e receitas
  mantiveram exatamente o snapshot completo de 111 itens, 64 receitas e 69
  categorias preservadas. A interface apresenta cada rótulo equivalente uma vez.
- A versão final foi instalada no iPhone 12 Pro com o mesmo Bundle ID, Team,
  container iCloud e App Group. A cópia de leitura posterior passou no
  `quick_check` nos dois bancos e não apresentou registro original ausente ou
  campo original alterado, exceto o contador técnico de revisão ignorado.
- O teste adicional de interface no iPhone físico foi interrompido antes de
  executar por falta de autorização do XCTest (`Timed out while enabling
  automation mode`). Essa rodada não é contabilizada como aprovada.
- Nenhuma chamada de IA ou alteração de chaves/backend foi necessária.

## Teste manual

1. Em uma instalação na tela de boas-vindas, escolha **Já uso o Savoria** e
   **Buscar meus dados**, usando a mesma Conta Apple de um aparelho já sincronizado.
2. Confira o andamento, os dados disponíveis e **Abrir Savoria**. Reabra o app
   para verificar que o onboarding não retorna e que seus dados continuam acessíveis.
3. Sem dados sincronizados ou sem acesso à conta, confira a orientação e a
   possibilidade de tentar novamente, sem indicação falsa de recuperação concluída.

O Simulator valida a interface e os estados isolados. A recuperação real e os
efeitos de CloudKit exigem dispositivos Apple reais; não apagar dados ou desligar
a sincronização de um aparelho configurado para simular uma instalação nova.

## Referências Apple

- [Sincronização de modelos entre dispositivos](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)
- [Preservação de modelos entre execuções](https://developer.apple.com/documentation/swiftdata/preserving-your-apps-model-data-across-launches)
