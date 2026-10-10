# Savoria: ações por página e retorno ao app

Estado atualizado em10/10: otimizações anteriores incluídas no build com refinamento visual 90a873f0 instalado no iPhone12Pro. Execução/conferência física e A/B continuam pendentes. Não há prova de ausência de microengasgos em todas as páginas.

**A baseline d3d8a950 foi substituída pela instalação solicitada dos novos ajustes visuais.** Não executar o roteiro abaixo supondo que ela ainda esteja instalada, nem reinstalar versão antiga. Os marcos seguintes descrevem o histórico de09/10. Nova captura deve medir a versão atual como referência para mudanças futuras, sem alegar A/B anterior completo. Ver [registro visual](../visual/2026-10-10-refinement.md).

## Referências e protocolo

Skill aplicada: `/Users/pedrosalles/.codex/skills/ios-action-tracing/SKILL.md`.
Apple: https://developer.apple.com/documentation/xcode/improving-app-responsiveness e https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance.

O scheme `SavoriaPerformance` executa `PageActionTracingTests.testPagesAndForeground` e `testSettingsAndForeground` em Release; Debug também pode ser comparado explicitamente. O roteiro percorre Home, Listas (Despensa, Mercado e Utensílios quando habilitado), Receitas e detalhe quando houver uma receita acessível, Nutrição/calendário, Buscar e os oito destinos de Ajustes, incluindo Gerenciar dados apenas para leitura. Faz três passagens pelas abas, rolagens, calendário e background/foreground. Não registra, edita, apaga, compra, chama IA ou adiciona fixtures ao banco. Destinos opcionais sem dados são pulados, o que deve aparecer na auditoria do resultado, não contar como cobertura efetiva.

`-SavoriaActionTrace` liga captura limitada com IDs e tempo monotônico. Frames são callbacks CADisplayLink do ciclo principal, não tempos de apresentação GPU. O início da troca é o handler da seleção, não o reconhecimento do toque. `hostActive` e `loaded` são fases SwiftUI, não comprovação de primeiro pixel visível. Há no máximo 256 eventos e 4096 amostras por lote, janela de cinco segundos após ação, interrupção ao sair do primeiro plano e gravação assíncrona após a interação em `Library/Caches/ActionTraces`. Apenas nomes de páginas/fases e medidas, sem textos de alimentos ou IDs de modelos.

No uso normal, os logs de desempenho, signposts adicionais e watchdog de 10 Hz ficam desligados. Erros continuam registrados. Os flags `-SavoriaPerformanceLogs` e `-PerfAutoTabSwitch` permitem diagnósticos explícitos. O autorun é Debug e usa seleção por estado; não é uma medida de latência de toque.

Para A/B: manter aparelho, configuração, dados, cache e script iguais. Separar primeira visita, visita já preparada, retorno curto e retorno após manutenção de cinco minutos. Instrumentação deve estar igual entre execuções. Não restaurar uma versão antiga ou apagar dados para obter uma baseline.

## Caminhos inspecionados

| Página | Caminho da ação | Trabalho e intervenção |
|---|---|---|
| Home | seleção → host permanente → HomeLiveInputsObserver → projeções em cache | Eliminar estado de diagnóstico e pré-montagens inúteis no uso normal. Preservar atualização no foreground para não ocultar mudanças remotas/data civil. |
| Listas | seleção → DeferredTabPage → queries → agrupamento/ordenação → List | Retirar espera fixa de 320 ms. Queries e ordenação ainda precisam de profiling com grande população. |
| Receitas | seleção → DeferredTabPage → queries → compatibilidade/projeções → imagens | Retirar espera de 80 ms; cancelar e impedir recálculos/prefetch/notebooks ocultos ou em background; reconciliar os inputs atuais na volta. |
| Nutrição | seleção → queries → dia/calendário → macros/estado | Retirar espera de 320 ms; indexar histórico uma vez por atualização, preservando ordem, primeiro log duplicado e dias civis/DST. |
| Buscar/Assistente | seleção → estado/busca → resultados/serviço → atualização | Roteiro de navegação e retorno preparado; sem chamadas pagas. Diagnósticos e estado extra de troca deixam de executar no uso normal. Latência de inferência não medida. |
| Ajustes e destinos | apresentação → Form/navigation → serviço correspondente | Oito destinos têm IDs estáveis e eventos individuais e passaram, inclusive Gerenciar dados apenas para leitura; nenhum toggle de sync, compra ou recuperação acionado. |

