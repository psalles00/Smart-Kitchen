import SwiftUI

struct TestView: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color.blue // background
            
            VStack(spacing: 0) {
                Text("Header")
                    .padding(.top, 40)
                
                ZStack {
                    RoundedRectangle(cornerRadius: 24).fill(Color.white)
                    ScrollView {
                        Text("Content")
                    }
                }
                .padding(24)
            }
        }
    }
}
