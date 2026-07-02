import Foundation

struct TerminalInjectedCommandDelivery {
    private(set) var command: String?
    private var pendingCommand: String?
    private var deliveredCommand: String?

    mutating func setCommand(_ rawValue: String?) -> Bool {
        let normalized = Self.normalized(rawValue)
        guard command != normalized else { return false }
        command = normalized
        pendingCommand = nil
        deliveredCommand = nil
        return true
    }

    mutating func prepareDelivery() -> String? {
        guard let command,
              pendingCommand != command,
              deliveredCommand != command
        else { return nil }
        pendingCommand = command
        return command
    }

    mutating func completePendingDelivery(_ delivered: String) -> Bool {
        guard command == delivered,
              pendingCommand == delivered,
              deliveredCommand != delivered
        else { return false }
        pendingCommand = nil
        deliveredCommand = delivered
        return true
    }

    mutating func cancelPendingDelivery(_ pending: String? = nil) {
        guard let pending else {
            pendingCommand = nil
            return
        }
        if pendingCommand == pending {
            pendingCommand = nil
        }
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
