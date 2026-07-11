import Foundation

enum ExternalIDESource: String, Codable {
    case builtIn
    case custom
}

enum ExternalIDEOpenBehavior: String, Codable {
    case application
    case finder
}

struct ExternalIDE: Identifiable, Codable, Equatable {
    let id: String
    let displayName: String
    let bundleIdentifiers: [String]
    let executableNames: [String]
    let appPaths: [String]
    let launchArguments: [String]
    let source: ExternalIDESource
    let openBehavior: ExternalIDEOpenBehavior

    init(
        id: String,
        displayName: String,
        bundleIdentifiers: [String],
        executableNames: [String] = [],
        appPaths: [String] = [],
        launchArguments: [String] = [],
        source: ExternalIDESource = .builtIn,
        openBehavior: ExternalIDEOpenBehavior = .application
    ) {
        self.id = id
        self.displayName = displayName
        self.bundleIdentifiers = bundleIdentifiers
        self.executableNames = executableNames
        self.appPaths = appPaths
        self.launchArguments = launchArguments
        self.source = source
        self.openBehavior = openBehavior
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        bundleIdentifiers = try container.decode([String].self, forKey: .bundleIdentifiers)
        executableNames = try container.decode([String].self, forKey: .executableNames)
        appPaths = try container.decode([String].self, forKey: .appPaths)
        launchArguments = try container.decode([String].self, forKey: .launchArguments)
        source = try container.decode(ExternalIDESource.self, forKey: .source)
        openBehavior = try container.decodeIfPresent(ExternalIDEOpenBehavior.self, forKey: .openBehavior) ?? .application
    }
}

struct ExternalIDECustomApplication: Identifiable, Codable, Equatable {
    let id: String
    let displayName: String
    let bundleIdentifier: String?
    let appPath: String

    init(id: String? = nil, displayName: String, bundleIdentifier: String?, appPath: String) {
        self.id = id ?? (bundleIdentifier ?? appPath)
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.appPath = appPath
    }

    var ide: ExternalIDE {
        ExternalIDE(
            id: id,
            displayName: displayName,
            bundleIdentifiers: bundleIdentifier.map { [$0] } ?? [],
            appPaths: [appPath],
            source: .custom
        )
    }
}
