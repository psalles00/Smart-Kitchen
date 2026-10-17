# Cabeçalhos e descrições compactos

Home e Nutrição usam a mesma tipografia de descrição: 14,5 pontos, semibold arredondada, fatos destacados em branco e conectores/data em branco a 55%. O texto cresce até três linhas, sem reservar uma faixa vazia quando ocupa menos linhas. A margem antes da descrição é zero e a separação até o painel é de oito pontos; a altura fixa anterior da Home foi removida. No Mac, as calorias da Home também entram na frase.

`PageHeaderPalette` compartilha o degradê branco → cinza 174/255 e a cor dos controles entre os cabeçalhos. O estilo dos grupos de botões é aplicado pelo ambiente apenas no cabeçalho. O Assistente/SavorIA usa a mesma paleta nas páginas; o fundo escuro do seu cabeçalho mantém o contraste também no modo claro.

A descrição de Nutrição reúne a data selecionada, quantidade de registros, estado do dia e calorias consumidas/meta. Clicar nela mantém o acesso ao Progresso. O resumo continua acompanhando a data selecionada no calendário. Os dois textos novos têm traduções nos sete idiomas disponíveis.

Nenhuma mudança em modelos, stores, bootstrap, Team ou capabilities. A validação usa os dados existentes, sem compras, chamadas de IA ou registros alimentares de teste.

## Teste manual

1. Abra a Home: confira a proximidade entre título, descrição e painel.
2. Visite Listas, Receitas, Nutrição e Buscar: compare o degradê dos títulos e o cinza dos controles com a Home.
3. Em Nutrição, selecione um dia no calendário e confira data, registros e calorias na descrição. Toque na descrição para abrir Progresso e volte.
4. Saia do app e volte: confira que os dados e a página selecionada permanecem acessíveis.

## Evidências

Builds Debug para macOS e iPhone 17 Pro Simulator. Abertura e conferência nativa no Mac; teste existente `PageActionTracingTests.testPagesAndForeground` para navegação, rolagem e retomada nas cinco páginas do iOS. Catálogo validado preservando todos os textos anteriores e cobrindo os seis idiomas traduzidos, além do português de origem.

Resultados, capturas e leituras privadas de integridade ficam em `Coding/Builds/Savoria-E2E-20261012`, prefixo `header-summary-`, data 20261017.

Resultado em 17/10/2026: teste das cinco páginas aprovado, com três ciclos de navegação e retomada. Home/Nutrição inspecionadas visualmente nas duas plataformas; acesso ao Progresso pela descrição conferido no Mac. Snapshots do Mac e verificação dos stores Private/Shared do Simulator preservaram os dados, IDs e hashes das mídias. Versões finais instaladas e abertas nas duas plataformas, com Team e capabilities iCloud conferidos.
