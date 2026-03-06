import SwiftUI
import AppKit

enum AppState {
    case editing
    case processing
    case reviewing
}

/// Height of 5 lines of body text, approximately
private let fiveLineHeight: CGFloat = 100

struct ContentView: View {
    @AppStorage("anthropicAPIKey") private var apiKey: String = ""

    @StateObject private var promptStore = PromptStore.shared
    @State private var prompt: String = PromptStore.shared.prompts.first ?? ""
    @State private var selectedPromptIndex: Int? = 0
    @State private var context: String = ""
    @State private var text: String = ""
    @State private var appState: AppState = .editing
    @State private var oldText: String = ""
    @State private var newText: String = ""
    @State private var errorMessage: String? = nil

    @State private var promptHeight: CGFloat = fiveLineHeight
    @State private var contextHeight: CGFloat = fiveLineHeight

    var body: some View {
        VStack(spacing: 0) {

            // ── Prompt section ──
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Prompt")
                        .font(.headline)
                    Spacer()

                    // Saved prompts dropdown
                    Menu {
                        ForEach(Array(promptStore.prompts.enumerated()), id: \.offset) { index, saved in
                            Button {
                                selectedPromptIndex = index
                                prompt = saved
                            } label: {
                                HStack {
                                    Text(saved)
                                    if selectedPromptIndex == index {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Saved Prompts", systemImage: "list.bullet")
                            .labelStyle(.iconOnly)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 24)
                    .disabled(appState == .processing || appState == .reviewing)

                    Button {
                        promptStore.add(prompt)
                        if let idx = promptStore.prompts.firstIndex(of: prompt.trimmingCharacters(in: .whitespacesAndNewlines)) {
                            selectedPromptIndex = idx
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Save current prompt")
                    .disabled(
                        appState == .processing || appState == .reviewing ||
                        prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        promptStore.prompts.contains(prompt.trimmingCharacters(in: .whitespacesAndNewlines))
                    )

                    Button {
                        if let idx = selectedPromptIndex {
                            promptStore.delete(at: idx)
                            selectedPromptIndex = nil
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete selected saved prompt")
                    .disabled(appState == .processing || appState == .reviewing || selectedPromptIndex == nil)
                }

                TextEditor(text: $prompt)
                    .font(.body)
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                    .disabled(appState == .processing || appState == .reviewing)
                    .onChange(of: prompt) { newValue in
                        if let idx = selectedPromptIndex,
                           idx < promptStore.prompts.count,
                           promptStore.prompts[idx] != newValue {
                            selectedPromptIndex = nil
                        }
                    }
            }
            .frame(height: promptHeight)
            .padding(.horizontal)
            .padding(.top)

            // ── Drag handle between Prompt and Context ──
            DragHandle()
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            let delta = value.translation.height
                            let newPrompt = promptHeight + delta
                            if newPrompt >= 40 {
                                promptHeight = newPrompt
                            }
                        }
                )

            // ── Context section ──
            VStack(alignment: .leading, spacing: 4) {
                Text("Context")
                    .font(.headline)

                TextEditor(text: $context)
                    .font(.body)
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                    .disabled(appState == .processing || appState == .reviewing)
            }
            .frame(height: contextHeight)
            .padding(.horizontal)

            // ── Drag handle between Context and Text ──
            DragHandle()
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            let delta = value.translation.height
                            let newContext = contextHeight + delta
                            if newContext >= 40 {
                                contextHeight = newContext
                            }
                        }
                )

            // ── Text / Diff section (fills remaining space) ──
            VStack(alignment: .leading, spacing: 4) {
                Text("Text")
                    .font(.headline)

                Group {
                    if appState == .reviewing {
                        EditableDiffView(oldText: $oldText, newText: $newText)
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
            .padding(.horizontal)

            // ── Error message ──
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.callout)
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // ── Buttons ──
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
                    Button("Reject All") {
                        reject()
                    }
                    .keyboardShortcut(.escape, modifiers: [])

                    Button("Process") {
                        reprocessText()
                    }

                    Button("Accept All") {
                        accept()
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
            .padding(.top, 8)
        }
        .onAppear {
            loadClipboard()
        }
        .onReceive(NotificationCenter.default.publisher(for: .windowSummoned)) { _ in
            if appState == .editing {
                loadClipboard()
            }
        }
    }

    // MARK: - Actions

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
                let result = try await ClaudeAPI.process(
                    text: oldText,
                    prompt: prompt,
                    context: context,
                    apiKey: apiKey
                )
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

    private func reprocessText() {
        errorMessage = nil
        let currentOld = oldText
        let currentNew = newText
        appState = .processing

        Task {
            do {
                let result = try await ClaudeAPI.reprocess(
                    originalText: currentOld,
                    currentText: currentNew,
                    prompt: prompt,
                    context: context,
                    apiKey: apiKey
                )
                await MainActor.run {
                    oldText = currentOld
                    newText = result
                    appState = .reviewing
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    oldText = currentOld
                    newText = currentNew
                    appState = .reviewing
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

// MARK: - Drag Handle

struct DragHandle: View {
    @State private var isHovering = false

    var body: some View {
        Rectangle()
            .fill(isHovering ? Color.accentColor.opacity(0.5) : Color(nsColor: .separatorColor))
            .frame(height: 4)
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}
