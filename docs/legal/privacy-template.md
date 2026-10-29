# Política de Privacidade — Savoria

_Última atualização: 28 de outubro de 2026._

A Savoria ("nós", "nosso") respeita a sua privacidade. Esta política descreve
quais dados o aplicativo Savoria (o "App") utiliza, quando são compartilhados
e como você pode exercer seus direitos de privacidade.

## 1. Quem somos

- Controlador dos dados: **Pedro Salles** (desenvolvedor independente).
- Contato: `pedrosalles00@gmail.com`.

## 2. Dados que coletamos

| Categoria | Dados | Finalidade | Base legal |
|-----------|-------|------------|------------|
| Conteúdo do usuário | Mensagens, receitas, ingredientes, refeições, fotos e áudio escolhidos | Funcionamento local e pedidos aos serviços de IA/busca autorizados | Execução de contrato; consentimento para envio aos serviços externos |
| Saúde e atividade | Perfil nutricional, idade em anos, sexo informado, altura, peso, atividade, metas e registros alimentares | Cálculos e acompanhamento; contexto para IA quando autorizado | Execução de contrato; consentimento para envio aos serviços externos |
| Identificador técnico | UUID gerado pelo App e guardado nas preferências locais, enviado com alimento e voto ao avaliar uma referência nutricional | Evitar votos duplicados no cache compartilhado | Consentimento para uso dos serviços externos |
| Conta Apple | Identificador StoreKit / iCloud | Sincronização e validação de compras | Execução de contrato |
| Histórico de compras | ID das transações da App Store | Validação de assinatura Premium | Execução de contrato |
| Diagnósticos | Registros técnicos locais de erros e execução | Solução de problemas | Interesse legítimo |

Não coletamos localização, contatos, dados biométricos ou dados de uso para
fins publicitários.

## 3. Onde os dados ficam armazenados

- **No dispositivo:** receitas, despensa, mercado, refeições e configurações
  são armazenados localmente em SwiftData.
- **iCloud privado:** se o usuário ativar a sincronização, os mesmos dados
  são replicados para o container CloudKit privado da sua Apple ID.
  O acesso é controlado pela sua conta Apple. Esse armazenamento é distinto
  do conteúdo que você autoriza enviar aos serviços descritos na seção 4.
- **Compartilhamento Familiar:** quando ativado, somente os usuários
  convidados por você têm acesso aos dados compartilhados via CloudKit.

## 4. Inteligência Artificial, buscas e serviços externos

Antes do primeiro envio aos serviços de IA, o App pede autorização explícita.
Recusar não impede o uso das receitas, listas e demais recursos locais.
Em Configurações, você pode usar **Autorizar serviços de IA** ou
**Revogar autorização de IA**. Essa escolha é local a cada instalação.

Conforme a função escolhida, podem ser enviados mensagens e histórico da conversa,
itens da despensa, receitas, nomes e marcas de alimentos, registros alimentares,
metas e dados do perfil nutricional. Fotos ou áudio selecionados também podem ser
enviados para análise ou transcrição. O conteúdo de texto livre pode conter dados
pessoais que você tenha escrito; não prometemos anonimização desse conteúdo.

Os serviços envolvidos são:

