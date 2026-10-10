# Savoria: refinamento visual de 10/10/2026

Estado parcial. Implementação em 90a873f0; builds aprovados e instalação física confirmada. Conferência visual e navegação da versão final pendentes, sem push desta atualização.

## Alterações

- Coluna iOS ocupa a largura disponível.
- Fundo mais escuro, campo compartilhado no iOS18+ e fade RGB de 0,55s, mantendo o relógio do shader. SwiftUI gerencia o fundo transparente do NavigationStack por containerBackground. iOS17 mantém campos locais com relógio comum e fade, sem animação redundante da raiz.
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

## Conferência pendente

1. Percorrer Home, Listas, Receitas, Nutrição e Buscar; conferir largura, fundo escuro e continuidade do campo com fade de cor.
2. Conferir título/menu, frases e kcal da Home; abrir Configurações e expandir/recolher o calendário de Nutrição.
3. Sair e voltar em cada página, confirmar conteúdo existente e ausência de bloqueio de toque. Depois validar no iPhone livre e fazer push do commit local, sem force push.
