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
    case focusNextPane
    case focusPreviousPane
    case focusLastPane
    case focusPane1
    case focusPane2
    case focusPane3
    case focusPane4
    case focusPane5
    case focusPane6
    case focusPane7
    case focusPane8
    case focusPane9
    case focusPaneLeft
    case focusPaneRight
    case focusPaneUp
    case focusPaneDown
    case increasePaneWidth
    case decreasePaneWidth
    case increasePaneHeight
    case decreasePaneHeight
    case balancePanes
    case swapPaneLeft
    case swapPaneRight
    case swapPaneUp
    case swapPaneDown
    case movePaneLeft
    case movePaneRight
    case movePaneUp
    case movePaneDown
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
    case replaceInEditor
    case openVCSTab
    case commandPalette
    case quickOpen
    case ask
    case agentCommandCenter
    case switchWorktree
    case saveFile
    case goToSymbol
    case goToLine
    case inlineEdit
    case toggleSidebar
    case toggleFileTree
    case toggleGlobalSearch
    case toggleProblemsPanel
    case toggleBrowserPanel
    case browserBack
    case browserForward
    case browserReload
    case browserFocusAddressBar
    case browserNewPage
    case browserClosePage
    case browserNextPage
    case browserPreviousPage
    case browserReadPage
    case toggleAgentInstructions
    case toggleMCPControlPanel
    case closeActiveSidePanel
    case toggleNotificationPanel
    case toggleAgentMissionControl
    case toggleFooterTerminal
    case openKajiAgentSplit
    case openFooterLauncher1
    case openFooterLauncher2
    case openFooterLauncher3
    case openFooterLauncher4
    case openFooterLauncher5
    case toggleAIUsage
    case navigateBack
    case navigateForward
    case vcsRefresh
    case vcsCommit
    case vcsPull
    case vcsPush
    case vcsCreatePR
    case fileTreeNewFile
    case fileTreeNewFolder
    case fileTreeToggleChangedOnly

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

    var paneSelectionIndex: Int? {
        switch self {
        case .focusPane1: 0
        case .focusPane2: 1
        case .focusPane3: 2
        case .focusPane4: 3
        case .focusPane5: 4
        case .focusPane6: 5
        case .focusPane7: 6
        case .focusPane8: 7
        case .focusPane9: 8
        default: nil
        }
    }

    var footerLauncherIndex: Int? {
        switch self {
        case .openFooterLauncher1: 0
        case .openFooterLauncher2: 1
        case .openFooterLauncher3: 2
        case .openFooterLauncher4: 3
        case .openFooterLauncher5: 4
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
