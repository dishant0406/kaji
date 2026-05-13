import Foundation

enum LanguagePackCatalogFetcher {
    static func fetch(from url: URL) async throws -> LanguagePackCatalogPayload {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            throw FetchError.invalidStatus(http.statusCode)
        }
        return try JSONDecoder().decode(LanguagePackCatalogPayload.self, from: data)
    }

    enum FetchError: LocalizedError {
        case invalidStatus(Int)

        var errorDescription: String? {
            switch self {
            case let .invalidStatus(status):
                "Language pack registry returned HTTP \(status)."
            }
        }
    }
}
