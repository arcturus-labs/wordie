import Foundation

class PromptStore: ObservableObject {
    static let shared = PromptStore()

    private let key = "savedPrompts"
    private let defaultPrompt = "Tighten up this text while keeping the tone and meaning"

    @Published var prompts: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(prompts) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([String].self, from: data),
           !saved.isEmpty {
            prompts = saved
        } else {
            prompts = [defaultPrompt]
        }
    }

    func add(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !prompts.contains(trimmed) else { return }
        prompts.append(trimmed)
    }

    func delete(at index: Int) {
        guard prompts.indices.contains(index) else { return }
        prompts.remove(at: index)
    }
}
