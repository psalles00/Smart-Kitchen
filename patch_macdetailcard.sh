sed -i '' -e '/\.fill(Color(nsColor: \.windowBackgroundColor))/d' \
          -e '/RoundedRectangle(cornerRadius: 18, style: \.continuous)/d' \
          -e '/\.background(/d' \
          "/Users/pedrosalles/Documents/Coding/Smart Kitchen/SmartKitchen/App/ContentView.swift"
