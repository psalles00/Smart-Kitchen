# NÃO altere capabilities automaticamente.
Nunca, JAMAIS, remova a capability "iCloud" do xCode.

# Após finalizar
Após finalizar uma tarefa que foi dada:
1. leia novamente o código alterado e se certifique que cada detalhe e cada linha estão bem escritos, estruturados, e livres de erro.
2. Caso identifique algum problema, corrija-o imediatamente.
3. Identifique se a capability "iCloud" está presente no projeto. Se não estiver, adicione-a imediatamente nos containers iOS, macoS, com os servicies ativados: iCloud Documents, e CloudKit ativado; e com os containers ativados: Containers "iCloud.com.pedrosalles.smartkitchen.syn".

# Build
Sempre que fizer qualquer modificação no código, dê build usando o simulador em iPhone 17 Pro.
O app deve abrir automaticamente usando o app compilado no simulador.

# Fluxo de Testes
Sempre após implementar funções novas, finalize provendo ao usuário, um fluxo (lista) de ideias/etapas pra que ele teste manualmente cada uma das etapas implementadas.