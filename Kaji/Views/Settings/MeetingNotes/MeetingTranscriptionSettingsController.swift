import Combine
import Foundation

@MainActor
final class MeetingTranscriptionSettingsController: ObservableObject {
    enum EndpointEditorState: Equatable {
        case hidden
        case creating
        case editing(UUID)
    }

    enum CredentialEditorState: Equatable {
        case hidden
        case creating
        case editing(UUID)
    }

    enum ModelControlState: Equatable {
        case local([MeetingDiscoveredTranscriptionModel])
        case credentialRequired
        case loading
        case loaded([MeetingDiscoveredTranscriptionModel], isStale: Bool, isRefreshing: Bool)
        case failed(String)
        case manual
    }

    enum ModelDisplayState: Equatable {
        case local
        case credentialRequired
        case loading
        case loaded
        case failed
        case manual
    }

    let settingsStore: MeetingNotesSettingsStore
    let catalog: MeetingTranscriptionProviderCatalog

    @Published private(set) var credentialProfiles: [STTCredentialProfileMetadata] = []
    @Published var endpointEditorState = EndpointEditorState.hidden
    @Published var credentialEditorState = CredentialEditorState.hidden
    @Published var showsAdvanced = false
    @Published private var revision = 0
    private var modelRefreshTask: Task<Void, Never>?
    @Published var usesManualModelEntry = false
    @Published var endpointName = ""
    @Published var restBaseURL = ""
    @Published var webSocketBaseURL = ""
    @Published var credentialName = ""
    @Published var credentialSecret = ""
    @Published var manualModelID = ""
    @Published var endpointError: String?
    @Published var credentialError: String?

    init(
        settingsStore: MeetingNotesSettingsStore = .shared,
        catalog: MeetingTranscriptionProviderCatalog = .shared
    ) {
        self.settingsStore = settingsStore
        self.catalog = catalog
    }

    func start() {
        repairEndpointSelection()
        refreshCredentialProfiles()
        loadModelsIfNeeded()
    }

    var selectedPresentation: MeetingTranscriptionModulePresentation? {
        catalog.presentation(providerID: settings.sttProviderID)
    }

    var selectedEndpoint: MeetingTranscriptionEndpointProfile? {
        catalog.endpointStore.profile(id: settings.sttEndpointProfileID)
    }

    var selectedModelMetadata: MeetingDiscoveredTranscriptionModel? {
        settings.sttModelMetadata ?? availableModels.first { $0.id == settings.sttModelID }
    }

    var selectedModel: MeetingTranscriptionModelDescriptor? {
        if settings.sttProviderID == FluidAudioMeetingTranscriptionProvider.providerID {
            return selectedPresentation?.descriptor.model(id: settings.sttModelID)
        }
        guard let endpoint = settings.sttEndpointSnapshot,
              let model = selectedModelMetadata
        else { return nil }
        return try? MeetingTranscriptionDynamicDescriptorFactory.modelDescriptor(
            providerID: settings.sttProviderID,
            model: model,
            endpoint: endpoint,
            mode: settings.sttMode,
            diarizationEnabled: settings.sttDiarizationEnabled
        )
    }

    var providerOptions: [KajiSelectOption<String>] {
        catalog.presentations.map {
            KajiSelectOption(id: $0.id, title: $0.descriptor.displayName, value: $0.id)
        }
    }

    var endpointOptions: [KajiSelectOption<String>] {
        catalog.endpointProfiles(providerID: settings.sttProviderID).map {
            KajiSelectOption(id: $0.id.uuidString, title: $0.displayName, value: $0.id.uuidString)
        }
    }

    var modelDisplayState: ModelDisplayState {
        switch modelControlState {
        case .local: .local
        case .credentialRequired: .credentialRequired
        case .loading: .loading
        case .loaded: .loaded
        case .failed: .failed
        case .manual: .manual
        }
    }

    var displayedModels: [MeetingDiscoveredTranscriptionModel] {
        guard case let .loaded(models, _, _) = modelControlState else { return [] }
        return models
    }

    var modelListIsStale: Bool {
        guard case let .loaded(_, isStale, _) = modelControlState else { return false }
        return isStale
    }

