import SwiftUI

enum ActionDetailMode: Identifiable {
    case view(Action)
    case edit(Action)

    var id: UUID {
        switch self {
        case .view(let a): return a.id
        case .edit(let a): return a.id
        }
    }

    var action: Action {
        switch self {
        case .view(let a): return a
        case .edit(let a): return a
        }
    }
}

struct ActionDetailSheet: View {
    let mode: ActionDetailMode
    let onOpenSettings: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var systemPrompt: String

    init(mode: ActionDetailMode, onOpenSettings: @escaping () -> Void) {
        self.mode = mode
        self.onOpenSettings = onOpenSettings
        self._name = State(initialValue: mode.action.name)
        self._systemPrompt = State(initialValue: mode.action.systemPrompt)
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var action: Action { mode.action }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerRow
            nameRow
            metadataRow
            promptSection
            Spacer(minLength: 0)
            footerRow
        }
        .padding(20)
        .frame(minWidth: 440, maxWidth: 580)
    }

    private var headerRow: some View {
        HStack {
            Text(isEditing ? "Upravit akci" : "Detail akce")
                .font(.headline)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var nameRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Název").font(.caption).foregroundStyle(.secondary)
            if isEditing {
                TextField("Název akce", text: $name)
            } else {
                Text(action.name).fontWeight(.medium)
            }
        }
    }

    private var metadataRow: some View {
        HStack(spacing: 20) {
            labeledValue("Provider", action.provider.displayName)
            labeledValue("Model", action.model)
            labeledValue("Teplota", String(format: "%.1f", action.temperature))
            labeledValue("Max. tokenů", "\(action.maxTokens)")
        }
    }

    private func labeledValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout).lineLimit(1).truncationMode(.middle)
        }
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Systémový prompt").font(.caption).foregroundStyle(.secondary)
            if isEditing {
                TextEditor(text: $systemPrompt)
                    .font(.callout)
                    .frame(minHeight: 140, maxHeight: 300)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
            } else {
                ScrollView {
                    Text(action.systemPrompt)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(minHeight: 80, maxHeight: 260)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private var footerRow: some View {
        HStack {
            if isEditing {
                Button("Plné nastavení") {
                    SettingsNavigation.shared.selectedTab = .actions
                    dismiss()
                    onOpenSettings()
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Zavřít") { dismiss() }
            if isEditing {
                Button("Uložit") { saveEdits(); dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func saveEdits() {
        ConfigStore.shared.update { store in
            if let idx = store.actions.firstIndex(where: { $0.id == action.id }) {
                store.actions[idx].name = name
                store.actions[idx].systemPrompt = systemPrompt
            }
        }
    }
}
