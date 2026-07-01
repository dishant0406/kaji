import Foundation
import TermyKit

enum TermyBytes {
    static func string(_ bytes: TermyFfiBytes) -> String? {
        guard let ptr = bytes.ptr, bytes.len > 0 else { return nil }
        return String(bytes: UnsafeBufferPointer(start: ptr, count: Int(bytes.len)), encoding: .utf8)
    }

    static func array(_ bytes: TermyFfiBytes) -> [UInt8] {
        guard let ptr = bytes.ptr, bytes.len > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: ptr, count: Int(bytes.len)))
    }
}
