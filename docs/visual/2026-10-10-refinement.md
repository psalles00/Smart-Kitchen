# Savoria: refinamento visual de 10/10/2026

Refinamento em90a873f0 com correção posterior do shader oculto. Builds e instalação nos dois destinos aprovados; shader conferido no iPhone12Pro e no iPhone17Pro simulado. Dois roteiros de navegação/foreground passaram. O A/B de performance física continua pendente.

## Alterações

- Coluna iOS ocupa a largura disponível.
- Fundo mais escuro, campos locais dentro dos hosts de página com relógio e paleta compartilhados, fade RGB de 0,55s e animação somente na página ativa. A raiz preta não executa shader oculto atrás do TabView. O containerBackground transparente da navegação não torna o host de abas transparente; desenhar apenas atrás dele ocultava o campo no iOS27.
- Borda de 0,75pt discreta, com topo clareado e paleta derivada do shader.
- Home usa frases de até três linhas e kcal restantes com ícone, sem círculo. Skeleton acompanha esse espaço.
- Título Savoria com 44pt e gradiente branco/cinza como Rotina; menu de duas cápsulas com área de toque de 46×44pt.
- Layout macOS preservado. Textos reutilizam traduções existentes nos sete idiomas.

## Evidências e limites

Artefatos: `/Volumes/PS-Externo/Coding/Builds/Savoria-Visual-20261010`.

Build final Debug por UDID do iPhone12Pro e Release do iPhone17Pro iOS27 passaram, logs native-container-device-build.log e native-container-build.log. Bundle com.pedrosalles.smartkitchen.sync, Team44K57HQAP9, containers syn/sync na ordem original, CloudKit/CloudDocuments, App Group da extensão e assinatura conferidos. Sem alterações de schemas, bootstrap, URLs relativas Private.store/Shared.store, capabilities ou sync. Cinco arquivos preexistentes mantidos byte a byte e fora do commit.

Instalação física confirmada em physical-install.json, sem desinstalar. Aparelho bloqueado no lockState; conteúdo físico ainda sem readback. A instalação substitui a antiga baseline d3d8a950, portanto o A/B físico anterior não foi concluído e não deve ser retomado supondo essa versão instalada.

Simulador recebeu o executável final, SHA256 37bc057a14d9ac229ae875b99ca9f0456e539b1f074a17618b22c53cb0328e36, igual ao produto Release. Container rotacionado pelo sistema, com contagens preservadas: cinco itens, duas receitas, um perfil e zero registros alimentares. Isso não substitui conferência física.

Dois roteiros da implementação intermediária falharam no calendário e Configurações. A intervenção experimental em UIViewController foi substituída pela API pública SwiftUI; não declarar a regressão corrigida sem reteste. Roteiros finais, lançamento direto e interação manual ficaram bloqueados nos serviços do simulador antes de validar o app. Também não houve resposta aos controles da própria tela inicial. Instalações interrompidas foram reconciliadas por hash e contagens, sem reinstalar versão antiga ou apagar dados. Disco interno oscilou até273MB e depois9,5GB; instalador foi amostrado aguardando registro LaunchServices, mas causalidade com espaço livre não foi provada. Somente o simulador próprio foi reiniciado, preservando dados; nenhum serviço global foi reiniciado, nem caches apagados.

## Roteiro manual complementar

1. Percorrer Home, Listas, Receitas, Nutrição e Buscar; conferir largura, fundo escuro e continuidade do campo com fade de cor.
2. Conferir título/menu, frases e kcal da Home; abrir Configurações e expandir/recolher o calendário de Nutrição.
3. Sair e voltar em cada página, confirmar conteúdo existente e ausência de bloqueio de toque. Esses fluxos passaram no simulador; esta revisão manual no físico complementa a conferência do shader feita no Device Hub.

## Correção do fundo ausente

Relato de Pedro em10/10 e screenshot `shader-before.png` confirmaram cabeçalho preto sem shader. Configurações abriu/fechou pelo Device Hub nesta retomada, portanto o bloqueio de interação da rodada anterior não se reproduziu nesse controle. A supressão dos fundos locais foi removida; o campo agora é desenhado dentro do host visível, com o mesmo relógio, paleta e pausa em segundo plano. Sem intervenção nos ancestrais UIKit.

Build Debug físico e Release simulador passaram (`shader-device-build.log`, `shader-sim-build.log`). Assinatura/capabilities conferidas (`shader-signing.json`) e instalação física confirmada (`shader-device-install.json`) preservando o app. Após Pedro confirmar desbloqueio, launch físico confirmou sucesso (`shader-device-launch.json`); Device Hub mostrou Nutrição verde e Home vermelha, com cabeçalho, coluna, título/menu e dados anteriores visíveis. Navegação física adicional por CUA não foi confiável; não inferir testes de toque completos nessa plataforma.

O instalador do simulador inicialmente ficou na ponte host_support com installd ocioso. Reiniciar somente CoreSimulatorBridge do UUID997 recuperou a leitura. A operação avançou e aguardou container_disk_usage; reiniciar somente containermanagerd em modo agent do mesmo UUID concluiu a instalação com exit0. Não houve reinício de serviço global, apagamento ou modificação de stores. Amostras preservadas no diretório de artefatos.

Executável instalado confere com Release: SHA256 `34d1630a9c8b6577107222369961b1ce1e5f172cef350e98ab576aa01913c101`. Contagens antes/depois iguais: cinco itens, duas receitas, um perfil, zero registros (`shader-before-data.json`, `shader-after-data.json`). `shader-after-home.png` e attachments exportados de `shader-navigation.xcresult` mostram o campo no cabeçalho: Home vermelho, Listas azul, Receitas dourado e Nutrição verde. A captura de Buscar mostra o fundo neutro próprio desse fluxo. Os dois testes passaram com zero falhas: cinco abas em três ciclos, scroll, calendário, retorno do background, receita/detalhe e oito destinos de Configurações. Os 308,8s do XCTest incluem automação/espera; não são uma medida de latência de toque ou prova de ausência de hitches no aparelho físico.

Mudança restrita às camadas de fundo e remoção da flag de supressão. Relógio comum, fade RGB0,55s, limite20fps, isolamento em leaf, redução de movimento e pausa fora da aba ativa/background preservados. Schemas, bootstrap, URLs de stores, sincronização e assinatura não foram editados. Arquivos preexistentes preservados por hashes e excluídos do commit.
