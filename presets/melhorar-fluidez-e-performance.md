# Preset: melhorar fluidez e performance

Use este preset quando uma interacao, animacao, swipe, scroll, drag, header, lista ou transicao estiver visualmente pesada, com queda de frames, atraso de atualizacao, trabalho demais na main thread ou sensacao de baixa taxa de atualizacao.

## Prompt pronto

```text
Faca um overview profundo, testes e correcao de performance desta interacao.

Contexto:
- A estetica visual e as animacoes atuais devem ser preservadas.
- A sensacao esperada e de movimento extremamente fluido, como se aproveitasse telas de 120hz.
- A interacao deve continuar responsiva mesmo quando o usuario repetir o gesto rapidamente.
- O final da animacao deve ser rapido, mas ainda com desaceleracao sutil.
- Atualizacoes visuais dependentes do gesto devem acontecer no momento correto, sem bloquear o movimento.

Objetivo:
Identifique exatamente o que acontece durante a acao, quais funcoes, recomputacoes, layouts, leituras de estado, persistencias, logs, timers, observers, fetches, bindings ou atualizacoes estao rodando junto com o gesto/animacao, e substitua trabalho pesado por alternativas mais leves.

Instrucoes:
- Leia o codigo antes de propor solucao.
- Nao repita automaticamente as correcoes obvias ou ja tentadas.
- Instrumente o comportamento quando necessario.
- Compare antes/depois com numeros, traces ou probes.
- Procure trabalho sincronizado na main thread.
- Procure recomposicoes SwiftUI desnecessarias.
- Procure leituras/escritas repetidas em UserDefaults, AppStorage, storage, banco, rede ou disco durante o gesto.
- Procure atualizacoes de header, stripe, calendario, listas ou modelos acontecendo no mesmo frame do movimento.
- Procure layout, medicao, formatacao de datas, filtros, sorts, maps, allocations e criacao de objetos dentro do hot path.
- Prefira APIs nativas, compositing leve, animacoes com custo baixo e atualizacoes coalescidas.
- Preserve a logica funcional, a aparencia e o timing perceptivo das animacoes.
- Pode refatorar funcoes e fluxo de animacao se isso reduzir custo real.

Validacao obrigatoria:
- Rode os testes/builds disponiveis.
- Execute a app e valide no simulador/dispositivo configurado pelo projeto.
- Quando possivel, meca frames lentos, duracao do gesto, trabalho repetido e chamadas duplicadas.
- Confirme que nao existe trabalho pesado acontecendo junto com o swipe/scroll/drag.
- Confirme que headers, stripes ou elementos dependentes atualizam no momento correto sem derrubar o frame rate.

So conclua quando:
- O movimento estiver fluido em repeticoes rapidas.
- O app nao parecer cair para baixa taxa de frames.
- O processamento durante o gesto estiver minimizado.
- As animacoes continuarem com a mesma intencao visual.
- Voce tiver rodado a validacao final e explicado o que mudou, o que foi medido e qual risco residual sobrou.
```

## Checklist de investigacao

- Mapear o hot path do gesto: entrada do usuario, atualizacao de estado, animacao, commit visual e atualizacao final.
- Separar trabalho que precisa ocorrer durante o gesto do trabalho que pode ocorrer apos a animacao.
- Identificar fontes de invalidez ampla de view: objetos observados grandes, bindings globais, `@AppStorage`, `Environment`, `PreferenceKey`, `GeometryReader` e `onChange` em cascata.
- Reduzir trabalho por frame: formatacao, filtros, ordenacoes, alocacoes, criacao de colecoes, logs, persistencia e chamadas sincronas.
- Coalescer atualizacoes repetidas: evitar recalcular a mesma coisa para cada tick de animacao.
- Usar caches pequenos e invalidados explicitamente quando o dado for estavel durante a interacao.
- Confirmar que alteracoes de header/date stripe nao competem com o movimento principal quando isso for perceptivel.
- Verificar se a animacao roda por transform/compositing sempre que possivel, sem forcar layout caro a cada frame.
- Remover instrumentacao ruidosa ou logs de debug do hot path antes de finalizar, mantendo apenas o que for util e barato.

## Adaptacao para outros projetos SwiftUI

- Use o esquema, bundle id, simulador e comando de build do projeto atual.
- Se o app ja tiver infraestrutura de logs/traces, use a infraestrutura existente.
- Se nao houver traces prontos, adicione marcadores simples com OSLog, signposts ou prints temporarios com prefixo unico.
- Evite comandos ou nomes especificos de outro app; trate qualquer exemplo como modelo a adaptar.

## Evidencias esperadas no fechamento

- Arquivos alterados.
- Causa principal encontrada.
- Mudancas feitas para reduzir custo.
- Resultado dos testes/builds.
- Metricas ou observacoes comparativas antes/depois.
- Qualquer risco residual ou ponto que ainda dependa de teste em device fisico.
