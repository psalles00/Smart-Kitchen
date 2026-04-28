import Foundation

/// Helpers para escalar quantidades de ingredientes com base num multiplicador
/// (porção alvo / porção original) sem alterar o modelo persistido.
///
/// Tudo é feito em memória, apenas para apresentação no detail.
enum IngredientQuantityScaler {

    /// Formata uma quantidade `Double` aplicando o multiplicador `m`.
    /// Mantém número inteiro como inteiro, e usa frações comuns (½, ¼, ⅓…) quando aplicável.
    static func formatQuantity(_ quantity: Double?, by multiplier: Double) -> String? {
        guard let q = quantity, q > 0, multiplier > 0 else { return nil }
        let scaled = q * multiplier
        return formatNumber(scaled)
    }

    /// Aplica um multiplicador a uma string livre de quantidade (ex.: "1 ½", "200", "0,5").
    /// Se não conseguir extrair um número, retorna a string original.
    static func scaleQuantityString(_ raw: String, by multiplier: Double) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, multiplier > 0 else { return raw }

        if let parsed = parseLeadingNumber(trimmed) {
            let scaled = parsed.value * multiplier
            let rest = String(trimmed[parsed.endIndex...]).trimmingCharacters(in: .whitespaces)
            let formatted = formatNumber(scaled)
            return rest.isEmpty ? formatted : "\(formatted) \(rest)"
        }
        return raw
    }

    /// Formata um Double como número limpo:
    /// - inteiro se a fração for muito pequena
    /// - usa fração unicode (½, ¼, ¾, ⅓, ⅔) quando próximo
    /// - caso contrário usa 1 casa decimal com vírgula (pt-BR)
    static func formatNumber(_ value: Double) -> String {
        if value <= 0 { return "0" }
        let rounded = (value * 100).rounded() / 100
        let intPart = Int(rounded)
        let frac = rounded - Double(intPart)

        // Tolerância para detectar frações conhecidas.
        let tol = 0.04
        let fractionMap: [(Double, String)] = [
            (0.0, ""),
            (0.25, "¼"),
            (1.0/3.0, "⅓"),
            (0.5, "½"),
            (2.0/3.0, "⅔"),
            (0.75, "¾"),
            (1.0, "")  // arredonda para inteiro acima
        ]

        for (target, glyph) in fractionMap {
            if abs(frac - target) <= tol {
                if target >= 0.97 {
                    // Subiu para o próximo inteiro.
                    return "\(intPart + 1)"
                }
                if target <= 0.04 {
                    return "\(intPart)"
                }
                if intPart == 0 {
                    return glyph
                }
                return "\(intPart) \(glyph)"
            }
        }

        // Fallback: formato decimal pt-BR com até 1 casa.
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: rounded)) ?? "\(rounded)"
    }

    /// Tenta ler o número à esquerda da string. Aceita inteiros, decimais (com . ou ,),
    /// frações ASCII ("1/2") e composições simples ("1 1/2"). Retorna o valor e o índice
    /// onde o restante começa.
    private static func parseLeadingNumber(_ text: String) -> (value: Double, endIndex: String.Index)? {
        // Mapa de frações unicode no início.
        let unicodeFractions: [(String, Double)] = [
            ("½", 0.5), ("¼", 0.25), ("¾", 0.75),
            ("⅓", 1.0/3.0), ("⅔", 2.0/3.0),
            ("⅕", 0.2), ("⅖", 0.4), ("⅗", 0.6), ("⅘", 0.8),
            ("⅙", 1.0/6.0), ("⅚", 5.0/6.0),
            ("⅛", 0.125), ("⅜", 0.375), ("⅝", 0.625), ("⅞", 0.875)
        ]
        for (glyph, value) in unicodeFractions {
            if text.hasPrefix(glyph) {
                let endIndex = text.index(text.startIndex, offsetBy: glyph.count)
                return (value, endIndex)
            }
        }

        // Padrão: inteiro opcional + (espaço + fração unicode | espaço + frac ASCII | decimal | frac ASCII pura)
        // Pega o primeiro token "número-ish".
        let pattern = #"^(\d+(?:[.,]\d+)?)(?:\s+(\d+)/(\d+))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, range: range), match.range.location == 0 else {
            // Frac ASCII pura: "1/2 xícara"
            let fracPattern = #"^(\d+)/(\d+)"#
            if let r = try? NSRegularExpression(pattern: fracPattern),
               let m = r.firstMatch(in: text, range: range) {
                let num = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let den = Double(ns.substring(with: m.range(at: 2))) ?? 1
                guard den > 0 else { return nil }
                if let endIndex = text.index(text.startIndex, offsetBy: m.range.length, limitedBy: text.endIndex) {
                    return (num / den, endIndex)
                }
            }
            return nil
        }

        let mainStr = ns.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: ".")
        guard let main = Double(mainStr) else { return nil }
        var total = main
        var consumed = match.range.length

        if match.range(at: 2).location != NSNotFound,
           match.range(at: 3).location != NSNotFound {
            let num = Double(ns.substring(with: match.range(at: 2))) ?? 0
            let den = Double(ns.substring(with: match.range(at: 3))) ?? 1
            if den > 0 { total += num / den }
        }

        // Verifica fração unicode logo após o número (com ou sem espaço): "1 ½ xícara".
        let after = ns.substring(from: consumed)
        let trimmed = after.drop { $0 == " " }
        for (glyph, value) in unicodeFractions {
            if trimmed.hasPrefix(glyph) {
                total += value
                let extra = (after.count - trimmed.count) + glyph.count
                consumed += extra
                break
            }
        }

        if let endIndex = text.index(text.startIndex, offsetBy: consumed, limitedBy: text.endIndex) {
            return (total, endIndex)
        }
        return nil
    }
}
