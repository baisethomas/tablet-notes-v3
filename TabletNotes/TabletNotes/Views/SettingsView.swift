import SwiftUI

struct SettingsView: View {
    var onNext: (() -> Void)?
    var body: some View {
        VStack(spacing: 24) {
            Text("Settings Screen")
                .font(.largeTitle)
                .padding()
            Button("Back to Home") {
                onNext?()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    SettingsView()
}
