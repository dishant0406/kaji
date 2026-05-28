import Foundation

struct CodingAgentDefinition: Hashable, Identifiable {
    let id: String
    let displayName: String
    let annotationValues: [String]
    let iconName: String
    let executableNames: [String]
    let executableSearchDirectories: [String]
    let defaultCommand: String
    let installCommand: AIProviderInstaller.InstallCommand?
    let configDirectories: [String]
    let dataDirectories: [String]
    let hookStrategy: CodingAgentHookStrategy
    let historyStrategy: CodingAgentHistoryStrategy
    let modelStrategy: CodingAgentModelStrategy
    let usageStrategy: CodingAgentUsageStrategy
    let commandProfile: CodingAgentCommandProfile
    let models: [String]
    let defaultModel: String?
    let modelListCommand: CodingAgentListCommand?
    let stopEscapeCount: Int
    let globalInstructionFiles: [String]
    let projectInstructionFiles: [String]
    let homeSkillDirectories: [String]
    let projectSkillDirectories: [String]
    let processMatchNames: [String]
    let processCommandMarkers: [String]
    let processKillPatterns: [String]
    let notificationPolicy: CodingAgentNotificationPolicy

    init(
        id: String,
        displayName: String,
        annotationValues: [String],
        iconName: String,
        executableNames: [String],
        executableSearchDirectories: [String],
        defaultCommand: String,
        installCommand: AIProviderInstaller.InstallCommand?,
        configDirectories: [String],
        dataDirectories: [String],
        hookStrategy: CodingAgentHookStrategy,
        historyStrategy: CodingAgentHistoryStrategy,
        modelStrategy: CodingAgentModelStrategy,
        usageStrategy: CodingAgentUsageStrategy,
        commandProfile: CodingAgentCommandProfile,
        models: [String],
        defaultModel: String?,
        modelListCommand: CodingAgentListCommand?,
        stopEscapeCount: Int,
        globalInstructionFiles: [String],
        projectInstructionFiles: [String],
        homeSkillDirectories: [String],
        projectSkillDirectories: [String],
        processMatchNames: [String] = [],
        processCommandMarkers: [String] = [],
        processKillPatterns: [String] = [],
        notificationPolicy: CodingAgentNotificationPolicy = .default
    ) {
        self.id = id
        self.displayName = displayName
        self.annotationValues = annotationValues
        self.iconName = iconName
        self.executableNames = executableNames
        self.executableSearchDirectories = executableSearchDirectories
        self.defaultCommand = defaultCommand
        self.installCommand = installCommand
        self.configDirectories = configDirectories
        self.dataDirectories = dataDirectories
        self.hookStrategy = hookStrategy
        self.historyStrategy = historyStrategy
        self.modelStrategy = modelStrategy
        self.usageStrategy = usageStrategy
        self.commandProfile = commandProfile
        self.models = models
        self.defaultModel = defaultModel
        self.modelListCommand = modelListCommand
        self.stopEscapeCount = stopEscapeCount
        self.globalInstructionFiles = globalInstructionFiles
        self.projectInstructionFiles = projectInstructionFiles
        self.homeSkillDirectories = homeSkillDirectories
        self.projectSkillDirectories = projectSkillDirectories
        self.processMatchNames = processMatchNames
        self.processCommandMarkers = processCommandMarkers
        self.processKillPatterns = processKillPatterns
        self.notificationPolicy = notificationPolicy
    }

    func matches(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return searchableValues.contains(normalized)
    }

    func hasPrefixMatch(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return true }
        return searchableValues.contains { $0.hasPrefix(normalized) }
    }

    private var searchableValues: [String] {
        ([id, displayName] + annotationValues + executableNames + processMatchNames).map { $0.lowercased() }
    }
}

struct CodingAgentNotificationPolicy: Hashable {
    static let `default` = Self()

    let suppressRoutineProviderEvents: Bool
    let suppressCompletionUserDelivery: Bool
    let coalesceGenericCompletions: Bool

    init(
        suppressRoutineProviderEvents: Bool = false,
        suppressCompletionUserDelivery: Bool = false,
        coalesceGenericCompletions: Bool = false
    ) {
        self.suppressRoutineProviderEvents = suppressRoutineProviderEvents
        self.suppressCompletionUserDelivery = suppressCompletionUserDelivery
        self.coalesceGenericCompletions = coalesceGenericCompletions
    }
}

struct CodingAgentCommandProfile: Hashable {
    let prompt: CodingAgentPromptPlacement
    let modelFlag: String?
    let resume: CodingAgentResumeStrategy
    let skillInvocation: CodingAgentSkillInvocation
}

struct CodingAgentListCommand: Hashable {
    let executableName: String
    let arguments: [String]
}

enum CodingAgentHookStrategy: Hashable {
    case none
    case nativeConfig(String)
    case bundledPlugin(scriptName: String)
    case sessionMonitor(String)
}

enum CodingAgentHistoryStrategy: Hashable {
    case none
    case jsonlFiles(String)
    case jsonFiles(String)
    case sqlite(String)
    case custom(String)
}

enum CodingAgentModelStrategy: Hashable {
    case staticList
    case command(CodingAgentListCommand)
    case none
}

enum CodingAgentUsageStrategy: Hashable {
    case none
    case providerAPI(String)
    case localAuthFile(String)
}

enum CodingAgentPromptPlacement: Hashable {
    case positional
    case flag(String)
}

enum CodingAgentResumeStrategy: Hashable {
    case unsupported
    case subcommand(String)
    case subcommandWithPromptFlag(command: String, promptFlag: String)
    case flag(String)
    case flagWithPrompt(sessionFlag: String, promptFlag: String)
}

enum CodingAgentSkillInvocation: Hashable {
    case instructionTemplate(String)
    case slashCommand(prefix: String)

    func prompt(skill: AskSkillOption, userPrompt: String) -> String {
        switch self {
        case let .instructionTemplate(template):
            let instruction = template
                .replacingOccurrences(of: "{name}", with: skill.name)
                .replacingOccurrences(of: "{path}", with: skill.path)
            return userPrompt.isEmpty ? instruction : "\(instruction) \(userPrompt)"
        case let .slashCommand(prefix):
            let command = "\(prefix)\(skill.name)"
            return userPrompt.isEmpty ? command : "\(command) \(userPrompt)"
        }
    }
}