    var modelListIsRefreshing: Bool {
        guard case let .loaded(_, _, isRefreshing) = modelControlState else { return false }
        return isRefreshing
    }

    var modelFailureMessage: String {
        guard case let .failed(message) = modelControlState else { return "Models could not be loaded." }
        return message
    }

    var credentialOptions: [KajiSelectOption<String>] {
        [KajiSelectOption(id: "none", title: "Choose API key", value: "")] + credentialProfiles.map {
            KajiSelectOption(id: $0.id.uuidString, title: $0.displayName, value: $0.id.uuidString)
        }
    }

    var modeOptions: [KajiSelectOption<String>] {
        supportedModes.map {
            KajiSelectOption(id: $0.rawValue, title: Self.modeTitle($0), value: $0.rawValue)
        }
    }

    var languageOptions: [KajiSelectOption<String>] {
        let codes = selectedModelMetadata?.languageCodes.sorted() ?? []
        return [KajiSelectOption(id: "automatic", title: "Automatic", value: "")] + codes.map {
            KajiSelectOption(id: $0, title: $0, value: $0)
        }
    }

    var retentionOptions: [KajiSelectOption<String>] {
        guard selectedEndpoint?.source != .custom else { return [] }
        return retentionPresentations.filter { $0.retention != .configurable }.map {
            KajiSelectOption(id: $0.retention.rawValue, title: $0.label, value: $0.retention.rawValue)
        }
    }

    var modelControlState: ModelControlState {
        if settings.sttProviderID == FluidAudioMeetingTranscriptionProvider.providerID {
            return .local(localModels)
        }
        guard selectedEndpoint?.discovery.kind != .manual else { return .manual }
        guard settings.sttCredentialProfileID != nil else { return .credentialRequired }
        guard let endpointID = settings.sttEndpointProfileID else {
            return .failed("Choose an endpoint first.")
        }
        let snapshot = catalog.modelCatalogStore.catalog(
            endpointProfileID: endpointID,
            credentialProfileID: settings.sttCredentialProfileID
        )
        let models = snapshot?.endpointFingerprint == settings.sttEndpointSnapshot?.originFingerprint
            ? snapshot?.models.filter { $0.modes.contains(settings.sttMode) } ?? []
            : []
        switch catalog.modelCatalogStore.state(
            endpointProfileID: endpointID,
            credentialProfileID: settings.sttCredentialProfileID
        ) {
        case .loading:
            return models.isEmpty ? .loading : .loaded(models, isStale: false, isRefreshing: true)
        case .loaded:
            return .loaded(models, isStale: false, isRefreshing: false)
        case .stale:
            return .loaded(models, isStale: true, isRefreshing: false)
        case let .failed(message):
            return models.isEmpty ? .failed(message) : .loaded(models, isStale: true, isRefreshing: false)
        case .idle:
            return models.isEmpty ? .loading : .loaded(models, isStale: false, isRefreshing: false)
        }
    }

    var modelOptions: [KajiSelectOption<String>] {
        availableModels.filter { $0.modes.contains(settings.sttMode) }.map {
            KajiSelectOption(id: $0.id, title: $0.displayName, value: $0.id)
        }
    }

    var showsEndpoint: Bool {
        settings.sttProviderID != FluidAudioMeetingTranscriptionProvider.providerID
    }

    var showsCredential: Bool {
        selectedPresentation?.viewMetadata.credentialLabel != nil
    }

    var showsMode: Bool {
        supportedModes.count > 1
    }

    var showsLanguage: Bool {
        selectedModelMetadata != nil && !languageOptions.isEmpty
    }

    var showsDiarization: Bool {
        selectedModel?.capabilities.diarization.availability != .unsupported
    }

    var showsMaximumSpeakers: Bool {
        showsDiarization && settings.sttDiarizationEnabled
    }

    var showsRetentionPicker: Bool {
        retentionOptions.count > 1
    }

    var retentionText: String? {
        if selectedEndpoint?.source == .custom { return "Controlled by endpoint operator" }
        guard retentionOptions.count == 1 else { return nil }
        return retentionOptions.first?.title
    }

