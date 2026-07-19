import Foundation

struct MeetingTranscriptionCost: Codable, Hashable {
    let currencyCode: String
    let micros: Int64

    init(currencyCode: String, micros: Int64) throws {
        let normalizedCurrency = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalizedCurrency.count == 3,
              normalizedCurrency.unicodeScalars.allSatisfy({ CharacterSet.uppercaseLetters.contains($0) }),
              micros >= 0
        else {
            throw MeetingTranscriptionValidationError.invalidBudget("cost")
        }
        self.currencyCode = normalizedCurrency
        self.micros = micros
    }

    private enum CodingKeys: String, CodingKey {
        case currencyCode
        case micros
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            currencyCode: container.decode(String.self, forKey: .currencyCode),
            micros: container.decode(Int64.self, forKey: .micros)
        )
    }
}

enum MeetingTranscriptionCostBudgetError: Error, Equatable {
    case currencyMismatch
    case limitExceeded
    case reservationNotFound
    case duplicateReservation
    case invalidSettlement
}

struct MeetingTranscriptionCostBudgetSnapshot: Codable, Hashable {
    let limit: MeetingTranscriptionCost
    let settledMicros: Int64
    let reservedMicros: Int64

    var remainingMicros: Int64 {
        max(0, limit.micros - settledMicros - reservedMicros)
    }
}

actor MeetingTranscriptionCostBudget {
    private let limit: MeetingTranscriptionCost
    private var settledMicros: Int64 = 0
    private var reservations: [UUID: Int64] = [:]

    init(limit: MeetingTranscriptionCost) {
        self.limit = limit
    }

    func reserve(operationID: UUID, estimatedCost: MeetingTranscriptionCost) throws {
        try validateCurrency(estimatedCost)
        guard reservations[operationID] == nil else {
            throw MeetingTranscriptionCostBudgetError.duplicateReservation
        }
        let reserved = reservations.values.reduce(Int64(0), +)
        let total = settledMicros.addingReportingOverflow(reserved)
        let projected = total.partialValue.addingReportingOverflow(estimatedCost.micros)
        guard !total.overflow, !projected.overflow, projected.partialValue <= limit.micros else {
            throw MeetingTranscriptionCostBudgetError.limitExceeded
        }
        reservations[operationID] = estimatedCost.micros
    }

    func settle(operationID: UUID, actualCost: MeetingTranscriptionCost) throws {
        try validateCurrency(actualCost)
        guard let reservation = reservations[operationID] else {
            throw MeetingTranscriptionCostBudgetError.reservationNotFound
        }
        let reserved = reservations.values.reduce(Int64(0), +) - reservation
        let updated = settledMicros.addingReportingOverflow(actualCost.micros)
        let total = updated.partialValue.addingReportingOverflow(reserved)
        guard !updated.overflow, !total.overflow, total.partialValue <= limit.micros else {
            throw MeetingTranscriptionCostBudgetError.invalidSettlement
        }
        reservations.removeValue(forKey: operationID)
        settledMicros = updated.partialValue
    }

    func release(operationID: UUID) throws {
        guard reservations.removeValue(forKey: operationID) != nil else {
            throw MeetingTranscriptionCostBudgetError.reservationNotFound
        }
    }

    func snapshot() -> MeetingTranscriptionCostBudgetSnapshot {
        MeetingTranscriptionCostBudgetSnapshot(
            limit: limit,
            settledMicros: settledMicros,
            reservedMicros: reservations.values.reduce(Int64(0), +)
        )
    }

    private func validateCurrency(_ cost: MeetingTranscriptionCost) throws {
        guard cost.currencyCode == limit.currencyCode else {
            throw MeetingTranscriptionCostBudgetError.currencyMismatch
        }
    }
}
