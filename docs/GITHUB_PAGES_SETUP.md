# GitHub Pages Setup

Resposta curta: sim, **GitHub Pages** e a forma mais prática e gratuita para hospedar essas páginas legais do Savoria.

Por que faz sentido aqui:
- As páginas são estáticas e não precisam de backend.
- O custo é zero.
- O deploy é simples.
- As URLs podem ser usadas direto no App Store Connect.

## Opção mais simples
git checkout main
git pull origin main
1. Suba este repositório para o GitHub.
2. Abra o repositório no GitHub.
3. Vá em **Settings** > **Pages**.
4. Em **Build and deployment**, escolha **Deploy from a branch**.
5. Em **Branch**, selecione a branch principal.
6. Em **Folder**, selecione **/docs**.
7. Salve.
8. Aguarde o GitHub publicar o site.

Depois disso, as URLs padrão ficam no formato:

- `https://SEU-USUARIO.github.io/NOME-DO-REPO/privacy/`
- `https://SEU-USUARIO.github.io/NOME-DO-REPO/terms/`

Essas duas URLs já podem ser colocadas no App Store Connect.

## Se o repositório for privado

Se o seu plano atual não permitir GitHub Pages para esse repositório privado, a saída mais simples é:

1. Criar um repositório público separado só para as páginas legais.
2. Copiar a pasta `docs/` para esse repositório.
3. Ativar GitHub Pages nesse repositório público.

## Se você quiser usar `savoria.app`

Depois que o site estiver funcionando no domínio padrão do GitHub Pages:

1. Configure o DNS do seu domínio.
2. Em **Settings** > **Pages**, adicione o domínio customizado.
3. Ative **Enforce HTTPS** depois que o certificado estiver pronto.

Configuração DNS típica para o domínio raiz:

```text
A     @     185.199.108.153
A     @     185.199.109.153
A     @     185.199.110.153
A     @     185.199.111.153
CNAME www   SEU-USUARIO.github.io
```

Depois disso, as URLs finais podem ficar assim:

- `https://savoria.app/privacy/`
- `https://savoria.app/terms/`

## O que preencher no App Store Connect

- **Privacy Policy URL**: URL de `privacy`
- **Terms of Use URL**: URL de `terms`

## Observação importante

Antes de publicar, confirme estes dois pontos:

1. O e-mail `support@savoria.app` existe e recebe mensagens.
2. O domínio final que você vai usar no App Store Connect já abre sem erro.