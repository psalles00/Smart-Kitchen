import Foundation

func patchInfoPlist() {
    let path = "SmartKitchen/Resources/Info.plist"
    do {
        var content = try String(contentsOfFile: path, encoding: .utf8)
        
        let badKeys = [
            "<key>ExaAPIKey</key>\\n\\t\\t<string>$(EXA_API_KEY)</string>\\n\\t\\t",
            "<key>OpenAIAPIKey</key>\\n\\t\\t<string>$(OPENAI_API_KEY)</string>\\n\\t\\t",
            "<key>OpenRouterAPIKey</key>\\n\\t\\t<string>$(OPENROUTER_API_KEY)</string>\\n\\t\\t"
        ]
        
        for key in badKeys {
            content = content.replacingOccurrences(of: key, with: "")
        }
        
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        print("Patched Info.plist")
    } catch {
        print("Error patching Info.plist: \\(error)")
    }
}
patchInfoPlist()