As abas visitadas continuam montadas, preservando navegação e evitando uma explosão de remontagem/queries ao retornar. A pré-montagem antiga apenas criava placeholders inativos, pois DeferredTabPage aguardava seleção ativa, sem preparar os dados; foi retirada. Leituras de tema/visibilidade do fundo iOS foram isoladas em ActivePageBackground, sem fazer o layout principal chamar novamente os builders de conteúdo apenas para atualizar o fundo. O visual e o shader permanecem os mesmos; ganho dessa separação ainda precisa de medida. Stores, schemas, CloudKit, Team e capabilities não foram alterados. Nenhum texto de produto foi adicionado.

## Evidência obtida

Baseline de instrumentação: commit d3d8a950, iPhone 12 Pro físico, iOS 27.0, Debug. Houve captura observada de Home e Listas; não foi o roteiro completo e controlado. Uma troca para Listas levou 565,24 ms de handler até `loaded`, 73,01 ms até `hostActive`. Houve callback do ciclo principal com intervalo máximo 262,34 ms nessa sequência (281 amostras); isso não prova hitch GPU nem atribui todo o tempo à espera de 320 ms. Não usar uma única ação como distribuição p50/p95 de trocas. Abertura também teve gaps maiores, ainda sem stacks válidos para atribuição.

Benchmark isolado Foundation otimizado no Mac: 2190 registros sintéticos, 365 logs, 63 consultas de datas e 11 leituras de dia selecionado por execução; 30 repetições alternadas, dois aquecimentos, checksum idêntico 75035. Baseline p50 122,08 ms / p95 124,54 ms / máximo 131,20 ms; índice p50 2,17 ms / p95 2,41 ms / máximo 2,43 ms. Inclui construir o índice, não apenas procurar nele. É custo do algoritmo, não latência da tela nem benchmark físico. A implementação compilada no app coincide byte a byte com a do benchmark. Verificações diretas de vazio/futuro, DST de 25 horas, limites de dias, ordem, precedência de log e reconstrução após edição/exclusão passaram. Os cinco DayHistoryIndexTests passaram no app Debug do simulador: vazio/futuro, DST/limites/ordem, precedência de logs, edição/exclusão e diagnóstico desligado sem formatar metadata. A suíte completa do projeto não foi repetida nesta etapa.

## Ambiente e limites

Artefatos completos em `/Volumes/PS-Externo/Coding/Builds/Savoria-Performance-20261009`: fontes/JSON do benchmark, captura física e resumo, logs de builds, tentativa Instruments e xcresult da tentativa de roteiro. Simulador próprio iPhone 17 Pro iOS 27.0: cinco itens, duas receitas e um perfil; não representa um histórico populado. Contagens obtidas somente por leitura SQLite. CloudKit desativado no simulador pela regra preexistente do projeto; não representa sincronização física.

Instruments/xctrace ficou bloqueado ao lançar/anexar no simulador, sem trace CPU/GPU válido. O runner de UI também não iniciou a execução dos casos em 270 segundos e foi interrompido, com xcresult preservado. Outro simulador próprio iOS 26.1 ficou aguardando System App; não houve reset, reinício do serviço, desinstalação ou limpeza. O Mac teve forte carga concorrente e disco interno variando aproximadamente entre 600 MB e 3 GB; um dSYM falhou por falta de espaço. Temporários próprios foram direcionados ao volume externo e os builds seguintes passaram. Não atribuir esses bloqueios ao código do app sem evidência.

O iPhone físico foi compilado/instalado com captura e abriu. A comparação controlada de todas as páginas aguarda Pedro deixar o aparelho livre, porque ele estava usando outro app. Não iniciar o roteiro automaticamente antes dessa confirmação. O custo do shader/GPU e das sombras ainda está em hipótese; seu visual foi preservado. Ainda não se pode afirmar que o app inteiro está livre de microengasgos.

## Teste manual quando o aparelho estiver livre

1. Percorrer todas as abas três vezes, alternando rapidamente e rolando para cima/baixo; conferir o conteúdo e a página selecionada.
2. Em Nutrição alternar dia, semana, calendário e hoje; em Receitas abrir detalhe e voltar; em Listas trocar subdivisões.
3. Em cada página sair para Home do iPhone e retornar; repetir um retorno após cinco minutos, conferir dados e navegação, capturar os mesmos flags/configuração antes/depois.

## Retomada sem instalar uma baseline antiga

