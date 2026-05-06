#!/usr/bin/env python3
"""Merge premium gating / monetization translations into Localizable.xcstrings.

Source language is pt-BR. We add localizations for: en, es, fr, it, de, ja.
Existing keys are updated only when translations are missing or differ.
"""
import json
from pathlib import Path

T = {
    # ---- FeatureGate display names (Feature) ----
    "IA": {"en": "AI", "es": "IA", "fr": "IA", "it": "IA", "de": "KI", "ja": "AI"},
    "Importações": {"en": "Imports", "es": "Importaciones", "fr": "Imports", "it": "Importazioni", "de": "Importe", "ja": "インポート"},
    "IA Nutricional": {"en": "Nutrition AI", "es": "IA Nutricional", "fr": "IA Nutrition", "it": "IA Nutrizione", "de": "Ernährungs-KI", "ja": "栄養AI"},

    # ---- Hard gate display names ----
    "Sincronização iCloud": {"en": "iCloud Sync", "es": "Sincronización iCloud", "fr": "Synchronisation iCloud", "it": "Sincronizzazione iCloud", "de": "iCloud-Sync", "ja": "iCloud同期"},
    "Compartilhamento Familiar": {"en": "Family Sharing", "es": "Compartir en familia", "fr": "Partage familial", "it": "Condivisione in famiglia", "de": "Familienfreigabe", "ja": "ファミリー共有"},
    "Exportar Backup": {"en": "Export Backup", "es": "Exportar copia", "fr": "Exporter la sauvegarde", "it": "Esporta backup", "de": "Backup exportieren", "ja": "バックアップ書き出し"},

    # ---- Counters & reset ----
    "Hoje: %@": {"en": "Today: %@", "es": "Hoy: %@", "fr": "Aujourd'hui : %@", "it": "Oggi: %@", "de": "Heute: %@", "ja": "今日: %@"},
    "Renova à meia-noite": {"en": "Resets at midnight", "es": "Se renueva a medianoche", "fr": "Réinitialisé à minuit", "it": "Si rinnova a mezzanotte", "de": "Setzt sich um Mitternacht zurück", "ja": "深夜に更新"},

    # ---- Paywall ----
    "Você atingiu o limite diário de %@.": {"en": "You've reached today's %@ limit.", "es": "Alcanzaste el límite diario de %@.", "fr": "Vous avez atteint la limite quotidienne de %@.", "it": "Hai raggiunto il limite giornaliero di %@.", "de": "Du hast das tägliche %@-Limit erreicht.", "ja": "本日の%@の上限に達しました。"},
    "Desbloqueie tudo no Savoria": {"en": "Unlock everything in Savoria", "es": "Desbloquea todo en Savoria", "fr": "Débloquez tout dans Savoria", "it": "Sblocca tutto in Savoria", "de": "Schalte alles in Savoria frei", "ja": "Savoriaのすべてをアンロック"},

    # ---- Recipe import limit ----
    "Você atingiu o limite diário de importações (%lld/%lld). Assine Premium para importar quantas receitas quiser.": {
        "en": "You've reached today's import limit (%lld/%lld). Subscribe to Premium to import unlimited recipes.",
        "es": "Alcanzaste el límite diario de importaciones (%lld/%lld). Suscríbete a Premium para importar recetas sin límite.",
        "fr": "Vous avez atteint la limite quotidienne d'imports (%lld/%lld). Abonnez-vous à Premium pour des imports illimités.",
        "it": "Hai raggiunto il limite giornaliero di importazioni (%lld/%lld). Abbonati a Premium per importare ricette senza limiti.",
        "de": "Du hast das tägliche Import-Limit erreicht (%lld/%lld). Schließe Premium ab für unbegrenzte Importe.",
        "ja": "本日のインポート上限に達しました (%lld/%lld)。Premiumに登録すると無制限にレシピを取り込めます。"
    },

    # ---- Plan card ----
    "Plano atual": {"en": "Current plan", "es": "Plan actual", "fr": "Plan actuel", "it": "Piano attuale", "de": "Aktueller Plan", "ja": "現在のプラン"},
    "Free": {"en": "Free", "es": "Gratis", "fr": "Gratuit", "it": "Gratis", "de": "Gratis", "ja": "無料"},
    "Premium Anual": {"en": "Premium Annual", "es": "Premium Anual", "fr": "Premium Annuel", "it": "Premium Annuale", "de": "Premium Jährlich", "ja": "プレミアム年間"},
    "Premium Mensal": {"en": "Premium Monthly", "es": "Premium Mensual", "fr": "Premium Mensuel", "it": "Premium Mensile", "de": "Premium Monatlich", "ja": "プレミアム月間"},
    "Renova em %@": {"en": "Renews on %@", "es": "Se renueva el %@", "fr": "Renouvellement le %@", "it": "Si rinnova il %@", "de": "Verlängert sich am %@", "ja": "更新日: %@"},
    "Gerenciar": {"en": "Manage", "es": "Gestionar", "fr": "Gérer", "it": "Gestisci", "de": "Verwalten", "ja": "管理"},
    "Conhecer Premium": {"en": "See Premium", "es": "Conocer Premium", "fr": "Découvrir Premium", "it": "Scopri Premium", "de": "Premium entdecken", "ja": "Premiumを見る"},

    # ---- Restore feedback ----
    "Não foi possível restaurar agora. Tente novamente.": {"en": "Couldn't restore right now. Please try again.", "es": "No se pudo restaurar ahora. Inténtalo de nuevo.", "fr": "Impossible de restaurer pour le moment. Réessayez.", "it": "Impossibile ripristinare ora. Riprova.", "de": "Wiederherstellung gerade nicht möglich. Bitte erneut versuchen.", "ja": "現在復元できません。再度お試しください。"},
    "Assinatura restaurada com sucesso.": {"en": "Subscription restored successfully.", "es": "Suscripción restaurada con éxito.", "fr": "Abonnement restauré avec succès.", "it": "Abbonamento ripristinato con successo.", "de": "Abo erfolgreich wiederhergestellt.", "ja": "サブスクリプションを復元しました。"},
    "Sua assinatura já estava ativa.": {"en": "Your subscription was already active.", "es": "Tu suscripción ya estaba activa.", "fr": "Votre abonnement était déjà actif.", "it": "Il tuo abbonamento era già attivo.", "de": "Dein Abo war bereits aktiv.", "ja": "サブスクリプションはすでに有効です。"},
    "Nenhuma compra anterior encontrada.": {"en": "No previous purchases found.", "es": "No se encontraron compras anteriores.", "fr": "Aucun achat précédent trouvé.", "it": "Nessun acquisto precedente trovato.", "de": "Keine früheren Käufe gefunden.", "ja": "過去の購入は見つかりませんでした。"},

    # ---- Inline premium badge ----
    "Premium": {"en": "Premium", "es": "Premium", "fr": "Premium", "it": "Premium", "de": "Premium", "ja": "プレミアム"},

    # ---- Backup labels ----
    "Exportar backup": {"en": "Export backup", "es": "Exportar copia de seguridad", "fr": "Exporter la sauvegarde", "it": "Esporta backup", "de": "Backup exportieren", "ja": "バックアップを書き出す"},
    "Importar backup": {"en": "Import backup", "es": "Importar copia de seguridad", "fr": "Importer la sauvegarde", "it": "Importa backup", "de": "Backup importieren", "ja": "バックアップを読み込む"},
}


def main():
    path = Path("Shared/Localization/Localizable.xcstrings")
    data = json.loads(path.read_text())
    strings = data["strings"]

    added = 0
    updated = 0
    for key, langs in T.items():
        is_new = key not in strings
        entry = strings.setdefault(key, {})
        entry.setdefault("extractionState", "manual")
        loc = entry.setdefault("localizations", {})
        for lang, value in langs.items():
            existing = loc.get(lang, {}).get("stringUnit", {}).get("value")
            existing_state = loc.get(lang, {}).get("stringUnit", {}).get("state")
            if existing == value and existing_state == "translated":
                continue
            loc[lang] = {"stringUnit": {"state": "translated", "value": value}}
            if not is_new:
                updated += 1
        if is_new:
            added += 1

    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    print(f"keys processed: {len(T)}; added: {added}; updated: {updated}")


if __name__ == "__main__":
    main()