    var showsLocalModelDownload: Bool {
        selectedPresentation?.viewMetadata.showsLocalModelDownloadAffordance == true
    }

    var destinationSummary: String {
        guard settings.sttMode != .localChunked else { return "Audio is transcribed on this Mac." }
        let host = settings.sttEndpointSnapshot.flatMap { endpoint in
            [endpoint.restBaseURL, endpoint.webSocketBaseURL]
                .compactMap { $0.flatMap { URL(string: $0)?.host } }
                .first
        } ?? settings.sttProviderID
        if selectedEndpoint?.source == .custom {
            return "Audio is sent to \(host). The endpoint operator controls processing and retention."
        }
        return "Audio is sent to \(host) using the selected provider account."
    }

    var selectedRetentionPresentation: MeetingTranscriptionRetentionPresentation? {
        retentionPresentations.first { $0.retention == settings.sttRetention }
    }

    var requiresSelectedAttestation: Bool {
        guard settings.sttRetention == .none else { return false }
        if settings.sttProviderID == OpenAIMeetingTranscriptionProvider.providerID {
            return settings.sttMode == .cloudRealtime
        }
        return selectedRetentionPresentation?.requiredAttestation != nil
    }

    func selectProvider(_ providerID: String) {
        guard providerID != settings.sttProviderID,
              let endpoint = catalog.endpointProfiles(providerID: providerID).first
        else { return }
        updateSettings { $0.sttProviderID = providerID
            $0.sttCredentialProfileID = nil
            $0.sttModelID = ""
            $0.sttModelMetadata = nil
            $0.sttAccountAttestations.removeAll { $0.providerID != providerID }
            $0.localFallbackEnabled = false
        }
        applyEndpoint(endpoint, clearsBoundSelection: true)
        closeEditors()
    }

    func selectEndpoint(_ id: UUID) {
        guard let endpoint = catalog.endpointStore.profile(id: id), endpoint.id != selectedEndpoint?.id else { return }
        applyEndpoint(endpoint, clearsBoundSelection: true)
        closeEditors()
    }

    func selectCredential(_ id: UUID?) {
        guard id != settings.sttCredentialProfileID else { return }
        updateSettings { $0.sttCredentialProfileID = id
            $0.sttModelID = ""
            $0.sttModelMetadata = nil
        }
        credentialName = credentialProfiles.first { $0.id == id }?.displayName ?? ""
        credentialSecret = ""
        credentialEditorState = .hidden
        loadModelsIfNeeded(force: false)
    }

    func selectMode(_ mode: MeetingTranscriptionMode) {
        guard supportedModes.contains(mode), mode != settings.sttMode else { return }
        let keepsModel = selectedModelMetadata?.modes.contains(mode) == true
        updateSettings { $0.sttMode = mode
            $0.sttDiarizationEnabled = false
            $0.sttMaximumSpeakers = nil
            if !keepsModel {
                $0.sttModelID = ""
                $0.sttModelMetadata = nil
            }
        }
    }

    func selectModel(_ id: String) {
        guard let model = availableModels.first(where: { $0.id == id }) else { return }
        updateSettings { $0.sttModelID = model.id
            $0.sttModelMetadata = model
        }
    }

    func selectLanguage(_ code: String) {
        updateSettings { $0.sttLanguageCodes = code.isEmpty ? [] : [code] }
    }

    func selectRetention(_ retention: MeetingTranscriptionDataRetentionClass) {
        guard retentionOptions.contains(where: { $0.value == retention.rawValue }) else { return }
        updateSettings { $0.sttRetention = retention }
    }

    func setDiarization(_ enabled: Bool) {
        updateSettings { $0.sttDiarizationEnabled = enabled
            if !enabled { $0.sttMaximumSpeakers = nil }
        }
    }

    func setMaximumSpeakers(_ value: Int) {
        updateSettings { $0.sttMaximumSpeakers = min(32, max(1, value)) }
    }

    func setAutomaticLanguageDetection(_ enabled: Bool) {
        updateSettings { $0.sttProviderOptions.automaticLanguageDetection = enabled }
    }

    func setLocalFallback(_ enabled: Bool) {
        updateSettings { $0.localFallbackEnabled = enabled }
    }

