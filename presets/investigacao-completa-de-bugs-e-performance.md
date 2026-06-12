# Preset: investigacao completa de bugs e performance

Use este preset quando o problema persiste depois de uma correcao, envolve performance e estado interno ao mesmo tempo, ou quando o usuario relata que "ainda demora", "ainda falha" ou "nao ficou instantaneo".

Este preset combina medicao de performance, logs de estado e regras de investigacao profunda de performance do app.

## Prompt pronto

```text
Use o preset investigacao completa de bugs e performance para fazer um overview profundo, testes e correcao deste problema ate estabilizar.

Contexto:
- A estetica visual e as animacoes atuais devem ser preservadas.
- A sensacao esperada e de movimento extremamente fluido, como se aproveitasse telas de 120hz.
- A interacao deve continuar responsiva mesmo quando o usuario repetir o gesto rapidamente.
- O final da animacao deve ser rapido, mas ainda com desaceleracao sutil.
- Atualizacoes visuais dependentes do gesto devem acontecer no momento correto, sem bloquear o movimento.

Objetivo:
- Combinar medicao de tempos, traces e logs de estado.
- Instrumentar tanto tempo quanto estado.
- Criar uma reproducao headless sempre que possivel.
- Rodar ciclos curtos de medir, corrigir, testar e analisar ate estabilizar.
- Identificar exatamente o que roda durante a acao: funcoes, recomputacoes, layouts, leituras de estado, persistencias, logs, timers, observers, fetches, bindings e atualizacoes de UI.
- Substituir trabalho pesado por alternativas mais leves sem alterar a logica funcional, aparencia ou timing perceptivo.

Instrucoes:
1. Definir a metrica de sucesso antes de mexer no codigo, por exemplo tap ate visual aberto < 50ms.
2. Ler o codigo antes de propor solucao e mapear o hot path do gesto.
3. Nao repita automaticamente as correcoes obvias ou ja tentadas.
4. Instrumente o comportamento quando necessario.
5. Adicionar signposts para tempos e logs de debug para estado/decisoes.
6. Garantir que todo log tenha uma chave comum: trace id, target id, data, item id ou fluxo.
7. Rodar baseline no simulador/dispositivo configurado pelo projeto, usando a build mais recente.
8. Identificar se o atraso vem de resolucao, estado, render, layout, IO, rede, animacao, commit async ou main thread.
9. Procurar trabalho sincronizado na main thread.
10. Procurar recomposicoes SwiftUI desnecessarias, invalidacoes amplas e leituras/escritas repetidas em UserDefaults, AppStorage, storage, banco, rede ou disco.
11. Procurar atualizacoes de header, stripe, calendario, listas ou modelos acontecendo no mesmo frame do movimento.
12. Procurar layout, medicao, formatacao de datas, filtros, sorts, maps, allocations, criacao de objetos, timers, observers e logs dentro do hot path.
13. Separar trabalho que precisa ocorrer durante o gesto do trabalho que pode ocorrer apos a animacao.
14. Prefira APIs nativas, compositing leve, animacoes com custo baixo e atualizacoes coalescidas.
15. Coalescer atualizacoes repetidas e usar caches pequenos com invalidacao explicita quando isso reduzir custo real.
16. Preserve a logica funcional, a aparencia e o timing perceptivo das animacoes.
17. Pode refatorar funcoes e fluxo de animacao se isso reduzir custo real.
18. Corrigir uma causa por vez quando possivel.
19. Recompilar, instalar e repetir o mesmo autorun ou reproducao.
20. Comparar baseline vs resultado com numeros, traces, probes, min, max, media e ordem dos eventos.
21. Se o problema continuar, adicionar marcadores mais proximos do trecho suspeito e repetir.

Validacao obrigatoria:
- Rode os testes/builds disponiveis.
- Execute a app e valide no simulador/dispositivo configurado pelo projeto.
- Quando possivel, meca frames lentos, duracao do gesto, trabalho repetido e chamadas duplicadas.
- Confirme que nao existe trabalho pesado acontecendo junto com o swipe/scroll/drag.
- Confirme que headers, stripes ou elementos dependentes atualizam no momento correto sem derrubar o frame rate.

So conclua quando:
- A metrica for atingida ou houver um bloqueio concreto.
- O movimento estiver fluido em repeticoes rapidas quando o problema envolver interacao visual.
- O app nao parecer cair para baixa taxa de frames.
- O processamento durante o gesto estiver minimizado.
- As animacoes continuarem com a mesma intencao visual.
- Voce tiver rodado a validacao final e explicado o que mudou, o que foi medido e qual risco residual sobrou.

Ao responder, inclua:
- Baseline.
- Mudancas feitas.
- Resultado final.
- Evidencia dos logs/traces.
- O que foi medido.
- Ordem dos eventos quando houver trace.
- Qualquer risco residual.
```

