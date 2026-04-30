# Recursos do Smart Kitchen

Este documento lista, de forma direta e organizada, as funcionalidades principais do aplicativo Smart Kitchen. Destinado a novos usuários, cada item descreve o que o app faz e breves notas sobre requisitos quando relevantes.

## Requisitos rápidos
- **iCloud (opcional):** necessário para sincronização entre dispositivos (`iCloud.com.pedrosalles.smartkitchen.sync`).
- **Chave de IA (opcional):** configurar `APIConfig.openAIAPIKey` para recursos avançados de LLM; há fallback para OpenRouter se configurado.
- **Permissões:** acesso a Fotos, Microfone/Câmera (para importação), e Notificações quando aplicável.

## Receitas
- **Criar e editar receitas:** campos completos (nome, categorias, tempo, dificuldade, porções, tags).
- **Ingredientes estruturados:** quantidades, unidades livres, seções e ordenação por etapas.
- **Passos de preparo:** passos ordenados com instruções e duração opcional por passo.
- **Mídia de preparo:** anexar fotos e vídeos às receitas (preview em tela cheia, reprodução de vídeo).
- **Modo Cozinhar (step-by-step):** visual fullscreen passo-a-passo com barra de progresso e navegação entre passos.
- **Escalonamento de porções (apresentação):** ajustar porções exibidas sem alterar dados persistidos; quantidades formatadas com frações.
- **Favoritar e metadata:** marcar favoritos, visualizar tempo total, porções e tags/categorias.

## Importação de Receitas
- **Importar de URLs (web/social):** extrai e estrutura receitas a partir de páginas e links sociais.
- **Importar por imagem (OCR):** reconhece texto de fotos de receitas/recibos e estrutura via LLM.
- **Importar por vídeo local:** extrai áudio/transcrição e estrutura receita automaticamente (limite de duração para vídeos compartilhados).
- **Pipeline com estágios:** interface que mostra estágios do processamento (analisando → extraindo → organizando → finalizando).
- **Aprimoramento por LLM:** reestruturação e normalização do rascunho por modelos de linguagem para melhorar a precisão.

## Despensa (Pantry)
- **Gerenciamento de itens da despensa:** adicionar, editar, agrupar por categoria e ver datas de validade.
- **Formatação de quantidades:** exibição amigável (inteiros, frações unicode, decimais locais).
- **Detecção de duplicatas:** prevenção e deduplicação de itens.

## Lista de Compras (Grocery)
- **Criar e editar lista de compras:** adicionar itens manualmente ou enviar ingredientes faltantes a partir de uma receita.
- **Ordenação por seção de mercado:** mapeamento de categorias para seções de supermercado para facilitar compras.
- **Marcar como comprado:** ações rápidas (swipe) para checar itens; agrupamento e filtros.

## Utensílios
- **Lista de utensílios separada:** adicionar, editar, categorizar e vincular a receitas quando aplicável.

## Assistente e IA
- **Chat com Assistente integrado:** converse com o assistente (perguntas, sugestões, ajuda com receitas e listas).
- **Ações automáticas (tool-calls):** o assistente pode solicitar execução de ferramentas internas (por exemplo, criar/editar itens, buscas) e incorporar resultados na conversa.
- **Histórico de conversas:** conversas e mensagens são armazenadas localmente (pode ser sincronizado via iCloud quando ativado).
- **Modo IA / Widgets:** widget que abre o app direto no chat com teclado pronto.
- **Fallbacks de modelo:** suporta OpenAI como padrão e OpenRouter como fallback, caso a chave OpenAI não esteja disponível.

## Nutrição
- **Análise nutricional por texto:** transformar descrições de refeições em estimativas de macros/energia.
- **Análise por imagem:** estimativa nutricional a partir de foto do prato (modelo vision + LLM).
- **Leitura de rótulos:** extrair valores de rótulos nutricionais e converter para por-100g quando necessário.
- **Cache e lookup:** integra com Exa/Supabase e cache local para valores por-100g (write-through cache quando possível).
- **Perfil e histórico nutricional:** registrar entradas alimentares e visualizar somatórios por dia.

## Sincronização e Compartilhamento
- **Sincronização iCloud (CloudKit):** opção para manter dados entre dispositivos com stores separados (`Private` e `Shared`).
- **Compartilhamento via CloudKit Share:** criar CKShare e convidar participantes; escolher escopo de compartilhamento (tudo, apenas listas, apenas receitas).
- **Migração segura e recuperação:** rotinas para migração de stores legados, deduplicação e backups automáticos para evitar perda de dados.

## Extensões & Integrações do Sistema
- **Share Extension (iOS):** compartilhar URL, texto, imagem ou vídeo diretamente para o app (usa App Group para hand-off).
- **Widgets (WidgetKit):** widgets para abrir o assistente e o modo IA rapidamente (Deep Links `smartkitchen://assistant`, `smartkitchen://aichat`).

## Backups e Restauração
- **Backups internos automáticos e manuais:** snapshots locais em `Application Support/Backups` com histórico e opção de restauração.
- **Backups externos:** salvar arquivo ZIP em pasta do usuário via bookmark de segurança (auto-backup diário opcional).
- **Importar/Exportar:** suportado formato de backup (v1/v2) e exportação para arquivo compactado.

## Mídia & Performance
- **Miniaturas otimizadas:** cache em memória + disco para thumbnails rápidos e downsample de imagens.
- **Reprodução de mídia:** suporte a playback de vídeos anexados às receitas.
- **Limites de importação:** vídeos compartilhados têm limite (ex.: 20 minutos para Share Extension).

## Pesquisa e Autocomplete
- **Pesquisa unificada:** busca cruzada por receitas, itens e utensílios com ranking e sugestões.
- **Autocomplete de itens:** base de dados pré-carregada com títulos, ícones e categorias para preenchimento rápido.

## Configurações & Privacidade
- **Gerenciamento de chaves e preferências:** configurar chaves de API, backups, preferências de mídia e sincronização em Ajustes.
- **Proteção de dados:** avisos e confirmações para operações destrutivas (reset de dados, apagar iCloud); migrações feitas com cuidado.

## Observações e limitações importantes
- **iCloud / CloudKit:** mudanças na configuração de containers ou stores exigem migração e backups — não altere sem plano de rollback.
- **IA:** alguns recursos dependem de chave OpenAI; há fallback para OpenRouter, mas a precisão pode variar.
- **OCR / Visão:** disponibilidade depende das APIs da plataforma e permissões do usuário.

---
Se quiser, posso:
- Salvar este arquivo como `FEATURES.md` no repositório (feito automaticamente se desejar).
- Gerar uma versão resumida para apresentação (slide/one-pager).
- Incluir instruções rápidas de teste manual para cada área.
