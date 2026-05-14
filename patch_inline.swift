import Foundation

func patch() {
    let path1 = "SmartKitchen/Views/Assistant/InlineChatView.swift"
    let path2 = "SmartKitchen/Views/Assistant/AssistantView.swift"
    
    do {
        var content = try String(contentsOfFile: path1, encoding: .utf8)
        content = content.replacingOccurrences(of: "content: \"Desculpe, ocorreu um erro: \\(error.localizedDescription)\",", with: "content: \"\\(String(localized: \"Desculpe, ocorreu um erro:\")) \\(error.localizedDescription)\",")
        
        let oldBanner = """
            // Error banner
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .onTapGesture { self.errorMessage = nil }
            }
"""
        let newBanner = """
            // Error banner
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, searchBarState != nil ? 64 : 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .onTapGesture { self.errorMessage = nil }
            }
"""
        content = content.replacingOccurrences(of: oldBanner, with: newBanner)
        try content.write(toFile: path1, atomically: true, encoding: .utf8)
        print("Patched InlineChatView")
        
        var content2 = try String(contentsOfFile: path2, encoding: .utf8)
        content2 = content2.replacingOccurrences(of: "content: \"Desculpe, ocorreu um erro: \\(error.localizedDescription)\"", with: "content: \"\\(String(localized: \"Desculpe, ocorreu um erro:\")) \\(error.localizedDescription)\"")
        try content2.write(toFile: path2, atomically: true, encoding: .utf8)
        print("Patched AssistantView")
        
    } catch {
        print("Error: \\(error)")
    }
}
patch()
