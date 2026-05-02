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
    @State private var geminiKey = ""
    @State private var grokKey = ""
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
    @State private var showRestartAlert = false
    @State private var showLogWarning = false
    @State private var updateState: UpdateState = .idle
    @State private var newPatternLabel = ""
    @State private var newPatternRegex = ""
    private enum PatternField: Hashable { case label, regex }
    @FocusState private var patternFocus: PatternField?

    private enum UpdateState: Equatable {
        case idle, checking, upToDate, failed
        case available(version: String, url: URL)
    }

    var body: some View {
        TabView(selection: $nav.selectedTab) {
            generalTab
                .tabItem { Label(L("settings.tab.general"), systemImage: "gearshape") }
                .tag(SettingsTab.general)
            actionsTab
                .tabItem { Label(L("settings.tab.actions"), systemImage: "list.bullet") }
                .tag(SettingsTab.actions)
            providersTab
                .tabItem { Label(L("settings.tab.providers"), systemImage: "key") }
                .tag(SettingsTab.providers)
        }
        .frame(minWidth: 620, minHeight: 520)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
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
                Toggle(L("settings.general.launch_at_login"), isOn: $launchAtLogin)
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
                Toggle(L("settings.general.auto_copy_close"), isOn: $config.autoCopyAndClose)
                    .onChange(of: config.autoCopyAndClose) { _, val in
                        ConfigStore.shared.update { $0.autoCopyAndClose = val }
                    }
                Toggle(L("settings.general.markdown_output"), isOn: $config.markdownOutput)
                    .onChange(of: config.markdownOutput) { _, val in
                        ConfigStore.shared.update { $0.markdownOutput = val }
                    }
                Stepper(String(format: L("settings.general.history_limit"),
                               config.historyLimit == 0 ? L("settings.general.history_off") : "\(config.historyLimit)"),
                        value: $config.historyLimit, in: 0...10)
                    .onChange(of: config.historyLimit) { _, val in
                        ConfigStore.shared.update { $0.historyLimit = val }
                        HistoryStore.shared.trim(to: val)
                    }
            }
            Section(L("settings.general.section.language")) {
                Picker(L("settings.general.language.picker_label"), selection: $config.appLanguage) {
                    ForEach(AppLanguage.allCases, id: \.self) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .onChange(of: config.appLanguage) { _, val in
                    ConfigStore.shared.update { $0.appLanguage = val }
                    showRestartAlert = true
                }
                Text(L("settings.general.language.restart.message"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(L("settings.general.section.logging")) {
                Toggle(L("settings.general.logging.toggle"), isOn: $config.historyLogEnabled)
                    .onChange(of: config.historyLogEnabled) { _, enabled in
                        if enabled {
                            if !config.historyLogWarningShown {
                                config.historyLogEnabled = false
                                showLogWarning = true
                            } else if config.historyLogDirectory == nil {
                                selectLogDirectory()
                            } else {
                                ConfigStore.shared.update { $0.historyLogEnabled = true }
                            }
                        } else {
                            ConfigStore.shared.update { $0.historyLogEnabled = false }
                        }
                    }
                if config.historyLogEnabled || config.historyLogDirectory != nil {
                    HStack {
                        Text(L("settings.general.logging.directory_label"))
                            .foregroundStyle(.secondary)
                        Text(config.historyLogDirectory ?? L("settings.general.logging.no_directory"))
                            .lineLimit(1)
                            .truncationMode(.head)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button(L("settings.general.logging.choose_button")) { selectLogDirectory() }
                    }
                    LabeledContent(L("settings.general.logging.prefix_label")) {
                        TextField("", text: $config.historyLogFilePrefix)
                            .frame(maxWidth: 200)
                            .onChange(of: config.historyLogFilePrefix) { _, val in
                                ConfigStore.shared.update { $0.historyLogFilePrefix = val }
                                Task { await HistoryLogger.shared.resetHandleCache() }
                            }
                    }
                    Text(L("settings.general.logging.caption"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section(L("settings.general.section.sensitive")) {
                Toggle(L("settings.general.sensitive.enabled"), isOn: $config.sensitiveContentCheckEnabled)
                    .onChange(of: config.sensitiveContentCheckEnabled) { _, val in
                        ConfigStore.shared.update { $0.sensitiveContentCheckEnabled = val }
                    }
                if config.sensitiveContentCheckEnabled {
                    DisclosureGroup(L("settings.general.sensitive.builtin_label")) {
                        ForEach(SensitiveContentDetector.builtInPatterns) { pattern in
                            HStack(spacing: 8) {
                                Text(pattern.label)
                                    .frame(width: 140, alignment: .leading)
                                Text(pattern.pattern)
                                    .monospaced()
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .font(.caption)
                        }
                    }
                    ForEach(config.customSensitivePatterns) { pattern in
                        HStack(spacing: 8) {
                            Text(pattern.label)
                                .frame(width: 140, alignment: .leading)
                            Text(pattern.pattern)
                                .monospaced()
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button(role: .destructive) {
                                config.customSensitivePatterns.removeAll { $0.id == pattern.id }
                                ConfigStore.shared.update { $0.customSensitivePatterns = config.customSensitivePatterns }
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .font(.caption)
                    }
                    LabeledContent(L("settings.general.sensitive.label_placeholder")) {
                        TextField("", text: $newPatternLabel)
                            .focused($patternFocus, equals: .label)
                            .onSubmit { patternFocus = .regex }
                    }
                    LabeledContent(L("settings.general.sensitive.regex_placeholder")) {
                        TextField("", text: $newPatternRegex)
                            .focused($patternFocus, equals: .regex)
                            .foregroundStyle(!newPatternRegex.isEmpty && !isValidRegex(newPatternRegex) ? .red : .primary)
                            .onSubmit {
                                guard !newPatternLabel.isEmpty, isValidRegex(newPatternRegex) else { return }
                                let p = SensitivePattern(label: newPatternLabel, pattern: newPatternRegex)
                                config.customSensitivePatterns.append(p)
                                ConfigStore.shared.update { $0.customSensitivePatterns = config.customSensitivePatterns }
                                newPatternLabel = ""
                                newPatternRegex = ""
                                patternFocus = .label
                            }
                    }
                    if !newPatternRegex.isEmpty && !isValidRegex(newPatternRegex) {
                        Text(L("settings.general.sensitive.invalid_regex"))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    HStack {
                        Spacer()
                        Button(L("settings.general.sensitive.add_button")) {
                            let p = SensitivePattern(label: newPatternLabel, pattern: newPatternRegex)
                            config.customSensitivePatterns.append(p)
                            ConfigStore.shared.update { $0.customSensitivePatterns = config.customSensitivePatterns }
                            newPatternLabel = ""
                            newPatternRegex = ""
                        }
                        .disabled(newPatternLabel.isEmpty || !isValidRegex(newPatternRegex))
                    }
                }
            }
            Section(L("settings.general.section.backup")) {
                Text(L("settings.general.backup.description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button(L("settings.general.export_config")) { exportConfig() }
                    Button(L("settings.general.import_config")) { importConfig() }
                }
            }
            Section(L("settings.general.section.hotkey")) {
                HStack {
                    Text(L("settings.general.hotkey_label"))
                    Spacer()
                    HotkeyRecorderView(keyCode: $config.hotkeyKeyCode, modifiers: $config.hotkeyModifiers)
                        .frame(width: 150, height: 26)
                        .onChange(of: config.hotkeyKeyCode) { saveHotkey() }
                        .onChange(of: config.hotkeyModifiers) { saveHotkey() }
                }
                Text(L("settings.general.hotkey_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(L("settings.general.section.updates")) {
                HStack {
                    Button(L("settings.general.check_updates")) {
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
                        ProgressView().controlSize(.small)
                    case .upToDate:
                        Label(L("settings.general.update.up_to_date"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.callout)
                    case .available(let version, let url):
                        Link(destination: url) {
                            Label(String(format: L("settings.general.update.available"), version), systemImage: "arrow.down.circle.fill")
                                .font(.callout)
                        }
                    case .failed:
                        Label(L("settings.general.update.failed"), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                }
                Toggle(L("settings.general.auto_update"), isOn: $config.autoUpdateCheck)
                    .onChange(of: config.autoUpdateCheck) { _, val in
                        ConfigStore.shared.update { $0.autoUpdateCheck = val }
                    }
            }
            Section(L("settings.general.section.reset")) {
                Text(L("settings.general.reset.description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(L("settings.general.reset.button"), role: .destructive) {
                    showResetAlert = true
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert(L("settings.alert.import_config.title"), isPresented: $showConfigImportAlert) {
            Button(L("settings.alert.import_config.replace"), role: .destructive) {
                guard let imported = importedConfig else { return }
                ConfigStore.shared.update { $0 = imported }
                config = ConfigStore.shared.config
                importedConfig = nil
            }
            Button(L("common.cancel"), role: .cancel) { importedConfig = nil }
        } message: {
            Text(L("settings.alert.import_config.message"))
        }
        .alert(L("settings.alert.reset.title"), isPresented: $showResetAlert) {
            Button(L("settings.alert.reset.confirm"), role: .destructive) {
                ConfigStore.shared.reset()
                config = ConfigStore.shared.config
                NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
            }
            Button(L("common.cancel"), role: .cancel) {}
        } message: {
            Text(L("settings.alert.reset.message"))
        }
        .alert(L("settings.general.language.restart.title"), isPresented: $showRestartAlert) {
            Button(L("settings.general.language.restart.now")) { relaunchApp() }
            Button(L("common.later"), role: .cancel) {}
        } message: {
            Text(L("settings.general.language.restart.message"))
        }
        .alert(L("settings.general.logging.alert.title"), isPresented: $showLogWarning) {
            Button(L("settings.general.logging.alert.enable")) { selectLogDirectory() }
            Button(L("common.cancel"), role: .cancel) { }
        } message: {
            Text(L("settings.general.logging.alert.message"))
        }
    }

    private func isValidRegex(_ pattern: String) -> Bool {
        !pattern.isEmpty && (try? NSRegularExpression(pattern: pattern)) != nil
    }

    private func selectLogDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L("settings.general.logging.choose_button")
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                if !config.historyLogWarningShown {
                    config.historyLogEnabled = false
                    ConfigStore.shared.update { $0.historyLogEnabled = false }
                }
                return
            }
            config.historyLogDirectory = url.path
            config.historyLogEnabled = true
            config.historyLogWarningShown = true
            ConfigStore.shared.update {
                $0.historyLogDirectory = url.path
                $0.historyLogEnabled = true
                $0.historyLogWarningShown = true
            }
            Task { await HistoryLogger.shared.resetHandleCache() }
        }
    }

    private func relaunchApp() {
        let path = Bundle.main.bundleURL.path
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", path]
        try? task.run()
        NSApp.terminate(nil)
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
                Button(L("settings.actions.add")) {
                    config.actions.append(Action(
                        name: L("settings.actions.new_name"),
                        systemPrompt: "",
                        provider: .openai,
                        model: "gpt-5.5",
                        enabled: true
                    ))
                    ConfigStore.shared.update { $0.actions = config.actions }
                }
                Spacer()
                Button(L("settings.actions.import")) { importActions() }
                Button(L("settings.actions.export")) { exportActions() }
                    .disabled(config.actions.isEmpty)
            }
            .padding(12)
        }
        .alert(L("settings.alert.import_actions.title"), isPresented: $showImportAlert) {
            Button(L("settings.alert.import_actions.add")) {
                let fresh = importedActions.map { var a = $0; a.id = UUID(); return a }
                config.actions.append(contentsOf: fresh)
                ConfigStore.shared.update { $0.actions = config.actions }
            }
            Button(L("settings.alert.import_config.replace"), role: .destructive) {
                let fresh = importedActions.map { var a = $0; a.id = UUID(); return a }
                config.actions = fresh
                ConfigStore.shared.update { $0.actions = config.actions }
            }
            Button(L("common.cancel"), role: .cancel) {}
        } message: {
            Text(String(format: L("settings.alert.import_actions.message"),
                        importedActions.count,
                        importedActions.count == 1 ? L("settings.alert.import_actions.singular") : L("settings.alert.import_actions.plural")))
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
                LabeledContent(L("settings.providers.api_key")) {
                    SecureField("", text: $openaiKey)
                        .onSubmit { saveKey(openaiKey, for: .openai) }
                }
                saveButton(for: .openai, key: openaiKey)
                fetchModelsRow(for: .openai)
                testConnectionRow(for: .openai)
            }
            Section("Anthropic") {
                LabeledContent(L("settings.providers.api_key")) {
                    SecureField("", text: $anthropicKey)
                        .onSubmit { saveKey(anthropicKey, for: .anthropic) }
                }
                saveButton(for: .anthropic, key: anthropicKey)
                fetchModelsRow(for: .anthropic)
                testConnectionRow(for: .anthropic)
            }
            Section("Google Gemini") {
                LabeledContent(L("settings.providers.api_key")) {
                    SecureField("", text: $geminiKey)
                        .onSubmit { saveKey(geminiKey, for: .gemini) }
                }
                saveButton(for: .gemini, key: geminiKey)
                fetchModelsRow(for: .gemini)
                testConnectionRow(for: .gemini)
            }
            Section("xAI Grok") {
                LabeledContent(L("settings.providers.api_key")) {
                    SecureField("", text: $grokKey)
                        .onSubmit { saveKey(grokKey, for: .grok) }
                }
                saveButton(for: .grok, key: grokKey)
                fetchModelsRow(for: .grok)
                testConnectionRow(for: .grok)
            }
            Section("Azure AI (slot 1)") {
                Text(L("settings.providers.azure.description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent(L("settings.providers.api_key")) {
                    SecureField("", text: $azureKey)
                        .onSubmit { saveKey(azureKey, for: .azureOpenai) }
                }
                LabeledContent(L("settings.providers.azure.deployment_url")) {
                    TextField("", text: Binding(
                        get: { config.azureEndpoint ?? "" },
                        set: {
                            config.azureEndpoint = $0.isEmpty ? nil : $0
                            ConfigStore.shared.update { $0.azureEndpoint = config.azureEndpoint }
                        }
                    ))
                }
                LabeledContent(L("settings.providers.azure.deployment_name")) {
                    TextField("", text: Binding(
                        get: { config.azureDeploymentName ?? "" },
                        set: {
                            config.azureDeploymentName = $0.isEmpty ? nil : $0
                            ConfigStore.shared.update { $0.azureDeploymentName = config.azureDeploymentName }
                        }
                    ))
                }
                LabeledContent(String(format: L("settings.providers.azure.api_version"), AppConfig.defaultAzureAPIVersion)) {
                    TextField("", text: Binding(
                        get: { config.azureAPIVersion ?? "" },
                        set: {
                            config.azureAPIVersion = $0.isEmpty ? nil : $0
                            ConfigStore.shared.update { $0.azureAPIVersion = config.azureAPIVersion }
                        }
                    ))
                }
                saveButton(for: .azureOpenai, key: azureKey)
                testConnectionRow(for: .azureOpenai)
            }
            Section("Azure AI (slot 2)") {
                LabeledContent(L("settings.providers.api_key")) {
                    SecureField("", text: $azureKey2)
                        .onSubmit { saveKey(azureKey2, for: .azureOpenai2) }
                }
                LabeledContent(L("settings.providers.azure.deployment_url")) {
                    TextField("", text: Binding(
                        get: { config.azureEndpoint2 ?? "" },
                        set: {
                            config.azureEndpoint2 = $0.isEmpty ? nil : $0
                            ConfigStore.shared.update { $0.azureEndpoint2 = config.azureEndpoint2 }
                        }
                    ))
                }
                LabeledContent(L("settings.providers.azure.deployment_name")) {
                    TextField("", text: Binding(
                        get: { config.azureDeploymentName2 ?? "" },
                        set: {
                            config.azureDeploymentName2 = $0.isEmpty ? nil : $0
                            ConfigStore.shared.update { $0.azureDeploymentName2 = config.azureDeploymentName2 }
                        }
                    ))
                }
                LabeledContent(String(format: L("settings.providers.azure.api_version"), AppConfig.defaultAzureAPIVersion)) {
                    TextField("", text: Binding(
                        get: { config.azureAPIVersion2 ?? "" },
                        set: {
                            config.azureAPIVersion2 = $0.isEmpty ? nil : $0
                            ConfigStore.shared.update { $0.azureAPIVersion2 = config.azureAPIVersion2 }
                        }
                    ))
                }
                saveButton(for: .azureOpenai2, key: azureKey2)
                testConnectionRow(for: .azureOpenai2)
            }
            Section(L("provider.custom1")) {
                LabeledContent(L("settings.providers.custom.base_url")) {
                    TextField("", text: Binding(
                        get: { config.customOpenAIBaseURL ?? "" },
                        set: {
                            config.customOpenAIBaseURL = $0.isEmpty ? nil : $0
                            ConfigStore.shared.update { $0.customOpenAIBaseURL = config.customOpenAIBaseURL }
                        }
                    ))
                }
                LabeledContent(L("settings.providers.custom.api_version")) {
                    TextField("", text: Binding(
                        get: { config.customOpenAIAPIVersion ?? "" },
                        set: {
                            config.customOpenAIAPIVersion = $0.isEmpty ? nil : $0
                            ConfigStore.shared.update { $0.customOpenAIAPIVersion = config.customOpenAIAPIVersion }
                        }
                    ))
                }
                Picker(L("settings.providers.token_param"), selection: $config.customOpenAITokenParam) {
                    ForEach(TokenParamStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .onChange(of: config.customOpenAITokenParam) { _, val in
                    ConfigStore.shared.update { $0.customOpenAITokenParam = val }
                }
                LabeledContent(L("settings.providers.api_key_optional")) {
                    SecureField("", text: $customKey)
                        .onSubmit { saveKey(customKey, for: .customOpenAI) }
                }
                saveButton(for: .customOpenAI, key: customKey)
                testConnectionRow(for: .customOpenAI)
            }
            Section(L("provider.custom2")) {
                LabeledContent(L("settings.providers.custom.base_url")) {
                    TextField("", text: Binding(
                        get: { config.customOpenAIBaseURL2 ?? "" },
                        set: {
                            config.customOpenAIBaseURL2 = $0.isEmpty ? nil : $0
                            ConfigStore.shared.update { $0.customOpenAIBaseURL2 = config.customOpenAIBaseURL2 }
                        }
                    ))
                }
                LabeledContent(L("settings.providers.custom.api_version")) {
                    TextField("", text: Binding(
                        get: { config.customOpenAIAPIVersion2 ?? "" },
                        set: {
                            config.customOpenAIAPIVersion2 = $0.isEmpty ? nil : $0
                            ConfigStore.shared.update { $0.customOpenAIAPIVersion2 = config.customOpenAIAPIVersion2 }
                        }
                    ))
                }
                Picker(L("settings.providers.token_param"), selection: $config.customOpenAITokenParam2) {
                    ForEach(TokenParamStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .onChange(of: config.customOpenAITokenParam2) { _, val in
                    ConfigStore.shared.update { $0.customOpenAITokenParam2 = val }
                }
                LabeledContent(L("settings.providers.api_key_optional")) {
                    SecureField("", text: $customKey2)
                        .onSubmit { saveKey(customKey2, for: .customOpenAI2) }
                }
                saveButton(for: .customOpenAI2, key: customKey2)
                testConnectionRow(for: .customOpenAI2)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            Task { @MainActor in
                loadKeys()
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows where window.title == "JZLLMContext" && window.isVisible {
                    window.makeKeyAndOrderFront(nil)
                    break
                }
            }
        }
    }

    @ViewBuilder
    private func fetchModelsRow(for provider: ProviderType) -> some View {
        HStack(spacing: 8) {
            Button {
                Task { await fetchModels(for: provider) }
            } label: {
                if isFetching == provider {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(L("settings.providers.fetching"))
                    }
                } else {
                    Label(L("settings.providers.fetch_models"), systemImage: "arrow.clockwise")
                }
            }
            .disabled(isFetching != nil)

            if let stored = config.modelPresets[provider.rawValue] {
                Text(String(format: L("settings.providers.models_saved"), stored.count))
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
                        ProgressView().controlSize(.small)
                        Text(L("settings.providers.testing"))
                    }
                } else {
                    Label(L("settings.providers.test_connection"), systemImage: "network")
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
            Button(L("common.save")) { saveKey(key, for: provider) }
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
        geminiKey = (try? KeychainStore.load(for: .gemini)) ?? ""
        grokKey = (try? KeychainStore.load(for: .grok)) ?? ""
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
                Text(String(format: L("settings.models.title"), provider.displayName))
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
                            Text(L("settings.models.in_use"))
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
                    .help(L("settings.models.help.recommend"))
                }
            }

            Divider()
            HStack {
                Button(L("common.cancel"), role: .cancel) { onCancel() }
                Spacer()
                Text(String(format: L("settings.models.count"), models.filter(\.isIncluded).count, models.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L("common.save")) { onSave(models) }
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
                TextField(L("action.row.name_placeholder"), text: $action.name)
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
                .help(action.isDefault ? L("action.row.help.is_default") : L("action.row.help.set_default"))
                Button {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .confirmationDialog(
                    String(format: L("action.row.delete.confirm"), action.name),
                    isPresented: $confirmDelete,
                    titleVisibility: .visible
                ) {
                    Button(L("action.row.delete.button"), role: .destructive) { onDelete() }
                }
            }

            providerModelRow

            TextEditor(text: $action.systemPrompt)
                .font(.callout)
                .frame(minHeight: 60, maxHeight: 100)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))

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
                TextField(L("action.row.model_placeholder"), text: $customModelText)
                    .frame(width: 260)
                    .onChange(of: customModelText) {
                        if !customModelText.isEmpty { action.model = customModelText }
                    }
            } else {
                Picker("Model", selection: $pickerModel) {
                    ForEach(action.provider.effectiveModels()) { preset in
                        Text(preset.isRecommended ? "\(preset.displayName) \(L("action.row.recommended"))" : preset.displayName)
                            .tag(preset.id)
                    }
                    Divider()
                    Text(L("action.row.custom_model")).tag(customSentinel)
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
                    TextField(L("action.row.model_placeholder"), text: $customModelText)
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
                Text(String(format: L("action.row.temperature"), action.temperature))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $action.temperature, in: 0.0...2.0, step: 0.1)
                    .frame(width: 160)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 2) {
                Text(L("action.row.copy_close"))
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
                Text(L("action.row.max_tokens"))
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
        case .openai:        L("provider.openai")
        case .azureOpenai:   L("provider.azure1")
        case .azureOpenai2:  L("provider.azure2")
        case .anthropic:     L("provider.anthropic")
        case .gemini:        L("provider.gemini")
        case .grok:          L("provider.grok")
        case .customOpenAI:  L("provider.custom1")
        case .customOpenAI2: L("provider.custom2")
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
        case .gemini:
            [
                .init(id: "gemini-3.1-pro",        displayName: "gemini-3.1-pro",        isRecommended: true),
                .init(id: "gemini-3-flash-preview", displayName: "gemini-3-flash-preview"),
                .init(id: "gemini-3.1-flash-lite",  displayName: "gemini-3.1-flash-lite")
            ]
        case .grok:
            [
                .init(id: "grok-4.20",              displayName: "grok-4.20",              isRecommended: true),
                .init(id: "grok-4.20-non-reasoning", displayName: "grok-4.20-non-reasoning"),
                .init(id: "grok-4-1-fast-reasoning", displayName: "grok-4.1-fast-reasoning")
            ]
        case .customOpenAI, .customOpenAI2:
            []
        }
    }
}
