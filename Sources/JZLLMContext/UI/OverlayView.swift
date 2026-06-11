import SwiftUI
import MarkdownUI
import UniformTypeIdentifiers

struct OverlayView: View {
    @ObservedObject var state: OverlayState
    let onClose: () -> Void
    let onOpenSettings: () -> Void

    @StateObject private var engine = ActionEngine()
    @ObservedObject private var history = HistoryStore.shared
    @ObservedObject private var updateState = UpdateState.shared
    @State private var contextText: String?
    @State private var contextError: String?
    @State private var isResolvingContext = false
    @State private var contextIsFromOCR = false
    @State private var lastAction: Action?
    @State private var lastInput: String = ""
    @State private var didCopy = false
    @State private var userContext: String = ""
    @State private var ignoreClipboard: Bool = false
    @State private var clipboardChanged: Bool = false
    @State private var knownClipboardChangeCount: Int = NSPasteboard.general.changeCount
    @State private var showHistory = false
    @State private var shownHistoryResult: String?
    @State private var actionDetailMode: ActionDetailMode? = nil
    @State private var pendingSend: PendingSend? = nil
    @State private var droppedFileURL: URL? = nil
    @State private var resolveTask: Task<Void, Never>? = nil
    @State private var isDragTargeted: Bool = false
    @State private var contextSourceName: String? = nil
    @FocusState private var userContextFocused: Bool