O binário d3d8a950 instalado no iPhone foi mantido como baseline com captura. As otimizações foram compiladas separadamente; a instalação física deve ocorrer depois de capturar o roteiro inicial, quando Pedro confirmar aparelho livre. Foi preparado `BaselineInstalledAppRunner-v3/installed-app-baseline.xctestrun` no diretório de artefatos, contendo somente o runner assinado, sem pacote Savoria.app, sem UITargetAppPath e sem dependências de produtos do app. Seleciona somente `testPagesAndForeground`, cujos IDs já estão presentes na baseline. Esse caminho ainda não foi executado/validado. A intenção é lançar a versão instalada via bundle ID, conforme [a resolução de builds documentada pela Apple](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/init(bundleidentifier:)); nunca reinstalar uma versão antiga para A/B. Se o manifest for rejeitado, diagnosticar; não resetar/desinstalar. A captura inicial não identifica corretamente todas as páginas no evento foreground; novos marcadores individuais de Ajustes/detalhe não existiam nessa baseline. Não comparar esses destinos como se houvesse A/B físico válido.

## Último marco de validação

O roteiro Release `optimized-pages-settings.xcresult` passou: cinco abas em três ciclos, rolagens onde o driver encontrou scroll view/tabela, Mercado/Despensa, calendário, detalhe de receita encontrado e sete destinos de Ajustes, com background/foreground. Um caso, zero falhas; 180 segundos de duração XCTest, incluindo driver/idling, não latência de toque. Utensílios estava desabilitado; câmera, voz, inferências de IA, onboarding/paywall, formulários e histórico nutricional populado não foram exercitados. Isto não é cobertura de todas as telas possíveis. Capturas de Listas e Receitas confirmaram dados existentes e visual preservado. As primeiras tentativas efetivas falharam por duplicação de nós nativos AX e escolha de botão Voltar de outra barra; seletores corrigidos, sem restaurar app/dados.

A última unidade de captura distingue cada destino e detalhe de receita, separa os casos de abas/Ajustes e acrescenta Gerenciar dados somente para leitura. Builds Release simulador/Debug genérico iOS passaram. Roteiro final optimized-destination-traces.xcresult passou: dois casos, zero falhas, 196 segundos de duração XCTest. Trinta lotes e 6313 callbacks preservados em optimized-simulator-traces; os oito destinos e detalhe de receita têm eventos loaded e foreground verificados. Essa cobertura funcional não comprova apresentação GPU ou suavidade física. A tentativa de compilar testes unitários em Release revelou que esse build não expõe o módulo para @testable; os cinco testes dirigidos passaram na configuração Debug normal, sem mudar o build Release do app. Resultado performance-index-tests.xcresult: cinco casos, zero falhas. O mesmo código atual em Release foi instalado e aberto novamente no simulador, sem flags de trace. Os builds Debug genérico iOS anteriores passaram, com signing/entitlements verificados; o último por UDID falhou quando CoreDevice informou unavailable. O iPhone voltou a aparecer paired/available, mas a confirmação humana de aparelho livre segue pendente. O controle CUA encontrou Mac bloqueado; não houve confirmação de desbloqueio. Isso não substitui instalação/execução física: a versão otimizada ainda não foi instalada nele.

As contagens do simulador após atualização continuaram cinco itens, duas receitas e um perfil; o sistema rotacionou o UUID do container, mantendo os dados e as URLs relativas Private.store/Shared.store. Ainda faltam A/B físico controlado, retorno após cinco minutos, população real e captura CPU/GPU válida. Não há como garantir ausência de microengasgos com a evidência atual.

Há alterações locais preexistentes fora dos commits de performance (StoreKit, testes de IA e arquivos de usuário do Xcode). O xcodegen reorganizou metadata local de schemes já sujo; esse arquivo também ficou fora dos commits. Não afirmar preservação byte a byte desse metadata. Signing, App Groups e entitlements foram comparados antes/depois e permaneceram iguais.

## Entrega parcial e retomada

Fontes em commits focados: d3d8a950 (captura opt-in), c5b46b91 (otimizações), 304b6d62 (seletores), c77e8253 (destinos). Assinatura do último build físico: Bundle com.pedrosalles.smartkitchen.sync, Team 44K57HQAP9, containers syn/sync na ordem original, CloudKit/CloudDocuments e App Groups da extensão confirmados. Nenhum schema, configuração de stores ou sync foi alterado.

Pendência única no Things: YJdfWrJfsHbdmbsyARxqZ, Validar performance do Savoria, retida por disponibilidade humana nesta mesma thread. Próximo passo: Mac desbloqueado e iPhone 12 Pro conectado/livre; executar baseline existente sem reinstalar versão antiga, instalar otimização preservando dados e repetir o mesmo roteiro/configuração/dados. Acrescentar retorno após cinco minutos, rolagens em listas povoadas, CPU/GPU e caminhos ainda não exercitados. Não concluir pelo sucesso de builds/testes lógicos nem retomar automaticamente sem a condição humana.
