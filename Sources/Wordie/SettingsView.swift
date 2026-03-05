import SwiftUI

struct SettingsView: View {
    @AppStorage("anthropicAPIKey") private var apiKey: String = ""
    @State private var showKey = false

    var body: some View {
        Form {
            Section {
                HStack {
                    if showKey {
                        TextField("Anthropic API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("Anthropic API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button(showKey ? "Hide" : "Show") {
                        showKey.toggle()
                    }
                    .frame(width: 50)
                }

                Text("Get your API key from console.anthropic.com")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
    }
}
