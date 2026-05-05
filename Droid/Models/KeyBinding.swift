import AppKit
import SwiftUI

enum ShortcutAction: String, Codable, CaseIterable, Identifiable {
    case newTab
    case closeTab
    case renameTab
    case pinUnpinTab
    case splitRight
    case splitDown
    case closePane
    case focusPaneLeft
    case focusPaneRight
    case focusPaneUp
    case focusPaneDown
    case nextTab
    case previousTab
    case toggleThemePicker
    case newProject
    case openProject
    case reloadConfig
    case selectTab1
    case selectTab2
    case selectTab3
    case selectTab4
    case selectTab5
    case selectTab6
    case selectTab7
    case selectTab8
    case selectTab9
    case nextProject
    case previousProject
    case selectProject1
    case selectProject2
    case selectProject3
    case selectProject4
    case selectProject5
    case selectProject6
    case selectProject7
    case selectProject8
    case selectProject9
    case findInTerminal
    case openVCSTab
    case quickOpen
    case ask
    case agentCommandCenter
    case switchWorktree
    case saveFile
    case toggleSidebar
    case toggleFileTree
    case toggleAIUsage
    case navigateBack
    case navigateForward

    static var allCases: [Self] { ShortcutReferenceCatalog.actions }

    var id: String { rawValue }

    var displayName: String { ShortcutReferenceCatalog.definition(for: self).displayName }
    var category: String { ShortcutReferenceCatalog.definition(for: self).category }
    var scope: ShortcutScope { ShortcutReferenceCatalog.definition(for: self).scope }

    static var categories: [String] {
        ShortcutReferenceCatalog.categories
    }

    static func tabAction(for index: Int) -> Self? {
        let actions: [Self] = [
            .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5,
            .selectTab6, .selectTab7, .selectTab8, .selectTab9,
        ]
        guard index >= 1, index <= actions.count else { return nil }
        return actions[index - 1]
    }

    static func projectAction(for index: Int) -> Self? {
        let actions: [Self] = [
            .selectProject1, .selectProject2, .selectProject3, .selectProject4, .selectProject5,
            .selectProject6, .selectProject7, .selectProject8, .selectProject9,
        ]
        guard index >= 1, index <= actions.count else { return nil }
        return actions[index - 1]
    }

    var tabSelectionIndex: Int? {
        switch self {
        case .selectTab1: 0
        case .selectTab2: 1
        case .selectTab3: 2
        case .selectTab4: 3
        case .selectTab5: 4
        case .selectTab6: 5
        case .selectTab7: 6
        case .selectTab8: 7
        case .selectTab9: 8
        default: nil
        }
    }

    var projectSelectionIndex: Int? {
        switch self {
        case .selectProject1: 0
        case .selectProject2: 1
        case .selectProject3: 2
        case .selectProject4: 3
        case .selectProject5: 4
        case .selectProject6: 5
        case .selectProject7: 6
        case .selectProject8: 7
        case .selectProject9: 8
        default: nil
        }
    }
}

struct KeyBinding: Codable, Identifiable {
    let action: ShortcutAction
    var combo: KeyCombo

    var id: String { action.rawValue }

    static var defaults: [Self] { ShortcutReferenceCatalog.defaultBindings }
}
