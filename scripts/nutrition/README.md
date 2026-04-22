# Smart Kitchen — Nutrition backend (Supabase)

Arquitetura híbrida MVP (free tier):
- **Supabase Postgres** guarda dados BR canônicos (TACO) + cache de respostas de APIs externas + logs do usuário.
- **USDA FoodData Central API** (CC0, grátis, 1000 req/h) para alimentos US/globais.
- **Open Food Facts API** (ODbL, grátis) para lookup por código de barras.

Tudo isso cabe confortavelmente nos 500 MB do plano free.

---

## 1. Setup inicial (uma vez)

### 1.1 Aplicar o schema

1. Abra o projeto no [Supabase Dashboard](https://supabase.com/dashboard/project/yfcmvdijvgeaihvwyssb) → **SQL Editor** → **New query**.
2. Cole o conteúdo de [`000_schema.sql`](000_schema.sql) e clique **Run**. Deve retornar "Success. No rows returned".
3. Nova query, cole [`001_seed_reference.sql`](001_seed_reference.sql) e **Run**.

### 1.2 Expor o schema `nutrition` no PostgREST

Por padrão o Supabase só expõe `public`. Para o app e o script poderem usar `nutrition.*` direto:

1. Dashboard → **Settings** → **API** → **Exposed schemas**.
2. Adicione `nutrition` à lista (deixe `public` também). **Save**.

> Alternativa: se preferir não expor, copie as tabelas para o schema `public` via views, mas expor é mais limpo.

### 1.3 Configurar variáveis de ambiente

```bash
cd scripts/nutrition
cp .env.example .env
# edite .env e cole o SERVICE_ROLE key (Dashboard → Settings → API → service_role)
```

⚠️ **Nunca commite o `.env`.** Ele já está no `.gitignore`.

---

## 2. Importar TACO (597 alimentos BR)

```bash
cd scripts/nutrition
node import_taco.mjs
```

Saída esperada:
```
→ Loading reference data from Supabase...
→ Parsed TACO.json: 597 foods
→ Upserting foods...
  597/597 foods upserted.
→ Building food_nutrients...
  ~15000 nutrient rows ready.
→ Upserting food_nutrients...
  15000/15000 food_nutrients upserted.
✅ TACO import complete.
```

É idempotente — rodar de novo apenas sobrescreve linhas existentes.

---

## 3. Verificação

No SQL Editor:

```sql
-- contagens
select s.code, count(f.*) as foods
from nutrition.sources s
left join nutrition.foods f on f.source_id = s.id
group by s.code order by foods desc;
-- esperado: taco = 597

-- teste de busca fuzzy
select * from nutrition.search_food('arroz integral', 'BR', 5);

-- detalhe de um alimento
select nutrition.get_food_detail(
  (select id from nutrition.foods where name_pt ilike 'Arroz, integral, cozido' limit 1)
);
```

---

## 4. O que o app Swift vai consumir

### Endpoints prontos (via anon key)

| Uso                                 | Chamada                                                                                                                                 |
| ----------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| Buscar alimento (TACO local)        | `POST /rest/v1/rpc/search_food` body `{"q":"arroz","country":"BR","max_results":20}`                                                    |
| Detalhe completo de um alimento     | `POST /rest/v1/rpc/get_food_detail` body `{"food_uuid":"<uuid>"}`                                                                       |
| Buscar alimento US/global           | `GET https://api.nal.usda.gov/fdc/v1/foods/search?api_key=DEMO_KEY&query=...` (migrar para key própria)                                 |
| Código de barras                    | `GET https://world.openfoodfacts.org/api/v2/product/{ean}.json`                                                                         |
| Cachear resposta externa no DB      | `POST /rest/v1/foods_cache` (insert com authenticated JWT)                                                                              |

### Header obrigatório do PostgREST

Toda chamada REST ao schema `nutrition` precisa do header:
```
Accept-Profile: nutrition
Content-Profile: nutrition   (em POST/PATCH)
```

Quando usa `rpc/...`, o `Content-Profile` já resolve.

---

## 5. Atribuições obrigatórias

O app precisa exibir, em uma tela de "Créditos de dados":

- **TACO**: "Dados: TACO 4ª ed. (NEPA/Unicamp) — https://www.nepa.unicamp.br/taco/"
- **Open Food Facts**: "Contém dados do Open Food Facts (ODbL) — https://world.openfoodfacts.org/"
- **USDA** (opcional): "U.S. Department of Agriculture, FoodData Central"

A consulta `SELECT code, attribution_text, website_url FROM nutrition.sources WHERE attribution_required;` retorna tudo que precisa ser exibido.

---

## 6. Licenças das fontes

| Fonte        | Licença                | Uso comercial | Observações                                      |
| ------------ | ---------------------- | ------------- | ------------------------------------------------ |
| TACO (NEPA)  | Livre com citação      | ✅            | Dataset JSON via github.com/marcelosanto/tabela_taco (MIT) |
| USDA FDC     | CC0 1.0                | ✅            | Domínio público                                  |
| Open Food Facts | ODbL 1.0 + DbCL 1.0 | ✅            | Attribution + share-alike para derivados         |

---

## 7. Próximos passos (após MVP)

- Importar IBGE POF (tabela de medidas caseiras BR) — precisa do XLS oficial.
- Importar USDA Foundation Foods em bulk (~500 alimentos, ~5 MB) se precisar de maior cobertura offline.
- Adicionar `food_portions` + `food_aliases` se necessário.
- `pgvector` para busca semântica de nomes de alimentos informais ("pão na chapa").
