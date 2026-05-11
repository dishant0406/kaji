import Foundation

struct NotificationEndpointSender {
    enum Error: LocalizedError {
        case invalidURL
        case invalidHeader(String)
        case requestFailed(Int)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                "Invalid endpoint URL."
            case let .invalidHeader(line):
                "Invalid header line: \(line)"
            case let .requestFailed(code):
                "Endpoint returned HTTP \(code)."
            }
        }
    }

    var sendData: @Sendable (URLRequest, Data?) async throws -> (Data, URLResponse) = {
        request,
        body in
        var request = request
        request.httpBody = body
        return try await URLSession.shared.data(for: request)
    }

    func send(
        destination: NotificationDeliveryDestination,
        bearerToken: String,
        event: NotificationOutboundEvent
    ) async throws {
        guard let url = URL(string: destination.endpointURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw Error.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = destination.method.rawValue
        request.setValue(destination.contentType.rawValue, forHTTPHeaderField: "Content-Type")

        for header in try headers(from: destination.headersTemplate, event: event) {
            request.setValue(header.value, forHTTPHeaderField: header.key)
        }

        if !bearerToken.isEmpty {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        let bodyText = NotificationTemplateRenderer.render(destination.bodyTemplate, event: event)
        let bodyData = bodyText.isEmpty ? nil : Data(bodyText.utf8)
        let (_, response) = try await sendData(request, bodyData)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode)
        else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw Error.requestFailed(statusCode)
        }
    }

    private func headers(
        from template: String,
        event: NotificationOutboundEvent
    ) throws -> [String: String] {
        try template
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .reduce(into: [:]) { result, line in
                let rendered = NotificationTemplateRenderer.render(line, event: event)
                let parts = rendered.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { throw Error.invalidHeader(rendered) }
                result[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
            }
    }
}
