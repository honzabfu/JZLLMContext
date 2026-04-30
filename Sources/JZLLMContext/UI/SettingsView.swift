import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum SettingsTab: String, Hashable { case general, actions, providers }

@MainActor
class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    @Published var selectedTab: SettingsTab = .general
}

struct SettingsView: View {
    @ObservedObject private var nav = SettingsNavigation.shared
    @State private var config = ConfigStore.shared.config
    @State private var openaiKey = ""
    @State private var anthropicKey = ""
    @State private var azureKey = ""
    @State private var azureKey2 = ""
    @State private var customKey = ""
    @State private var customKey2 = ""
    @State private var keySaveStatus: [ProviderType: Bool] = [:]
    @State private var launchAtLogin = false
    @State private var importedActions: [Action] = []
    @State private var showImportAlert = false
    @State private var importedConfig: AppConfig? = nil
    @State private var showConfigImportAlert = false
    @State private var isFetching: ProviderType? = nil
    @State private var fetchError: [ProviderType: String] = [:]
    @State private var isTesting: ProviderType? = nil
    @State private var testResult: [ProviderType: Bool] = [:]
    @State private var testError: [ProviderType: String] = [:]
    @State private var reviewModels: [FetchedModel] = []
    @State private var reviewingProvider: ProviderType? = nil
    @State private var showResetAlert = false
    @State private var updateState: UpdateState = .idle

    private enum UpdateState: Equatable {
        case idle, checking, upToDate, failed
        case available(version: String, url: URL)
    }