## Comandos uteis

```sh
rg -n "<prefixo-ou-marker>" artifacts/traces/*.log
rg -n "BEGIN|END|instant|<flow-name>" artifacts/traces/<nome>.log
xcrun simctl launch --terminate-running-process '<SIMULADOR_DO_PROJETO>' <BUNDLE_ID_DO_APP>
```

Adapte os comandos para o projeto atual. Use o scheme, bundle id, pasta de build, simulador/dispositivo e sistema de logging que ja existirem no app.

## Adaptacao para outros projetos SwiftUI

- Funciona em outros projetos SwiftUI se os comandos especificos forem adaptados.
- Preserve a disciplina do preset: baseline, logs/traces, correcao, rebuild e comparacao.
- Troque qualquer infraestrutura especifica por equivalentes do projeto: OSLog, signposts, MetricKit, Instruments, XCTest, UI tests, previews controladas ou prints temporarios.
- Se o projeto nao tiver autorun headless, crie uma reproducao minima ou use um teste/manual scriptado antes de mexer em varias causas.
- Generalizar os comandos nao diminui a eficacia; o que mantem a eficacia e medir no ambiente real do app e usar a infraestrutura local sempre que existir.

## Checklist de investigacao

- Mapear entrada do usuario, atualizacao de estado, animacao, commit visual e atualizacao final.
- Mapear o hot path do gesto: entrada do usuario, atualizacao de estado, animacao, commit visual e atualizacao final.
- Separar trabalho que precisa ocorrer durante o gesto do trabalho que pode ocorrer apos a animacao.
- Confirmar que headers, stripes, calendarios, listas ou modelos nao competem com o movimento principal.
- Verificar se a animacao roda por transform/compositing sempre que possivel, sem forcar layout caro a cada frame.
- Verificar objetos observados grandes, bindings globais, `@AppStorage`, `Environment`, `PreferenceKey`, `GeometryReader` e `onChange` em cascata.
- Reduzir trabalho por frame: formatacao, filtros, ordenacoes, alocacoes, criacao de colecoes, logs, persistencia e chamadas sincronas.
- Coalescer atualizacoes repetidas: evitar recalcular a mesma coisa para cada tick de animacao.
- Usar caches pequenos e invalidados explicitamente quando o dado for estavel durante a interacao.
- Confirmar que atualizacoes dependentes do gesto acontecem no momento correto.
- Remover instrumentacao ruidosa ou logs de debug do hot path antes de finalizar, mantendo apenas o que for util e barato.
- Repetir medir, corrigir e validar ate a metrica ser atingida.

## Evidencias esperadas no fechamento

- Arquivos alterados.
- Causa principal encontrada.
- Baseline e resultado final.
- Arquivos de logs/traces analisados.
- Metricas comparativas antes/depois.
- Resultado dos testes/builds.
- Risco residual ou ponto que ainda dependa de teste em device fisico.
