import Foundation

struct FileIconManifest: Decodable {
    struct IconDefinition: Decodable, Equatable {
        let iconPath: String?
    }

    let iconDefinitions: [String: IconDefinition]
    let folderNames: [String: String]
    let folderNamesExpanded: [String: String]
    let rootFolderNames: [String: String]
    let rootFolderNamesExpanded: [String: String]
    let fileExtensions: [String: String]
    let fileNames: [String: String]
    let file: String?
    let folder: String?
    let folderExpanded: String?
    let rootFolder: String?
    let rootFolderExpanded: String?

    static let materialIconTheme = loadMaterialIconTheme()

    private enum CodingKeys: String, CodingKey {
        case iconDefinitions
        case folderNames
        case folderNamesExpanded
        case rootFolderNames
        case rootFolderNamesExpanded
        case fileExtensions
        case fileNames
        case file
        case folder
        case folderExpanded
        case rootFolder
        case rootFolderExpanded
    }

    init(
        iconDefinitions: [String: IconDefinition],
        folderNames: [String: String],
        folderNamesExpanded: [String: String],
        rootFolderNames: [String: String],
        rootFolderNamesExpanded: [String: String],
        fileExtensions: [String: String],
        fileNames: [String: String],
        file: String?,
        folder: String?,
        folderExpanded: String?,
        rootFolder: String?,
        rootFolderExpanded: String?
    ) {
        self.iconDefinitions = iconDefinitions
        self.folderNames = folderNames
        self.folderNamesExpanded = folderNamesExpanded
        self.rootFolderNames = rootFolderNames
        self.rootFolderNamesExpanded = rootFolderNamesExpanded
        self.fileExtensions = fileExtensions
        self.fileNames = fileNames
        self.file = file
        self.folder = folder
        self.folderExpanded = folderExpanded
        self.rootFolder = rootFolder
        self.rootFolderExpanded = rootFolderExpanded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        iconDefinitions = try container.decodeIfPresent([String: IconDefinition].self, forKey: .iconDefinitions) ?? [:]
        folderNames = try container.decodeIfPresent([String: String].self, forKey: .folderNames) ?? [:]
        folderNamesExpanded = try container.decodeIfPresent([String: String].self, forKey: .folderNamesExpanded) ?? [:]
        rootFolderNames = try container.decodeIfPresent([String: String].self, forKey: .rootFolderNames) ?? [:]
        rootFolderNamesExpanded = try container.decodeIfPresent([String: String].self, forKey: .rootFolderNamesExpanded) ?? [:]
        fileExtensions = try container.decodeIfPresent([String: String].self, forKey: .fileExtensions) ?? [:]
        fileNames = try container.decodeIfPresent([String: String].self, forKey: .fileNames) ?? [:]
        file = try container.decodeIfPresent(String.self, forKey: .file)
        folder = try container.decodeIfPresent(String.self, forKey: .folder)
        folderExpanded = try container.decodeIfPresent(String.self, forKey: .folderExpanded)
        rootFolder = try container.decodeIfPresent(String.self, forKey: .rootFolder)
        rootFolderExpanded = try container.decodeIfPresent(String.self, forKey: .rootFolderExpanded)
    }

    private static func loadMaterialIconTheme() -> FileIconManifest {
        let fallback = FileIconManifest(
            iconDefinitions: [:],
            folderNames: [:],
            folderNamesExpanded: [:],
            rootFolderNames: [:],
            rootFolderNamesExpanded: [:],
            fileExtensions: [:],
            fileNames: [:],
            file: nil,
            folder: nil,
            folderExpanded: nil,
            rootFolder: nil,
            rootFolderExpanded: nil
        )

        let urls = [
            Bundle.appResources.url(
                forResource: "material-icons",
                withExtension: "json",
                subdirectory: "FileIcons/MaterialIconTheme"
            ),
            Bundle.main.url(
                forResource: "material-icons",
                withExtension: "json",
                subdirectory: "FileIcons/MaterialIconTheme"
            ),
        ]

        for case let url? in urls {
            guard let data = try? Data(contentsOf: url),
                  let manifest = try? JSONDecoder().decode(FileIconManifest.self, from: data),
                  !manifest.iconDefinitions.isEmpty
            else { continue }
            return manifest
        }

        return fallback
    }
}
