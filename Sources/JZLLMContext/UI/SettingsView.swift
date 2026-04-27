import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @State private var config = ConfigStore.shared.config
    @State private var openaiKey = ""
    @State private var anthropicKey = ""
    @State private var azureKey = ""
    @State private var customKey = ""
    @State private var keySaveStatus: [ProviderType: Bool] = [:]
    @State private var launchAtLogin = false
    @State private var importedActions: [Action] = []
    @State private var showImportAlert = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("Obecné", systemImage: "gearshape") }
            actionsTab
                .tabItem { Label("Akce", systemImage: "list.bullet") }
            providersTab
                .tabItem { Label("Providery", systemImage: "key") }
            shortcutTab
                .tabItem { Label("Zkratka", systemImage: "keyboard") }
        }
        .frame(width: 620, height: 520)
        .onAppear {
            loadKeys()
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Spustit při přihlášení", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !enabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var shortcutTab: some View {
        Form {
            Section {
                HStack {
                    Text("Globální zkratka")
                    Spacer()
                    HotkeyRecorderView(keyCode: $config.hotkeyKeyCode, modifiers: $config.hotkeyModifiers)
                        .frame(width: 150, height: 26)
                        .onChange(of: config.hotkeyKeyCode) { saveHotkey() }
                        .onChange(of: config.hotkeyModifiers) { saveHotkey() }
                }
            }
            Section {
                Text("Klikni na pole a stiskni požadovanou kombinaci kláves. Kliknutí znovu zruší záznam.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func saveHotkey() {
        ConfigStore.shared.update {
            $0.hotkeyKeyCode = config.hotkeyKeyCode
            $0.hotkeyModifiers = config.hotkeyModifiers
        }
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
    }

    private var actionsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                ForEach($config.actions) { $action in
                    ActionRow(action: $action, onDelete: {
                        config.actions.removeAll { $0.id == action.id }
                        ConfigStore.shared.update { $0.actions = config.actions }
                    })
                }
                .onMove { from, to in
                    config.actions.move(fromOffsets: from, toOffset: to)
                    ConfigStore.shared.update { $0.actions = config.actions }
                }
            }
            Divider()
            HStack {
                Button("Přidat akci") {
                    config.actions.append(Action(
                        name: "Nová akce",
                        systemPrompt: "",
                        provider: .openai,
                        model: "gpt-4o",
                        enabled: true
                    ))
                    ConfigStore.shared.update { $0.actions = config.actions }
                }
                Spacer()
                Button("Importovat…") { importActions() }
                Button("Exportovat…") { exportActions() }
                    .disabled(config.actions.isEmpty)
            }
            .padding(12)
        }
        .alert("Importovat akce", isPresented: $showImportAlert) {
            Button("Přidat k existujícím") {
                let fresh = importedActions.map { var a = $0; a.id = UUID(); return a }
                config.actions.append(contentsOf: fresh)
                ConfigStore.shared.update { $0.actions = config.actions }
            }
            Button("Nahradit vše", role: .destructive) {
                let fresh = importedActions.map { var a = $0; a.id = UUID(); return a }
                config.actions = fresh
                ConfigStore.shared.update { $0.actions = config.actions }
            }
            Button("Zrušit", role: .cancel) {}
        } message: {
            Text("Nalezeno \(importedActions.count) \(importedActions.count == 1 ? "akce" : "akcí"). Přidat k existujícím, nebo nahradit vše?")
        }
    }

    private func exportActions() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config.actions) else { return }
        let panel = NSSavePanel()
        panel.title = "Exportovat akce"
        panel.nameFieldStringValue = "JZLLMContext-actions.json"
        panel.allowedContentTypes = [.json]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func importActions() {
        let panel = NSOpenPanel()
        panel.title = "Importovat akce"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                  let data = try? Data(contentsOf: url),
                  let actions = try? JSONDecoder().decode([Action].self, from: data),
                  !actions.isEmpty else { return }
            DispatchQueue.main.async {
                importedActions = actions
                showImportAlert = true
            }
        }
    }

    private var providersTab: some View {
        Form {
            Section("OpenAI") {
                SecureField("API klíč", text: $openaiKey)
                    .onSubmit { saveKey(openaiKey, for: .openai) }
                saveButton(for: .openai, key: openaiKey)
            }
            Section("Anthropic") {
                SecureField("API klíč", text: $anthropicKey)
                    .onSubmit { saveKey(anthropicKey, for: .anthropic) }
                saveButton(for: .anthropic, key: anthropicKey)
            }
            Section("Azure OpenAI") {
                SecureField("API klíč", text: $azureKey)
                    .onSubmit { saveKey(azureKey, for: .azureOpenai) }
                TextField("Endpoint URL", text: Binding(
                    get: { config.azureEndpoint ?? "" },
                    set: {
                        config.azureEndpoint = $0.isEmpty ? nil : $0
                        ConfigStore.shared.update { $0.azureEndpoint = config.azureEndpoint }
                    }
                ))
                TextField("Deployment name", text: Binding(
                    get: { config.azureDeploymentName ?? "" },
                    set: {
                        config.azureDeploymentName = $0.isEmpty ? nil : $0
                        ConfigStore.shared.update { $0.azureDeploymentName = config.azureDeploymentName }
                    }
                ))
                saveButton(for: .azureOpenai, key: azureKey)
            }
            Section("Vlastní OpenAI-compatible") {
                TextField("Base URL (např. http://localhost:11434/v1)", text: Binding(
                    get: { config.customOpenAIBaseURL ?? "" },
                    set: {
                        config.customOpenAIBaseURL = $0.isEmpty ? nil : $0
                        ConfigStore.shared.update { $0.customOpenAIBaseURL = config.customOpenAIBaseURL }
                    }
                ))
                SecureField("API klíč (volitelné)", text: $customKey)
                    .onSubmit { saveKey(customKey, for: .customOpenAI) }
                saveButton(for: .customOpenAI, key: customKey)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func saveButton(for provider: ProviderType, key: String) -> some View {
        HStack {
            Button("Uložit") { saveKey(key, for: provider) }
                .disabled(key.isEmpty)
            if let saved = keySaveStatus[provider] {
                Image(systemName: saved ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(saved ? .green : .red)
            }
        }
    }

    private func saveKey(_ key: String, for provider: ProviderType) {
        do {
            try KeychainStore.save(apiKey: key, for: provider)
            keySaveStatus[provider] = true
        } catch {
            keySaveStatus[provider] = false
        }
    }

    private func loadKeys() {
        openaiKey = (try? KeychainStore.load(for: .openai)) ?? ""
        anthropicKey = (try? KeychainStore.load(for: .anthropic)) ?? ""
        azureKey = (try? KeychainStore.load(for: .azureOpenai)) ?? ""
        customKey = (try? KeychainStore.load(for: .customOpenAI)) ?? ""
    }
}

private struct ActionRow: View {
    @Binding var action: Action
    var onDelete: () -> Void
    @State private var pickerModel: String = ""
    @State private var customModelText: String = ""
    @State private var confirmDelete = false

    private let customSentinel = "__custom__"

    private var isCustom: Bool { pickerModel == customSentinel }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("", isOn: $action.enabled)
                    .labelsHidden()
                TextField("Název akce", text: $action.name)
                    .font(.headline)
                Spacer()
                Button {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .confirmationDialog(
                    "Smazat akci \"\(action.name)\"?",
                    isPresented: $confirmDelete,
                    titleVisibility: .visible
                ) {
                    Button("Smazat", role: .destructive) { onDelete() }
                }
            }

            providerModelRow

            TextEditor(text: $action.systemPrompt)
                .font(.callout)
                .frame(minHeight: 60, maxHeight: 100)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))

            parametersRow
        }
        .padding(.vertical, 6)
        .onAppear { syncPickerFromAction() }
        .onChange(of: action) {
            ConfigStore.shared.update { store in
                if let idx = store.actions.firstIndex(where: { $0.id == action.id }) {
                    store.actions[idx] = action
                }
            }
        }
    }

    private func syncPickerFromAction() {
        let presetIDs = action.provider.presetModels.map(\.id)
        if !presetIDs.isEmpty && presetIDs.contains(action.model) {
            pickerModel = action.model
            customModelText = ""
        } else {
            pickerModel = customSentinel
            customModelText = action.model
        }
    }

    private var providerModelRow: some View {
        HStack(spacing: 6) {
            Picker("Provider", selection: $action.provider) {
                ForEach(ProviderType.allCases, id: \.self) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .labelsHidden()
            .frame(width: 120)
            .onChange(of: action.provider) {
                let presets = action.provider.presetModels
                if presets.isEmpty {
                    action.model = ""
                    pickerModel = customSentinel
                    customModelText = ""
                } else {
                    let first = presets.first!.id
                    action.model = first
                    pickerModel = first
                    customModelText = ""
                }
            }

            if action.provider.presetModels.isEmpty {
                TextField("název modelu", text: $customModelText)
                    .frame(width: 260)
                    .onChange(of: customModelText) {
                        if !customModelText.isEmpty { action.model = customModelText }
                    }
            } else {
                Picker("Model", selection: $pickerModel) {
                    ForEach(action.provider.presetModels) { preset in
                        Text(preset.displayName).tag(preset.id)
                    }
                    Divider()
                    Text("Vlastní model…").tag(customSentinel)
                }
                .labelsHidden()
                .frame(width: 200)
                .onChange(of: pickerModel) {
                    if pickerModel != customSentinel {
                        action.model = pickerModel
                        customModelText = ""
                    }
                }

                if isCustom {
                    TextField("název modelu", text: $customModelText)
                        .frame(width: 160)
                        .onChange(of: customModelText) {
                            if !customModelText.isEmpty { action.model = customModelText }
                        }
                }
            }
        }
    }

    private var parametersRow: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Teplota: \(action.temperature, specifier: "%.1f")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $action.temperature, in: 0.0...2.0, step: 0.1)
                    .frame(width: 160)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 2) {
                Text("Max. tokenů")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("", value: $action.maxTokens, format: .number)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                    Stepper("", value: $action.maxTokens, in: 256...32000, step: 256)
                        .labelsHidden()
                }
            }
        }
    }
}

extension ProviderType {
    var displayName: String {
        switch self {
        case .openai: "OpenAI"
        case .azureOpenai: "Azure OpenAI"
        case .anthropic: "Anthropic"
        case .customOpenAI: "Vlastní"
        }
    }

    var presetModels: [ModelPreset] {
        switch self {
        case .openai:
            [
                .init(id: "gpt-4o", displayName: "gpt-4o [Doporučeno]"),
                .init(id: "gpt-4o-mini", displayName: "gpt-4o-mini"),
                .init(id: "o4-mini", displayName: "o4-mini"),
                .init(id: "o3", displayName: "o3")
            ]
        case .azureOpenai:
            [.init(id: "gpt-4o", displayName: "gpt-4o")]
        case .anthropic:
            [
                .init(id: "claude-sonnet-4-6", displayName: "claude-sonnet-4.6 [Doporučeno]"),
                .init(id: "claude-opus-4-7", displayName: "claude-opus-4.7"),
                .init(id: "claude-haiku-4-5-20251001", displayName: "claude-haiku-4.5")
            ]
        case .customOpenAI:
            []
        }
    }
}

struct ModelPreset: Identifiable {
    let id: String
    let displayName: String
}
