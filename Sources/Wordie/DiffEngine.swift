import Foundation

enum DiffToken: Identifiable {
    case unchanged(String)
    case added(String)
    case removed(String)

    var id: String {
        switch self {
        case .unchanged(let s): return "u:\(s):\(UUID().uuidString)"
        case .added(let s): return "a:\(s):\(UUID().uuidString)"
        case .removed(let s): return "r:\(s):\(UUID().uuidString)"
        }
    }
}

struct DiffEngine {
    /// Tokenize text into words preserving whitespace as separate tokens
    static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inWhitespace = false

        for ch in text {
            let charIsWhitespace = ch.isWhitespace
            if current.isEmpty {
                current.append(ch)
                inWhitespace = charIsWhitespace
            } else if charIsWhitespace == inWhitespace {
                current.append(ch)
            } else {
                tokens.append(current)
                current = String(ch)
                inWhitespace = charIsWhitespace
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    /// Compute word-level diff using Myers' algorithm (LCS-based)
    static func diff(old: String, new: String) -> [DiffToken] {
        let oldTokens = tokenize(old)
        let newTokens = tokenize(new)

        let lcs = longestCommonSubsequence(oldTokens, newTokens)

        var result: [DiffToken] = []
        var oi = 0, ni = 0, li = 0

        while oi < oldTokens.count || ni < newTokens.count {
            if li < lcs.count {
                // Emit removed tokens from old until we hit the LCS token
                while oi < oldTokens.count && oldTokens[oi] != lcs[li] {
                    result.append(.removed(oldTokens[oi]))
                    oi += 1
                }
                // Emit added tokens from new until we hit the LCS token
                while ni < newTokens.count && newTokens[ni] != lcs[li] {
                    result.append(.added(newTokens[ni]))
                    ni += 1
                }
                // Emit the common token
                if li < lcs.count {
                    result.append(.unchanged(lcs[li]))
                    oi += 1
                    ni += 1
                    li += 1
                }
            } else {
                // Past LCS — remaining old tokens are removed, new are added
                while oi < oldTokens.count {
                    result.append(.removed(oldTokens[oi]))
                    oi += 1
                }
                while ni < newTokens.count {
                    result.append(.added(newTokens[ni]))
                    ni += 1
                }
            }
        }

        return result
    }

    private static func longestCommonSubsequence(_ a: [String], _ b: [String]) -> [String] {
        let m = a.count, n = b.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 1...max(m, 1) {
            guard i <= m else { break }
            for j in 1...max(n, 1) {
                guard j <= n else { break }
                if a[i - 1] == b[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack
        var result: [String] = []
        var i = m, j = n
        while i > 0 && j > 0 {
            if a[i - 1] == b[j - 1] {
                result.append(a[i - 1])
                i -= 1
                j -= 1
            } else if dp[i - 1][j] > dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        return result.reversed()
    }
}
