# Central de Debug apenas no desenvolvimento

O botão com `ladybug.fill` usa as medidas e o desenho do Rotina. No iOS, fica imediatamente à esquerda de Configurações na página inicial. No macOS, aparece no cabeçalho inicial; Configurações continua na barra lateral nativa.

O botão, seu estado de apresentação, a central e as simulações de assinatura/limites estão dentro de `#if DEBUG`. Release não recebe esses tipos nem uma view oculta/espaço reservado. Uma preferência Premium deixada por Debug é ignorada em Release; apenas o entitlement verificado pelo StoreKit determina o plano. Archive continua usando Release. Para usar a central, compile explicitamente com configuração Debug; o Run do esquema Savoria mantém sua configuração anterior.

Opções: App Store, Grátis e Premium; onboarding completo com paywall, preparação e paywall isolado; contadores reais/disponíveis/esgotados; diagnóstico e retorno ao estado real. Prévia não salva respostas do onboarding, não restaura/completa compras e não carrega o catálogo real do paywall. Simulações preservam entitlement e contadores reais. Chamadas de IA feitas fora das prévias continuam sendo reais. As credenciais locais já existentes continuam exclusivas do Debug no iOS.

Todos os idiomas do catálogo são atendidos: português, inglês, espanhol, francês, alemão, italiano e japonês. Nenhuma alteração de schema, store, container, Team ou capability.

## Teste manual

1. Em Debug, abra a página inicial e toque na joaninha. No iOS ela deve estar à esquerda de Configurações.
2. Alterne Premium e Grátis. A assinatura real exibida deve permanecer igual. Volte para App Store.
3. Abra e feche as prévias de onboarding + paywall, paywall isolado e preparação. Dados e onboarding real devem permanecer como antes.
4. Alterne os contadores simulados e use Voltar ao estado real antes de encerrar os testes.
5. Em Release, confirme a ausência da joaninha, da opção de debug nas configurações e do espaço do botão. Reabra Debug e confirme o retorno do acesso.

## Validação

- `DevelopmentBuildContractTests`: isolamento das simulações, entitlement e contadores; a versão Release do teste de assinatura prova que a preferência Debug é ignorada.
- `PageActionTracingTests.testDevelopmentHomeDebugPlansAndPreviews`: posição do botão, planos e prévias no iPhone 17 Pro Simulator.
- `PageActionTracingTests.testProductionHomeHasNoDebugEntryOrSettingsOption`: ausência do acesso em Release e largura original do botão de Configurações.
- Conferência nativa do macOS: planos, onboarding, preparação e paywall. Snapshots antes/depois preservam listas, receitas, categorias e metadados.

Logs e resultados privados ficam em `Coding/Builds/Savoria-E2E-20261012`, prefixo `home-debug-`, data 20261017.

Para executar os unitários em Release, use `ENABLE_TESTABILITY=YES` somente no comando `build-for-testing`, mantendo a configuração Release e sem definir `DEBUG`. O projeto não habilita testabilidade para distribuição. No Mac Apple Silicon, os testes desta tarefa usam `ONLY_ACTIVE_ARCH=YES ARCHS=arm64`. A inspeção do binário Release do macOS usa o build normal, sem essa opção de testabilidade.

Resultado em 17/10/2026: builds Debug e Release nas duas plataformas; cinco testes aprovados e um teste de contadores omitido intencionalmente em Release, onde a simulação não existe. UI de produção conferida sem botão/opção e com Configurações mantendo 46 pontos de largura. Binário Release do macOS sem identificadores do menu e sem a chave de override de assinatura. Debug instalado e aberto no Mac e no iPhone 17 Pro Simulator. Leitura final do Mac e integridade dos stores Private/Shared do Simulator sem mudanças nos dados, IDs ou hashes das mídias.