    func setKeyterms(_ text: String) {
        updateSettings { $0.sttKeyterms = text.split(whereSeparator: \.isNewline).map(String.init) }
    }

    func setAttestation(_ kind: MeetingTranscriptionAccountAttestationKind, enabled: Bool) {
        updateSettings { $0.sttAccountAttestations.removeAll { $0.kind == kind }
            if enabled,
               let attestation = try? MeetingTranscriptionAccountAttestation(
                   kind: kind,
                   acceptedAtMilliseconds: max(0, Int64(Date().timeIntervalSince1970 * 1000))
               )
            {
                $0.sttAccountAttestations.append(attestation)
            }
            if kind == .assemblyAITrainingOptOut {
                $0.sttProviderOptions.trainingOptOutEnabled = enabled
            }
        }
    }

    func beginCreateEndpoint() {
        endpointEditorState = .creating
        endpointName = ""
        restBaseURL = ""
        webSocketBaseURL = ""
        endpointError = nil
    }

    func beginEditEndpoint() {
        guard let endpoint = selectedEndpoint, endpoint.source == .custom else { return }
        endpointEditorState = .editing(endpoint.id)
        endpointName = endpoint.displayName
        restBaseURL = endpoint.restBaseURL ?? ""
        webSocketBaseURL = endpoint.webSocketBaseURL ?? ""
        endpointError = nil
    }

    func cancelEndpointEditor() {
        endpointEditorState = .hidden
        endpointError = nil
    }

    func saveEndpoint() {
        guard let variant = selectedEndpoint?.variant,
              let discovery = discoveryConfiguration(providerID: settings.sttProviderID)
        else { return }
        let existing = endpointEditorState.editingID.flatMap(catalog.endpointStore.profile)
        let id = existing?.id ?? UUID()
        do {
            let profile = try MeetingTranscriptionEndpointProfile(
                id: id,
                providerID: settings.sttProviderID,
                displayName: endpointName,
                variant: variant,
                regionID: existing?.regionID ?? "custom-\(id.uuidString.lowercased().prefix(8))",
                restBaseURL: variant == .assemblyAIStreamingV3 ? nil : restBaseURL,
                webSocketBaseURL: webSocketBaseURL,
                discovery: discovery,
                source: .custom
            )
            let originChanged = existing.map { $0.snapshot.originFingerprint != profile.snapshot.originFingerprint } ?? true
            try catalog.endpointStore.saveCustom(profile)
            if originChanged { catalog.modelCatalogStore.remove(endpointProfileID: profile.id) }
            applyEndpoint(profile, clearsBoundSelection: originChanged)
            endpointEditorState = .hidden
            endpointError = nil
        } catch {
            endpointError = "Use a public HTTPS and WSS endpoint without credentials, query parameters, or fragments."
        }
    }

    func deleteEndpoint() {
        guard let endpoint = selectedEndpoint, endpoint.source == .custom else { return }
        do {
            try catalog.endpointStore.deleteCustom(id: endpoint.id)
            catalog.modelCatalogStore.remove(endpointProfileID: endpoint.id)
            guard let replacement = catalog.endpointProfiles(providerID: endpoint.providerID).first else { return }
            applyEndpoint(replacement, clearsBoundSelection: true)
            endpointEditorState = .hidden
            endpointError = nil
        } catch {
            endpointError = "The endpoint could not be deleted."
        }
    }

    func beginCreateCredential() {
        credentialEditorState = .creating
        credentialName = ""
        credentialSecret = ""
        credentialError = nil
    }

    func beginEditCredential() {
        guard let id = settings.sttCredentialProfileID else { return }
        credentialEditorState = .editing(id)
        credentialName = credentialProfiles.first { $0.id == id }?.displayName ?? ""
        credentialSecret = ""
        credentialError = nil
    }

    func cancelCredentialEditor() {
        credentialEditorState = .hidden
        credentialSecret = ""
        credentialError = nil
    }

