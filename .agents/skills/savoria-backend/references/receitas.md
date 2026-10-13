# Receitas da Vault e edições

Cliente no repositório `scripts/savoria-agent.py`. Origem canônica `/Volumes/PS-Externo/PS Vault/Alimentação/Receitas`.

```sh
python3 scripts/savoria-agent.py snapshot > /caminho/privado/antes.json
python3 scripts/savoria-agent.py from-vault --output /caminho/privado/manifesto.json
python3 scripts/savoria-agent.py plan /caminho/privado/manifesto.json --revision REVISAO > /caminho/privado/plano.json
python3 scripts/savoria-agent.py apply PLAN_UUID --revision REVISAO --request-id UUID
python3 scripts/savoria-agent.py snapshot > /caminho/privado/depois.json
```

Use `umask 077` antes de redirecionamentos. Arquivos de captura/manifesto precisam de caminhos novos, o cliente não sobrescreve. `from-vault` salva também `.source.json` com Markdown integral e hashes. Templates, Contexto e AGENTS não são receitas; duas notas legadas sem type também são reconhecidas pela estrutura. Notas sem ingredientes/preparo exigem revisão, não omissão silenciosa.

UUIDs determinísticos por caminho da nota/filho evitam duplicatas. Receita já importada com mesmo SHA é omitida do novo manifesto, conservando edições feitas pelo usuário. Fonte alterada após importação exige merge explícito com IDs existentes; não sobrescrever relações cegamente. Se todas estão importadas, informar no-op e não enviar manifesto vazio.

Capas locais são resolvidas dentro da Vault e fixadas por SHA256 no plano; alteração entre prévia/aplicação exige novo plano. Origem `obsidian://` e Markdown original ficam na receita. Embeds de vídeos permanecem na nota fonte, não viram vídeos embutidos no app. Quantidades não explícitas permanecem ausentes; tempos/calorias/rendimento não são inventados. O modelo do app usa valores padrão quando a fonte não os fornece.

Manifesto aditivo de receita:
```json
{
  "mode": "upsert", "source": "pedido de Pedro", "items": [], "categories": [], "showReserve": false,
  "recipes": [{"id": "UUID_EXISTENTE_OU_NOVO", "name": "Título", "isFavorite": true}]
}
```

Em receitas, campos omitidos são preservados. Campos de snapshot `imageSHA256`, `createdAt`, `updatedAt`, `nutrition` e `media` são somente leitura: não copie o snapshot inteiro no manifesto. Para capa, forneça `coverPath` absoluto e `coverSHA256`. Ingredientes/seções/passos são upserts por ID, filhos omitidos não são apagados. Use os IDs do snapshot em edições e respeite a associação com a própria receita.

No readback, compare cobertura de todas notas, Markdown/SHA/origem/capa e cada ingrediente/seção/passo por ID; confirme que receitas anteriores e listas não mudaram. Um recibo não substitui a conferência. Para provar app encerrado, faça shutdown normal, espere o processo sair, execute snapshot e confirme health com zero janelas e os mesmos dados. Não encerre enquanto houver edições pendentes do usuário.