    var body: some View {
        TabView(selection: $nav.selectedTab) {
            generalTab
                .tabItem { Label("Obecné", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            actionsTab
                .tabItem { Label("Akce", systemImage: "list.bullet") }
                .tag(SettingsTab.actions)
            providersTab
                .tabItem { Label("Providery", systemImage: "key") }
                .tag(SettingsTab.providers)
        }
        .frame(minWidth: 620, minHeight: 520)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            Task { @MainActor in loadKeys() }
        }
        .sheet(item: $reviewingProvider) { provider in
            ModelReviewSheet(provider: provider, models: $reviewModels) { saved in
                let presets = saved
                    .filter(\.isIncluded)
                    .map { ModelPreset(id: $0.id, displayName: $0.displayName, isRecommended: $0.isRecommended) }
                ConfigStore.shared.update { $0.modelPresets[provider.rawValue] = presets }
                config = ConfigStore.shared.config
                reviewingProvider = nil
            } onCancel: {
                reviewingProvider = nil
            }
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
                Toggle("Po dokončení akce zkopírovat výsledek a zavřít panel", isOn: $config.autoCopyAndClose)
                    .onChange(of: config.autoCopyAndClose) { _, val in
                        ConfigStore.shared.update { $0.autoCopyAndClose = val }
                    }
                Toggle("Zobrazovat výsledek s formátováním", isOn: $config.markdownOutput)
                    .onChange(of: config.markdownOutput) { _, val in
                        ConfigStore.shared.update { $0.markdownOutput = val }
                    }
                Stepper("Historie výsledků: \(config.historyLimit == 0 ? "vypnuto" : "\(config.historyLimit)")",
                        value: $config.historyLimit, in: 0...10)
                    .onChange(of: config.historyLimit) { _, val in
                        ConfigStore.shared.update { $0.historyLimit = val }
                        HistoryStore.shared.trim(to: val)
                    }
            }
            Section("Záloha konfigurace") {
                Text("Zahrnuje: akce, globální zkratku, nastavení Azure endpointů, výběr modelů a ostatní volby. Nezahrnuje API klíče (ty zůstávají v Keychainu).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("Exportovat konfiguraci…") { exportConfig() }
                    Button("Importovat konfiguraci…") { importConfig() }
                }
            }
            Section("Globální zkratka") {
                HStack {
                    Text("Zkratka")
                    Spacer()
                    HotkeyRecorderView(keyCode: $config.hotkeyKeyCode, modifiers: $config.hotkeyModifiers)
                        .frame(width: 150, height: 26)
                        .onChange(of: config.hotkeyKeyCode) { saveHotkey() }
                        .onChange(of: config.hotkeyModifiers) { saveHotkey() }
                }
                Text("Klikni na pole a stiskni požadovanou kombinaci kláves. Kliknutí znovu zruší záznam.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Aktualizace") {
                HStack {
                    Button("Zkontrolovat aktualizace") {
                        updateState = .checking
                        Task {
                            do {
                                let release = try await UpdateChecker.fetchLatest()
                                if release.version == UpdateChecker.currentVersion {
                                    updateState = .upToDate
                                } else if let url = URL(string: release.html_url) {
                                    updateState = .available(version: release.version, url: url)
                                } else {
                                    updateState = .failed
                                }
                            } catch {
                                updateState = .failed
                            }
                        }
                    }
                    .disabled(updateState == .checking)

                    switch updateState {
                    case .idle:
                        EmptyView()
                    case .checking:
                        ProgressView().scaleEffect(0.7)
                    case .upToDate:
                        Label("Máte aktuální verzi", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.callout)
                    case .available(let version, let url):
                        Link(destination: url) {
                            Label("Dostupná verze \(version)", systemImage: "arrow.down.circle.fill")
                                .font(.callout)
                        }
                    case .failed:
                        Label("Nepodařilo se ověřit", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                }
            }
            Section("Resetovat nastavení") {
                Text("Odstraní všechna nastavení, akce a poskytovatele. API klíče zůstanou v Keychainu zachovány.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Smazat konfiguraci…", role: .destructive) {
                    showResetAlert = true
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Importovat konfiguraci", isPresented: $showConfigImportAlert) {
            Button("Nahradit vše", role: .destructive) {
                guard let imported = importedConfig else { return }
                ConfigStore.shared.update { $0 = imported }
                config = ConfigStore.shared.config
                importedConfig = nil
            }
            Button("Zrušit", role: .cancel) { importedConfig = nil }
        } message: {
            Text("Importovaná konfigurace nahradí všechny akce, zkratku i ostatní nastavení. API klíče zůstanou beze změny.")
        }
        .alert("Smazat konfiguraci?", isPresented: $showResetAlert) {
            Button("Smazat vše", role: .destructive) {
                ConfigStore.shared.reset()
                config = ConfigStore.shared.config
                NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
            }
            Button("Zrušit", role: .cancel) {}
        } message: {
            Text("Tato akce odstraní všechny akce, globální zkratku, nastavení providerů a ostatní volby. API klíče v Keychainu zůstanou zachovány. Akci nelze vrátit zpět.")
        }
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
                    ActionRow(action: $action, onSetDefault: {
                        let targetID = action.id
                        for i in config.actions.indices {
                            config.actions[i].isDefault = config.actions[i].id == targetID
                        }
                        ConfigStore.shared.update { $0.actions = config.actions }
                    }, onDelete: {
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
                        model: "gpt-5.5",
                        enabled: true
                    ))
                    ConfigStore.shared.update { $0.actions = config.actions }
                }
                Spacer()
                Button("Importovat akce…") { importActions() }
                Button("Exportovat akce…") { exportActions() }
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

    private func exportConfig() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(ConfigStore.shared.config) else { return }
        let panel = NSSavePanel()
        panel.title = "Exportovat konfiguraci"
        panel.nameFieldStringValue = "JZLLMContext-config.json"
        panel.allowedContentTypes = [.json]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.title = "Importovat konfiguraci"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                  let data = try? Data(contentsOf: url),
                  let cfg = try? JSONDecoder().decode(AppConfig.self, from: data) else { return }
            DispatchQueue.main.async {
                importedConfig = cfg
                showConfigImportAlert = true
            }
        }
    }

    private var providersTab: some View {
        Form {
            Section("OpenAI") {
                SecureField("API klíč", text: $openaiKey)
                    .onSubmit { saveKey(openaiKey, for: .openai) }
                saveButton(for: .openai, key: openaiKey)
                fetchModelsRow(for: .openai)
                testConnectionRow(for: .openai)
            }
            Section("Anthropic") {
                SecureField("API klíč", text: $anthropicKey)
                    .onSubmit { saveKey(anthropicKey, for: .anthropic) }
                saveButton(for: .anthropic, key: anthropicKey)
                fetchModelsRow(for: .anthropic)
                testConnectionRow(for: .anthropic)
            }
            Section("Azure AI (slot 1)") {
                Text("Zadej celou URL deployment (vč. cesty /openai/deployments/…), nebo jen resource URL + deployment name zvlášť. Aplikace přidá /chat/completions a ?api-version automaticky.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("API klíč", text: $azureKey)
                    .onSubmit { saveKey(azureKey, for: .azureOpenai) }
                TextField("Deployment URL (např. https://hub.openai.azure.com/openai/deployments/muj-model)", text: Binding(
                    get: { config.azureEndpoint ?? "" },
                    set: {
                        config.azureEndpoint = $0.isEmpty ? nil : $0
                        ConfigStore.shared.update { $0.azureEndpoint = config.azureEndpoint }
                    }
                ))
                TextField("Deployment name (jen pokud výše zadáváš pouze resource URL)", text: Binding(
                    get: { config.azureDeploymentName ?? "" },
                    set: {
                        config.azureDeploymentName = $0.isEmpty ? nil : $0
                        ConfigStore.shared.update { $0.azureDeploymentName = config.azureDeploymentName }
                    }
                ))
                TextField("API verze (výchozí: \(AppConfig.defaultAzureAPIVersion))", text: Binding(
                    get: { config.azureAPIVersion ?? "" },
                    set: {
                        config.azureAPIVersion = $0.isEmpty ? nil : $0
                        ConfigStore.shared.update { $0.azureAPIVersion = config.azureAPIVersion }
                    }
                ))
                saveButton(for: .azureOpenai, key: azureKey)
                testConnectionRow(for: .azureOpenai)
            }
            Section("Azure AI (slot 2)") {
                SecureField("API klíč", text: $azureKey2)
                    .onSubmit { saveKey(azureKey2, for: .azureOpenai2) }
                TextField("Deployment URL (např. https://hub.openai.azure.com/openai/deployments/muj-model)", text: Binding(
                    get: { config.azureEndpoint2 ?? "" },
                    set: {
                        config.azureEndpoint2 = $0.isEmpty ? nil : $0
                        ConfigStore.shared.update { $0.azureEndpoint2 = config.azureEndpoint2 }
                    }
                ))
                TextField("Deployment name (jen pokud výše zadáváš pouze resource URL)", text: Binding(
                    get: { config.azureDeploymentName2 ?? "" },
                    set: {
                        config.azureDeploymentName2 = $0.isEmpty ? nil : $0
                        ConfigStore.shared.update { $0.azureDeploymentName2 = config.azureDeploymentName2 }
                    }
                ))
                TextField("API verze (výchozí: \(AppConfig.defaultAzureAPIVersion))", text: Binding(
                    get: { config.azureAPIVersion2 ?? "" },
                    set: {
                        config.azureAPIVersion2 = $0.isEmpty ? nil : $0
                        ConfigStore.shared.update { $0.azureAPIVersion2 = config.azureAPIVersion2 }
                    }
                ))
                saveButton(for: .azureOpenai2, key: azureKey2)
                testConnectionRow(for: .azureOpenai2)
            }
            Section("Vlastní API (slot 1)") {
                TextField("Base URL (např. http://localhost:11434/v1)", text: Binding(
                    get: { config.customOpenAIBaseURL ?? "" },
                    set: {
                        config.customOpenAIBaseURL = $0.isEmpty ? nil : $0
                        ConfigStore.shared.update { $0.customOpenAIBaseURL = config.customOpenAIBaseURL }
                    }
                ))
                TextField("API verze (volitelné, přidá ?api-version=…)", text: Binding(
                    get: { config.customOpenAIAPIVersion ?? "" },
                    set: {
                        config.customOpenAIAPIVersion = $0.isEmpty ? nil : $0
                        ConfigStore.shared.update { $0.customOpenAIAPIVersion = config.customOpenAIAPIVersion }
                    }
                ))
                Picker("Parametr max. tokenů", selection: $config.customOpenAITokenParam) {
                    ForEach(TokenParamStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .onChange(of: config.customOpenAITokenParam) { _, val in
                    ConfigStore.shared.update { $0.customOpenAITokenParam = val }
                }
                SecureField("API klíč (volitelné)", text: $customKey)
                    .onSubmit { saveKey(customKey, for: .customOpenAI) }
                saveButton(for: .customOpenAI, key: customKey)
                testConnectionRow(for: .customOpenAI)
            }
            Section("Vlastní API (slot 2)") {
                TextField("Base URL (např. http://localhost:11434/v1)", text: Binding(
                    get: { config.customOpenAIBaseURL2 ?? "" },
                    set: {
                        config.customOpenAIBaseURL2 = $0.isEmpty ? nil : $0
                        ConfigStore.shared.update { $0.customOpenAIBaseURL2 = config.customOpenAIBaseURL2 }
                    }
                ))
                TextField("API verze (volitelné, přidá ?api-version=…)", text: Binding(
                    get: { config.customOpenAIAPIVersion2 ?? "" },
                    set: {
                        config.customOpenAIAPIVersion2 = $0.isEmpty ? nil : $0
                        ConfigStore.shared.update { $0.customOpenAIAPIVersion2 = config.customOpenAIAPIVersion2 }
                    }
                ))
                Picker("Parametr max. tokenů", selection: $config.customOpenAITokenParam2) {
                    ForEach(TokenParamStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .onChange(of: config.customOpenAITokenParam2) { _, val in
                    ConfigStore.shared.update { $0.customOpenAITokenParam2 = val }
                }
                SecureField("API klíč (volitelné)", text: $customKey2)
                    .onSubmit { saveKey(customKey2, for: .customOpenAI2) }
                saveButton(for: .customOpenAI2, key: customKey2)
                testConnectionRow(for: .customOpenAI2)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private func fetchModelsRow(for provider: ProviderType) -> some View {
        HStack(spacing: 8) {
            Button {
                Task { await fetchModels(for: provider) }
            } label: {
                if isFetching == provider {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("Načítám modely…")
                    }
                } else {
                    Label("Aktualizovat modely", systemImage: "arrow.clockwise")
                }
            }
            .disabled(isFetching != nil)

            if let stored = config.modelPresets[provider.rawValue] {
                Text("\(stored.count) modelů uloženo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        if let error = fetchError[provider] {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func fetchModels(for provider: ProviderType) async {
        isFetching = provider
        fetchError[provider] = nil
        do {
            let models = try await ModelFetcher.fetch(for: provider)
            reviewModels = models
            reviewingProvider = provider
        } catch {
            fetchError[provider] = error.localizedDescription
        }
        isFetching = nil
    }

    @ViewBuilder
    private func testConnectionRow(for provider: ProviderType) -> some View {
        HStack(spacing: 8) {
            Button {
                Task { await testConnection(for: provider) }
            } label: {
                if isTesting == provider {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("Testuji…")
                    }
                } else {
                    Label("Ověřit připojení", systemImage: "network")
                }
            }
            .disabled(isTesting != nil)

            if let success = testResult[provider] {
                Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(success ? .green : .red)
                if success {
                    Text("OK")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        if let error = testError[provider] {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func testConnection(for provider: ProviderType) async {
        isTesting = provider
        testResult.removeValue(forKey: provider)
        testError.removeValue(forKey: provider)
        do {
            try await ConnectionTester.test(for: provider)
            testResult[provider] = true
        } catch {
            testResult[provider] = false
            testError[provider] = error.localizedDescription
        }
        isTesting = nil
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
        azureKey2 = (try? KeychainStore.load(for: .azureOpenai2)) ?? ""
        customKey = (try? KeychainStore.load(for: .customOpenAI)) ?? ""
        customKey2 = (try? KeychainStore.load(for: .customOpenAI2)) ?? ""
    }
}

// MARK: - Model Review Sheet

private struct ModelReviewSheet: View {
    let provider: ProviderType
    @Binding var models: [FetchedModel]
    let onSave: ([FetchedModel]) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Modely – \(provider.displayName)")
                    .font(.headline)
                Spacer()
            }
            .padding()
            Divider()

            List($models) { $model in
                HStack(spacing: 10) {
                    Toggle("", isOn: $model.isIncluded)
                        .labelsHidden()
                        .onChange(of: model.isIncluded) { _, included in
                            if !included && model.isRecommended {
                                model.isRecommended = false
                            }
                        }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.displayName)
                            .strikethrough(!model.isIncluded, color: .secondary)
                            .foregroundStyle(model.isIncluded ? .primary : .secondary)
                        if model.inUseByAction {
                            Text("Používáno v akci")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                    Button {
                        let targetID = model.id
                        for i in models.indices {
                            models[i].isRecommended = models[i].id == targetID
                        }
                    } label: {
                        Image(systemName: model.isRecommended ? "star.fill" : "star")
                            .foregroundStyle(model.isRecommended ? Color.yellow : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.isIncluded)
                    .help("Označit jako doporučený model")
                }
            }

            Divider()
            HStack {
                Button("Zrušit", role: .cancel) { onCancel() }
                Spacer()
                Text("\(models.filter(\.isIncluded).count) z \(models.count) modelů")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Uložit") { onSave(models) }
                    .buttonStyle(.borderedProminent)
                    .disabled(models.filter(\.isIncluded).isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 440)
    }
}

// MARK: - Action Row

private struct ActionRow: View {
    @Binding var action: Action
    var onSetDefault: () -> Void
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
                    onSetDefault()
                } label: {
                    Image(systemName: action.isDefault ? "return.left" : "return.left")
                        .foregroundStyle(action.isDefault ? Color.accentColor : Color.secondary.opacity(0.4))
                        .fontWeight(action.isDefault ? .semibold : .regular)
                }
                .buttonStyle(.plain)
                .help(action.isDefault ? "Výchozí akce (spustí se stiskem Enter)" : "Nastavit jako výchozí akci pro Enter")
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
        let presetIDs = action.provider.effectiveModels().map(\.id)
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
                let presets = action.provider.effectiveModels()
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

            if action.provider.effectiveModels().isEmpty {
                TextField("název modelu", text: $customModelText)
                    .frame(width: 260)
                    .onChange(of: customModelText) {
                        if !customModelText.isEmpty { action.model = customModelText }
                    }
            } else {
                Picker("Model", selection: $pickerModel) {
                    ForEach(action.provider.effectiveModels()) { preset in
                        Text(preset.isRecommended ? "\(preset.displayName) [Doporučeno]" : preset.displayName)
                            .tag(preset.id)
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
                Text("Zkopírovat a zavřít")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $action.autoCopyClose) {
                    ForEach(AutoCopyClose.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
                .pickerStyle(.menu)
            }

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

// MARK: - ProviderType extensions

extension ProviderType: Identifiable {
    public var id: String { rawValue }
}

extension ProviderType {
    var displayName: String {
        switch self {
        case .openai:        "OpenAI"
        case .azureOpenai:   "Azure AI (slot 1)"
        case .azureOpenai2:  "Azure AI (slot 2)"
        case .anthropic:     "Anthropic"
        case .customOpenAI:  "Vlastní API (slot 1)"
        case .customOpenAI2: "Vlastní API (slot 2)"
        }
    }

    func effectiveModels() -> [ModelPreset] {
        let stored = ConfigStore.shared.config.modelPresets[rawValue] ?? []
        return stored.isEmpty ? presetModels : stored
    }

    var presetModels: [ModelPreset] {
        switch self {
        case .openai:
            [
                .init(id: "gpt-5.5",      displayName: "gpt-5.5",             isRecommended: true),
                .init(id: "gpt-5.4-mini", displayName: "gpt-5.4-mini"),
                .init(id: "o4-mini",      displayName: "o4-mini (legacy)"),
                .init(id: "o3",           displayName: "o3 (legacy)"),
                .init(id: "o3-mini",      displayName: "o3-mini (legacy)"),
                .init(id: "gpt-4o",       displayName: "gpt-4o (legacy)"),
                .init(id: "gpt-4o-mini",  displayName: "gpt-4o-mini (legacy)")
            ]
        case .azureOpenai, .azureOpenai2:
            []
        case .anthropic:
            [
                .init(id: "claude-sonnet-4-6",         displayName: "claude-sonnet-4.6", isRecommended: true),
                .init(id: "claude-opus-4-7",            displayName: "claude-opus-4.7"),
                .init(id: "claude-haiku-4-5-20251001",  displayName: "claude-haiku-4.5")
            ]
        case .customOpenAI, .customOpenAI2:
            []
        }
    }
}
