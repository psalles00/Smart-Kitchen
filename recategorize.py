#!/usr/bin/env python3
"""Recategorize items_database.json with new category names and fixes."""

import json
import sys

DB_PATH = "SmartKitchen/Resources/items_database.json"

# Step 1: Simple category renames
RENAMES = {
    "Vegetais": "Verduras e Legumes",
    "Laticínios": "Laticínios e Ovos",
    "Grãos e Massas": "Grãos, Massas e Cereais",
    "Snacks": "Snacks e Petiscos",
    "Limpeza": "Limpeza e Higiene",
    "Higiene Pessoal": "Limpeza e Higiene",
}

# Step 2: Fish/seafood items from "Proteínas" → "Peixes e Frutos do Mar"
# (everything else in Proteínas → "Carnes e Aves")
FISH_SEAFOOD_FILENAMES = {
    # Fish
    "fish.png", "fish-raw.png", "fish-cake.png", "fish-food.png",
    "fish-fillet.png", "salmon.png", "tuna.png", "sardine.png",
    "cod.png", "anchovy.png", "herring.png", "trout.png",
    "swordfish.png", "tilapia.png", "mackerel.png", "catfish.png",
    "fish-steak.png", "carp.png", "snapper.png", "bass.png",
    "dried-fish.png", "blowfish.png", "caviar.png", "sushi.png",
    "sashimi.png", "fish-sticks.png",
    # Seafood
    "shrimp.png", "crab.png", "lobster.png", "squid.png",
    "octopus.png", "oyster.png", "mussel.png", "clam.png",
    "scallop.png", "prawn.png", "crayfish.png", "seafood.png",
    "fried-shrimp.png",
}

# Fish/seafood keywords in titles (for items without obvious filenames)
FISH_KEYWORDS = {
    "peixe", "salmão", "salmao", "atum", "camarão", "camarao",
    "sardinha", "bacalhau", "anchova", "lula", "polvo", "lagosta",
    "caranguejo", "marisco", "ostra", "mexilhão", "mexilhao",
    "carangueijo", "tilápia", "tilapia", "truta", "robalo",
    "pescada", "merluza", "linguado", "tambaqui", "pacu",
    "pintado", "dourado", "surimi", "kani", "sashimi",
    "fish", "salmon", "tuna", "shrimp", "crab", "lobster",
    "squid", "octopus", "oyster", "mussel", "clam", "prawn",
    "anchovy", "sardine", "cod", "herring", "trout", "mackerel",
    "catfish", "tilapia", "swordfish", "caviar", "seafood",
    "scallop", "crayfish", "blowfish", "snapper",
}

# Step 3: Specific item moves (filename → new category)
SPECIFIC_MOVES = {
    # Eggs belong in Laticínios e Ovos
    "egg.png": "Laticínios e Ovos",
    "eggs.png": "Laticínios e Ovos",
    "fried-egg.png": "Laticínios e Ovos",
    "boiled-egg.png": "Laticínios e Ovos",
    "egg-carton.png": "Laticínios e Ovos",
    "quail-egg.png": "Laticínios e Ovos",
    # Cereal items that might be in wrong categories
    "oats.png": "Grãos, Massas e Cereais",
    "cereal.png": "Grãos, Massas e Cereais",
    "granola.png": "Grãos, Massas e Cereais",
    "muesli.png": "Grãos, Massas e Cereais",
    "cornflakes.png": "Grãos, Massas e Cereais",
    "quinoa.png": "Grãos, Massas e Cereais",
    "couscous.png": "Grãos, Massas e Cereais",
    # Containers/bottles that are in wrong categories
    "water-bottle.png": "Bebidas",
    "plastic-bottle.png": "Outros",
    "glass-bottle.png": "Outros",
    "can.png": "Outros",
    "jar.png": "Outros",
}


def is_fish_seafood(entry):
    """Check if a Proteínas item is fish/seafood."""
    filename = entry.get("nome_do_arquivo", "").lower()
    if filename in FISH_SEAFOOD_FILENAMES:
        return True
    # Check titles for fish keywords
    for title in entry.get("titulos", []):
        normalized = title.lower()
        for keyword in FISH_KEYWORDS:
            if keyword in normalized:
                return True
    return False


def recategorize(entries):
    """Apply all recategorization rules."""
    stats = {"renames": 0, "fish_split": 0, "meat_split": 0, "specific": 0}

    for entry in entries:
        filename = entry.get("nome_do_arquivo", "")
        old_cat = entry["categoria"]

        # Step 3 first: specific moves override everything
        if filename in SPECIFIC_MOVES:
            new_cat = SPECIFIC_MOVES[filename]
            if old_cat != new_cat:
                entry["categoria"] = new_cat
                stats["specific"] += 1
                continue

        # Step 2: Split Proteínas
        if old_cat == "Proteínas":
            if is_fish_seafood(entry):
                entry["categoria"] = "Peixes e Frutos do Mar"
                stats["fish_split"] += 1
            else:
                entry["categoria"] = "Carnes e Aves"
                stats["meat_split"] += 1
            continue

        # Step 1: Simple renames
        if old_cat in RENAMES:
            entry["categoria"] = RENAMES[old_cat]
            stats["renames"] += 1

    return stats


def main():
    with open(DB_PATH, "r", encoding="utf-8") as f:
        entries = json.load(f)

    print(f"Loaded {len(entries)} entries")

    # Show current category distribution
    cats = {}
    for e in entries:
        cats[e["categoria"]] = cats.get(e["categoria"], 0) + 1
    print("\nBEFORE:")
    for cat in sorted(cats.keys()):
        print(f"  {cat}: {cats[cat]}")

    stats = recategorize(entries)

    # Show new category distribution
    cats2 = {}
    for e in entries:
        cats2[e["categoria"]] = cats2.get(e["categoria"], 0) + 1
    print("\nAFTER:")
    for cat in sorted(cats2.keys()):
        print(f"  {cat}: {cats2[cat]}")

    print(f"\nChanges: {stats}")

    # Write back
    with open(DB_PATH, "w", encoding="utf-8") as f:
        json.dump(entries, f, ensure_ascii=False, indent=2)

    print(f"\nWritten to {DB_PATH}")


if __name__ == "__main__":
    main()
