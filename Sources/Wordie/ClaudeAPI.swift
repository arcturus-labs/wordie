import Foundation

struct ClaudeAPI {
    struct APIError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func process(text: String, prompt: String, apiKey: String) async throws -> String {
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

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 4096,
            "messages": [
                [
                    "role": "user",
                    "content": """
                    \(prompt)

                    Return ONLY the updated text with no preamble, explanation, or wrapper. Do not add quotes around it.

                    Text:
                    \(text)
                    """
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
