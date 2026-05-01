#!/usr/bin/env python3
"""Merge onboarding/paywall/feature-gate translations into Localizable.xcstrings.

Source language is pt-BR. We add localizations for: en, es, fr, it, de, ja.
Existing keys are updated (only missing langs filled in); new keys are inserted.
"""
import json
from pathlib import Path

# Each entry: pt-BR key -> dict of {lang: translation}
# Languages: en, es, fr, it, de, ja
T = {
    # ---- Buttons / generic UI ----
    "Continuar": {"en": "Continue", "es": "Continuar", "fr": "Continuer", "it": "Continua", "de": "Weiter", "ja": "続ける"},
    "Começar": {"en": "Get Started", "es": "Comenzar", "fr": "Commencer", "it": "Inizia", "de": "Loslegen", "ja": "はじめる"},
    "Pular": {"en": "Skip", "es": "Omitir", "fr": "Passer", "it": "Salta", "de": "Überspringen", "ja": "スキップ"},
    "Continuar com plano grátis": {"en": "Continue with free plan", "es": "Continuar con el plan gratuito", "fr": "Continuer avec le plan gratuit", "it": "Continua con il piano gratuito", "de": "Mit Gratis-Plan fortfahren", "ja": "無料プランで続ける"},
    "Continuar com versão grátis": {"en": "Continue with free version", "es": "Continuar con la versión gratuita", "fr": "Continuer avec la version gratuite", "it": "Continua con la versione gratuita", "de": "Mit Gratis-Version fortfahren", "ja": "無料版で続ける"},
    "Restaurar": {"en": "Restore", "es": "Restaurar", "fr": "Restaurer", "it": "Ripristina", "de": "Wiederherstellen", "ja": "復元"},
    "Termos": {"en": "Terms", "es": "Términos", "fr": "Conditions", "it": "Termini", "de": "AGB", "ja": "利用規約"},
    "Privacidade": {"en": "Privacy", "es": "Privacidad", "fr": "Confidentialité", "it": "Privacy", "de": "Datenschutz", "ja": "プライバシー"},
    "Outro": {"en": "Other", "es": "Otro", "fr": "Autre", "it": "Altro", "de": "Andere", "ja": "その他"},

    # ---- Welcome / intro ----
    "Sua cozinha mais inteligente.": {"en": "Your smarter kitchen.", "es": "Tu cocina más inteligente.", "fr": "Votre cuisine plus intelligente.", "it": "La tua cucina più intelligente.", "de": "Deine smartere Küche.", "ja": "より賢いキッチン。"},
    "Despensa e mercado, conectados.": {"en": "Pantry and shopping, connected.", "es": "Despensa y mercado, conectados.", "fr": "Garde-manger et courses, connectés.", "it": "Dispensa e spesa, connesse.", "de": "Vorrat und Einkauf, verbunden.", "ja": "パントリーと買い物が連携。"},
    "Calorias sem culpa.": {"en": "Calories without guilt.", "es": "Calorías sin culpa.", "fr": "Calories sans culpabilité.", "it": "Calorie senza sensi di colpa.", "de": "Kalorien ohne schlechtes Gewissen.", "ja": "罪悪感のないカロリー管理。"},
    "Receitas direto das redes.": {"en": "Recipes straight from social media.", "es": "Recetas directo desde las redes.", "fr": "Recettes directement depuis les réseaux.", "it": "Ricette direttamente dai social.", "de": "Rezepte direkt aus den Netzwerken.", "ja": "SNSから直接レシピを取り込み。"},
    "Compartilhe links do Instagram, TikTok e YouTube — a IA monta a receita pra você.": {"en": "Share links from Instagram, TikTok and YouTube — AI assembles the recipe for you.", "es": "Comparte enlaces de Instagram, TikTok y YouTube — la IA arma la receta por ti.", "fr": "Partagez des liens d'Instagram, TikTok et YouTube — l'IA assemble la recette pour vous.", "it": "Condividi link da Instagram, TikTok e YouTube — l'IA assembla la ricetta per te.", "de": "Teile Links von Instagram, TikTok und YouTube — die KI baut das Rezept für dich.", "ja": "Instagram、TikTok、YouTubeのリンクを共有 — AIがレシピを組み立てます。"},
    "Compartilhe um link do TikTok ou Instagram e o Smart Kitchen estrutura tudo pra você — ingredientes, passos e mídias.": {"en": "Share a TikTok or Instagram link and Smart Kitchen structures everything — ingredients, steps and media.", "es": "Comparte un enlace de TikTok o Instagram y Smart Kitchen lo estructura todo — ingredientes, pasos y medios.", "fr": "Partagez un lien TikTok ou Instagram et Smart Kitchen structure tout — ingrédients, étapes et médias.", "it": "Condividi un link TikTok o Instagram e Smart Kitchen struttura tutto — ingredienti, passaggi e media.", "de": "Teile einen TikTok- oder Instagram-Link und Smart Kitchen strukturiert alles — Zutaten, Schritte und Medien.", "ja": "TikTokやInstagramのリンクを共有すると、Smart Kitchenが全て整理します — 材料、手順、メディア。"},
    "Conte macros nos dias que quiser. A IA do Smart Kitchen entende as lacunas e ainda dá ideias de receita com o que você tem em casa.": {"en": "Track macros on the days you want. Smart Kitchen's AI understands the gaps and even suggests recipes from what you have at home.", "es": "Cuenta macros los días que quieras. La IA de Smart Kitchen entiende los huecos y sugiere recetas con lo que tienes en casa.", "fr": "Comptez les macros les jours que vous voulez. L'IA de Smart Kitchen comprend les lacunes et suggère des recettes avec ce que vous avez chez vous.", "it": "Conta i macro nei giorni che vuoi. L'IA di Smart Kitchen capisce le lacune e suggerisce ricette con ciò che hai in casa.", "de": "Zähle Makros an den Tagen, an denen du willst. Die KI von Smart Kitchen versteht die Lücken und schlägt Rezepte mit dem vor, was du zuhause hast.", "ja": "好きな日にマクロを記録。Smart KitchenのAIがギャップを把握し、家にある食材でレシピも提案します。"},
    "Tirou da despensa? Vai pro mercado. Comprou? Volta pra despensa. Sem listas paralelas, sem trabalho dobrado.": {"en": "Used something from the pantry? Off to the shopping list. Bought it? Back to the pantry. No parallel lists, no double work.", "es": "¿Sacaste algo de la despensa? Va al mercado. ¿Lo compraste? Vuelve a la despensa. Sin listas paralelas, sin trabajo doble.", "fr": "Utilisé du garde-manger ? Direction la liste de courses. Acheté ? Retour au garde-manger. Pas de listes parallèles, pas de double travail.", "it": "Preso dalla dispensa? Va nella lista. Comprato? Torna in dispensa. Niente liste parallele, niente lavoro doppio.", "de": "Aus dem Vorrat genommen? Ab auf die Einkaufsliste. Gekauft? Zurück in den Vorrat. Keine Parallellisten, keine doppelte Arbeit.", "ja": "パントリーから使った？買い物リストへ。買った？パントリーに戻る。並行リストや二度手間はもうありません。"},

    # ---- Selection screens ----
    "O que tem na sua despensa?": {"en": "What's in your pantry?", "es": "¿Qué hay en tu despensa?", "fr": "Qu'y a-t-il dans votre garde-manger ?", "it": "Cosa c'è nella tua dispensa?", "de": "Was ist in deinem Vorrat?", "ja": "パントリーには何がありますか？"},
    "O que precisa comprar?": {"en": "What do you need to buy?", "es": "¿Qué necesitas comprar?", "fr": "Que devez-vous acheter ?", "it": "Cosa devi comprare?", "de": "Was musst du kaufen?", "ja": "何を買う必要がありますか？"},
    "O que você gosta de cozinhar?": {"en": "What do you like to cook?", "es": "¿Qué te gusta cocinar?", "fr": "Qu'aimez-vous cuisiner ?", "it": "Cosa ti piace cucinare?", "de": "Was kochst du gerne?", "ja": "何を料理するのが好きですか？"},
    "Escolha pelo menos 3 itens para sua primeira lista de compras.": {"en": "Pick at least 3 items for your first shopping list.", "es": "Elige al menos 3 artículos para tu primera lista de compras.", "fr": "Choisissez au moins 3 articles pour votre première liste.", "it": "Scegli almeno 3 articoli per la tua prima lista.", "de": "Wähle mindestens 3 Artikel für deine erste Einkaufsliste.", "ja": "最初の買い物リストに少なくとも3つ選んでください。"},
    "Escolha pelo menos 3 itens. Você pode editar tudo depois.": {"en": "Pick at least 3 items. You can edit everything later.", "es": "Elige al menos 3 artículos. Puedes editarlo todo después.", "fr": "Choisissez au moins 3 articles. Vous pourrez tout modifier plus tard.", "it": "Scegli almeno 3 articoli. Potrai modificare tutto dopo.", "de": "Wähle mindestens 3 Artikel. Du kannst später alles ändern.", "ja": "少なくとも3つ選んでください。後で全て編集できます。"},
    "Escolha pelo menos 3 receitas para começar sua coleção.": {"en": "Pick at least 3 recipes to start your collection.", "es": "Elige al menos 3 recetas para empezar tu colección.", "fr": "Choisissez au moins 3 recettes pour démarrer votre collection.", "it": "Scegli almeno 3 ricette per iniziare la tua collezione.", "de": "Wähle mindestens 3 Rezepte, um deine Sammlung zu starten.", "ja": "コレクションを始めるために少なくとも3つのレシピを選んでください。"},
    "Selecione mais \\(3 - count) para continuar": {"en": "Select \\(3 - count) more to continue", "es": "Selecciona \\(3 - count) más para continuar", "fr": "Sélectionnez encore \\(3 - count) pour continuer", "it": "Seleziona altri \\(3 - count) per continuare", "de": "Wähle noch \\(3 - count) aus, um fortzufahren", "ja": "続けるにはあと\\(3 - count)つ選択してください"},
    "\\(count) selecionadas": {"en": "\\(count) selected", "es": "\\(count) seleccionadas", "fr": "\\(count) sélectionnées", "it": "\\(count) selezionate", "de": "\\(count) ausgewählt", "ja": "\\(count)個選択済み"},
    "\\(count) selecionados": {"en": "\\(count) selected", "es": "\\(count) seleccionados", "fr": "\\(count) sélectionnés", "it": "\\(count) selezionati", "de": "\\(count) ausgewählt", "ja": "\\(count)個選択済み"},

    # ---- Tutorial steps ----
    "Despensa": {"en": "Pantry", "es": "Despensa", "fr": "Garde-manger", "it": "Dispensa", "de": "Vorrat", "ja": "パントリー"},
    "Mercado": {"en": "Shopping", "es": "Mercado", "fr": "Courses", "it": "Spesa", "de": "Einkauf", "ja": "買い物"},
    "Acabou na despensa? Mande pro mercado.": {"en": "Out of stock? Send it to the shopping list.", "es": "¿Se acabó en la despensa? Envíalo al mercado.", "fr": "Plus en stock ? Envoyez-le sur la liste de courses.", "it": "Finito in dispensa? Mandalo nella lista.", "de": "Aufgebraucht? Schick's auf die Einkaufsliste.", "ja": "パントリーで切れた？買い物リストへ。"},
    "Toque no carrinho de um item para movê-lo para sua lista de compras.": {"en": "Tap an item's cart icon to move it to your shopping list.", "es": "Toca el ícono de carrito de un artículo para moverlo a tu lista.", "fr": "Touchez l'icône panier d'un article pour le déplacer vers votre liste.", "it": "Tocca l'icona del carrello di un articolo per spostarlo nella lista.", "de": "Tippe auf das Warenkorb-Symbol eines Artikels, um ihn auf die Liste zu setzen.", "ja": "アイテムのカートアイコンをタップして買い物リストへ。"},
    "Toque no ícone de carrinho de um item": {"en": "Tap an item's cart icon", "es": "Toca el ícono de carrito de un artículo", "fr": "Touchez l'icône panier d'un article", "it": "Tocca l'icona del carrello", "de": "Tippe auf das Warenkorb-Symbol", "ja": "カートアイコンをタップ"},
    "Vai para o mercado": {"en": "Going to shopping list", "es": "Va al mercado", "fr": "Va dans la liste", "it": "Va nella lista", "de": "Geht zur Einkaufsliste", "ja": "買い物リストへ"},
    "Comprou? Marca como feito.": {"en": "Bought it? Mark as done.", "es": "¿Lo compraste? Márcalo como hecho.", "fr": "Acheté ? Marquez comme fait.", "it": "Comprato? Segnalo fatto.", "de": "Gekauft? Als erledigt markieren.", "ja": "買った？完了にマーク。"},
    "O item é enviado direto para sua despensa. Toque na caixinha de um item.": {"en": "The item goes straight to your pantry. Tap an item's checkbox.", "es": "El artículo va directo a tu despensa. Toca la casilla de un artículo.", "fr": "L'article va directement dans votre garde-manger. Touchez la case d'un article.", "it": "L'articolo va dritto in dispensa. Tocca la casella di un articolo.", "de": "Der Artikel wandert direkt in deinen Vorrat. Tippe auf die Checkbox.", "ja": "アイテムは直接パントリーへ。チェックボックスをタップ。"},
    "Toque na caixinha de um item": {"en": "Tap an item's checkbox", "es": "Toca la casilla de un artículo", "fr": "Touchez la case d'un article", "it": "Tocca la casella", "de": "Tippe auf die Checkbox", "ja": "チェックボックスをタップ"},
    "Toque em um item acima": {"en": "Tap an item above", "es": "Toca un artículo arriba", "fr": "Touchez un article ci-dessus", "it": "Tocca un articolo sopra", "de": "Tippe oben auf einen Artikel", "ja": "上のアイテムをタップ"},
    "Marque um item acima": {"en": "Check an item above", "es": "Marca un artículo arriba", "fr": "Cochez un article ci-dessus", "it": "Spunta un articolo sopra", "de": "Markiere oben einen Artikel", "ja": "上のアイテムにチェック"},
    "Vai para a despensa": {"en": "Going to pantry", "es": "Va a la despensa", "fr": "Va au garde-manger", "it": "Va in dispensa", "de": "Geht in den Vorrat", "ja": "パントリーへ"},
    "Tudo enviado!": {"en": "All sent!", "es": "¡Todo enviado!", "fr": "Tout envoyé !", "it": "Tutto inviato!", "de": "Alles gesendet!", "ja": "全て送信！"},
    "Lista concluída!": {"en": "List complete!", "es": "¡Lista completada!", "fr": "Liste terminée !", "it": "Lista completata!", "de": "Liste fertig!", "ja": "リスト完了！"},
    "Acesso rápido": {"en": "Quick access", "es": "Acceso rápido", "fr": "Accès rapide", "it": "Accesso rapido", "de": "Schnellzugriff", "ja": "クイックアクセス"},
    "Adicione o Savoria à sua tela inicial para acessar receitas, despensa e lista de compras com um toque.": {"en": "Add Savoria to your home screen to access recipes, pantry and shopping list with one tap.", "es": "Añade Savoria a tu pantalla de inicio para acceder a recetas, despensa y lista con un toque.", "fr": "Ajoutez Savoria à votre écran d'accueil pour accéder aux recettes, garde-manger et liste en un toucher.", "it": "Aggiungi Savoria alla schermata Home per accedere a ricette, dispensa e lista con un tocco.", "de": "Füge Savoria zum Startbildschirm hinzu, um mit einem Tipp auf Rezepte, Vorrat und Liste zuzugreifen.", "ja": "Savoriaをホーム画面に追加して、レシピ・パントリー・買い物リストにワンタップでアクセス。"},
    "Toque em Compartilhar": {"en": "Tap Share", "es": "Toca Compartir", "fr": "Touchez Partager", "it": "Tocca Condividi", "de": "Tippe auf Teilen", "ja": "共有をタップ"},

    # ---- Goals / nutrition ----
    "Qual é o seu objetivo?": {"en": "What's your goal?", "es": "¿Cuál es tu objetivo?", "fr": "Quel est votre objectif ?", "it": "Qual è il tuo obiettivo?", "de": "Was ist dein Ziel?", "ja": "目標は何ですか？"},
    "Vamos ajustar suas metas de calorias e macros pra você.": {"en": "We'll tune your calorie and macro goals.", "es": "Ajustaremos tus metas de calorías y macros.", "fr": "Nous ajusterons vos objectifs caloriques et macros.", "it": "Adatteremo i tuoi obiettivi di calorie e macro.", "de": "Wir passen deine Kalorien- und Makroziele an.", "ja": "カロリーとマクロの目標を調整します。"},
    "Perder peso": {"en": "Lose weight", "es": "Perder peso", "fr": "Perdre du poids", "it": "Perdere peso", "de": "Abnehmen", "ja": "減量"},
    "Reduzir calorias com déficit saudável": {"en": "Reduce calories with a healthy deficit", "es": "Reducir calorías con déficit saludable", "fr": "Réduire les calories avec un déficit sain", "it": "Ridurre le calorie con un deficit sano", "de": "Kalorien mit gesundem Defizit reduzieren", "ja": "健康的な不足でカロリーを減らす"},
    "Manter peso": {"en": "Maintain weight", "es": "Mantener peso", "fr": "Maintenir le poids", "it": "Mantenere il peso", "de": "Gewicht halten", "ja": "体重維持"},
    "Equilibrar consumo e gasto energético": {"en": "Balance intake and energy expenditure", "es": "Equilibrar consumo y gasto energético", "fr": "Équilibrer apport et dépense énergétique", "it": "Bilanciare apporto e dispendio energetico", "de": "Aufnahme und Energieverbrauch ausbalancieren", "ja": "摂取と消費のバランスをとる"},
    "Ganhar peso": {"en": "Gain weight", "es": "Ganar peso", "fr": "Prendre du poids", "it": "Prendere peso", "de": "Zunehmen", "ja": "増量"},
    "Ganhar massa com superávit calórico": {"en": "Gain mass with a calorie surplus", "es": "Ganar masa con superávit calórico", "fr": "Prendre de la masse avec un surplus calorique", "it": "Aumentare la massa con un surplus calorico", "de": "Mit Kalorienüberschuss Masse aufbauen", "ja": "カロリー過剰で体重増加"},
    "Qual é o seu sexo biológico?": {"en": "What's your biological sex?", "es": "¿Cuál es tu sexo biológico?", "fr": "Quel est votre sexe biologique ?", "it": "Qual è il tuo sesso biologico?", "de": "Was ist dein biologisches Geschlecht?", "ja": "生物学的性別は？"},
    "Usamos isso pra calcular sua taxa metabólica basal com precisão.": {"en": "We use this to calculate your basal metabolic rate accurately.", "es": "Lo usamos para calcular tu tasa metabólica basal con precisión.", "fr": "Nous l'utilisons pour calculer précisément votre métabolisme de base.", "it": "Lo usiamo per calcolare con precisione il tuo metabolismo basale.", "de": "Damit berechnen wir deinen Grundumsatz genau.", "ja": "基礎代謝率を正確に計算するために使用します。"},
    "Feminino": {"en": "Female", "es": "Femenino", "fr": "Féminin", "it": "Femminile", "de": "Weiblich", "ja": "女性"},
    "Masculino": {"en": "Male", "es": "Masculino", "fr": "Masculin", "it": "Maschile", "de": "Männlich", "ja": "男性"},
    "Quando você nasceu?": {"en": "When were you born?", "es": "¿Cuándo naciste?", "fr": "Quand êtes-vous né ?", "it": "Quando sei nato?", "de": "Wann wurdest du geboren?", "ja": "いつ生まれましたか？"},
    "Sua idade afeta a quantidade de calorias que seu corpo precisa.": {"en": "Your age affects how many calories your body needs.", "es": "Tu edad afecta cuántas calorías necesita tu cuerpo.", "fr": "Votre âge influence vos besoins caloriques.", "it": "L'età influenza il fabbisogno calorico.", "de": "Dein Alter beeinflusst, wie viele Kalorien dein Körper braucht.", "ja": "年齢は体に必要なカロリー量に影響します。"},
    "Sua altura e peso": {"en": "Your height and weight", "es": "Tu altura y peso", "fr": "Votre taille et poids", "it": "Altezza e peso", "de": "Größe und Gewicht", "ja": "身長と体重"},
    "Altura": {"en": "Height", "es": "Altura", "fr": "Taille", "it": "Altezza", "de": "Größe", "ja": "身長"},
    "Peso atual": {"en": "Current weight", "es": "Peso actual", "fr": "Poids actuel", "it": "Peso attuale", "de": "Aktuelles Gewicht", "ja": "現在の体重"},
    "Como é sua rotina?": {"en": "What's your routine like?", "es": "¿Cómo es tu rutina?", "fr": "Quelle est votre routine ?", "it": "Com'è la tua routine?", "de": "Wie sieht dein Alltag aus?", "ja": "ライフスタイルは？"},
    "Inclui exercício e movimentação do dia a dia.": {"en": "Includes exercise and day-to-day activity.", "es": "Incluye ejercicio y movimiento diario.", "fr": "Inclut l'exercice et l'activité quotidienne.", "it": "Include esercizio e movimento quotidiano.", "de": "Enthält Sport und Alltagsbewegung.", "ja": "運動と日常の動きを含みます。"},
    "Sedentário": {"en": "Sedentary", "es": "Sedentario", "fr": "Sédentaire", "it": "Sedentario", "de": "Sitzend", "ja": "座りがち"},
    "Pouco ou nenhum exercício": {"en": "Little or no exercise", "es": "Poco o nada de ejercicio", "fr": "Peu ou pas d'exercice", "it": "Poco o nessun esercizio", "de": "Wenig oder kein Sport", "ja": "ほとんど運動しない"},
    "Leve": {"en": "Light", "es": "Ligero", "fr": "Léger", "it": "Leggero", "de": "Leicht", "ja": "軽め"},
    "Exercício leve 1–3x por semana": {"en": "Light exercise 1–3x a week", "es": "Ejercicio ligero 1–3x por semana", "fr": "Exercice léger 1–3x par semaine", "it": "Esercizio leggero 1–3x a settimana", "de": "Leichter Sport 1–3x pro Woche", "ja": "軽い運動を週1〜3回"},
    "Moderado": {"en": "Moderate", "es": "Moderado", "fr": "Modéré", "it": "Moderato", "de": "Moderat", "ja": "中程度"},
    "Exercício moderado 3–5x por semana": {"en": "Moderate exercise 3–5x a week", "es": "Ejercicio moderado 3–5x por semana", "fr": "Exercice modéré 3–5x par semaine", "it": "Esercizio moderato 3–5x a settimana", "de": "Moderater Sport 3–5x pro Woche", "ja": "中程度の運動を週3〜5回"},
    "Ativo": {"en": "Active", "es": "Activo", "fr": "Actif", "it": "Attivo", "de": "Aktiv", "ja": "活発"},
    "Muito ativo": {"en": "Very active", "es": "Muy activo", "fr": "Très actif", "it": "Molto attivo", "de": "Sehr aktiv", "ja": "とても活発"},
    "Exercício intenso 6–7x por semana": {"en": "Intense exercise 6–7x a week", "es": "Ejercicio intenso 6–7x por semana", "fr": "Exercice intense 6–7x par semaine", "it": "Esercizio intenso 6–7x a settimana", "de": "Intensiver Sport 6–7x pro Woche", "ja": "激しい運動を週6〜7回"},
    "Extremamente ativo": {"en": "Extremely active", "es": "Extremadamente activo", "fr": "Extrêmement actif", "it": "Estremamente attivo", "de": "Extrem aktiv", "ja": "極めて活発"},
    "Treino físico pesado ou trabalho manual": {"en": "Heavy training or manual labor", "es": "Entrenamiento pesado o trabajo manual", "fr": "Entraînement intense ou travail manuel", "it": "Allenamento pesante o lavoro manuale", "de": "Hartes Training oder körperliche Arbeit", "ja": "激しいトレーニングまたは肉体労働"},
    "Exercício muito intenso diário": {"en": "Very intense daily exercise", "es": "Ejercicio muy intenso a diario", "fr": "Exercice très intense quotidien", "it": "Esercizio molto intenso quotidiano", "de": "Sehr intensiver täglicher Sport", "ja": "非常に激しい毎日の運動"},
    "Quanto quer ganhar por semana?": {"en": "How much do you want to gain per week?", "es": "¿Cuánto quieres ganar por semana?", "fr": "Combien voulez-vous prendre par semaine ?", "it": "Quanto vuoi prendere a settimana?", "de": "Wie viel willst du pro Woche zunehmen?", "ja": "週にどれだけ増やしたいですか？"},
    "Quanto quer perder por semana?": {"en": "How much do you want to lose per week?", "es": "¿Cuánto quieres perder por semana?", "fr": "Combien voulez-vous perdre par semaine ?", "it": "Quanto vuoi perdere a settimana?", "de": "Wie viel willst du pro Woche abnehmen?", "ja": "週にどれだけ減らしたいですか？"},
    "Recomendamos entre 0,3 e 0,75 kg/semana para resultados sustentáveis.": {"en": "We recommend between 0.3 and 0.75 kg/week for sustainable results.", "es": "Recomendamos entre 0,3 y 0,75 kg/semana para resultados sostenibles.", "fr": "Nous recommandons entre 0,3 et 0,75 kg/semaine pour des résultats durables.", "it": "Consigliamo tra 0,3 e 0,75 kg/settimana per risultati sostenibili.", "de": "Wir empfehlen 0,3 bis 0,75 kg/Woche für nachhaltige Ergebnisse.", "ja": "持続可能な結果のため、週0.3〜0.75kgを推奨します。"},
    "Ritmos acima de 0,75 kg/semana podem ser difíceis de manter.": {"en": "Rates above 0.75 kg/week may be hard to maintain.", "es": "Ritmos superiores a 0,75 kg/semana pueden ser difíciles de mantener.", "fr": "Au-delà de 0,75 kg/semaine, c'est difficile à tenir.", "it": "Ritmi sopra 0,75 kg/settimana possono essere difficili da mantenere.", "de": "Raten über 0,75 kg/Woche sind schwer zu halten.", "ja": "週0.75kgを超えるペースは維持が難しい場合があります。"},
    "Sem necessidade de definir um ritmo de mudança.": {"en": "No need to set a change rate.", "es": "No es necesario definir un ritmo de cambio.", "fr": "Pas besoin de définir un rythme de changement.", "it": "Non serve impostare un ritmo di cambiamento.", "de": "Keine Änderungsrate nötig.", "ja": "変化率を設定する必要はありません。"},
    "Vamos manter seu peso atual com calorias equilibradas.": {"en": "We'll keep your current weight with balanced calories.", "es": "Mantendremos tu peso actual con calorías equilibradas.", "fr": "Nous maintiendrons votre poids actuel avec des calories équilibrées.", "it": "Manterremo il peso attuale con calorie bilanciate.", "de": "Wir halten dein aktuelles Gewicht mit ausgewogenen Kalorien.", "ja": "バランスの取れたカロリーで現在の体重を維持します。"},
    "Devagar": {"en": "Slow", "es": "Lento", "fr": "Lent", "it": "Lento", "de": "Langsam", "ja": "ゆっくり"},
    "Agressivo": {"en": "Aggressive", "es": "Agresivo", "fr": "Agressif", "it": "Aggressivo", "de": "Aggressiv", "ja": "積極的"},
    "kg/semana": {"en": "kg/week", "es": "kg/semana", "fr": "kg/semaine", "it": "kg/settimana", "de": "kg/Woche", "ja": "kg/週"},

    # ---- Preparing screen ----
    "Personalizando sua experiência…": {"en": "Personalizing your experience…", "es": "Personalizando tu experiencia…", "fr": "Personnalisation de votre expérience…", "it": "Personalizzando la tua esperienza…", "de": "Erlebnis wird personalisiert…", "ja": "あなたの体験をパーソナライズ中…"},
    "Calculando suas calorias": {"en": "Calculating your calories", "es": "Calculando tus calorías", "fr": "Calcul de vos calories", "it": "Calcolando le calorie", "de": "Kalorien werden berechnet", "ja": "カロリーを計算中"},
    "Ajustando macros": {"en": "Adjusting macros", "es": "Ajustando macros", "fr": "Ajustement des macros", "it": "Regolando i macro", "de": "Makros werden angepasst", "ja": "マクロを調整中"},
    "Preparando despensa": {"en": "Preparing pantry", "es": "Preparando despensa", "fr": "Préparation du garde-manger", "it": "Preparando la dispensa", "de": "Vorrat wird vorbereitet", "ja": "パントリーを準備中"},
    "Salvando receitas": {"en": "Saving recipes", "es": "Guardando recetas", "fr": "Sauvegarde des recettes", "it": "Salvando le ricette", "de": "Rezepte werden gespeichert", "ja": "レシピを保存中"},
    "Tudo certo!": {"en": "All set!", "es": "¡Todo listo!", "fr": "C'est parti !", "it": "Tutto pronto!", "de": "Alles bereit!", "ja": "準備完了！"},

    # ---- Paywall ----
    "Desbloqueie tudo no Savoria": {"en": "Unlock everything in Savoria", "es": "Desbloquea todo en Savoria", "fr": "Débloquez tout dans Savoria", "it": "Sblocca tutto in Savoria", "de": "Schalte alles in Savoria frei", "ja": "Savoriaの全機能を解放"},
    "Comece com 7 dias grátis no plano anual.": {"en": "Start with a 7-day free trial on the annual plan.", "es": "Empieza con 7 días gratis en el plan anual.", "fr": "Commencez par 7 jours gratuits sur le plan annuel.", "it": "Inizia con 7 giorni gratis sul piano annuale.", "de": "Starte mit 7 Tagen gratis im Jahresplan.", "ja": "年間プランで7日間無料体験を始める。"},
    "7 dias grátis": {"en": "7-day free trial", "es": "7 días gratis", "fr": "7 jours gratuits", "it": "7 giorni gratis", "de": "7 Tage gratis", "ja": "7日間無料"},
    "IA ilimitada": {"en": "Unlimited AI", "es": "IA ilimitada", "fr": "IA illimitée", "it": "IA illimitata", "de": "Unbegrenzte KI", "ja": "AI無制限"},
    "Sugestões, importações e nutrição sem limites.": {"en": "Suggestions, imports and nutrition without limits.", "es": "Sugerencias, importaciones y nutrición sin límites.", "fr": "Suggestions, imports et nutrition sans limites.", "it": "Suggerimenti, importazioni e nutrizione senza limiti.", "de": "Vorschläge, Imports und Ernährung ohne Limits.", "ja": "提案・インポート・栄養を無制限で。"},
    "Compartilhamento familiar": {"en": "Family sharing", "es": "Compartir en familia", "fr": "Partage familial", "it": "Condivisione familiare", "de": "Familienfreigabe", "ja": "家族共有"},
    "Despensa e listas em tempo real com a família.": {"en": "Real-time pantry and lists with family.", "es": "Despensa y listas en tiempo real con la familia.", "fr": "Garde-manger et listes en temps réel en famille.", "it": "Dispensa e liste in tempo reale con la famiglia.", "de": "Vorrat und Listen in Echtzeit mit der Familie.", "ja": "家族とリアルタイムでパントリーとリスト共有。"},
    "iCloud + backup": {"en": "iCloud + backup", "es": "iCloud + copia de seguridad", "fr": "iCloud + sauvegarde", "it": "iCloud + backup", "de": "iCloud + Backup", "ja": "iCloud + バックアップ"},
    "Sincronização entre dispositivos com restauração.": {"en": "Cross-device sync with restore.", "es": "Sincronización entre dispositivos con restauración.", "fr": "Synchronisation multi-appareils avec restauration.", "it": "Sincronizzazione tra dispositivi con ripristino.", "de": "Geräteübergreifende Sync mit Wiederherstellung.", "ja": "デバイス間同期と復元。"},
    "Recursos novos primeiro": {"en": "New features first", "es": "Funciones nuevas primero", "fr": "Nouvelles fonctionnalités en premier", "it": "Nuove funzioni prima", "de": "Neue Funktionen zuerst", "ja": "新機能をいち早く"},
    "Acesso antecipado a tudo que lançamos.": {"en": "Early access to everything we launch.", "es": "Acceso anticipado a todo lo que lanzamos.", "fr": "Accès anticipé à tout ce que nous lançons.", "it": "Accesso anticipato a tutto ciò che lanciamo.", "de": "Früher Zugriff auf alles, was wir veröffentlichen.", "ja": "リリースされる全機能への早期アクセス。"},
    "Anual": {"en": "Annual", "es": "Anual", "fr": "Annuel", "it": "Annuale", "de": "Jährlich", "ja": "年間"},
    "Mensal": {"en": "Monthly", "es": "Mensual", "fr": "Mensuel", "it": "Mensile", "de": "Monatlich", "ja": "月間"},
    "Plano Anual": {"en": "Annual Plan", "es": "Plan Anual", "fr": "Plan annuel", "it": "Piano annuale", "de": "Jahresplan", "ja": "年間プラン"},
    "Plano Mensal": {"en": "Monthly Plan", "es": "Plan Mensual", "fr": "Plan mensuel", "it": "Piano mensile", "de": "Monatsplan", "ja": "月間プラン"},
    "/ano": {"en": "/year", "es": "/año", "fr": "/an", "it": "/anno", "de": "/Jahr", "ja": "/年"},
    "/mês": {"en": "/month", "es": "/mes", "fr": "/mois", "it": "/mese", "de": "/Monat", "ja": "/月"},
    "Equivale a %@/mês": {"en": "That's %@/month", "es": "Equivale a %@/mes", "fr": "Soit %@/mois", "it": "Equivale a %@/mese", "de": "Entspricht %@/Monat", "ja": "%@/月相当"},
    "Iniciar 7 dias grátis": {"en": "Start 7-day free trial", "es": "Iniciar 7 días gratis", "fr": "Démarrer les 7 jours gratuits", "it": "Inizia 7 giorni gratis", "de": "7 Tage gratis starten", "ja": "7日間無料体験を開始"},
    "Assinar agora": {"en": "Subscribe now", "es": "Suscribirse ahora", "fr": "S'abonner maintenant", "it": "Abbonati ora", "de": "Jetzt abonnieren", "ja": "今すぐ登録"},
    "Não se preocupe — você pode atualizar quando quiser.": {"en": "No worries — you can upgrade anytime.", "es": "Tranquilo — puedes mejorar cuando quieras.", "fr": "Pas de souci — vous pouvez passer à un plan supérieur à tout moment.", "it": "Tranquillo — puoi fare l'upgrade quando vuoi.", "de": "Keine Sorge — du kannst jederzeit upgraden.", "ja": "ご安心を — いつでもアップグレードできます。"},

    # ---- Feature gate ----
    "IA": {"en": "AI", "es": "IA", "fr": "IA", "it": "IA", "de": "KI", "ja": "AI"},
    "Importações": {"en": "Imports", "es": "Importaciones", "fr": "Imports", "it": "Importazioni", "de": "Imports", "ja": "インポート"},
    "IA Nutricional": {"en": "Nutrition AI", "es": "IA Nutricional", "fr": "IA Nutritionnelle", "it": "IA Nutrizionale", "de": "Ernährungs-KI", "ja": "栄養AI"},
    "Você atingiu o limite mensal de %@.": {"en": "You've reached the monthly limit for %@.", "es": "Has alcanzado el límite mensual de %@.", "fr": "Vous avez atteint la limite mensuelle de %@.", "it": "Hai raggiunto il limite mensile di %@.", "de": "Du hast das Monatslimit für %@ erreicht.", "ja": "%@の月間上限に達しました。"},
    "Esta semana": {"en": "This week", "es": "Esta semana", "fr": "Cette semaine", "it": "Questa settimana", "de": "Diese Woche", "ja": "今週"},

    # ---- Recipe seed: titles & descriptions ----
    "Panqueca Americana": {"en": "American Pancakes", "es": "Panqueques Americanos", "fr": "Pancakes américains", "it": "Pancake americani", "de": "American Pancakes", "ja": "アメリカンパンケーキ"},
    "Café da manhã fofinho e dourado em 25 minutos.": {"en": "Fluffy golden breakfast in 25 minutes.", "es": "Desayuno esponjoso y dorado en 25 minutos.", "fr": "Petit-déjeuner moelleux et doré en 25 minutes.", "it": "Colazione soffice e dorata in 25 minuti.", "de": "Fluffiges goldenes Frühstück in 25 Minuten.", "ja": "25分でふわふわの黄金朝食。"},
    "Salada Caesar": {"en": "Caesar Salad", "es": "Ensalada César", "fr": "Salade César", "it": "Insalata Caesar", "de": "Caesar Salad", "ja": "シーザーサラダ"},
    "Clássico crocante com molho cremoso.": {"en": "Crunchy classic with creamy dressing.", "es": "Clásico crujiente con aderezo cremoso.", "fr": "Classique croquant avec sauce crémeuse.", "it": "Classico croccante con condimento cremoso.", "de": "Knuspriger Klassiker mit cremigem Dressing.", "ja": "クリーミーなドレッシングのカリカリクラシック。"},
    "Brigadeiro": {"en": "Brigadeiro", "es": "Brigadeiro", "fr": "Brigadeiro", "it": "Brigadeiro", "de": "Brigadeiro", "ja": "ブリガデイロ"},
    "O doce brasileiro que ninguém recusa.": {"en": "The Brazilian sweet no one can refuse.", "es": "El dulce brasileño que nadie rechaza.", "fr": "La douceur brésilienne irrésistible.", "it": "Il dolce brasiliano che nessuno rifiuta.", "de": "Das brasilianische Süß, das niemand ablehnt.", "ja": "誰もが好きなブラジルのお菓子。"},
    "Smoothie Bowl": {"en": "Smoothie Bowl", "es": "Smoothie Bowl", "fr": "Smoothie bowl", "it": "Smoothie bowl", "de": "Smoothie Bowl", "ja": "スムージーボウル"},
    "Tigela energética de frutas para começar o dia.": {"en": "Energizing fruit bowl to start the day.", "es": "Bol energético de frutas para empezar el día.", "fr": "Bol énergétique aux fruits pour bien commencer.", "it": "Ciotola energetica di frutta per iniziare la giornata.", "de": "Energiebowl mit Früchten für den Start in den Tag.", "ja": "一日を始める元気なフルーツボウル。"},
    "Frango Grelhado com Legumes": {"en": "Grilled Chicken with Veggies", "es": "Pollo a la Parrilla con Verduras", "fr": "Poulet grillé aux légumes", "it": "Pollo grigliato con verdure", "de": "Gegrilltes Hähnchen mit Gemüse", "ja": "鶏肉と野菜のグリル"},
    "Proteína magra e legumes na chapa.": {"en": "Lean protein and grilled vegetables.", "es": "Proteína magra y verduras a la plancha.", "fr": "Protéine maigre et légumes grillés.", "it": "Proteina magra e verdure alla piastra.", "de": "Magere Proteine und gegrilltes Gemüse.", "ja": "赤身プロテインと焼き野菜。"},
    "Espaguete à Carbonara": {"en": "Spaghetti Carbonara", "es": "Espaguetis a la Carbonara", "fr": "Spaghetti à la carbonara", "it": "Spaghetti alla carbonara", "de": "Spaghetti Carbonara", "ja": "スパゲッティ・カルボナーラ"},
    "Italiano cremoso, sem creme de leite, em 20 min.": {"en": "Creamy Italian, no cream, in 20 minutes.", "es": "Italiano cremoso, sin nata, en 20 min.", "fr": "Italien crémeux, sans crème, en 20 min.", "it": "Italiano cremoso, senza panna, in 20 min.", "de": "Cremig italienisch, ohne Sahne, in 20 Min.", "ja": "生クリーム不使用のクリーミーなイタリアン、20分で。"},
    "Pasta ao molho rosé": {"en": "Pasta with Pink Sauce", "es": "Pasta a la salsa rosa", "fr": "Pâtes sauce rose", "it": "Pasta al sugo rosé", "de": "Pasta mit Rosé-Sauce", "ja": "ロゼソースのパスタ"},

    # ---- Tags ----
    "doce": {"en": "sweet", "es": "dulce", "fr": "sucré", "it": "dolce", "de": "süß", "ja": "甘い"},
    "café da manhã": {"en": "breakfast", "es": "desayuno", "fr": "petit-déjeuner", "it": "colazione", "de": "Frühstück", "ja": "朝食"},
    "saudável": {"en": "healthy", "es": "saludable", "fr": "sain", "it": "sano", "de": "gesund", "ja": "ヘルシー"},
    "salada": {"en": "salad", "es": "ensalada", "fr": "salade", "it": "insalata", "de": "Salat", "ja": "サラダ"},
    "brasileiro": {"en": "Brazilian", "es": "brasileño", "fr": "brésilien", "it": "brasiliano", "de": "brasilianisch", "ja": "ブラジル料理"},
    "italiano": {"en": "Italian", "es": "italiano", "fr": "italien", "it": "italiano", "de": "italienisch", "ja": "イタリアン"},
    "fitness": {"en": "fitness", "es": "fitness", "fr": "fitness", "it": "fitness", "de": "Fitness", "ja": "フィットネス"},
    "jantar": {"en": "dinner", "es": "cena", "fr": "dîner", "it": "cena", "de": "Abendessen", "ja": "夕食"},
    "Fácil": {"en": "Easy", "es": "Fácil", "fr": "Facile", "it": "Facile", "de": "Einfach", "ja": "簡単"},

    # ---- Ingredients (used in seed recipes) ----
    "Açúcar": {"en": "Sugar", "es": "Azúcar", "fr": "Sucre", "it": "Zucchero", "de": "Zucker", "ja": "砂糖"},
    "Alface": {"en": "Lettuce", "es": "Lechuga", "fr": "Laitue", "it": "Lattuga", "de": "Salat", "ja": "レタス"},
    "Alface romana": {"en": "Romaine lettuce", "es": "Lechuga romana", "fr": "Laitue romaine", "it": "Lattuga romana", "de": "Römersalat", "ja": "ロメインレタス"},
    "Alho": {"en": "Garlic", "es": "Ajo", "fr": "Ail", "it": "Aglio", "de": "Knoblauch", "ja": "にんにく"},
    "Arroz": {"en": "Rice", "es": "Arroz", "fr": "Riz", "it": "Riso", "de": "Reis", "ja": "米"},
    "Azeite": {"en": "Olive oil", "es": "Aceite de oliva", "fr": "Huile d'olive", "it": "Olio d'oliva", "de": "Olivenöl", "ja": "オリーブオイル"},
    "Bacon": {"en": "Bacon", "es": "Tocino", "fr": "Bacon", "it": "Pancetta", "de": "Speck", "ja": "ベーコン"},
    "Banana": {"en": "Banana", "es": "Plátano", "fr": "Banane", "it": "Banana", "de": "Banane", "ja": "バナナ"},
    "Banana congelada": {"en": "Frozen banana", "es": "Plátano congelado", "fr": "Banane congelée", "it": "Banana congelata", "de": "Gefrorene Banane", "ja": "冷凍バナナ"},
    "Batata": {"en": "Potato", "es": "Papa", "fr": "Pomme de terre", "it": "Patata", "de": "Kartoffel", "ja": "じゃがいも"},
    "Brócolis": {"en": "Broccoli", "es": "Brócoli", "fr": "Brocoli", "it": "Broccoli", "de": "Brokkoli", "ja": "ブロッコリー"},
    "Café": {"en": "Coffee", "es": "Café", "fr": "Café", "it": "Caffè", "de": "Kaffee", "ja": "コーヒー"},
    "Carne moída": {"en": "Ground beef", "es": "Carne molida", "fr": "Viande hachée", "it": "Carne macinata", "de": "Hackfleisch", "ja": "ひき肉"},
    "Cebola": {"en": "Onion", "es": "Cebolla", "fr": "Oignon", "it": "Cipolla", "de": "Zwiebel", "ja": "玉ねぎ"},
    "Cenoura": {"en": "Carrot", "es": "Zanahoria", "fr": "Carotte", "it": "Carota", "de": "Karotte", "ja": "にんじん"},
    "Chocolate": {"en": "Chocolate", "es": "Chocolate", "fr": "Chocolat", "it": "Cioccolato", "de": "Schokolade", "ja": "チョコレート"},
    "Chocolate em pó": {"en": "Cocoa powder", "es": "Cacao en polvo", "fr": "Cacao en poudre", "it": "Cacao in polvere", "de": "Kakaopulver", "ja": "ココアパウダー"},
    "Croutons": {"en": "Croutons", "es": "Croutons", "fr": "Croûtons", "it": "Crostini", "de": "Croutons", "ja": "クルトン"},
    "Espaguete": {"en": "Spaghetti", "es": "Espagueti", "fr": "Spaghetti", "it": "Spaghetti", "de": "Spaghetti", "ja": "スパゲッティ"},
    "Farinha": {"en": "Flour", "es": "Harina", "fr": "Farine", "it": "Farina", "de": "Mehl", "ja": "小麦粉"},
    "Farinha de trigo": {"en": "Wheat flour", "es": "Harina de trigo", "fr": "Farine de blé", "it": "Farina di grano", "de": "Weizenmehl", "ja": "薄力粉"},
    "Feijão": {"en": "Beans", "es": "Frijoles", "fr": "Haricots", "it": "Fagioli", "de": "Bohnen", "ja": "豆"},
    "Frango": {"en": "Chicken", "es": "Pollo", "fr": "Poulet", "it": "Pollo", "de": "Hähnchen", "ja": "鶏肉"},
    "Frutas vermelhas": {"en": "Berries", "es": "Frutos rojos", "fr": "Fruits rouges", "it": "Frutti rossi", "de": "Beeren", "ja": "ベリー"},
    "Granola": {"en": "Granola", "es": "Granola", "fr": "Granola", "it": "Granola", "de": "Granola", "ja": "グラノーラ"},
    "Iogurte": {"en": "Yogurt", "es": "Yogur", "fr": "Yaourt", "it": "Yogurt", "de": "Joghurt", "ja": "ヨーグルト"},
    "Iogurte natural": {"en": "Plain yogurt", "es": "Yogur natural", "fr": "Yaourt nature", "it": "Yogurt naturale", "de": "Naturjoghurt", "ja": "プレーンヨーグルト"},
    "Leite": {"en": "Milk", "es": "Leche", "fr": "Lait", "it": "Latte", "de": "Milch", "ja": "牛乳"},
    "Leite condensado": {"en": "Condensed milk", "es": "Leche condensada", "fr": "Lait concentré sucré", "it": "Latte condensato", "de": "Kondensmilch", "ja": "コンデンスミルク"},
    "Limão": {"en": "Lemon", "es": "Limón", "fr": "Citron", "it": "Limone", "de": "Zitrone", "ja": "レモン"},
    "Macarrão": {"en": "Pasta", "es": "Pasta", "fr": "Pâtes", "it": "Pasta", "de": "Nudeln", "ja": "パスタ"},
    "Manteiga": {"en": "Butter", "es": "Mantequilla", "fr": "Beurre", "it": "Burro", "de": "Butter", "ja": "バター"},
    "Maçã": {"en": "Apple", "es": "Manzana", "fr": "Pomme", "it": "Mela", "de": "Apfel", "ja": "りんご"},
    "Ovos": {"en": "Eggs", "es": "Huevos", "fr": "Œufs", "it": "Uova", "de": "Eier", "ja": "卵"},
    "Parmesão ralado": {"en": "Grated parmesan", "es": "Parmesano rallado", "fr": "Parmesan râpé", "it": "Parmigiano grattugiato", "de": "Geriebener Parmesan", "ja": "粉パルメザン"},
    "Pasta de dente": {"en": "Toothpaste", "es": "Pasta de dientes", "fr": "Dentifrice", "it": "Dentifricio", "de": "Zahnpasta", "ja": "歯磨き粉"},
    "Peito de frango": {"en": "Chicken breast", "es": "Pechuga de pollo", "fr": "Blanc de poulet", "it": "Petto di pollo", "de": "Hähnchenbrust", "ja": "鶏むね肉"},
    "Peito de frango grelhado": {"en": "Grilled chicken breast", "es": "Pechuga de pollo a la parrilla", "fr": "Blanc de poulet grillé", "it": "Petto di pollo grigliato", "de": "Gegrillte Hähnchenbrust", "ja": "グリルチキン"},
    "Peixe": {"en": "Fish", "es": "Pescado", "fr": "Poisson", "it": "Pesce", "de": "Fisch", "ja": "魚"},
    "Pão": {"en": "Bread", "es": "Pan", "fr": "Pain", "it": "Pane", "de": "Brot", "ja": "パン"},
    "Queijo": {"en": "Cheese", "es": "Queso", "fr": "Fromage", "it": "Formaggio", "de": "Käse", "ja": "チーズ"},
    "Sabão": {"en": "Soap", "es": "Jabón", "fr": "Savon", "it": "Sapone", "de": "Seife", "ja": "石鹸"},
    "Sal": {"en": "Salt", "es": "Sal", "fr": "Sel", "it": "Sale", "de": "Salz", "ja": "塩"},
    "Salgadinho": {"en": "Snack", "es": "Snack", "fr": "Snack", "it": "Snack", "de": "Snack", "ja": "スナック"},
    "Suco": {"en": "Juice", "es": "Jugo", "fr": "Jus", "it": "Succo", "de": "Saft", "ja": "ジュース"},
    "Tomate": {"en": "Tomato", "es": "Tomate", "fr": "Tomate", "it": "Pomodoro", "de": "Tomate", "ja": "トマト"},
    "Água": {"en": "Water", "es": "Agua", "fr": "Eau", "it": "Acqua", "de": "Wasser", "ja": "水"},
    "1 lata de tomate pelado": {"en": "1 can of peeled tomatoes", "es": "1 lata de tomate pelado", "fr": "1 boîte de tomates pelées", "it": "1 lattina di pomodori pelati", "de": "1 Dose geschälte Tomaten", "ja": "ホールトマト1缶"},
    "200 ml de creme de leite": {"en": "200 ml of cream", "es": "200 ml de nata", "fr": "200 ml de crème", "it": "200 ml di panna", "de": "200 ml Sahne", "ja": "生クリーム200ml"},
    "300 g de penne": {"en": "300 g of penne", "es": "300 g de penne", "fr": "300 g de penne", "it": "300 g di penne", "de": "300 g Penne", "ja": "ペンネ300g"},
    "25 min": {"en": "25 min", "es": "25 min", "fr": "25 min", "it": "25 min", "de": "25 Min", "ja": "25分"},
    "4 porções": {"en": "4 servings", "es": "4 porciones", "fr": "4 portions", "it": "4 porzioni", "de": "4 Portionen", "ja": "4人分"},

    # ---- Units ----
    "xícara": {"en": "cup", "es": "taza", "fr": "tasse", "it": "tazza", "de": "Tasse", "ja": "カップ"},
    "xícaras": {"en": "cups", "es": "tazas", "fr": "tasses", "it": "tazze", "de": "Tassen", "ja": "カップ"},
    "colher de sopa": {"en": "tablespoon", "es": "cucharada", "fr": "cuillère à soupe", "it": "cucchiaio", "de": "Esslöffel", "ja": "大さじ"},
    "colheres de sopa": {"en": "tablespoons", "es": "cucharadas", "fr": "cuillères à soupe", "it": "cucchiai", "de": "Esslöffel", "ja": "大さじ"},
    "lata": {"en": "can", "es": "lata", "fr": "boîte", "it": "lattina", "de": "Dose", "ja": "缶"},
    "pé": {"en": "head", "es": "pie", "fr": "pied", "it": "cespo", "de": "Stück", "ja": "株"},
    "pitada": {"en": "pinch", "es": "pizca", "fr": "pincée", "it": "pizzico", "de": "Prise", "ja": "ひとつまみ"},

    # ---- Recipe steps ----
    "Misture os ingredientes secos em uma tigela.": {"en": "Mix the dry ingredients in a bowl.", "es": "Mezcla los ingredientes secos en un bol.", "fr": "Mélangez les ingrédients secs dans un bol.", "it": "Mescola gli ingredienti secchi in una ciotola.", "de": "Trockene Zutaten in einer Schüssel mischen.", "ja": "乾燥材料をボウルで混ぜる。"},
    "Em outra, bata os ovos com leite e manteiga derretida.": {"en": "In another, whisk eggs with milk and melted butter.", "es": "En otro, bate los huevos con leche y mantequilla derretida.", "fr": "Dans un autre, fouettez les œufs avec lait et beurre fondu.", "it": "In un'altra, sbatti uova con latte e burro fuso.", "de": "In einer anderen Eier mit Milch und geschmolzener Butter verquirlen.", "ja": "別のボウルで卵・牛乳・溶かしバターを混ぜる。"},
    "Junte tudo até a massa ficar homogênea.": {"en": "Combine until smooth.", "es": "Junta todo hasta que la masa quede homogénea.", "fr": "Mélangez jusqu'à obtenir une pâte lisse.", "it": "Unisci tutto fino a ottenere un impasto omogeneo.", "de": "Alles glatt rühren.", "ja": "なめらかになるまで混ぜる。"},
    "Doure os dois lados em frigideira antiaderente.": {"en": "Brown both sides in a nonstick pan.", "es": "Dora los dos lados en sartén antiadherente.", "fr": "Dorez des deux côtés dans une poêle antiadhésive.", "it": "Doraa entrambi i lati in padella antiaderente.", "de": "Beide Seiten in einer beschichteten Pfanne goldbraun braten.", "ja": "ノンスティックパンで両面を焼く。"},
    "Sirva com mel ou frutas.": {"en": "Serve with honey or fruit.", "es": "Sirve con miel o frutas.", "fr": "Servez avec du miel ou des fruits.", "it": "Servi con miele o frutta.", "de": "Mit Honig oder Früchten servieren.", "ja": "ハチミツやフルーツを添えて。"},
    "Lave e rasgue as folhas de alface.": {"en": "Wash and tear the lettuce leaves.", "es": "Lava y rompe las hojas de lechuga.", "fr": "Lavez et déchirez les feuilles de laitue.", "it": "Lava e spezza le foglie di lattuga.", "de": "Salatblätter waschen und zerrupfen.", "ja": "レタスを洗ってちぎる。"},
    "Grelhe o frango temperado e fatie.": {"en": "Grill the seasoned chicken and slice.", "es": "Asa el pollo sazonado y rebana.", "fr": "Grillez le poulet assaisonné et tranchez.", "it": "Griglia il pollo condito e affetta.", "de": "Gewürztes Hähnchen grillen und schneiden.", "ja": "下味した鶏肉をグリルしてスライス。"},
    "Combine alface, croutons e frango.": {"en": "Combine lettuce, croutons and chicken.", "es": "Combina lechuga, croutons y pollo.", "fr": "Mélangez laitue, croûtons et poulet.", "it": "Unisci lattuga, crostini e pollo.", "de": "Salat, Croutons und Hähnchen mischen.", "ja": "レタス・クルトン・鶏肉を合わせる。"},
    "Regue com molho caesar e finalize com parmesão.": {"en": "Drizzle with Caesar dressing and top with parmesan.", "es": "Riega con salsa César y termina con parmesano.", "fr": "Arrosez de sauce César et finissez avec le parmesan.", "it": "Condisci con salsa Caesar e finisci con parmigiano.", "de": "Mit Caesar-Dressing beträufeln und mit Parmesan toppen.", "ja": "シーザードレッシングをかけパルメザンで仕上げる。"},
    "Misture todos os ingredientes em uma panela.": {"en": "Mix all ingredients in a saucepan.", "es": "Mezcla todos los ingredientes en una olla.", "fr": "Mélangez tous les ingrédients dans une casserole.", "it": "Mescola tutti gli ingredienti in una pentola.", "de": "Alle Zutaten in einem Topf mischen.", "ja": "全材料を鍋で混ぜる。"},
    "Cozinhe em fogo baixo mexendo até desgrudar do fundo.": {"en": "Cook on low heat, stirring until it pulls from the bottom.", "es": "Cocina a fuego lento removiendo hasta que se despegue del fondo.", "fr": "Cuisez à feu doux en remuant jusqu'à ce que ça se détache du fond.", "it": "Cuoci a fuoco basso mescolando finché non si stacca dal fondo.", "de": "Bei niedriger Hitze unter Rühren kochen, bis es sich vom Boden löst.", "ja": "弱火でかき混ぜ、底から離れるまで煮る。"},
    "Espere esfriar, faça bolinhas e passe no granulado.": {"en": "Let cool, roll into balls and coat in sprinkles.", "es": "Deja enfriar, haz bolitas y pasa por granulado.", "fr": "Laissez refroidir, formez des boules et enrobez de vermicelles.", "it": "Lascia raffreddare, forma palline e passa nelle codette.", "de": "Abkühlen lassen, Kugeln formen und in Streuseln wälzen.", "ja": "冷めたら丸めてグラニュレートをまぶす。"},
    "Bata banana, frutas e iogurte no liquidificador.": {"en": "Blend banana, berries and yogurt.", "es": "Bate plátano, frutas y yogur en la licuadora.", "fr": "Mixez banane, fruits et yaourt.", "it": "Frulla banana, frutti e yogurt.", "de": "Banane, Beeren und Joghurt mixen.", "ja": "バナナ・ベリー・ヨーグルトをミキサーにかける。"},
    "Despeje em uma tigela.": {"en": "Pour into a bowl.", "es": "Vierte en un bol.", "fr": "Versez dans un bol.", "it": "Versa in una ciotola.", "de": "In eine Schüssel füllen.", "ja": "ボウルに注ぐ。"},
    "Decore com granola e frutas frescas.": {"en": "Top with granola and fresh fruit.", "es": "Decora con granola y frutas frescas.", "fr": "Garnissez de granola et de fruits frais.", "it": "Decora con granola e frutta fresca.", "de": "Mit Granola und frischen Früchten toppen.", "ja": "グラノーラと新鮮なフルーツをトッピング。"},
    "Tempere o frango com sal, pimenta e alho.": {"en": "Season chicken with salt, pepper and garlic.", "es": "Sazona el pollo con sal, pimienta y ajo.", "fr": "Assaisonnez le poulet avec sel, poivre et ail.", "it": "Condisci il pollo con sale, pepe e aglio.", "de": "Hähnchen mit Salz, Pfeffer und Knoblauch würzen.", "ja": "鶏肉に塩・こしょう・にんにくで下味。"},
    "Grelhe 6–8 minutos de cada lado.": {"en": "Grill 6–8 minutes per side.", "es": "Asa 6–8 minutos por cada lado.", "fr": "Grillez 6–8 minutes de chaque côté.", "it": "Griglia 6–8 minuti per lato.", "de": "6–8 Minuten pro Seite grillen.", "ja": "片面6〜8分ずつ焼く。"},
    "Salteie os legumes no azeite.": {"en": "Sauté vegetables in olive oil.", "es": "Saltea las verduras en aceite de oliva.", "fr": "Faites sauter les légumes à l'huile d'olive.", "it": "Salta le verdure nell'olio d'oliva.", "de": "Gemüse in Olivenöl anbraten.", "ja": "野菜をオリーブオイルで炒める。"},
    "Sirva o frango ao lado dos legumes.": {"en": "Serve the chicken alongside the vegetables.", "es": "Sirve el pollo junto a las verduras.", "fr": "Servez le poulet avec les légumes.", "it": "Servi il pollo con le verdure.", "de": "Hähnchen mit dem Gemüse servieren.", "ja": "野菜と一緒に鶏肉を盛る。"},
    "Cozinhe o espaguete al dente em água salgada.": {"en": "Cook spaghetti al dente in salted water.", "es": "Cocina los espaguetis al dente en agua con sal.", "fr": "Cuisez les spaghetti al dente dans l'eau salée.", "it": "Cuoci gli spaghetti al dente in acqua salata.", "de": "Spaghetti al dente in Salzwasser kochen.", "ja": "塩水でスパゲッティをアルデンテに茹でる。"},
    "Doure o bacon em fogo médio.": {"en": "Brown the bacon over medium heat.", "es": "Dora el bacon a fuego medio.", "fr": "Faites dorer le bacon à feu moyen.", "it": "Rosola il bacon a fuoco medio.", "de": "Speck bei mittlerer Hitze anbraten.", "ja": "ベーコンを中火で焼く。"},
    "Bata as gemas com o parmesão.": {"en": "Whisk yolks with parmesan.", "es": "Bate las yemas con el parmesano.", "fr": "Fouettez les jaunes avec le parmesan.", "it": "Sbatti i tuorli con il parmigiano.", "de": "Eigelb mit Parmesan verquirlen.", "ja": "卵黄とパルメザンを混ぜる。"},
    "Misture tudo fora do fogo, ajustando com a água da massa.": {"en": "Mix everything off the heat, adjusting with pasta water.", "es": "Mezcla todo fuera del fuego, ajustando con agua de la pasta.", "fr": "Mélangez le tout hors du feu, ajustez avec l'eau de cuisson.", "it": "Mescola tutto fuori dal fuoco, regolando con l'acqua di cottura.", "de": "Alles abseits der Hitze mischen, mit Nudelwasser anpassen.", "ja": "火から下ろしてパスタの茹で汁で調整しながら和える。"},

    # ---- Round 2 redesign additions ----
    "Pulou um dia? Sem problema.": {"en": "Skipped a day? No problem.", "es": "¿Saltaste un día? Sin problema.", "fr": "Sauté un jour ? Aucun souci.", "it": "Saltato un giorno? Nessun problema.", "de": "Einen Tag ausgelassen? Kein Problem.", "ja": "1日スキップしても大丈夫。"},
    "O Savoria calcula uma média inteligente apenas com os dias que você registrou — nada de zerar sua semana porque você esqueceu de logar.": {"en": "Savoria computes a smart average from only the days you logged — no more zeroing out your week because you forgot.", "es": "Savoria calcula un promedio inteligente solo con los días que registraste — sin arruinar la semana por olvidar.", "fr": "Savoria calcule une moyenne intelligente uniquement avec les jours enregistrés — fini de remettre la semaine à zéro pour un oubli.", "it": "Savoria calcola una media intelligente solo dai giorni registrati — niente settimane azzerate per una dimenticanza.", "de": "Savoria berechnet einen intelligenten Durchschnitt nur aus den protokollierten Tagen — keine Nullwoche wegen vergessener Einträge.", "ja": "Savoriaは記録した日だけから賢く平均を算出 — 記録漏れで週がリセットされません。"},
    "Média de \\(loggedDaysCount) dias registrados": {"en": "Average of \\(loggedDaysCount) logged days", "es": "Promedio de \\(loggedDaysCount) días registrados", "fr": "Moyenne sur \\(loggedDaysCount) jours enregistrés", "it": "Media di \\(loggedDaysCount) giorni registrati", "de": "Durchschnitt aus \\(loggedDaysCount) protokollierten Tagen", "ja": "記録された\\(loggedDaysCount)日の平均"},
    "Média": {"en": "Average", "es": "Promedio", "fr": "Moyenne", "it": "Media", "de": "Durchschnitt", "ja": "平均"},
    "Assistente IA": {"en": "AI Assistant", "es": "Asistente IA", "fr": "Assistant IA", "it": "Assistente IA", "de": "KI-Assistent", "ja": "AIアシスタント"},
    "Recebemos seus dados. Seu Savoria está pronto pra usar.": {"en": "We've got your data. Your Savoria is ready to use.", "es": "Tenemos tus datos. Tu Savoria está listo.", "fr": "Vos données sont là. Votre Savoria est prêt.", "it": "Abbiamo i tuoi dati. Il tuo Savoria è pronto.", "de": "Deine Daten sind da. Dein Savoria ist startklar.", "ja": "データを受け取りました。Savoriaの準備完了です。"},
    "Escolha pelo menos 3 itens. Arraste para descobrir mais.": {"en": "Pick at least 3 items. Drag to discover more.", "es": "Elige al menos 3 artículos. Arrastra para ver más.", "fr": "Choisissez au moins 3 articles. Glissez pour en découvrir plus.", "it": "Scegli almeno 3 articoli. Trascina per scoprirne altri.", "de": "Wähle mindestens 3 Artikel. Ziehe, um mehr zu entdecken.", "ja": "3つ以上選んでください。ドラッグして他のアイテムも探せます。"},
    "Por meta": {"en": "By goal", "es": "Por meta", "fr": "Par objectif", "it": "Per obiettivo", "de": "Nach Ziel", "ja": "目標から"},
    "Por semana": {"en": "Per week", "es": "Por semana", "fr": "Par semaine", "it": "A settimana", "de": "Pro Woche", "ja": "週ごと"},
    "Quero chegar a": {"en": "I want to reach", "es": "Quiero llegar a", "fr": "Je veux atteindre", "it": "Voglio arrivare a", "de": "Ich will erreichen", "ja": "目標体重"},
    "Em quantos meses": {"en": "In how many months", "es": "En cuántos meses", "fr": "En combien de mois", "it": "In quanti mesi", "de": "In wie vielen Monaten", "ja": "何ヶ月で"},
    "mês": {"en": "month", "es": "mes", "fr": "mois", "it": "mese", "de": "Monat", "ja": "ヶ月"},
    "meses": {"en": "months", "es": "meses", "fr": "mois", "it": "mesi", "de": "Monate", "ja": "ヶ月"},
    "Equivale a %.2f kg/semana": {"en": "That's %.2f kg/week", "es": "Equivale a %.2f kg/semana", "fr": "Soit %.2f kg/semaine", "it": "Equivale a %.2f kg/settimana", "de": "Entspricht %.2f kg/Woche", "ja": "%.2f kg/週相当"},
    "Defina o peso-alvo e o prazo. Você pode ajustar pra kg/semana se preferir.": {"en": "Set your target weight and timeframe. You can switch to kg/week if you prefer.", "es": "Define tu peso objetivo y el plazo. Puedes cambiar a kg/semana si prefieres.", "fr": "Définissez le poids cible et le délai. Vous pouvez basculer sur kg/semaine si vous préférez.", "it": "Imposta peso obiettivo e tempo. Puoi passare a kg/settimana se preferisci.", "de": "Lege Zielgewicht und Zeitraum fest. Du kannst auf kg/Woche umschalten, wenn du willst.", "ja": "目標体重と期間を設定。お好みでkg/週に切り替えられます。"},
    "Qual seu plano de perda?": {"en": "What's your weight-loss plan?", "es": "¿Cuál es tu plan de pérdida?", "fr": "Quel est votre plan de perte ?", "it": "Qual è il tuo piano di perdita?", "de": "Wie sieht dein Abnehm-Plan aus?", "ja": "減量プランは？"},
    "Qual seu plano de ganho?": {"en": "What's your weight-gain plan?", "es": "¿Cuál es tu plan de ganancia?", "fr": "Quel est votre plan de prise ?", "it": "Qual è il tuo piano di crescita?", "de": "Wie sieht dein Zunehm-Plan aus?", "ja": "増量プランは？"},
}


def main():
    path = Path("Shared/Localization/Localizable.xcstrings")
    data = json.loads(path.read_text())
    strings = data["strings"]

    added = 0
    updated = 0
    for key, langs in T.items():
        entry = strings.setdefault(key, {})
        # xcstrings expects "extractionState":"manual" for keys not in source code
        entry.setdefault("extractionState", "manual")
        loc = entry.setdefault("localizations", {})
        was_new = "localizations" not in entry or not loc
        for lang, value in langs.items():
            existing = loc.get(lang, {}).get("stringUnit", {}).get("value")
            if existing == value and loc.get(lang, {}).get("stringUnit", {}).get("state") == "translated":
                continue
            loc[lang] = {"stringUnit": {"state": "translated", "value": value}}
            if was_new:
                pass
            else:
                updated += 1
        if was_new:
            added += 1

    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    print(f"keys processed: {len(T)}; added: {added}; updated: {updated}")


if __name__ == "__main__":
    main()
