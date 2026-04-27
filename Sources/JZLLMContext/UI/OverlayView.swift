import SwiftUI

struct OverlayView: View {
    @ObservedObject var state: OverlayState
    let onClose: () -> Void
    let onOpenSettings: () -> Void

    @StateObject private var engine = ActionEngine()
    @State private var contextText: String?
    @State private var contextError: String?
    @State private var isResolvingContext = false
    @State private var contextIsFromOCR = false
    @State private var lastAction: Action?
    @State private var didCopy = false

    private var actions: [Action] { ConfigStore.shared.actions.filter(\.enabled) }

    private var isMissingKeyError: Bool {
        guard let err = engine.lastError as? LLMError,
              case .missingAPIKey = err else { return false }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    contextPreview
                    actionButtons
                    if !engine.result.isEmpty || engine.errorMessage != nil {
                        Divider()
                        resultArea
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 640, height: 480)
        .background(.regularMaterial)
        .onAppear { resolveContext() }
        .onChange(of: state.refreshID) { resolveContext() }
        .onKeyPress(.escape) { onClose(); return .handled }
    }

    private var headerBar: some View {
        HStack {
            Text("JZLLMContext")
                .font(.headline)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
                actionButton(
                    title: "Rozpoznat text z obrázku (OCR)",
                    missingKey: false,
                    isRunning: false
                ) {
                    if let text = contextText { engine.showText(text) }
                }
                Divider()
            }
            ForEach(actions) { action in
                actionButton(
                    title: action.name,
                    missingKey: !KeychainStore.hasKey(for: action.provider),
                    isRunning: engine.isLoading && lastAction == action
                ) {
                    runAction(action)
                }
            }
        }
    }

    private func actionButton(title: String, missingKey: Bool, isRunning: Bool, action: @escaping () -> Void) -> some View {
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
            if let error = engine.errorMessage {
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
            } else {
                ScrollView {
                    Text(engine.result)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(minHeight: 80)

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

    private func resolveContext() {
        engine.reset()
        isResolvingContext = true
        contextText = nil
        contextError = nil
        didCopy = false
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
        lastAction = action
        didCopy = false
        engine.run(action: action, input: text)
    }

    private func copyResult() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(engine.result, forType: .string)
        didCopy = true
    }
}
