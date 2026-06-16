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
    @State private var customProviderKeys: [String: String] = [:]
    @State private var keySaveStatus: [ProviderType: Bool] = [:]
    @State private var keySaveStatusResetTasks: [ProviderType: Task<Void, Never>] = [:]
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
    @State private var newExcludeFilter = ""
    @State private var newIncludeFilter = ""
    @State private var newHeaderKey: [UUID: String] = [:]
    @State private var newHeaderValue: [UUID: String] = [:]
    @State private var showDeleteProviderAlert = false
    @State private var providerToDelete: CustomProvider? = nil
    @State private var expandedProviders: Set<String> = []
    @State private var selectedActionID: UUID?

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
            config = ConfigStore.shared.config
        }
        // Keep the local snapshot in sync with edits made outside this window
        // (e.g. prompt edits via the overlay's ActionDetailSheet) so that
        // whole-array writes like onSetDefault don't persist stale data.
        // Deferred via receive(on:) to avoid re-entrant state updates from
        // this view's own onChange → ConfigStore.update calls.
        .onReceive(NotificationCenter.default.publisher(for: .configDidChange)
            .receive(on: DispatchQueue.main)) { _ in
            config = ConfigStore.shared.config
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
        .alert(L("settings.providers.custom.delete_confirm_title"), isPresented: $showDeleteProviderAlert) {
            Button(L("common.delete"), role: .destructive) {
                if let cp = providerToDelete { performDeleteCustomProvider(cp) }
            }
            Button(L("common.cancel"), role: .cancel) { providerToDelete = nil }
        } message: {
            Text(String(format: L("settings.providers.custom.delete_confirm_message"),
                        providerToDelete?.name ?? ""))
        }
    }

    // MARK: - General Tab

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
                LabeledContent(L("settings.general.history_limit")) {
                    HStack(spacing: 4) {
                        Text(config.historyLimit == 0 ? L("settings.general.history_off") : "\(config.historyLimit)")
                            .foregroundStyle(.secondary)
                        Stepper("", value: $config.historyLimit, in: 0...10)
                            .labelsHidden()
                            .onChange(of: config.historyLimit) { _, val in
                                ConfigStore.shared.update { $0.historyLimit = val }
                                HistoryStore.shared.trim(to: val)
                            }
                    }
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
                            if !pattern.isValidRegex {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .help(L("settings.general.sensitive.invalid_regex"))
                            }
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
            Section(L("settings.general.section.updates")) {
                HStack {
                    Button(L("settings.general.check_updates")) {
                        updateState = .checking
                        Task {
                            do {
                                let release = try await UpdateChecker.fetchLatest()
                                if UpdateChecker.isNewer(release.version, than: UpdateChecker.currentVersion),
                                   let url = URL(string: release.html_url) {
                                    updateState = .available(version: release.version, url: url)
                                } else {
                                    updateState = .upToDate
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
            Section(L("settings.general.section.backup")) {
                Text(L("settings.general.backup.description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button(L("settings.general.export_config")) { exportConfig() }
                    Button(L("settings.general.import_config")) { importConfig() }
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

    // MARK: - Actions Tab

    private var actionsTab: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                actionList
                    .frame(width: 230)
                Divider()
                actionDetail
            }
            Divider()
            HStack {
                Button(L("settings.actions.add")) { addAction() }
                Spacer()
                Button(L("settings.actions.import")) { importActions() }
                Button(L("settings.actions.export")) { exportActions() }
                    .disabled(config.actions.isEmpty)
            }
            .padding(12)
        }
        .onAppear {
            if selectedActionID == nil { selectedActionID = config.actions.first?.id }
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
                selectedActionID = config.actions.first?.id
            }
            Button(L("common.cancel"), role: .cancel) {}
        } message: {
            Text(String(format: L("settings.alert.import_actions.message"),
                        importedActions.count,
                        importedActions.count == 1 ? L("settings.alert.import_actions.singular") : L("settings.alert.import_actions.plural")))
        }
    }

    private var actionList: some View {
        List(selection: $selectedActionID) {
            ForEach(config.actions) { action in
                HStack(spacing: 8) {
                    Toggle("", isOn: Binding(
                        get: { action.enabled },
                        set: { val in updateAction(action.id) { $0.enabled = val } }
                    ))
                    .labelsHidden()
                    .controlSize(.small)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(action.name.isEmpty ? L("settings.actions.new_name") : action.name)
                            .lineLimit(1)
                        Text("\(action.provider.displayName) · \(action.model)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    if action.isDefault {
                        Image(systemName: "return")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help(L("action.row.help.is_default"))
                    }
                }
                .padding(.vertical, 2)
                .tag(action.id)
            }
            .onMove { from, to in
                config.actions.move(fromOffsets: from, toOffset: to)
                ConfigStore.shared.update { $0.actions = config.actions }
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private var actionDetail: some View {
        if let id = selectedActionID, let binding = actionBinding(for: id) {
            ActionDetailEditor(
                action: binding,
                onSetDefault: {
                    for i in config.actions.indices {
                        config.actions[i].isDefault = config.actions[i].id == id
                    }
                    ConfigStore.shared.update { $0.actions = config.actions }
                },
                onDelete: { deleteAction(id) }
            )
            // Recreate the editor per selection so its @State model-picker
            // fields re-sync via onAppear for the newly selected action.
            .id(id)
        } else {
            VStack {
                Spacer()
                Text(config.actions.isEmpty ? L("settings.actions.empty_list") : L("settings.actions.empty_selection"))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func actionBinding(for id: UUID) -> Binding<Action>? {
        guard let current = config.actions.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { config.actions.first(where: { $0.id == id }) ?? current },
            set: { newVal in
                guard let i = config.actions.firstIndex(where: { $0.id == id }) else { return }
                config.actions[i] = newVal
                ConfigStore.shared.update { $0.actions = config.actions }
            }
        )
    }

    private func updateAction(_ id: UUID, _ mutate: (inout Action) -> Void) {
        guard let i = config.actions.firstIndex(where: { $0.id == id }) else { return }
        mutate(&config.actions[i])
        ConfigStore.shared.update { $0.actions = config.actions }
    }

    private func addAction() {
        let action = Action(
            name: L("settings.actions.new_name"),
            systemPrompt: "",
            provider: .openai,
            model: "gpt-5.5",
            enabled: true
        )
        config.actions.append(action)
        ConfigStore.shared.update { $0.actions = config.actions }
        selectedActionID = action.id
    }

    private func deleteAction(_ id: UUID) {
        guard let idx = config.actions.firstIndex(where: { $0.id == id }) else { return }
        config.actions.remove(at: idx)
        ConfigStore.shared.update { $0.actions = config.actions }
        selectedActionID = config.actions.indices.contains(idx)
            ? config.actions[idx].id
            : config.actions.last?.id
    }

    // MARK: - Providers Tab

    private var providersTab: some View {
        Form {
            // Model filters first — they shape what every provider's
            // "Update Models" fetch shows, so they read as global settings.
            modelFiltersSection

            // Built-in providers
            providerSection("OpenAI", provider: .openai, hasKey: !openaiKey.isEmpty,
                            groupTitle: L("settings.providers.section.providers")) {
                LabeledContent(L("settings.providers.api_key")) {
                    SecureField("", text: $openaiKey)
                        .onSubmit { saveKey(openaiKey, for: .openai) }
                }
                saveButton(for: .openai, key: openaiKey)
                fetchModelsRow(for: .openai)
                testConnectionRow(for: .openai, key: openaiKey)
            }
            providerSection("Anthropic", provider: .anthropic, hasKey: !anthropicKey.isEmpty) {
                LabeledContent(L("settings.providers.api_key")) {
                    SecureField("", text: $anthropicKey)
                        .onSubmit { saveKey(anthropicKey, for: .anthropic) }
                }
                saveButton(for: .anthropic, key: anthropicKey)
                fetchModelsRow(for: .anthropic)
                testConnectionRow(for: .anthropic, key: anthropicKey)
            }
            providerSection("Google Gemini", provider: .gemini, hasKey: !geminiKey.isEmpty) {
                LabeledContent(L("settings.providers.api_key")) {
                    SecureField("", text: $geminiKey)
                        .onSubmit { saveKey(geminiKey, for: .gemini) }
                }
                saveButton(for: .gemini, key: geminiKey)
                fetchModelsRow(for: .gemini)
                testConnectionRow(for: .gemini, key: geminiKey)
            }
            providerSection("xAI Grok", provider: .grok, hasKey: !grokKey.isEmpty) {
                LabeledContent(L("settings.providers.api_key")) {
                    SecureField("", text: $grokKey)
                        .onSubmit { saveKey(grokKey, for: .grok) }
                }
                saveButton(for: .grok, key: grokKey)
                fetchModelsRow(for: .grok)
                testConnectionRow(for: .grok, key: grokKey)
            }
            providerSection("Azure AI (slot 1)", provider: .azureOpenai, hasKey: !azureKey.isEmpty) {
                Text(L("settings.providers.azure.description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                LabeledContent(L("settings.providers.api_key")) {
                    SecureField("", text: $azureKey)
                        .onSubmit { saveKey(azureKey, for: .azureOpenai) }
                }
                LabeledContent(L("settings.providers.azure.deployment_url")) {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("", text: Binding(
                            get: { config.azureEndpoint ?? "" },
                            set: {
                                config.azureEndpoint = $0.isEmpty ? nil : $0
                                ConfigStore.shared.update { $0.azureEndpoint = config.azureEndpoint }
                            }
                        ))
                        .multilineTextAlignment(.leading)
                        Text(L("settings.providers.azure.deployment_url_placeholder"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                LabeledContent(L("settings.providers.azure.deployment_name")) {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("", text: Binding(
                            get: { config.azureDeploymentName ?? "" },
                            set: {
                                config.azureDeploymentName = $0.isEmpty ? nil : $0
                                ConfigStore.shared.update { $0.azureDeploymentName = config.azureDeploymentName }
                            }
                        ))
                        .multilineTextAlignment(.leading)
                        Text(L("settings.providers.azure.deployment_name_hint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                LabeledContent(L("settings.providers.azure.api_version")) {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("", text: Binding(
                            get: { config.azureAPIVersion ?? "" },
                            set: {
                                config.azureAPIVersion = $0.isEmpty ? nil : $0
                                ConfigStore.shared.update { $0.azureAPIVersion = config.azureAPIVersion }
                            }
                        ))
                        .multilineTextAlignment(.leading)
                        Text(String(format: L("settings.providers.azure.api_version_placeholder"), AppConfig.defaultAzureAPIVersion))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                saveButton(for: .azureOpenai, key: azureKey)
                testConnectionRow(for: .azureOpenai, key: azureKey)
            }
            providerSection("Azure AI (slot 2)", provider: .azureOpenai2, hasKey: !azureKey2.isEmpty) {
                LabeledContent(L("settings.providers.api_key")) {
                    SecureField("", text: $azureKey2)
                        .onSubmit { saveKey(azureKey2, for: .azureOpenai2) }
                }
                LabeledContent(L("settings.providers.azure.deployment_url")) {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("", text: Binding(
                            get: { config.azureEndpoint2 ?? "" },
                            set: {
                                config.azureEndpoint2 = $0.isEmpty ? nil : $0
                                ConfigStore.shared.update { $0.azureEndpoint2 = config.azureEndpoint2 }
                            }
                        ))
                        .multilineTextAlignment(.leading)
                        Text(L("settings.providers.azure.deployment_url_placeholder"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                LabeledContent(L("settings.providers.azure.deployment_name")) {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("", text: Binding(
                            get: { config.azureDeploymentName2 ?? "" },
                            set: {
                                config.azureDeploymentName2 = $0.isEmpty ? nil : $0
                                ConfigStore.shared.update { $0.azureDeploymentName2 = config.azureDeploymentName2 }
                            }
                        ))
                        .multilineTextAlignment(.leading)
                        Text(L("settings.providers.azure.deployment_name_hint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                LabeledContent(L("settings.providers.azure.api_version")) {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("", text: Binding(
                            get: { config.azureAPIVersion2 ?? "" },
                            set: {
                                config.azureAPIVersion2 = $0.isEmpty ? nil : $0
                                ConfigStore.shared.update { $0.azureAPIVersion2 = config.azureAPIVersion2 }
                            }
                        ))
                        .multilineTextAlignment(.leading)
                        Text(String(format: L("settings.providers.azure.api_version_placeholder"), AppConfig.defaultAzureAPIVersion))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                saveButton(for: .azureOpenai2, key: azureKey2)
                testConnectionRow(for: .azureOpenai2, key: azureKey2)
            }

            // Dynamic custom providers
            ForEach(config.customProviders) { cp in
                customProviderSection(cp: Binding(
                    get: { config.customProviders.first { $0.id == cp.id } ?? cp },
                    set: { newVal in
                        if let i = config.customProviders.firstIndex(where: { $0.id == cp.id }) {
                            config.customProviders[i] = newVal
                        }
                        ConfigStore.shared.update { $0.customProviders = config.customProviders }
                    }
                ))
            }

            Section {
                Button {
                    let newCP = CustomProvider(name: L("settings.providers.custom.new_name"),
                                               baseURL: "")
                    config.customProviders.append(newCP)
                    ConfigStore.shared.update { $0.customProviders = config.customProviders }
                    expandedProviders.insert(newCP.id.uuidString)
                } label: {
                    Label(L("settings.providers.add_custom"), systemImage: "plus")
                }
            }
        }
        .formStyle(.grouped)
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

    // MARK: - Collapsible Provider Section

    private func expansionBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { expandedProviders.contains(id) },
            set: { expanded in
                if expanded {
                    expandedProviders.insert(id)
                } else {
                    expandedProviders.remove(id)
                }
            }
        )
    }

    private func providerSection<Content: View>(
        _ name: String,
        provider: ProviderType,
        hasKey: Bool,
        showsKeyStatus: Bool = true,
        groupTitle: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        Section {
            DisclosureGroup(isExpanded: expansionBinding(provider.rawValue)) {
                content()
            } label: {
                providerHeader(name, provider: provider, hasKey: hasKey, showsKeyStatus: showsKeyStatus)
            }
        } header: {
            if let groupTitle {
                Text(groupTitle)
            }
        }
    }

    private func providerHeader(_ name: String, provider: ProviderType,
                                hasKey: Bool, showsKeyStatus: Bool) -> some View {
        HStack(spacing: 8) {
            Text(name)
                .fontWeight(.medium)
            Spacer()
            if let presets = config.modelPresets[provider.rawValue], !presets.isEmpty {
                Text(String(format: L("settings.providers.models_saved"), presets.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if showsKeyStatus {
                Image(systemName: hasKey ? "key.fill" : "key")
                    .font(.caption)
                    .foregroundStyle(hasKey ? Color.green : Color.secondary)
                    .help(L(hasKey ? "settings.providers.key_saved" : "settings.providers.key_missing"))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { expansionBinding(provider.rawValue).wrappedValue.toggle() }
    }

    // MARK: - Custom Provider Section

    @ViewBuilder
    private func customProviderSection(cp: Binding<CustomProvider>) -> some View {
        let cpID = cp.wrappedValue.id
        let provider = ProviderType(cpID.uuidString)
        let keyBinding = Binding<String>(
            get: { customProviderKeys[cpID.uuidString] ?? "" },
            set: { customProviderKeys[cpID.uuidString] = $0 }
        )

        Section {
            DisclosureGroup(isExpanded: expansionBinding(cpID.uuidString)) {
                LabeledContent(L("settings.providers.custom.name")) {
                    TextField("", text: cp.name)
                        .onChange(of: cp.wrappedValue.name) { _, _ in
                            ConfigStore.shared.update { $0.customProviders = config.customProviders }
                        }
                }
                LabeledContent(L("settings.providers.custom.base_url")) {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("", text: cp.baseURL)
                            .multilineTextAlignment(.leading)
                            .onChange(of: cp.wrappedValue.baseURL) { _, _ in
                                ConfigStore.shared.update { $0.customProviders = config.customProviders }
                            }
                        Text(AttributedString("http://localhost:11434/v1"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                LabeledContent(L("settings.providers.custom.api_version")) {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("", text: Binding(
                            get: { cp.wrappedValue.apiVersion ?? "" },
                            set: { cp.apiVersion.wrappedValue = $0.isEmpty ? nil : $0 }
                        ))
                        .multilineTextAlignment(.leading)
                        .onChange(of: cp.wrappedValue.apiVersion) { _, _ in
                            ConfigStore.shared.update { $0.customProviders = config.customProviders }
                        }
                        Text(L("settings.providers.custom.api_version_hint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                LabeledContent(L("settings.providers.custom.effective_url")) {
                    Text(effectiveChatURL(baseURL: cp.wrappedValue.baseURL, apiVersion: cp.wrappedValue.apiVersion))
                        .monospaced()
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Picker(L("settings.providers.token_param"), selection: cp.tokenParamStyle) {
                    ForEach(TokenParamStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .onChange(of: cp.wrappedValue.tokenParamStyle) { _, _ in
                    ConfigStore.shared.update { $0.customProviders = config.customProviders }
                }
                Toggle(L("settings.providers.custom.requires_key"), isOn: cp.requiresAPIKey)
                    .onChange(of: cp.wrappedValue.requiresAPIKey) { _, _ in
                        ConfigStore.shared.update { $0.customProviders = config.customProviders }
                    }
                LabeledContent(L("settings.providers.api_key_optional")) {
                    SecureField("", text: keyBinding)
                        .onSubmit { saveKey(keyBinding.wrappedValue, for: provider) }
                }
                saveButton(for: provider, key: keyBinding.wrappedValue)

                // Custom headers
                customHeadersRows(cp: cp, cpID: cpID)

                testConnectionRow(for: provider, key: keyBinding.wrappedValue)
                fetchModelsRow(for: provider)

                Button(role: .destructive) {
                    providerToDelete = cp.wrappedValue
                    showDeleteProviderAlert = true
                } label: {
                    Label(L("settings.providers.custom.delete"), systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                providerHeader(
                    cp.wrappedValue.name.isEmpty ? L("settings.providers.custom.unnamed") : cp.wrappedValue.name,
                    provider: provider,
                    hasKey: !(customProviderKeys[cpID.uuidString] ?? "").isEmpty,
                    showsKeyStatus: cp.wrappedValue.requiresAPIKey
                )
            }
        }
    }

    @ViewBuilder
    private func customHeadersRows(cp: Binding<CustomProvider>, cpID: UUID) -> some View {
        DisclosureGroup(L("settings.providers.custom.headers")) {
            ForEach(Array(cp.wrappedValue.customHeaders.keys.sorted()), id: \.self) { key in
                HStack {
                    Text(key)
                        .frame(width: 130, alignment: .leading)
                        .foregroundStyle(.secondary)
                    Text(cp.wrappedValue.customHeaders[key] ?? "")
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Button(role: .destructive) {
                        var headers = cp.wrappedValue.customHeaders
                        headers.removeValue(forKey: key)
                        cp.customHeaders.wrappedValue = headers
                        ConfigStore.shared.update { $0.customProviders = config.customProviders }
                    } label: {
                        Image(systemName: "minus.circle").foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                .font(.caption)
            }
            HStack(spacing: 6) {
                TextField(L("settings.providers.custom.header_key"), text: Binding(
                    get: { newHeaderKey[cpID] ?? "" },
                    set: { newHeaderKey[cpID] = $0 }
                ))
                .frame(width: 130)
                TextField(L("settings.providers.custom.header_value"), text: Binding(
                    get: { newHeaderValue[cpID] ?? "" },
                    set: { newHeaderValue[cpID] = $0 }
                ))
                Button(L("common.add")) {
                    guard let k = newHeaderKey[cpID], !k.isEmpty,
                          let v = newHeaderValue[cpID], !v.isEmpty else { return }
                    var headers = cp.wrappedValue.customHeaders
                    headers[k] = v
                    cp.customHeaders.wrappedValue = headers
                    ConfigStore.shared.update { $0.customProviders = config.customProviders }
                    newHeaderKey[cpID] = ""
                    newHeaderValue[cpID] = ""
                }
                .disabled((newHeaderKey[cpID] ?? "").isEmpty || (newHeaderValue[cpID] ?? "").isEmpty)
            }
            .font(.caption)
        }
    }

    private func performDeleteCustomProvider(_ cp: CustomProvider) {
        let providerType = ProviderType(cp.id.uuidString)
        KeychainStore.delete(for: providerType)
        // Reset any actions using this provider back to openai
        ConfigStore.shared.update {
            $0.customProviders.removeAll { $0.id == cp.id }
            for i in $0.actions.indices where $0.actions[i].provider == providerType {
                $0.actions[i].provider = .openai
                $0.actions[i].model = "gpt-5.5"
            }
            $0.modelPresets.removeValue(forKey: cp.id.uuidString)
        }
        config = ConfigStore.shared.config
        customProviderKeys.removeValue(forKey: cp.id.uuidString)
        providerToDelete = nil
    }

    // MARK: - Model Filters Section

    private var modelFiltersSection: some View {
        Section {
            modelFilterRow(
                title: L("settings.providers.model_exclude_filter"),
                hint: L("settings.providers.model_filter.hint_exclude"),
                filters: $config.modelExcludeFilters,
                newFilter: $newExcludeFilter,
                onAdd: addExcludeFilter,
                onRemove: { idx in
                    config.modelExcludeFilters.remove(at: idx)
                    ConfigStore.shared.update { $0.modelExcludeFilters = config.modelExcludeFilters }
                }
            )
            modelFilterRow(
                title: L("settings.providers.model_include_filter"),
                hint: L("settings.providers.model_filter.hint_include"),
                filters: $config.modelIncludeFilters,
                newFilter: $newIncludeFilter,
                onAdd: addIncludeFilter,
                onRemove: { idx in
                    config.modelIncludeFilters.remove(at: idx)
                    ConfigStore.shared.update { $0.modelIncludeFilters = config.modelIncludeFilters }
                }
            )
        } header: {
            Text(L("settings.providers.model_filters"))
        } footer: {
            Text(L("settings.providers.model_filters.scope"))
        }
    }

    @ViewBuilder
    private func modelFilterRow(title: String, hint: String,
                                filters: Binding<[String]>, newFilter: Binding<String>,
                                onAdd: @escaping () -> Void,
                                onRemove: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .fontWeight(.medium)
            filterTagsRow(filters: filters, onRemove: onRemove)
            HStack(spacing: 6) {
                TextField(L("settings.providers.model_filter.placeholder"), text: newFilter)
                    .onSubmit { onAdd() }
                Button(L("common.add")) { onAdd() }
                    .disabled(newFilter.wrappedValue.isEmpty)
            }
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func filterTagsRow(filters: Binding<[String]>, onRemove: @escaping (Int) -> Void) -> some View {
        if filters.wrappedValue.isEmpty {
            Text("—").foregroundStyle(.secondary).font(.caption)
        } else {
            FlowLayout(spacing: 4, lineSpacing: 4) {
                ForEach(Array(filters.wrappedValue.enumerated()), id: \.offset) { idx, filter in
                    HStack(spacing: 3) {
                        Text(filter).font(.caption)
                        Button { onRemove(idx) } label: {
                            Image(systemName: "xmark").font(.system(size: 9))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(UICornerRadius.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func addExcludeFilter() {
        let s = newExcludeFilter.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, !config.modelExcludeFilters.contains(s) else { return }
        config.modelExcludeFilters.append(s)
        ConfigStore.shared.update { $0.modelExcludeFilters = config.modelExcludeFilters }
        newExcludeFilter = ""
    }

    private func addIncludeFilter() {
        let s = newIncludeFilter.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, !config.modelIncludeFilters.contains(s) else { return }
        config.modelIncludeFilters.append(s)
        ConfigStore.shared.update { $0.modelIncludeFilters = config.modelIncludeFilters }
        newIncludeFilter = ""
    }

    // MARK: - Shared Provider Helpers

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
        .frame(maxWidth: .infinity, alignment: .leading)
        if let error = fetchError[provider] {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
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
    private func testConnectionRow(for provider: ProviderType, key: String = "") -> some View {
        HStack(spacing: 8) {
            Button {
                Task { await testConnection(for: provider, key: key) }
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
        .frame(maxWidth: .infinity, alignment: .leading)
        if let error = testError[provider] {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func testConnection(for provider: ProviderType, key: String = "") async {
        // Verifying without saving first would test the stale key from the
        // Keychain, which is confusing if the user just edited the field.
        if !key.isEmpty {
            saveKey(key, for: provider)
        }
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func saveKey(_ key: String, for provider: ProviderType) {
        do {
            try KeychainStore.save(apiKey: key, for: provider)
            keySaveStatus[provider] = true
        } catch {
            keySaveStatus[provider] = false
        }
        keySaveStatusResetTasks[provider]?.cancel()
        keySaveStatusResetTasks[provider] = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            keySaveStatus[provider] = nil
        }
    }

    private func loadKeys() {
        openaiKey    = (try? KeychainStore.load(for: .openai)) ?? ""
        anthropicKey = (try? KeychainStore.load(for: .anthropic)) ?? ""
        geminiKey    = (try? KeychainStore.load(for: .gemini)) ?? ""
        grokKey      = (try? KeychainStore.load(for: .grok)) ?? ""
        azureKey     = (try? KeychainStore.load(for: .azureOpenai)) ?? ""
        azureKey2    = (try? KeychainStore.load(for: .azureOpenai2)) ?? ""
        for cp in config.customProviders {
            let provider = ProviderType(cp.id.uuidString)
            customProviderKeys[cp.id.uuidString] = (try? KeychainStore.load(for: provider)) ?? ""
        }
    }

    private func effectiveChatURL(baseURL: String, apiVersion: String?) -> String {
        guard !baseURL.isEmpty else { return "—" }
        var base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        if !base.hasSuffix("/chat/completions") {
            base += "/chat/completions"
        }
        if let version = apiVersion, !version.isEmpty {
            var components = URLComponents(string: base)
            components?.queryItems = [URLQueryItem(name: "api-version", value: version)]
            return components?.url?.absoluteString ?? base
        }
        return base
    }

    // MARK: - Helpers

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

    private func exportActions() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config.actions) else { return }
        let panel = NSSavePanel()
        panel.title = L("settings.actions.export.panel_title")
        panel.nameFieldStringValue = "JZLLMContext-actions.json"
        panel.allowedContentTypes = [.json]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func importActions() {
        let panel = NSOpenPanel()
        panel.title = L("settings.actions.import.panel_title")
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
        // Custom header values often carry Authorization tokens or API keys —
        // strip them from the export, keeping the keys so the user knows
        // which headers to re-enter after import.
        var sanitized = ConfigStore.shared.config
        for i in sanitized.customProviders.indices {
            sanitized.customProviders[i].customHeaders =
                sanitized.customProviders[i].customHeaders.mapValues { _ in "" }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(sanitized) else { return }
        let panel = NSSavePanel()
        panel.title = L("settings.general.export_config.panel_title")
        panel.nameFieldStringValue = "JZLLMContext-config.json"
        panel.allowedContentTypes = [.json]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.title = L("settings.general.import_config.panel_title")
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
}

// MARK: - Model Review Sheet

private struct ModelReviewSheet: View {
    let provider: ProviderType
    @Binding var models: [FetchedModel]
    let onSave: ([FetchedModel]) -> Void
    let onCancel: () -> Void

    private var visibleModels: [FetchedModel] {
        let cfg = ConfigStore.shared.config
        var result = models
        if !cfg.modelIncludeFilters.isEmpty {
            result = result.filter { m in
                cfg.modelIncludeFilters.contains { m.id.lowercased().contains($0.lowercased()) }
            }
        }
        if !cfg.modelExcludeFilters.isEmpty {
            result = result.filter { m in
                !cfg.modelExcludeFilters.contains { m.id.lowercased().contains($0.lowercased()) }
            }
        }
        return result
    }

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
                let isVisible = visibleModels.contains(where: { $0.id == model.id })
                if isVisible {
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

// MARK: - Action Detail Editor

private struct ActionDetailEditor: View {
    @Binding var action: Action
    var onSetDefault: () -> Void
    var onDelete: () -> Void
    @State private var pickerModel: String
    @State private var customModelText: String
    @State private var confirmDelete = false

    private static let customSentinel = "__custom__"
    private var customSentinel: String { Self.customSentinel }

    private var isCustomModel: Bool { pickerModel == customSentinel }

    // The picker state must be seeded in init: the editor is recreated per
    // selected action via .id(_:), and onAppear does not fire reliably on
    // those identity swaps, which left the model picker blank.
    init(action: Binding<Action>, onSetDefault: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self._action = action
        self.onSetDefault = onSetDefault
        self.onDelete = onDelete
        let current = action.wrappedValue
        let presetIDs = current.provider.effectiveModels().map(\.id)
        if !presetIDs.isEmpty && presetIDs.contains(current.model) {
            self._pickerModel = State(initialValue: current.model)
            self._customModelText = State(initialValue: "")
        } else {
            self._pickerModel = State(initialValue: Self.customSentinel)
            self._customModelText = State(initialValue: current.model)
        }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent(L("action.detail.label.name")) {
                    TextField(L("action.row.name_placeholder"), text: $action.name)
                }
                Toggle(L("settings.actions.enabled"), isOn: $action.enabled)
                Toggle(L("settings.actions.default_toggle"), isOn: Binding(
                    get: { action.isDefault },
                    set: { isOn in
                        if isOn {
                            onSetDefault()
                        } else {
                            action.isDefault = false
                        }
                    }
                ))
                .help(action.isDefault ? L("action.row.help.is_default") : L("action.row.help.set_default"))
            }
            Section {
                Picker(L("action.detail.label.provider"), selection: $action.provider) {
                    ForEach(ProviderType.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
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
                modelRow
            }
            Section(L("action.detail.label.system_prompt")) {
                TextEditor(text: $action.systemPrompt)
                    .font(.callout)
                    .frame(minHeight: 200, maxHeight: 400)
            }
            Section(L("settings.actions.section.parameters")) {
                LabeledContent(String(format: L("action.row.temperature"), action.temperature)) {
                    Slider(value: $action.temperature, in: 0.0...2.0, step: 0.1)
                        .frame(maxWidth: 220)
                }
                LabeledContent(L("action.row.max_tokens")) {
                    HStack {
                        TextField("", value: $action.maxTokens, format: .number)
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $action.maxTokens, in: 256...32000, step: 256)
                            .labelsHidden()
                    }
                }
                Picker(L("action.row.copy_close"), selection: $action.autoCopyClose) {
                    ForEach(AutoCopyClose.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Toggle(L("action.row.ignore_clipboard"), isOn: $action.ignoreClipboard)
                    .help(L("action.row.help.ignore_clipboard"))
            }
            Section {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label(L("action.row.delete.button"), systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .confirmationDialog(
                    String(format: L("action.row.delete.confirm"), action.name),
                    isPresented: $confirmDelete,
                    titleVisibility: .visible
                ) {
                    Button(L("action.row.delete.button"), role: .destructive) { onDelete() }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { syncPickerFromAction() }
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

    @ViewBuilder
    private var modelRow: some View {
        if action.provider.effectiveModels().isEmpty {
            LabeledContent(L("action.detail.label.model")) {
                TextField(L("action.row.model_placeholder"), text: $customModelText)
                    .onChange(of: customModelText) {
                        if !customModelText.isEmpty { action.model = customModelText }
                    }
            }
        } else {
            Picker(L("action.detail.label.model"), selection: $pickerModel) {
                ForEach(action.provider.effectiveModels()) { preset in
                    Text(preset.isRecommended ? "\(preset.displayName) \(L("action.row.recommended"))" : preset.displayName)
                        .tag(preset.id)
                }
                Divider()
                Text(L("action.row.custom_model")).tag(customSentinel)
            }
            .onChange(of: pickerModel) {
                if pickerModel != customSentinel {
                    action.model = pickerModel
                    customModelText = ""
                }
            }

            if isCustomModel {
                LabeledContent("") {
                    TextField(L("action.row.model_placeholder"), text: $customModelText)
                        .onChange(of: customModelText) {
                            if !customModelText.isEmpty { action.model = customModelText }
                        }
                }
            }
        }
    }
}