- **Supabase:** infraestrutura do backend e processamento das solicitações;
  também mantém um cache compartilhado de referências de composição de alimentos,
  com nomes, nutrientes, fontes e avaliações, distinto do diário pessoal local.
  Ao avaliar uma referência, recebe também o identificador da instalação,
  associado ao alimento e ao voto para impedir avaliações duplicadas.
  [Política do Supabase](https://supabase.com/privacy).
- **OpenAI:** interpretação de pedidos, análise de imagens, respostas e transcrição.
  [Controles de dados da API](https://developers.openai.com/api/docs/guides/your-data).
- **OpenRouter e os provedores que processam seus modelos:** rota alternativa para
  solicitações de IA. A configuração do backend inclui modelos Gemini e Qwen;
  o provedor de execução pode variar conforme a disponibilidade da rota.
  [Política do OpenRouter](https://openrouter.ai/privacy) e
  [políticas dos provedores](https://openrouter.ai/docs/guides/privacy/provider-logging).
- **Exa:** buscas de receitas e de referências nutricionais.
  [Política do Exa](https://exa.ai/privacy-policy). O processamento pela API também
  está sujeito aos termos aplicáveis à oferta empresarial utilizada.
- **USDA FoodData Central:** consultas por nomes de alimentos para composição
  nutricional. [Privacidade do USDA](https://www.usda.gov/privacy-policy).

Ao abrir ou importar conteúdo da web, o site de origem e os servidores das imagens
podem receber a consulta ou o acesso necessário para carregar esse conteúdo.
Os serviços externos podem processar os dados fora do seu país. O envio usa
conexões HTTPS e é limitado ao funcionamento do recurso solicitado. Não usamos
os dados para publicidade nem rastreamento entre aplicativos ou sites.

### Retenção e exclusão

Dados locais e sincronizados permanecem até você os excluir pelos controles do App.
Cópias exportadas por você ficam nos locais escolhidos e precisam ser gerenciadas
separadamente. O cache compartilhado de referências nutricionais pode permanecer
até sua atualização, correção ou remoção administrativa. O identificador da
instalação e sua associação com alimentos/votos permanecem com as avaliações
até remoção administrativa; revogar a autorização não apaga avaliações anteriores.

Os serviços externos possuem suas próprias regras de retenção, segurança e
obrigações legais. Como referência, a documentação da OpenAI informa retenção
padrão de até 30 dias para monitoramento de abuso em chat, com exceções descritas
na documentação; a transcrição tem regras distintas. No OpenRouter, as condições
também dependem do provedor da rota. Não afirmamos que todas as rotas possuem
retenção zero. Consulte os documentos vinculados acima para as condições e exceções.

Revogar a autorização impede novos envios pelo App; isso não desfaz solicitações
já transmitidas, nem apaga automaticamente os dados nos provedores. Para solicitar
acesso, correção ou exclusão de dados sob nosso controle, contate
`pedrosalles00@gmail.com`. Pedidos que dependam de um provedor serão tratados
conforme os direitos aplicáveis, suas condições e eventuais obrigações de retenção.
Não é necessário adquirir Premium para fazer uma solicitação de privacidade.

## 5. Compras dentro do aplicativo (IAP)

O Savoria oferece duas assinaturas auto-renováveis:

- **Premium Anual** — R$ 99,90 por 12 meses (7 dias de teste grátis quando a oferta estiver disponível para a conta).
- **Premium Mensal** — R$ 49,90 por 1 mês.

Disclosures obrigatórios da Apple:

- O pagamento será cobrado da sua Apple ID na confirmação da compra.
- A renovação é automática salvo cancelamento até 24 horas antes do término
  do período atual. A renovação acontece em até 24 horas antes do término.
- O gerenciamento da assinatura, incluindo cancelamento, é feito em
  *Ajustes → seu nome → Assinaturas* no iPhone/iPad.
- Ao assinar, você concorda com os Termos de Uso e com esta Política de
  Privacidade.

## 6. Seus direitos

Você pode, a qualquer momento:

- Exportar todos os seus dados em formato `.zip` (requer Premium).
- Usar **Configurações → Gerenciar dados → Apagar todos os dados locais e do iCloud**.
  A ação exige confirmação e não apaga cópias que você exportou para outros locais.
  Desinstalar o App, por si só, não garante excluir os dados do iCloud.
- Desativar a sincronização iCloud sem perder dados locais.
- Revogar a autorização de IA nas Configurações; isso não exclui dados já enviados.
- Solicitar exclusão de dados ou correções: `pedrosalles00@gmail.com`.

Sob LGPD e GDPR, você tem direito de acesso, retificação, portabilidade,
oposição e revogação de consentimento.

## 7. Crianças

O Savoria não é direcionado a menores de 13 anos.

## 8. Alterações

Atualizações desta política serão publicadas em
`https://psalles00.github.io/Smart-Kitchen/privacy/`. O uso continuado do
app não substitui a autorização explícita exigida para o envio aos serviços de IA.

## 9. Contato

`pedrosalles00@gmail.com`
