# Widget do Assistente com teclado automático

O widget Assistente já usa `smartkitchen://assistant` nas famílias circular, retangular, inline e pequena. O problema estava no destino: a navegação do iOS abria a página, mas não solicitava foco ao campo persistente.

O destino agora navega até o Assistente e chama `SearchBarState.reveal(mode: .idle)`. O pedido fica em memória se chegar antes da montagem da tela; só é consumido após o splash, com o app ativo no iOS, e fora do onboarding/recuperação iCloud. Não altera stores, flags de sincronização ou preferências persistentes.

O foco recebe as duas tentativas limitadas já existentes (120 e 280 ms), inclusive se a barra já estiver visível. As tentativas são canceladas pelo mesmo controle de sessão ao dispensar o campo; não há polling ou timer contínuo. Uma barra remontada também honra o estado explícito de abertura. O widget SavorIA mantém seu destino de chat, com o mesmo mecanismo de foco.

No macOS, o link abre a página Assistente e expande/foca o campo nativo. Os links dos dois widgets preferem a janela existente, evitando criar outra janela em cada abertura. A conferência confirmou uma janela e digitação sem clicar no campo.

## Validação em 17/10/2026

- Builds Debug iOS e macOS, instalação e abertura preservando os dados, Team e capabilities iCloud.
- `testAssistantWidgetKeyboardOnColdLaunch`: abertura pelo URL exato e Bundle ID correto, teclado visível e digitação sem tocar no campo.
- `testAssistantWidgetKeyboardFromOtherPageAndBackground`: mesma verificação vindo de Receitas, com o app aberto e em segundo plano.
- Repetição da abertura a frio com o Simulator inicialmente bloqueado: aprovada. O XCTest faz a ativação/desbloqueio padrão do Simulator; isso não é prova de Face ID físico.
- Snapshots do Mac e verificação dos stores Private/Shared do Simulator sem alterações nos dados, identidades e hashes de mídias. O texto temporário `zx` foi apagado sem enviar mensagem; nenhuma inferência paga foi necessária.

Limite: a tentativa de adicionar e tocar o widget na galeria da tela bloqueada via Device Hub não foi concluída. A validação automatizada abre o mesmo URL no app contendo o widget, em vez de tocar a instância visual do WidgetKit. O iPhone físico não foi usado. Logs e capturas privados: `Coding/Builds/Savoria-E2E-20261012`, prefixo `widget-keyboard-`.

## Teste manual

1. Com a versão atualizada instalada, toque em Assistente abaixo do relógio na tela bloqueada e faça o desbloqueio normal do iOS.
2. Confira que Assistente aparece com o teclado virtual aberto; digite sem tocar no campo.
3. Repita após deixar o app em Receitas e após encerrar o app. Teste também o widget da tela inicial.
