import Foundation

enum PortProcessParser {
    static func parse(_ output: String) -> [PortProcessSnapshot] {
        let snapshots = output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .dropFirst()
            .compactMap(parseLine)
        return uniqueSorted(snapshots)
    }

    private static func parseLine(_ line: Substring) -> PortProcessSnapshot? {
        let columns = line.split(omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
        guard columns.count >= 9,
              let pid = Int32(columns[1]),
              let protocolIndex = columns.firstIndex(where: { $0 == "TCP" }),
              protocolIndex + 1 < columns.count
        else { return nil }

        let name = columns[(protocolIndex + 1)...].joined(separator: " ")
        guard name.contains("(LISTEN)"), let endpoint = name.split(separator: " ").first else { return nil }
        guard let port = parsePort(from: String(endpoint)) else { return nil }

        return PortProcessSnapshot(
            protocolName: "TCP",
            address: parseAddress(from: String(endpoint)),
            port: port,
            pid: pid,
            processName: String(columns[0])
        )
    }

    private static func parsePort(from endpoint: String) -> Int? {
        guard let separator = endpoint.lastIndex(of: ":") else { return nil }
        let value = endpoint[endpoint.index(after: separator)...]
        return Int(value)
    }

    private static func parseAddress(from endpoint: String) -> String {
        guard let separator = endpoint.lastIndex(of: ":") else { return endpoint }
        let address = endpoint[..<separator]
        return address.isEmpty ? "*" : String(address)
    }

    private static func uniqueSorted(_ snapshots: [PortProcessSnapshot]) -> [PortProcessSnapshot] {
        var seen = Set<String>()
        return snapshots
            .filter { seen.insert($0.id).inserted }
            .sorted { lhs, rhs in
                if lhs.port != rhs.port {
                    return lhs.port < rhs.port
                }
                if lhs.processName != rhs.processName {
                    return lhs.processName < rhs.processName
                }
                return lhs.pid < rhs.pid
            }
    }
}
