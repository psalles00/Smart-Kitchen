import Foundation

struct ItemEntry: Codable {
    let titulos: [String]
    let nomeDoArquivo: String
    let categoria: String

    enum CodingKeys: String, CodingKey {
        case titulos
        case nomeDoArquivo = "nome_do_arquivo"
        case categoria
    }
}
