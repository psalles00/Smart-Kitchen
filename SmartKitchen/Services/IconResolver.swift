import UIKit

/// Resolves ingredient/item names to icon image filenames from the bundled icon library.
/// Uses a keyword → filename mapping for common kitchen items, with a fuzzy fallback.
enum IconResolver {

    // MARK: - Public

    /// Returns a UIImage for a given item name, or nil if no match.
    static func image(for name: String) -> UIImage? {
        guard let filename = resolve(name) else { return nil }
        return loadBundledIcon(filename)
    }

    /// Returns the filename (without path) for a given item name.
    static func resolve(_ name: String) -> String? {
        let lower = name.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Exact match in mapping
        if let file = keywordMap[lower] {
            return file
        }

        // 2. Partial match — check if any keyword is contained in the name
        for (keyword, file) in keywordMap where lower.contains(keyword) {
            return file
        }

        // 3. Slug-based guess: "name" → "name.png"
        let slug = lower
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "á", with: "a")
            .replacingOccurrences(of: "ã", with: "a")
            .replacingOccurrences(of: "â", with: "a")
            .replacingOccurrences(of: "é", with: "e")
            .replacingOccurrences(of: "ê", with: "e")
            .replacingOccurrences(of: "í", with: "i")
            .replacingOccurrences(of: "ó", with: "o")
            .replacingOccurrences(of: "õ", with: "o")
            .replacingOccurrences(of: "ô", with: "o")
            .replacingOccurrences(of: "ú", with: "u")
            .replacingOccurrences(of: "ç", with: "c")

        let slugFile = slug + ".png"
        if loadBundledIcon(slugFile) != nil {
            return slugFile
        }

        return nil
    }

    // MARK: - Bundle Loading

    private static func loadBundledIcon(_ filename: String) -> UIImage? {
        guard let path = Bundle.main.path(forResource: filename, ofType: nil, inDirectory: "images-128") else {
            // Try without directory (flat copy)
            guard let path2 = Bundle.main.path(forResource: filename, ofType: nil) else {
                return nil
            }
            return UIImage(contentsOfFile: path2)
        }
        return UIImage(contentsOfFile: path)
    }

    // MARK: - Keyword Map (PT-BR → icon filename)

    /// Maps Portuguese ingredient/item names to icon filenames.
    private static let keywordMap: [String: String] = [
        // Frutas
        "banana": "banana.png",
        "maçã": "apple.png",
        "maca": "apple.png",
        "laranja": "orange.png",
        "limão": "lemon.png",
        "limao": "lemon.png",
        "abacaxi": "pineapple.png",
        "morango": "strawberry.png",
        "uva": "grapes.png",
        "manga": "mango.png",
        "melancia": "watermelon.png",
        "pêssego": "peach.png",
        "abacate": "avocado.png",
        "coco": "coconut.png",
        "pera": "pear.png",

        // Vegetais
        "tomate": "tomato.png",
        "cebola": "onion.png",
        "alho": "garlic.png",
        "batata": "potato.png",
        "cenoura": "carrot.png",
        "brócolis": "broccoli.png",
        "brocolis": "broccoli.png",
        "alface": "lettuce.png",
        "espinafre": "spinach.png",
        "pepino": "cucumber.png",
        "pimentão": "bell-pepper.png",
        "pimentao": "bell-pepper.png",
        "milho": "corn.png",
        "cogumelo": "mushroom.png",
        "abobrinha": "zucchini.png",
        "berinjela": "eggplant.png",
        "beterraba": "beetroot.png",
        "alcachofra": "artichoke.png",

        // Carnes
        "frango": "chicken-raw.png",
        "carne": "meat.png",
        "boi": "beef.png",
        "porco": "pork.png",
        "peixe": "fish-raw.png",
        "camarão": "shrimp.png",
        "camarao": "shrimp.png",
        "bacon": "bacon.png",
        "linguiça": "sausage.png",
        "linguica": "sausage.png",
        "costela": "ribs.png",
        "peru": "turkey.png",
        "salmão": "salmon.png",
        "salmao": "salmon.png",
        "atum": "tuna.png",

        // Laticínios
        "leite": "milk.png",
        "queijo": "cheese.png",
        "iogurte": "yogurt.png",
        "manteiga": "butter.png",
        "creme de leite": "cream.png",
        "ovo": "egg.png",
        "ovos": "egg.png",

        // Grãos e massas
        "arroz": "rice.png",
        "feijão": "beans.png",
        "feijao": "beans.png",
        "macarrão": "pasta.png",
        "macarrao": "pasta.png",
        "pão": "bread.png",
        "pao": "bread.png",
        "farinha": "flour.png",
        "aveia": "oats.png",
        "trigo": "wheat.png",

        // Temperos e condimentos
        "sal": "salt-shaker.png",
        "açúcar": "sugar.png",
        "acucar": "sugar.png",
        "pimenta": "pepper.png",
        "canela": "cinnamon.png",
        "orégano": "oregano.png",
        "oregano": "oregano.png",
        "manjericão": "basil.png",
        "manjericao": "basil.png",
        "azeite": "olive-oil.png",
        "óleo": "cooking-oil.png",
        "oleo": "cooking-oil.png",
        "vinagre": "balsamic-vinegar.png",
        "mel": "honey.png",
        "molho de soja": "soy-sauce.png",
        "shoyu": "soy-sauce.png",
        "ketchup": "ketchup.png",
        "mostarda": "mustard.png",
        "maionese": "mayonnaise.png",

        // Bebidas
        "café": "coffee.png",
        "cafe": "coffee.png",
        "chá": "tea.png",
        "cha": "tea.png",
        "suco": "juice.png",
        "água": "water.png",
        "agua": "water.png",
        "cerveja": "beer.png",
        "vinho": "wine.png",

        // Doces e sobremesas
        "chocolate": "chocolate.png",
        "brigadeiro": "brigadeiro.png",
        "bolo": "cake.png",
        "sorvete": "ice-cream.png",
        "pudim": "pudding.png",
        "biscoito": "cookie.png",
        "leite condensado": "condensed-milk.png",

        // Utensílios / Cozinha
        "panela": "cooking-pot.png",
        "frigideira": "frying-pan.png",
        "forno": "oven.png",
        "geladeira": "refrigerator.png",
        "liquidificador": "blender.png",
        "colher": "spoon.png",
        "garfo": "fork.png",
        "faca": "knife.png",
    ]
}
