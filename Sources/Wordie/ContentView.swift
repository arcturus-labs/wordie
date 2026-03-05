import SwiftUI
import AppKit

enum AppState {
    case editing
    case processing
    case reviewing
}

struct ContentView: View {
    @AppStorage("anthropicAPIKey") private var apiKey: String = ""

    @State private var prompt: String = "Tighten up this text to keep the tone and meaning"
    @State private var text: String = ""
    @State private var appState: AppState = .editing
    @State private var oldText: String = ""
    @State private var newText: String = ""
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(spacing: 12) {
            // Prompt field
            VStack(alignment: .leading, spacing: 4) {
                Text("Prompt")
                    .font(.headline)
                TextField("Prompt", text: $prompt)
                    .textFieldStyle(.roundedBorder)
                    .disabled(appState == .processing || appState == .reviewing)
            }

            // Main text area / diff display
            VStack(alignment: .leading, spacing: 4) {
                Text("Text")
                    .font(.headline)

                Group {
                    if appState == .reviewing {
                        EditableDiffView(oldText: oldText, newText: $newText)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                    } else {
                        TextEditor(text: $text)
                            .font(.body)
                            .padding(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                            .disabled(appState == .processing)
                            .opacity(appState == .processing ? 0.5 : 1.0)
                    }
                }
                .frame(maxHeight: .infinity)
            }

            // Error message
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.callout)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Buttons
            HStack {
                Spacer()

                if appState == .editing {
                    Button("Process") {
                        processText()
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else if appState == .processing {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Processing…")
                        .foregroundColor(.secondary)
                } else if appState == .reviewing {
                    Button("Reject") {
                        reject()
                    }
                    .keyboardShortcut(.escape, modifiers: [])

                    Button("Accept") {
                        accept()
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .onAppear {
            loadClipboard()
        }
    }

    private func loadClipboard() {
        if let clipboardString = NSPasteboard.general.string(forType: .string) {
            text = clipboardString
        }
    }

    private func processText() {
        errorMessage = nil
        oldText = text
        appState = .processing

        Task {
            do {
                let result = try await ClaudeAPI.process(text: oldText, prompt: prompt, apiKey: apiKey)
                await MainActor.run {
                    newText = result
                    appState = .reviewing
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    appState = .editing
                }
            }
        }
    }

    private func accept() {
        text = newText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(newText, forType: .string)
        appState = .editing
        errorMessage = nil
    }

    private func reject() {
        text = oldText
        appState = .editing
        errorMessage = nil
    }
}
