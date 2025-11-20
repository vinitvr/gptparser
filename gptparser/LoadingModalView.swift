import SwiftUI

struct LoadingModalView: View {
    let onCancel: () -> Void
    let onSkip: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.08).ignoresSafeArea()
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text("Welcome to Universal Chat Organizer")
                        .font(.title)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    Text("Your privacy is our priority. All your data stays on your device unless you choose to sync. Import your chat history to get started.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                ProgressView("Importing...")
                    .progressViewStyle(CircularProgressViewStyle())
                    .frame(width: 220)
                HStack(spacing: 18) {
                    Button("Cancel") { onCancel() }
                        .buttonStyle(.bordered)
                    Button("Skip to dashboard") { onSkip() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(40)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(NSColor.windowBackgroundColor)))
            .shadow(radius: 24)
        }
    }
}
