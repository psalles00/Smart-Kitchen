# Preset: investigar problemas com logs

Use este preset quando o problema e funcional, intermitente, ou depende de estado interno dificil de ver so com a UI.

## Prompt pronto

```text
Use o preset investigar problemas com logs para investigar e corrigir este problema.

Objetivo:
- Criar logs de debug estilo console/Xcode para cada acao relevante do problema.
- Compilar e testar o fluxo.
- Ler todos os logs gerados por aquela funcao/fluxo.
- Corrigir com base nos logs, nao por chute.

Passos obrigatorios:
1. Mapear o fluxo relatado pelo usuario em acoes pequenas.
2. Adicionar logs em cada fronteira importante: entrada da funcao, parametros, estado anterior, decisao condicional, mutacao de estado, chamada async, callback, erro, retorno e render.
3. Incluir ids, datas, contadores, flags e nomes de origem suficientes para correlacionar os eventos.
4. Usar prefixo unico para facilitar rg, por exemplo [Debug][FlowName].
5. Evitar dados sensiveis e logs verbosos demais em loops grandes.
6. Compilar usando o comando de build/teste do projeto.
7. Executar o fluxo no simulador com autorun, teste automatizado ou reproducao manual guiada por comando.
8. Coletar logs via OSLog, console do app, arquivo gerado ou saida do teste.
9. Ler todos os logs com o prefixo criado.
10. Corrigir o problema, remover ou reduzir logs temporarios quando nao forem mais uteis, e repetir o teste.

Ao responder, inclua:
- Prefixo usado nos logs.
- Caminho/saida analisada.
- Sequencia real observada.
- Causa encontrada.
- Correcao aplicada.
- Resultado do teste.
```

## Padrao de log recomendado

```swift
print("[Debug][FlowName] step=<step> id=\(id) state=\(state) count=\(count)")
```

Quando ja existir infraestrutura de logging no app, prefira ela ao `print`.

## Adaptacao para outros projetos SwiftUI

- Use o simulador/dispositivo, bundle id e comando de build configurados pelo projeto.
- Em projetos sem OSLog estruturado, comece com prints temporarios e prefixo unico.
- Em projetos com logger proprio, prefira o logger existente para manter os logs pesquisaveis no ambiente normal do app.
- Remova nomes, ids e comandos especificos de outro app ao copiar este preset.

## Checklist de investigacao

- Mapear entradas, saidas e efeitos colaterais do fluxo.
- Correlacionar eventos com uma chave comum: id, data, item ou trace.
- Registrar estado antes e depois de mutacoes importantes.
- Registrar decisoes condicionais que possam explicar divergencias.
- Registrar callbacks e pontos async.
- Evitar dados sensiveis.
- Reduzir ou remover logs temporarios antes de finalizar.

## Evidencias esperadas no fechamento

- Prefixo usado.
- Logs analisados.
- Sequencia real observada.
- Causa raiz.
- Mudancas feitas.
- Resultado da validacao.
