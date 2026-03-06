import Foundation

struct ClaudeAPI {
    struct APIError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Build the full message sent to Claude.
    /// If context is non-empty, it is included as background information.
    static func buildUserMessage(prompt: String, context: String, text: String) -> String {
        var message = prompt + "\n\n"

        let trimmedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedContext.isEmpty {
            message += "Use the following as background context to inform your edits, but do not include this context in your output:\n\n"
            message += "Context:\n\(trimmedContext)\n\n"
        }

        message += "Return ONLY the updated text with no preamble, explanation, or wrapper. Do not add quotes around it.\n\n"
        message += "Text:\n\(text)"

        return message
    }

    /// Build the message for reprocessing during a diff review.
    /// Provides both the original and current version so Claude understands the editing history.
    static func buildReprocessMessage(prompt: String, context: String, originalText: String, currentText: String) -> String {
        var message = prompt + "\n\n"

        let trimmedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedContext.isEmpty {
            message += "Use the following as background context to inform your edits, but do not include this context in your output:\n\n"
            message += "Context:\n\(trimmedContext)\n\n"
        }

        message += "Below are two versions of a text. The \"Original version\" is the starting point. The \"Current version\" is a work-in-progress revision. Update the current version according to the prompt above.\n\n"
        message += "Return ONLY the updated text with no preamble, explanation, or wrapper. Do not add quotes around it.\n\n"
        message += "Original version:\n\(originalText)\n\n"
        message += "Current version:\n\(currentText)"

        return message
    }

    static func reprocess(originalText: String, currentText: String, prompt: String, context: String, apiKey: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw APIError(message: "Anthropic API key not set. Go to Wordie → Settings (⌘,) to add your key.")
        }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 60

        let userMessage = buildReprocessMessage(prompt: prompt, context: context, originalText: originalText, currentText: currentText)

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 4096,
            "messages": [
                [
                    "role": "user",
                    "content": userMessage
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError(message: "Invalid response from API")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError(message: "API error (\(httpResponse.statusCode)): \(errorBody)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let resultText = firstBlock["text"] as? String else {
            throw APIError(message: "Could not parse API response")
        }

        return resultText
    }

    static func process(text: String, prompt: String, context: String, apiKey: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw APIError(message: "Anthropic API key not set. Go to Wordie → Settings (⌘,) to add your key.")
        }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 60

        let userMessage = buildUserMessage(prompt: prompt, context: context, text: text)

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 4096,
            "messages": [
                [
                    "role": "user",
                    "content": userMessage
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError(message: "Invalid response from API")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError(message: "API error (\(httpResponse.statusCode)): \(errorBody)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let resultText = firstBlock["text"] as? String else {
            throw APIError(message: "Could not parse API response")
        }

        return resultText
    }
}
