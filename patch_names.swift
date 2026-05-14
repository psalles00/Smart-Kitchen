import Foundation

func patch() {
    let path = "SmartKitchen/Services/AIService.swift"
    do {
        var content = try String(contentsOfFile: path, encoding: .utf8)
        content = content.replacingOccurrences(of: "\"ai-chat\"", with: "\"openai-chat\"")
        content = content.replacingOccurrences(of: "\"ai-transcribe\"", with: "\"openai-transcription\"")
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        print("Patched names in AIService")
    } catch {
        print("Error: \\(error)")
    }
}
patch()