    func saveCredential() {
        guard let endpoint = settings.sttEndpointSnapshot else {
            credentialError = "Choose an endpoint first."
            return
        }
        do {
            let profileID = try catalog.saveCredential(
                id: credentialEditorState.editingID,
                providerID: settings.sttProviderID,
                endpoint: endpoint,
                displayName: credentialName,
                secret: Data(credentialSecret.utf8)
            )
            updateSettings { $0.sttCredentialProfileID = profileID
                $0.sttModelID = ""
                $0.sttModelMetadata = nil
            }
            credentialSecret = ""
            credentialEditorState = .hidden
            credentialError = nil
            refreshCredentialProfiles()
            loadModelsIfNeeded(force: true)
        } catch {
            credentialError = "The API key could not be saved."
        }
    }

    func deleteCredential() {
        guard let profileID = settings.sttCredentialProfileID else { return }
        do {
            try catalog.deleteCredential(profileID: profileID)
            updateSettings { $0.sttCredentialProfileID = nil
                $0.sttModelID = ""
                $0.sttModelMetadata = nil
            }
            credentialEditorState = .hidden
            credentialName = ""
            credentialSecret = ""
            credentialError = nil
            refreshCredentialProfiles()
        } catch {
            credentialError = "The API key could not be deleted."
        }
    }

    func useManualModel() {
        let id = manualModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let model = try? MeetingTranscriptionDynamicDescriptorFactory.manualModel(
            id: id,
            mode: settings.sttMode
        )
        else { return }
        updateSettings { $0.sttModelID = model.id
            $0.sttModelMetadata = model
        }
        manualModelID = ""
        usesManualModelEntry = false
    }

    func refreshModels() {
        loadModelsIfNeeded(force: true)
    }

    func openManualModelEntry() {
        usesManualModelEntry = true
    }

    func closeManualModelEntry() {
        usesManualModelEntry = false
        manualModelID = ""
    }

    private var settings: MeetingNotesIntegrationSettings {
        settingsStore.settings
    }

    private var availableModels: [MeetingDiscoveredTranscriptionModel] {
        switch modelControlState {
        case let .local(models),
             let .loaded(models, _, _):
            var models = models
            if let selected = settings.sttModelMetadata, !models.contains(where: { $0.id == selected.id }) {
                models.append(selected)
            }
            return models
        case .credentialRequired,
             .failed,
             .loading,
             .manual:
            return settings.sttModelMetadata.map { [$0] } ?? []
        }
    }

    private var localModels: [MeetingDiscoveredTranscriptionModel] {
        SpeechModelRegistryStore.shared.models.compactMap { model in
            try? MeetingDiscoveredTranscriptionModel(
                id: model.id,
                displayName: model.title,
                modes: [.localChunked],
                capabilityConfidence: .providerReported,
                metadata: ["processing": "local"]
            )
        }
    }

    private var supportedModes: [MeetingTranscriptionMode] {
        let modes: Set<MeetingTranscriptionMode> = switch selectedEndpoint?.variant {
        case .fluidAudioLocal: [.localChunked]
        case .assemblyAIStreamingV3,
             .deepgram: [.cloudRealtime]
        case .elevenLabsScribe,
             .openAICompatible: [.cloudBatch, .cloudRealtime]
        case .azureOpenAI: [.cloudBatch]
        case nil: []
        }
        return modes.sorted { $0.rawValue < $1.rawValue }
    }

    private var retentionPresentations: [MeetingTranscriptionRetentionPresentation] {
        selectedPresentation?.viewMetadata.retentionPresentations ?? []
    }

    private func applyEndpoint(
        _ profile: MeetingTranscriptionEndpointProfile,
        clearsBoundSelection: Bool
    ) {
        updateSettings { $0.sttEndpointProfileID = profile.id
            $0.sttEndpointSnapshot = profile.snapshot
            $0.sttRegionID = profile.regionID
            $0.sttMode = Self.defaultMode(profile.variant)
            $0.sttRetention = profile.source == .custom ? .configurable : Self.defaultRetention(profile.variant)
            $0.sttLanguageCodes = []
            $0.sttDiarizationEnabled = false
            $0.sttMaximumSpeakers = nil
            if clearsBoundSelection {
                $0.sttCredentialProfileID = nil
                $0.sttModelID = ""
                $0.sttModelMetadata = nil
            }
        }
        refreshCredentialProfiles()
        loadModelsIfNeeded()
    }

