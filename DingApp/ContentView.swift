import SwiftUI

struct ContentView: View {
    @EnvironmentObject var tokenStore: TokenStore

    var body: some View {
        VStack(spacing: 20) {
            Text("ding")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Setup required")
                .font(.headline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
    }
}

#Preview {
    ContentView()
        .environmentObject(TokenStore())
}