    private var actions: [Action] { ConfigStore.shared.actions.filter(\.enabled) }
    private var defaultAction: Action? { actions.first(where: \.isDefault) ?? actions.first }
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
        .onDrop(of: [UTType.fileURL], isTargeted: $isDragTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.isFileURL else { return }
                Task { @MainActor in handleDroppedFile(url: url) }
            }
            return true
        }
        .overlay(alignment: .center) {
            if isDragTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .onAppear { resolveContext() }
        .onChange(of: state.refreshID) { resolveContext() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            let current = NSPasteboard.general.changeCount
            if current != knownClipboardChangeCount {
                clipboardChanged = true
            }
        }
        .onChange(of: engine.completedRunID) { _, completedID in
            guard completedID != nil, !engine.result.isEmpty else { return }
            HistoryStore.shared.add(actionName: lastAction?.name ?? "", input: lastInput, result: engine.result)
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
        .onKeyPress(.escape) {
            if droppedFileURL != nil {
                droppedFileURL = nil
                contextSourceName = nil
                resolveContext()
            } else {
                onClose()
            }
            return .handled
        }
        .onKeyPress { press in
            guard !userContextFocused,
                  !engine.isLoading,
                  let digit = Int(press.characters),
                  digit >= 1, digit <= actions.count else { return .ignored }
            runAction(actions[digit - 1])
            return .handled
        }
        .sheet(item: $actionDetailMode) { mode in
            ActionDetailSheet(mode: mode, onOpenSettings: onOpenSettings)
        }
        .sheet(item: $pendingSend) { pending in
            SensitiveWarningSheet(matches: pending.matches) {
                pendingSend = nil
                engine.run(action: pending.action, input: pending.input)
            } onCancel: {
                pendingSend = nil
            }
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
            if updateState.isAvailable, let url = updateState.updateURL {
                Button { NSWorkspace.shared.open(url) } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                }
                .iconButton()
                .help(updateState.updateVersion.map { String(format: L("menu.update.available"), $0) } ?? "")
            }
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
            }
            .iconButton()
            .help(L("overlay.help.settings"))
            if ConfigStore.shared.config.historyLimit > 0 {
                Button { showHistory.toggle() } label: {
                    Image(systemName: showHistory ? "clock.fill" : "clock")
                        .foregroundStyle(showHistory ? .primary : .secondary)
                }
                .iconButton()
            }
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .iconButton()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var historyPanel: some View {
        VStack(spacing: 0) {
            if history.entries.isEmpty {
                Text(L("overlay.history.empty"))
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
            let cfg = ConfigStore.shared.config
            if cfg.historyLogEnabled, let dir = cfg.historyLogDirectory {
                Divider()
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: dir))
                } label: {
                    Label(L("overlay.history.open_log_dir"), systemImage: "folder")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var userContextField: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "text.bubble")
                .foregroundStyle(.secondary)
                .font(.caption)
                .padding(.top, 2)
            TextField(L("overlay.context.placeholder"), text: $userContext, axis: .vertical)
                .focused($userContextFocused)
                .font(.caption)
                .lineLimit(1...3)
                .frame(maxWidth: .infinity)
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.isEmpty,
                          let action = defaultAction,
                          !engine.isLoading,
                          hasInput(for: action) else { return .ignored }
                    runAction(action)
                    return .handled
                }
            if !userContext.isEmpty {
                Button { userContext = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
                .iconButton()
                .help(L("overlay.help.clear_context"))
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var contextPreview: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: contextSourceName != nil ? "doc.fill" :
                  (contextIsFromOCR && !ignoreClipboard ? "doc.viewfinder" : "doc.on.clipboard"))
                .foregroundStyle(ignoreClipboard && contextSourceName == nil ? .tertiary : .secondary)
                .font(.caption)
                .padding(.top, 1)
            Group {
                if ignoreClipboard && contextSourceName == nil {
                    Text(L("overlay.clipboard.ignored"))
                        .foregroundStyle(.tertiary)
                        .italic()
                } else if isResolvingContext {
                    Text(contextSourceName != nil ? L("overlay.clipboard.file_loading") :
                         (contextIsFromOCR ? L("overlay.clipboard.ocr_loading") : L("overlay.clipboard.loading")))
                        .foregroundStyle(.secondary)
                } else if let text = contextText {
                    VStack(alignment: .leading, spacing: 2) {
                        if let name = contextSourceName {
                            Text(name).fontWeight(.medium)
                        }
                        Text(text.prefix(300) + (text.count > 300 ? "…" : ""))
                            .foregroundStyle(contextSourceName != nil ? .secondary : .primary)
                    }
                } else {
                    Text(contextError ?? L("overlay.clipboard.empty"))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .lineLimit(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 4) {
                if contextSourceName != nil {
                    Button {
                        droppedFileURL = nil
                        contextSourceName = nil
                        resolveContext()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .iconButton()
                    .help(L("overlay.file.clear"))
                } else {
                    Button {
                        ignoreClipboard.toggle()
                    } label: {
                        Image(systemName: ignoreClipboard ? "eye.slash" : "eye")
                            .foregroundStyle(ignoreClipboard ? .primary : .secondary)
                            .font(.caption)
                    }
                    .iconButton()
                    .help(ignoreClipboard ? L("overlay.help.use_clipboard") : L("overlay.help.ignore_clipboard"))
                    if clipboardChanged && !ignoreClipboard {
                        Button { resolveContext() } label: {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(.blue)
                                .font(.caption)
                        }
                        .iconButton()
                        .help(L("overlay.help.clipboard_changed"))
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .animation(.easeInOut(duration: 0.15), value: clipboardChanged)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(ignoreClipboard && contextSourceName == nil ? 0.4 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var actionButtons: some View {
        VStack(spacing: 6) {
            if contextIsFromOCR {
                actionButton(title: L("overlay.action.ocr"), missingKey: false, isRunning: false) {
                    if let text = contextText { engine.showText(text) }
                }
                Divider()
            }
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                actionButton(
                    actionModel: action,
                    title: action.name,
                    missingKey: action.provider.requiresApiKey && !KeychainStore.hasKey(for: action.provider),
                    isRunning: engine.isLoading && lastAction == action,
                    keyHint: index < 9 ? String(index + 1) : nil,
                    isDefaultAction: action.id == defaultAction?.id
                ) { runAction(action) }
            }
            if engine.isLoading {
                HStack {
                    Spacer()
                    Button(L("overlay.action.cancel")) { engine.cancel() }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private func actionButton(actionModel: Action? = nil, title: String, missingKey: Bool, isRunning: Bool, keyHint: String? = nil, isDefaultAction: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isRunning {
                    ProgressView().controlSize(.small)
                } else if missingKey {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                } else {
                    if isDefaultAction {
                        Image(systemName: "return")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    if let hint = keyHint {
                        Text(hint)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    } else if !isDefaultAction {
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.bordered)
        .disabled(engine.isLoading || !hasInput(for: actionModel))
        .help({
            guard let a = actionModel else { return "" }
            return a.systemPrompt.count > 200 ? String(a.systemPrompt.prefix(200)) + "…" : a.systemPrompt
        }())
        .contextMenu {
            if let item = actionModel {
                Button(L("overlay.context.menu.run")) { action() }
                Divider()
                Button(L("overlay.context.menu.view_prompt")) { actionDetailMode = .view(item) }
                Button(L("overlay.context.menu.edit")) { actionDetailMode = .edit(item) }
            }
        }
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
                        Button(L("overlay.error.retry")) { runAction(action) }
                    }
                    if isMissingKeyError {
                        Button(L("overlay.error.open_settings")) { onOpenSettings() }
                    }
                }
                Spacer()
            } else if let result = displayedResult {
                ScrollView {
                    if ConfigStore.shared.config.markdownOutput {
                        Markdown(result)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    } else {
                        Text(result)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .font(.body)
                    }
                }
                .frame(maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                HStack {
                    Button(didCopy ? L("overlay.result.copied") : L("overlay.result.copy")) {
                        copyResult()
                    }
                    .keyboardShortcut("c", modifiers: .command)
                    Spacer()
                    Button(L("overlay.result.close")) { onClose() }
                }
            }
        }
    }

    private func resolveVariables(in prompt: String) -> String {
        let df = DateFormatter()
        df.dateStyle = .long
        df.timeStyle = .none
        df.locale = Locale.current
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        return prompt
            .replacingOccurrences(of: "{{datum}}", with: df.string(from: Date()))
            .replacingOccurrences(of: "{{jazyk}}", with: lang)
            .replacingOccurrences(of: "{{kontext}}", with: userContext)
    }

    private func resolveContext() {
        guard droppedFileURL == nil else { return }
        userContextFocused = false
        engine.reset()
        isResolvingContext = true
        contextText = nil
        contextError = nil
        didCopy = false
        userContext = ""
        ignoreClipboard = false
        clipboardChanged = false
        knownClipboardChangeCount = NSPasteboard.general.changeCount
        shownHistoryResult = nil
        showHistory = false
        let pb = NSPasteboard.general
        contextIsFromOCR = pb.string(forType: .string)?.isEmpty != false
            && NSImage(pasteboard: pb) != nil
        resolveTask?.cancel()
        resolveTask = Task {
            let result = await ContextResolver.resolve()
            // A re-opened overlay starts a new resolve; the superseded one
            // must not race it for contextText
            guard !Task.isCancelled else { return }
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

    /// Mirrors the input selection in runAction(_:): manual context when the
    /// clipboard is ignored, clipboard/file text otherwise.
    private func hasInput(for action: Action?) -> Bool {
        if (ignoreClipboard || (action?.ignoreClipboard ?? false)) && droppedFileURL == nil {
            return !userContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return contextText != nil
    }

    private func runAction(_ action: Action) {
        userContextFocused = false
        lastAction = action
        didCopy = false
        shownHistoryResult = nil
        if action.ignoreClipboard && droppedFileURL == nil { ignoreClipboard = true }
        var resolved = action
        resolved.systemPrompt = resolveVariables(in: action.systemPrompt)
        let input: String
        if ignoreClipboard && droppedFileURL == nil {
            input = userContext
        } else {
            guard let text = contextText else { return }
            if !userContext.isEmpty && !action.systemPrompt.contains("{{kontext}}") {
                input = text + "\n\n---\n" + L("overlay.additional_context_label") + userContext
            } else {
                input = text
            }
        }
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        lastInput = input
        let cfg = ConfigStore.shared.config
        if cfg.sensitiveContentCheckEnabled {
            // userContext may be embedded into the system prompt via {{kontext}}
            // instead of the input, so it has to be scanned as well
            var textToCheck = input
            if !userContext.isEmpty && action.systemPrompt.contains("{{kontext}}") {
                textToCheck += "\n" + userContext
            }
            let matches = SensitiveContentDetector.detect(text: textToCheck, customPatterns: cfg.customSensitivePatterns)
            if !matches.isEmpty {
                pendingSend = PendingSend(action: resolved, input: input, matches: matches)
                return
            }
        }
        engine.run(action: resolved, input: input)
    }

    private func copyResult() {
        guard let text = displayedResult else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        // Our own write must not trip the external clipboard-change indicator
        knownClipboardChangeCount = NSPasteboard.general.changeCount
        clipboardChanged = false
        didCopy = true
    }

    private func handleDroppedFile(url: URL) {
        resolveTask?.cancel()
        Task {
            droppedFileURL = url
            contextSourceName = url.lastPathComponent
            contextText = nil
            contextError = nil
            contextIsFromOCR = false
            isResolvingContext = true
            let result = await ContextResolver.extractText(from: url)
            // Discard stale result if user cleared or replaced the file during extraction
            guard droppedFileURL == url else { return }
            switch result {
            case .text(let text, let isOCR):
                contextText = text
                contextIsFromOCR = isOCR
            case .error(let error):
                contextError = error.localizedDescription
                droppedFileURL = nil
                contextSourceName = nil
            }
            isResolvingContext = false
        }
    }
}

private extension View {
    func iconButton() -> some View {
        self.buttonStyle(.plain).focusEffectDisabled()
    }
}

private struct PendingSend: Identifiable {
    let id = UUID()
    let action: Action
    let input: String
    let matches: [SensitiveMatch]
}

private struct SensitiveWarningSheet: View {
    let matches: [SensitiveMatch]
    let onSend: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(L("overlay.sensitive.title"), systemImage: "exclamationmark.shield.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(L("overlay.sensitive.message"))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(matches) { match in
                    HStack(alignment: .top, spacing: 8) {
                        Text(match.label)
                            .fontWeight(.medium)
                            .frame(width: 140, alignment: .leading)
                        Text(match.matchedText)
                            .monospaced()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .font(.caption)
                }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            HStack {
                Button(L("common.cancel"), role: .cancel) { onCancel() }
                Spacer()
                Button(L("overlay.sensitive.send")) { onSend() }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
