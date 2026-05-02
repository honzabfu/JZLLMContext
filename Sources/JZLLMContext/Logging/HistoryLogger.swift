import Foundation

actor HistoryLogger {
    static let shared = HistoryLogger()
    private init() {}

    private lazy var fileDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private lazy var timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private var handleCache: [String: FileHandle] = [:]

    func log(action: Action, input: String, response: String, language: AppLanguage, at date: Date = .init()) async {
        let config = ConfigStore.shared.config
        guard config.historyLogEnabled, let dirPath = config.historyLogDirectory, !response.isEmpty else { return }

        let dateStr = fileDateFormatter.string(from: date)
        let prefix = config.historyLogFilePrefix
        let fileName = prefix.isEmpty ? "\(dateStr).md" : "\(prefix)\(dateStr).md"
        let dirURL = URL(fileURLWithPath: dirPath)
        let fileURL = dirURL.appendingPathComponent(fileName)
        let filePath = fileURL.path

        do {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

            let isNewFile = !FileManager.default.fileExists(atPath: filePath)
            if isNewFile {
                FileManager.default.createFile(atPath: filePath, contents: nil)
            }

            let handle: FileHandle
            if let cached = handleCache[filePath] {
                handle = cached
            } else {
                handle = try FileHandle(forWritingTo: fileURL)
                handleCache[filePath] = handle
            }

            let entry = format(action: action, input: input, response: response,
                               language: language, date: date,
                               isNewFile: isNewFile, dateStr: dateStr)
            guard let data = entry.data(using: .utf8) else { return }

            handle.seekToEndOfFile()
            try handle.write(contentsOf: data)
        } catch {
            handleCache[filePath] = nil
            fputs("[HistoryLogger] \(error)\n", stderr)
        }
    }

    func resetHandleCache() async {
        for handle in handleCache.values {
            try? handle.close()
        }
        handleCache = [:]
    }

    private func format(action: Action, input: String, response: String,
                        language: AppLanguage, date: Date,
                        isNewFile: Bool, dateStr: String) -> String {
        let timeStr = timeFormatter.string(from: date)
        let (lAction, lModel, lInput, lResponse) = labels(for: language)
        let providerModel = "\(action.provider.rawValue) / \(action.model)"

        var result = ""
        if isNewFile {
            result += "# JZLLMContext — \(dateStr)\n"
        }
        result += """

        ## \(timeStr)

        **\(lAction):** \(action.name)
        **\(lModel):** \(providerModel)

        **\(lInput):**
        \(input)

        **\(lResponse):**
        \(response)

        ---
        """
        return result
    }

    private func labels(for language: AppLanguage) -> (String, String, String, String) {
        let code = language.resolvedLocale.language.languageCode?.identifier ?? "en"
        switch code {
        case "cs": return ("Akce", "Model", "Vstup", "Odpověď")
        case "es": return ("Acción", "Modelo", "Entrada", "Respuesta")
        default:   return ("Action", "Model", "Input", "Response")
        }
    }
}
