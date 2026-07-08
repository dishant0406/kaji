import Foundation

struct AIGatewayHealthClient {
    func isHealthy(endpoint: String) async -> Bool {
        guard let url = URL(string: endpoint + "/health") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            return Self.isHealthyStatus(data)
        } catch {
            return false
        }
    }

    static func isHealthyStatus(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = object["status"] as? String
        else { return false }
        return status == "running" || status == "ok"
    }
}
