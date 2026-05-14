import Foundation

func patchInfoPlist() {
    let path = "SmartKitchen/Resources/Info.plist"
    do {
        var content = try String(contentsOfFile: path, encoding: .utf8)
        
        content = content.replacingOccurrences(of: "<string>$(SUPABASE_URL)</string>", with: "<string>https://yfcmvdijvgeaihvwyssb.supabase.co</string>")
        
        content = content.replacingOccurrences(of: "<string>$(SUPABASE_ANON_KEY)</string>", with: "<string>eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlmY212ZGlqdmdlYWlodnd5c3NiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY4ODAwMjEsImV4cCI6MjA5MjQ1NjAyMX0.Ffpszze5umpURnzNL_Fl3u7SFmjb_opQmWVPdpUjhiI</string>")
        
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        print("Hardcoded Supabase keys in Info.plist")
    } catch {
        print("Error patching Info.plist: \\(error)")
    }
}
patchInfoPlist()
