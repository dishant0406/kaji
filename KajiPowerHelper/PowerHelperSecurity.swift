import Foundation
import Security

enum PowerHelperCodeSigningRequirement {
    static func designated(identifier: String, teamIdentifier: String) -> String {
        let safeIdentifier = escaped(identifier)
        let safeTeamIdentifier = escaped(teamIdentifier)
        return "anchor apple generic and identifier \"\(safeIdentifier)\" and certificate leaf[subject.OU] = \"\(safeTeamIdentifier)\""
    }

    private static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

struct PowerHelperSigningIdentity: Equatable {
    let identifier: String
    let teamIdentifier: String

    var requirement: String {
        PowerHelperCodeSigningRequirement.designated(
            identifier: identifier,
            teamIdentifier: teamIdentifier
        )
    }
}

func currentKajiClientRequirement() -> String? {
    let helperURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let contentsURL = helperURL.deletingLastPathComponent().deletingLastPathComponent()
    let appURL = contentsURL.deletingLastPathComponent()
    guard appURL.pathExtension == "app" else { return nil }
    var appCode: SecStaticCode?
    guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &appCode) == errSecSuccess,
          let appCode,
          SecStaticCodeCheckValidity(appCode, [], nil) == errSecSuccess
    else { return nil }
    var requirement: SecRequirement?
    guard SecCodeCopyDesignatedRequirement(appCode, [], &requirement) == errSecSuccess,
          let requirement
    else { return nil }
    var requirementText: CFString?
    guard SecRequirementCopyString(requirement, [], &requirementText) == errSecSuccess,
          let requirementText
    else { return nil }
    return requirementText as String
}

func currentSigningIdentity() -> PowerHelperSigningIdentity? {
    var dynamicCode: SecCode?
    guard SecCodeCopySelf([], &dynamicCode) == errSecSuccess,
          let dynamicCode
    else { return nil }
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(dynamicCode, [], &staticCode) == errSecSuccess,
          let staticCode
    else { return nil }
    var information: CFDictionary?
    guard SecCodeCopySigningInformation(
        staticCode,
        SecCSFlags(rawValue: kSecCSSigningInformation),
        &information
    ) == errSecSuccess,
        let dictionary = information as? [String: Any],
        let identifier = dictionary[kSecCodeInfoIdentifier as String] as? String,
        let teamIdentifier = dictionary[kSecCodeInfoTeamIdentifier as String] as? String,
        !identifier.isEmpty,
        !teamIdentifier.isEmpty
    else { return nil }
    return PowerHelperSigningIdentity(identifier: identifier, teamIdentifier: teamIdentifier)
}
