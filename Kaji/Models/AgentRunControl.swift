import Foundation

enum AgentRunActionKind: String, Codable, Hashable {
    case jump
    case reply
    case stop
    case restart
    case resume
    case verify
    case openFile
    case openDiff
    case approve
    case deny
}

enum AgentRunCapability: Hashable {
    case available
    case unavailable(String)
    case hidden

    var isVisible: Bool {
        self != .hidden
    }

    var isAvailable: Bool {
        self == .available
    }
}

struct AgentRunCapabilities: Hashable {
    let jump: AgentRunCapability
    let reply: AgentRunCapability
    let stop: AgentRunCapability
    let restart: AgentRunCapability
    let resume: AgentRunCapability
    let verify: AgentRunCapability
    let openFiles: AgentRunCapability
    let openDiffs: AgentRunCapability
    let approve: AgentRunCapability
    let deny: AgentRunCapability
}

enum AgentRunControlAction: Hashable {
    case jump(AgentMissionControlItem)
    case reply(UUID, String)
    case stop(UUID)
    case restart(UUID)
    case resume(UUID)
    case verify(UUID)
    case openFile(UUID, AgentChangedFile)
    case openDiff(UUID, AgentChangedFile)
    case approve(UUID)
    case deny(UUID)
}

enum AgentRunControlResult: Hashable {
    case succeeded(String)
    case failed(String)
    case unavailable(String)
}
