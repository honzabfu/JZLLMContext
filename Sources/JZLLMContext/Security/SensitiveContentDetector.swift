import Foundation

struct SensitivePattern: Codable, Identifiable, Hashable {
    var id: UUID
    var label: String
    var pattern: String

    init(id: UUID = UUID(), label: String, pattern: String) {
        self.id = id
        self.label = label
        self.pattern = pattern
    }

    var isValidRegex: Bool {
        (try? NSRegularExpression(pattern: pattern)) != nil
    }
}

struct SensitiveMatch: Identifiable {
    let id = UUID()
    let label: String
    let matchedText: String
}

enum SensitiveContentDetector {
    static let builtInPatterns: [SensitivePattern] = [
        SensitivePattern(label: "OpenAI API Key",    pattern: #"sk-[a-zA-Z0-9\-_]{20,}"#),
        SensitivePattern(label: "Anthropic API Key", pattern: #"sk-ant-[a-zA-Z0-9\-_]{20,}"#),
        SensitivePattern(label: "Google API Key",    pattern: #"AIza[0-9A-Za-z\-_]{35}"#),
        SensitivePattern(label: "GitHub Token",      pattern: #"gh[pousr]_[A-Za-z0-9_]{36,}"#),
        SensitivePattern(label: "AWS Access Key",    pattern: #"AKIA[0-9A-Z]{16}"#),
        SensitivePattern(label: "Private Key",       pattern: #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#),
        SensitivePattern(label: "Bearer Token",      pattern: #"(?i)bearer\s+[a-zA-Z0-9\-._~+/]{20,}"#),
        SensitivePattern(label: "Password field",    pattern: #"(?i)(?:password|passwd|pwd)\s*[:=]\s*\S{3,}"#),
        SensitivePattern(label: "Secret field",      pattern: #"(?i)(?:secret|api_secret|client_secret)\s*[:=]\s*[a-zA-Z0-9\-._~+/]{8,}"#),
    ]

    static func detect(text: String, customPatterns: [SensitivePattern]) -> [SensitiveMatch] {
        (builtInPatterns + customPatterns).compactMap { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern.pattern) else { return nil }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  let matchRange = Range(match.range, in: text) else { return nil }
            let matched = String(text[matchRange])
            let display = matched.count > 40 ? String(matched.prefix(40)) + "…" : matched
            return SensitiveMatch(label: pattern.label, matchedText: display)
        }
    }
}
