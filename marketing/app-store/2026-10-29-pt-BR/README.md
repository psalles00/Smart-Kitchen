# Savoria — imagens da App Store em pt-BR

Nove PNGs RGB/sRGB sem transparência, 1320 × 2868, em `png/01.png` a `09.png`.
`preview.png`: visão geral 3 × 3. `sequence.png`: sequência horizontal.
`background-sequence.png`: panorama dos fundos. Textos em `copy.md`.

## Direção e regras permanentes

Referência: `/Volumes/PS-Externo/Coding/Rotina App/outputs/2026-10-02-appstore-localized/archived-delivery-folder/pt-BR`.
Mantidas as fontes Bricolage Grotesque Bold e Inter, a escala editorial, as curvas,
a moldura e o destaque de elementos. Paleta quente de pôr do sol.

**Nunca reaproveitar o fundo de uma posição antiga ao mudar a ordem.** O fundo
inteiro é um panorama de 11.880 × 2.868, recortado em nove partes consecutivas.
Curvas, iluminação e shader compartilham coordenadas absolutas. Ao reorganizar,
recompor o panorama e conferir todas as junções, tanto isoladas como na sequência.
A grade da peça 09 usa o mesmo contorno da curva clara, sem uma segunda superfície
branca atravessando o fundo. Regras aplicáveis também em `../AGENTS.md`.

## Ordem e comunicação

1. Apresentação do app.
2. Calorias sem obrigação de registrar todos os dias: média dos dias registrados;
   dias em branco não entram como zero. Quatro ícones maiores, com respiro.
3. Despensa → Mercado → Despensa: o texto explica que marcar um item faz a mudança
   automaticamente, nos dois sentidos. Prints sem a opção “Para depois”.
4. Ideias com a despensa: composição simplificada com contexto de ingredientes e
   quatro cartões, mantendo margens internas e sem a borda preta inferior.
5. Receita e ingredientes disponíveis.
6. Foto, texto e voz: câmera com visor e obturador, entrada digitada e áudio enviado
   com onda, duração e transcrição ilustrativa. Estimativas revisáveis.
7. Instagram, TikTok e YouTube → botão Compartilhar → Savoria. Preservada a
   informação sobre importação de receitas por fotos e arquivos.
8. Calorias e nutrientes.
9. Integração de receitas, listas e alimentação.

## Origem dos recursos

As capturas nativas vêm de views de produção no iPhone 17 Pro / Simulator em Release,
com fixture em ModelContainer **em memória, sem CloudKit**. Não são dados pessoais.
Teste: `AdaptiveWorkspaceRenderingTests.testAppStoreDemonstrationCaptures`, em
`SmartKitchenTests/ReserveListTests.swift`; última captura de listas passou com
uma execução e zero falhas, preservando 13 itens, cinco receitas e duas mensagens.
O estado `showReserve = false` existe só na fixture. As capturas são reutilizadas
nesta revisão gráfica; não houve alteração de funcionalidade do app.

Peça 02: infográfico ilustrativo, cinco dias somando 9.400 kcal, média 1.880 kcal.
A explicação foi confrontada com `NutritionAveragesService` e `SmartCountStepView`.
Peças 04 e 06: demonstrações simplificadas autorizadas, indicadas nas próprias artes;
não são prints literais nem evidência de inferência real. Fotos e ícones de comida
vêm dos recursos existentes do app. `crop-sources.json` registra origem dos recortes.
Moldura e fontes vêm do material de referência do Rotina.

Ícones sociais: [Simple Icons](https://github.com/simple-icons/simple-icons),
SVGs de [Instagram](https://raw.githubusercontent.com/simple-icons/simple-icons/develop/icons/instagram.svg),
[TikTok](https://raw.githubusercontent.com/simple-icons/simple-icons/develop/icons/tiktok.svg) e
[YouTube](https://raw.githubusercontent.com/simple-icons/simple-icons/develop/icons/youtube.svg),
obtidos em 29/10/2026. As marcas identificam as origens de importação;
não indicam parceria. Os símbolos de câmera, microfone, seta e compartilhar são
vetores locais. O pipeline de importação do app reconhece as três redes citadas.

## Revisão crítica e verificação

- Equilíbrio e agrupamento: foco principal por peça; fluxo visual social em uma linha.
- Respiro: margens internas dos destaques, sombras difusas; sem extrusão preta.
- Legibilidade: títulos e subtítulos dentro da área segura; fontes carregadas,
  proporções das capturas preservadas e sem títulos cortados no export.
- Clareza: câmera e áudio distinguíveis; ação das listas descrita de forma explícita.
- Continuidade: oito junções de fundo verificadas por pixels em `background-checks.json`;
  pequenas diferenças de antialiasing/grão entre pixels vizinhos são esperadas.
- Tipografia: famílias compartilhadas; tamanhos editoriais específicos por composição.
- Todos os PNGs foram inspecionados, incluindo a sequência e as composições alteradas
  em tamanho grande. Dimensões, alpha, bytes e hashes em `manifest.json`.

## Reprodução

```sh
node marketing/app-store/2026-10-29-pt-BR/prepare-crops.cjs
node marketing/app-store/2026-10-29-pt-BR/render.cjs
```

O renderer usa Playwright, Sharp e Chrome headless locais, encerrando o navegador
e o servidor ao terminar. O render completo valida as oito junções e atualiza os
manifestos. Para revisar manualmente, abrir a sequência e as nove imagens em alta.
Nenhuma chamada paga, inferência de IA ou publicação no App Store Connect.
