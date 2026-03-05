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
    @State private var diffTokens: [DiffToken] = []
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
                        DiffTextView(tokens: diffTokens)
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
                    diffTokens = DiffEngine.diff(old: oldText, new: newText)
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
        diffTokens = []
        appState = .editing
        errorMessage = nil
    }

    private func reject() {
        text = oldText
        diffTokens = []
        appState = .editing
        errorMessage = nil
    }
}

struct DiffTextView: NSViewRepresentable {
    let tokens: [DiffToken]

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.backgroundColor = .textBackgroundColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0

        scrollView.documentView = textView

        applyDiff(to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if let textView = scrollView.documentView as? NSTextView {
            applyDiff(to: textView)
        }
    }

    private func applyDiff(to textView: NSTextView) {
        let attributed = NSMutableAttributedString()
        let baseFont = NSFont.systemFont(ofSize: 14)

        for token in tokens {
            switch token {
            case .unchanged(let s):
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: baseFont,
                    .foregroundColor: NSColor.textColor
                ]
                attributed.append(NSAttributedString(string: s, attributes: attrs))

            case .removed(let s):
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: baseFont,
                    .foregroundColor: NSColor.systemRed,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .backgroundColor: NSColor.systemRed.withAlphaComponent(0.1)
                ]
                attributed.append(NSAttributedString(string: s, attributes: attrs))

            case .added(let s):
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: baseFont,
                    .foregroundColor: NSColor.systemGreen,
                    .backgroundColor: NSColor.systemGreen.withAlphaComponent(0.1)
                ]
                attributed.append(NSAttributedString(string: s, attributes: attrs))
            }
        }

        textView.textStorage?.setAttributedString(attributed)
    }
}
