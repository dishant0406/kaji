import Foundation

/// A contiguous run of changed columns on a single grid row, as reported by the
/// terminal core's damage tracker. Drives partial render-plan rebuilds so a
/// single-cell change (e.g. a cursor blink) does not force the whole grid to be
/// re-laid-out.
struct TerminalDirtySpan: Equatable {
    var row: Int
    var leftCol: Int
    var rightCol: Int
}

/// The shape of the change reported by `termy_terminal_take_damage`.
///
/// - `none`: nothing changed since the last poll; the cached render plan is reused.
/// - `full`: the entire visible grid changed (resize, scroll, clear); rebuild all rows.
/// - `partial`: only the listed rows changed; rebuild just those rows.
enum TerminalDamage: Equatable {
    case none
    case full
    case partial([TerminalDirtySpan])

    /// Whether anything changed and a redraw is warranted.
    var hasChanges: Bool {
        switch self {
        case .none:
            false
        case .full:
            true
        case let .partial(spans):
            !spans.isEmpty
        }
    }

    var dirtyRows: [Int]? {
        switch self {
        case .none:
            []
        case .full:
            nil
        case let .partial(spans):
            Array(Set(spans.map(\.row))).sorted()
        }
    }

    var dirtySpans: [TerminalDirtySpan]? {
        switch self {
        case .none:
            []
        case .full:
            nil
        case let .partial(spans):
            spans
        }
    }

    /// Adds one more dirty span (e.g. the cursor cell on a blink toggle) to the
    /// damage without losing what is already dirty.
    func union(_ span: TerminalDirtySpan) -> TerminalDamage {
        switch self {
        case .full:
            .full
        case .none:
            .partial([span])
        case let .partial(spans):
            TerminalDamage.partialCoalesced(spans + [span])
        }
    }

    static func partialCoalesced(_ spans: [TerminalDirtySpan]) -> TerminalDamage {
        guard !spans.isEmpty else {
            return .none
        }

        var rows: [Int: (left: Int, right: Int)] = [:]
        for span in spans {
            guard span.row >= 0, span.leftCol <= span.rightCol else {
                continue
            }
            if let existing = rows[span.row] {
                rows[span.row] = (
                    left: min(existing.left, span.leftCol),
                    right: max(existing.right, span.rightCol)
                )
            } else {
                rows[span.row] = (left: span.leftCol, right: span.rightCol)
            }
        }

        let coalesced = rows.keys.sorted().map { row in
            let range = rows[row] ?? (left: 0, right: 0)
            return TerminalDirtySpan(row: row, leftCol: range.left, rightCol: range.right)
        }
        return coalesced.isEmpty ? .none : .partial(coalesced)
    }
}
