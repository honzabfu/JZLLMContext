import SwiftUI

struct OverlayView: View {
    @ObservedObject var state: OverlayState
    let onClose: () -> Void
    let onOpenSettings: () -> Void

    @StateObject private var engine = ActionEngine()
    @ObservedObject private var history = HistoryStore.shared
    @State private var contextText: String?
    @State private var contextError: String?
    @State private var isResolvingContext = false
    @State private var contextIsFromOCR = false
    @State private var lastAction: Action?
    @State private var didCopy = false
    @State private var userContext: String = ""
    @State private var showHistory = false
    @State private var shownHistoryResult: String?
    @FocusState private var userContextFocused: Bool

    private var actions: [Action] { ConfigStore.shared.actions.filter(\.enabled) }
    private var displayedResult: String? {
        shownHistoryResult ?? (engine.result.isEmpty ? nil : engine.result)
    }


    private var isMissingKeyError: Bool {
        guard let err = engine.lastError as? LLMError,
              case .missingAPIKey = err else { return false }
        return true
    }

    private var hasResult: Bool { displayedResult != nil || engine.errorMessage != nil }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            if showHistory {
                historyPanel
                Divider()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    contextPreview
                    userContextField
                    actionButtons
                }
                .padding(16)
            }
            .frame(maxHeight: hasResult ? 200 : .infinity)
            if hasResult {
                Divider()
                resultArea.padding(16)
            }
        }
        .frame(minWidth: 480, idealWidth: 640, maxWidth: .infinity,
               minHeight: 300, idealHeight: 480, maxHeight: .infinity)
        .background(.regularMaterial)
        .onAppear { resolveContext() }
        .onChange(of: state.refreshID) { resolveContext() }
        .onChange(of: engine.isLoading) { _, isLoading in
            guard !isLoading, engine.errorMessage == nil, !engine.result.isEmpty else { return }
            HistoryStore.shared.add(actionName: lastAction?.name ?? "", input: contextText ?? "", result: engine.result)
            let shouldCopyClose: Bool
            switch lastAction?.autoCopyClose {
            case .always:   shouldCopyClose = true
            case .never:    shouldCopyClose = false
            default:        shouldCopyClose = ConfigStore.shared.config.autoCopyAndClose
            }
            if shouldCopyClose {
                copyResult()
                onClose()
            }
        }
        .onKeyPress(.escape) { onClose(); return .handled }
        .onKeyPress { press in
            guard !userContextFocused,
                  let digit = Int(press.characters),
                  digit >= 1, digit <= actions.count else { return .ignored }
            runAction(actions[digit - 1])
            return .handled
        }
    }

    private var headerBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("JZLLMContext")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            if ConfigStore.shared.config.historyLimit > 0 {
                Button { showHistory.toggle() } label: {
                    Image(systemName: showHistory ? "clock.fill" : "clock")
                        .foregroundStyle(showHistory ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var historyPanel: some View {
        Group {
            if history.entries.isEmpty {
                Text("Žádná historie")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(history.entries) { entry in
                            Button {
                                shownHistoryResult = entry.result
                                showHistory = false
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.actionName)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                        Text(entry.inputSnippet)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text(entry.date, style: .time)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
    }

    private var userContextField: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "text.bubble")
                .foregroundStyle(.secondary)
                .font(.caption)
                .padding(.top, 2)
            TextField("Doplňkový kontext…", text: $userContext, axis: .vertical)
                .focused($userContextFocused)
                .font(.caption)
                .lineLimit(1...3)
                .frame(maxWidth: .infinity)
        }
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var contextPreview: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: contextIsFromOCR ? "doc.viewfinder" : "doc.on.clipboard")
                .foregroundStyle(.secondary)
                .font(.caption)
                .padding(.top, 1)
            Group {
                if isResolvingContext {
                    Text(contextIsFromOCR ? "Rozpoznávám text z obrázku…" : "Čtu schránku…")
                        .foregroundStyle(.secondary)
                } else if let text = contextText {
                    Text(text.prefix(300) + (text.count > 300 ? "…" : ""))
                } else {
                    Text("Schránka je prázdná")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .lineLimit(4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var actionButtons: some View {
        VStack(spacing: 6) {
            if contextIsFromOCR {
                actionButton(title: "Rozpoznat text z obrázku (OCR)", missingKey: false, isRunning: false) {
                    if let text = contextText { engine.showText(text) }
                }
                Divider()
            }
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                actionButton(
                    title: action.name,
                    missingKey: !KeychainStore.hasKey(for: action.provider),
                    isRunning: engine.isLoading && lastAction == action,
                    keyHint: index < 9 ? String(index + 1) : nil
                ) { runAction(action) }
            }
            if engine.isLoading {
                HStack {
                    Spacer()
                    Button("Zrušit") { engine.cancel() }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private func actionButton(title: String, missingKey: Bool, isRunning: Bool, keyHint: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isRunning {
                    ProgressView().scaleEffect(0.65)
                } else if missingKey {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                } else if let hint = keyHint {
                    Text(hint)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                } else {
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.bordered)
        .disabled(engine.isLoading || contextText == nil)
    }

    private var resultArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = engine.errorMessage, shownHistoryResult == nil {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    if let action = lastAction {
                        Button("Zkusit znovu") { runAction(action) }
                    }
                    if isMissingKeyError {
                        Button("Otevřít nastavení") { onOpenSettings() }
                    }
                }
                Spacer()
            } else if let result = displayedResult {
                ScrollView {
                    Text(result)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                HStack {
                    Button(didCopy ? "Zkopírováno ✓" : "Zkopírovat") {
                        copyResult()
                    }
                    .keyboardShortcut("c", modifiers: .command)
                    Spacer()
                    Button("Zavřít") { onClose() }
                }
            }
        }
    }

    private func resolveVariables(in prompt: String) -> String {
        let df = DateFormatter()
        df.dateStyle = .long
        df.timeStyle = .none
        df.locale = Locale.current
        let lang = Locale.current.language.languageCode?.identifier ?? "cs"
        return prompt
            .replacingOccurrences(of: "{{datum}}", with: df.string(from: Date()))
            .replacingOccurrences(of: "{{jazyk}}", with: lang)
            .replacingOccurrences(of: "{{kontext}}", with: userContext)
    }

    private func resolveContext() {
        userContextFocused = false
        engine.reset()
        isResolvingContext = true
        contextText = nil
        contextError = nil
        didCopy = false
        userContext = ""
        shownHistoryResult = nil
        showHistory = false
        let pb = NSPasteboard.general
        contextIsFromOCR = pb.string(forType: .string)?.isEmpty != false
            && NSImage(pasteboard: pb) != nil
        Task {
            let result = await ContextResolver.resolve()
            switch result {
            case .text(let text, let isOCR):
                contextText = text
                contextIsFromOCR = isOCR
            case .error(let error):
                contextError = error.localizedDescription
            }
            isResolvingContext = false
        }
    }

    private func runAction(_ action: Action) {
        guard let text = contextText else { return }
        userContextFocused = false
        lastAction = action
        didCopy = false
        shownHistoryResult = nil
        var resolved = action
        resolved.systemPrompt = resolveVariables(in: action.systemPrompt)
        let input: String
        if !userContext.isEmpty && !action.systemPrompt.contains("{{kontext}}") {
            input = text + "\n\n---\nDoplňkový kontext: " + userContext
        } else {
            input = text
        }
        engine.run(action: resolved, input: input)
    }

    private func copyResult() {
        guard let text = displayedResult else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        didCopy = true
    }
}
