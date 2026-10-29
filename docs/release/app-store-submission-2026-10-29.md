# Savoria — preparação e envio de 29/10/2026

## Autorização e estado atual

Pedro autorizou traduzir a descrição para os demais idiomas, conferir a prontidão e enviar à App Store se tudo estiver correto. O envio completo à revisão ainda NÃO foi concluído. Não confundir upload do IPA ou inclusão de assinaturas no rascunho com submissão final.

## Verificado

- Dez localizações: pt-BR, en-US, es-ES, fr-FR, de-DE, it, ja, ko, zh-Hans e ar-SA. Descrições, promoções, palavras-chave, nomes e subtítulos salvos no App Store Connect e comparados aos arquivos locais pelo formulário visível. Revisão francesa trocou “recettes incomplètes” por receitas mesmo quando faltam ingredientes.
- Descrições incentivam registro diário e preservação do histórico quando ocorrerem esquecimentos pontuais. As dez segundas imagens foram alinhadas a essa mensagem, mantendo o panorama de fundo. Sem alteração nas funcionalidades do app.
- Catálogos da loja: `marketing/app-store/metadata/`; `validation.json` registra comprimentos e hashes. Limites conferidos: nome/subtítulo 30 caracteres, promoção 170, descrição 4.000 e palavras-chave 100 bytes. Seleção por relevância; não houve compra de métricas de busca.
- 90 capturas de iPhone enviadas, nove por idioma, usando imagens próprias no gerenciador de mídia. Interface nos sete idiomas suportados; inglês para coreano/chinês/árabe, com aviso explícito nas respectivas descrições. Arquivos derivados no tamanho obrigatório 1206×2622, preservando proporção com corte mínimo de enquadramento; fontes 1320×2868 permanecem no repositório. Os 90 hashes dos manifests foram conferidos.
- Archive e exportação App Store Connect concluídos no Xcode 27.1. IPA final: `/Volumes/PS-Externo/Coding/Builds/Savoria-AppStore-20261029/SubmissionFinal/Export/Savoria.ipa`.
- Versão 3.6.2 (3), SDK iphoneos27.1, bundle `com.pedrosalles.smartkitchen.sync`, Team `44K57HQAP9`; assinatura estrita e ZIP verificados. CloudKit Production, ordem dos dois containers iCloud e App Group preservados; `get-task-allow=false`, sem `.debug.dylib` e sem configuração privada de provedores preenchida no Info.plist. Resumo SHA-256 em `SubmissionFinal/package-summary.json`.
- Upload confirmado pelo Xcode: “Upload succeeded / Uploaded Savoria”. Build 3 apareceu processado no cadastro e foi associado à versão 3.6.2. Lançamento manual existente preservado.
- Privacidade atual conferida: sete tipos de dados publicados, vinculados ao usuário, com finalidades coerentes com a revisão anterior; URL pública preservada. Classificação etária, direitos de terceiros, declaração de não ser dispositivo médico, categorias Gastronomia e bebidas / Saúde e fitness e dados de revisão presentes.
- Anual 6822917042 e mensal 6822949625 incluídos no MESMO rascunho. Cada produto mostrou “Pronto para revisão”; lista de envios confirmou dois itens no rascunho criado às 18:30. Ainda falta incluir o app nesse rascunho e realizar a submissão conjunta.
- Metadados/imagens registrados em `a39b6198`, push confirmado para `origin/main` (https://github.com/psalles00/Smart-Kitchen.git). Alterações preexistentes fora do pedido foram preservadas.
- Provas funcionais compatíveis e Sandbox anteriores reutilizadas conforme `app-store-readiness-2026-10-28.md`. Nenhuma inferência paga, compra adicional, restauração, migração ou alteração de dados pessoais foi feita nesta preparação.

## Pendências reais

- [ ] Gerar/revisar/enviar capturas de iPad 13 polegadas | Executor comigo; CoreSimulator compartilhado precisa de recuperação autorizada.
- [ ] Confirmar o fim do processamento das imagens | Apple; verificar a validação atual antes de enviar.
- [ ] Incluir o app com os dois planos e enviar o rascunho à revisão | Execução comigo após resolver as capturas e os requisitos acima.

## Captura de iPad: diagnóstico e recuperação preservada

O primeiro executor reutilizado falhou ao carregar o bundle por símbolo ausente de `UnifiedItem`: teste antigo versus binário mais recente. O executor foi recompilado das fontes atuais (`TEST BUILD SUCCEEDED`), sem mudar código de produção.

A execução seguinte não conseguiu instalar/abrir o runner: `Mach error -308 / (ipc/mig) server died`. O iPad estava em Shutdown ao tentar encerrá-lo; foi iniciado novamente, sem apagar dados. A tentativa com o dispositivo reiniciado ficou sem avançar por vários minutos e consultas simples também ficaram pendentes. Somente o executor próprio foi interrompido para recuperação. Nenhum reset/uninstall, exclusão de DerivedData ou encerramento global foi realizado.

Resultados reprovados/inconclusivos são preservados em `SubmissionFinal/iPad-en.xcresult`, `iPad-en-current.xcresult` e `iPad-en-stable.xcresult`, com logs correspondentes; não contam como capturas aprovadas. Plano de retomada: recuperar o serviço com autorização, rodar o caso `AdaptiveWorkspaceRenderingTests/testAppStoreDemonstrationCaptures` em dados somente em memória nos sete idiomas, exportar os anexos, verificar dimensões/layout e enviar. Nenhuma nova chamada de IA é necessária.

Pedro foi consultado para reiniciar o CoreSimulator porque o serviço é compartilhado com outros trabalhos. A coordenação de Device Hub anteriormente autorizada foi usada para avisar “Rotina App”, preservando seus uploads e sem solicitar encerramento dos processos alheios. O servidor HTTP local temporário de metadados foi encerrado após a transferência dos textos; abas auxiliares concluídas também foram fechadas.
