# Supabase AI Setup

Este repositório já está preparado para tirar a chave da OpenAI do app e usar uma Edge Function da Supabase.

## O que já foi ligado no código

- O app agora prefere `SUPABASE_URL + /functions/v1/openai-chat`.
- A chave real da OpenAI fica só no secret `OPENAI_API_KEY` da Supabase.
- Em `DEBUG`, o app ainda aceita `OPENAI_API_KEY` por variável de ambiente como fallback local.
- Em `Release` e TestFlight, a IA só funciona quando `SUPABASE_URL` e `SUPABASE_ANON_KEY` estiverem configurados.

## Arquivos criados

- `supabase/functions/openai-chat/index.ts`
- `supabase/config.toml`

## Passo a passo obrigatório

1. Faça login no CLI da Supabase.

```bash
supabase login
```

2. Ligue esta pasta ao seu projeto da Supabase.

```bash
supabase link --project-ref yfcmvdijvgeaihvwyssb
```

O `project_id` em `supabase/config.toml` já foi ajustado para `yfcmvdijvgeaihvwyssb`.

3. Salve a chave da OpenAI no cofre da Supabase.

```bash
supabase secrets set OPENAI_API_KEY=sua_chave_aqui OPENAI_MODEL=gpt-4.1-mini
```

Ou use o script local que pede a chave sem ecoar no terminal:

```bash
./scripts/supabase/set_openai_secret.sh
```

4. Publique a função.

```bash
supabase functions deploy openai-chat
```

5. Preencha estes dois valores no app em `SmartKitchen/Resources/Info.plist`:

- `SUPABASE_URL` já está configurado como `https://yfcmvdijvgeaihvwyssb.supabase.co`
- `SUPABASE_ANON_KEY` = chave `anon public` do painel da Supabase

6. Rode o app e teste uma pergunta no assistente.

## Teste manual rápido

```bash
curl -i \
  -X POST "https://yfcmvdijvgeaihvwyssb.supabase.co/functions/v1/openai-chat" \
  -H "Content-Type: application/json" \
  -H "apikey: SUA_ANON_KEY" \
  -H "Authorization: Bearer SUA_ANON_KEY" \
  -d '{"messages":[{"role":"user","content":"Diga oi"}]}'
```

## Observações importantes

- `SUPABASE_ANON_KEY` não é segredo. Pode ficar no app.
- `OPENAI_API_KEY` é segredo. Nunca deve voltar para o app.
- A função está com `verify_jwt = true`, então o request precisa usar o token `anon` válido da sua Supabase.
- Isso resolve o problema principal de segurança das chaves, mas não substitui rate limit e proteção contra abuso. Essas camadas ainda valem para produção.