    private func repairEndpointSelection() {
        guard settings.sttEndpointSnapshot == nil,
              let endpoint = catalog.endpointStore.defaultProfile(
                  providerID: settings.sttProviderID,
                  regionID: settings.sttRegionID
              )
        else { return }
        applyEndpoint(endpoint, clearsBoundSelection: false)
    }

    private func refreshCredentialProfiles() {
        credentialProfiles = (try? catalog.credentialProfiles(
            providerID: settings.sttProviderID,
            endpoint: settings.sttEndpointSnapshot
        )) ?? []
    }

    private func loadModelsIfNeeded(force: Bool = false) {
        guard let endpoint = settings.sttEndpointSnapshot,
              endpoint.discovery.kind != .manual,
              endpoint.discovery.kind != .localRegistry,
              let credentialID = settings.sttCredentialProfileID
        else { return }
        let cached = catalog.modelCatalogStore.catalog(
            endpointProfileID: endpoint.profileID,
            credentialProfileID: credentialID
        )
        guard force || cached == nil || cached?.endpointFingerprint != endpoint.originFingerprint else { return }
        catalog.refreshModels(endpoint: endpoint, credentialProfileID: credentialID)
        modelRefreshTask?.cancel()
        modelRefreshTask = Task { [weak self] in
            guard let self else { return }
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(30))
            while !Task.isCancelled, clock.now < deadline {
                publishRevision()
                let state = catalog.modelCatalogStore.state(
                    endpointProfileID: endpoint.profileID,
                    credentialProfileID: credentialID
                )
                if state != .loading { return }
                try? await clock.sleep(for: .milliseconds(100))
            }
        }
    }

    private func closeEditors() {
        endpointEditorState = .hidden
        credentialEditorState = .hidden
        usesManualModelEntry = false
        endpointError = nil
        credentialError = nil
    }

    private func discoveryConfiguration(
        providerID: String
    ) -> MeetingTranscriptionModelDiscoveryConfiguration? {
        switch providerID {
        case OpenAIMeetingTranscriptionProvider.providerID:
            try? MeetingTranscriptionModelDiscoveryConfiguration(kind: .openAIModels, path: "/models")
        case DeepgramMeetingTranscriptionProvider.providerID:
            try? MeetingTranscriptionModelDiscoveryConfiguration(kind: .deepgramModels, path: "/v1/models")
        case ElevenLabsScribeMeetingTranscriptionProvider.providerID:
            try? MeetingTranscriptionModelDiscoveryConfiguration(kind: .elevenLabsModels, path: "/v1/models")
        default:
            try? MeetingTranscriptionModelDiscoveryConfiguration(kind: .manual)
        }
    }

    private static func defaultMode(_ variant: MeetingTranscriptionProtocolVariant) -> MeetingTranscriptionMode {
        switch variant {
        case .fluidAudioLocal: .localChunked
        case .assemblyAIStreamingV3,
             .deepgram: .cloudRealtime
        case .azureOpenAI,
             .elevenLabsScribe,
             .openAICompatible: .cloudBatch
        }
    }

    private func updateSettings(_ transform: (inout MeetingNotesIntegrationSettings) -> Void) {
        settingsStore.update(transform)
        revision &+= 1
    }

    private func publishRevision() {
        revision &+= 1
    }

    private static func defaultRetention(
        _ variant: MeetingTranscriptionProtocolVariant
    ) -> MeetingTranscriptionDataRetentionClass {
        variant == .fluidAudioLocal ? .none : .providerDefault
    }

    private static func modeTitle(_ mode: MeetingTranscriptionMode) -> String {
        switch mode {
        case .localChunked: "Local"
        case .cloudBatch: "Batch"
        case .cloudRealtime: "Realtime"
        }
    }
}

private extension MeetingTranscriptionSettingsController.EndpointEditorState {
    var editingID: UUID? {
        guard case let .editing(id) = self else { return nil }
        return id
    }
}

private extension MeetingTranscriptionSettingsController.CredentialEditorState {
    var editingID: UUID? {
        guard case let .editing(id) = self else { return nil }
        return id
    }
}
