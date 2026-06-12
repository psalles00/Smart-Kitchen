import Foundation

func patchAPIConfig() {
    let path = "SmartKitchen/Services/APIConfig.swift"
    do {
        var content = try String(contentsOfFile: path, encoding: .utf8)
        
        let oldFunc = """
    private static func bundleValue(infoKey: String, envKey: String) -> String {
        if let rawValue = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String {
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

#if DEBUG
"""
        let newFunc = """
    private static func bundleValue(infoKey: String, envKey: String) -> String {
        if let rawValue = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String {
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !trimmed.hasPrefix("$(") {
                return trimmed
            }
        }

#if DEBUG
"""
        content = content.replacingOccurrences(of: oldFunc, with: newFunc)
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        print("Patched APIConfig.swift")
    } catch {
        print("Error: \\(error)")
    }
}
patchAPIConfig()
