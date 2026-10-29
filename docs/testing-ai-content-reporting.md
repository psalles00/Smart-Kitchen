# Relatos de respostas da IA — 29/10/2026

O botão `Reportar resposta` aparece nas respostas do assistente, incluindo
receitas estruturadas, cartões de receitas sem texto e opções sem introdução.
No chat inline há uma ação por mensagem completa; bolhas independentes mantêm
a mesma ação. O usuário vê uma prévia, escreve o motivo e pode optar por incluir
a resposta. Essa opção começa desligada. Não são anexados histórico, fotos,
despensa, IDs do usuário ou logs. O app abre um rascunho no serviço de e-mail;
o usuário precisa efetivamente enviar. Se não houver serviço disponível, há
aviso com o contato e a opção de copiar o relato. Não foi enviado e-mail no teste.

## Evidências

- `report-cards-tests.xcresult`: quatro testes aprovados, zero falhas, no
  iPhone 17 Pro virtual. Testes de privacidade padrão, limites de texto e
  codificação de payload com tentativa de injeção em cabeçalho; prévia nativa
  e renderização dos três caminhos de mensagem com store em memória.
- Capturas em `Builds/Savoria-Nutrition-Final-20261028/report-cards-preview`:
  ação única visível abaixo da receita detalhada, cartão anexado e opções.
  Os seis itens sintéticos, uma receita e três mensagens foram preservados.
- A primeira execução focada iniciou antes de haver cena ativa. O teste agora
  espera a notificação nativa de ativação; o reteste passou. Não foi ocultada
  falha de produção nem alterado o bootstrap do app.
- Builds iOS e macOS passaram: `report-cards-build.log` e
  `report-cards-mac-build.log`. Mac Release instalado em `/Applications/Savoria.app`,
  com assinatura conferida. Interface abriu com os dados existentes.
- Mac: reutilizada conversa salva de receitas, sem nova inferência. Botão,
  folha nativa, prévia e opção desligada conferidos. Fechado sem enviar nem copiar.
  Captura `report-macos.png` na mesma pasta de evidências.
- Revisão independente encontrou uma omissão em cartões sem bolha de texto;
  corrigida no nível da mensagem e aprovada após examinar os três novos casos.
- Treze textos novos cobrem pt-BR, en, es, fr, de, it e ja. O fluxo é compartilhado.
- Sem nova chamada de IA, backend, polling ou atividade ociosa. Somente a ação
  explícita de abrir o e-mail entrega o texto escolhido ao serviço de e-mail.
  Os prompts existentes receberam instruções adicionais de conteúdo seguro;
  isso é uma defesa, não garantia de que qualquer modelo sempre a obedecerá.
- Manifesto passa a declarar também personalização para Health, Fitness e
  OtherUserContent, em coerência com recomendações solicitadas e rascunho ASC.
  Não houve novas categorias, tracking, payload de API ou alteração de dados.

## Conferência manual

1. Abra uma conversa salva e escolha `Reportar resposta` sob texto ou receita.
2. Confira que a resposta não aparece na prévia antes de marcar sua inclusão.
3. Escreva um motivo, confira a prévia e abra o e-mail; verifique destinatário e
   conteúdo, depois cancele o rascunho se estiver apenas testando.
4. Feche o relato e confira que a conversa e as receitas permanecem disponíveis.

Não é necessário conceder consentimento de IA nem fazer nova consulta para
reportar uma resposta já salva. Relatos devem ser monitorados pelo suporte;
o recurso não substitui a operação de atendimento nem a revisão da Apple.
