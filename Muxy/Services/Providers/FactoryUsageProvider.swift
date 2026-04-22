import CryptoKit
import Foundation

struct FactoryUsageProvider: AIUsageProvider {
    let id = "factory"
    let displayName = "Factory"
    let iconName = "factory"

    private static let usageEndpoint = URL(string: "https://api.factory.ai/api/organization/subscription/usage")
    private static let refreshEndpoint = URL(string: "https://api.workos.com/user_management/authenticate")
    private static let workosClientID = "client_01HNM792M5G5G1A2THWPXKFMXB"
    private static let refreshBuffer: TimeInterval = 24 * 60 * 60
    private static let keychainServices = ["Factory Token", "Factory token", "Factory Auth", "Droid Auth"]
    private static var factoryDir: String { NSHomeDirectory() + "/.factory" }

    func fetchUsageSnapshot() async -> AIProviderUsageSnapshot {
        do {
            let token = try await refreshedAccessToken()
            guard let endpoint = Self.usageEndpoint else {
                return snapshot(state: .error(message: "Unable to fetch usage"))
            }

            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Muxy", forHTTPHeaderField: "User-Agent")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["useCache": true])

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return snapshot(state: .error(message: "Unable to fetch usage"))
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                return snapshot(state: .unavailable(message: "Sign in to Factory"))
            }
            guard (200 ..< 300).contains(http.statusCode) else {
                usageLogger.error("Factory usage request failed with status \(http.statusCode)")
                return snapshot(state: .error(message: "Usage request failed"))
            }

            let parsed = try FactoryUsageParser.parse(from: data)
            guard !parsed.rows.isEmpty else {
                return snapshot(state: .unavailable(message: "No usage data"))
            }
            return AIProviderUsageSnapshot(
                providerID: id,
                providerName: parsed.planName.map { "Factory \($0)" } ?? displayName,
                providerIconName: iconName,
                state: .available,
                rows: parsed.rows
            )
        } catch AIUsageAuthError.missingCredentials {
            return snapshot(state: .unavailable(message: "Sign in to Factory"))
        } catch {
            usageLogger.error("Factory usage request failed: \(error.localizedDescription)")
            return snapshot(state: .error(message: "Unable to fetch usage"))
        }
    }

    private func refreshedAccessToken() async throws -> String {
        let stored = try readStoredCredentials()

        let expiresAt = stored.expiresAt ?? AIUsageOAuth.decodeJWTExpiry(stored.accessToken)
        if let expiresAt, Date() < expiresAt.addingTimeInterval(-Self.refreshBuffer) {
            return stored.accessToken
        }

        guard let refreshToken = stored.refreshToken,
              let endpoint = Self.refreshEndpoint
        else {
            return stored.accessToken
        }

        do {
            let refreshed = try await AIUsageOAuth.refresh(
                endpoint: endpoint,
                formBody: [
                    "client_id": Self.workosClientID,
                    "grant_type": "refresh_token",
                    "refresh_token": refreshToken,
                ]
            )
            persistCredentials(
                to: stored.source,
                accessToken: refreshed.accessToken,
                refreshToken: refreshed.refreshToken ?? refreshToken,
                expiresAt: refreshed.expiresAt ?? AIUsageOAuth.decodeJWTExpiry(refreshed.accessToken)
            )
            return refreshed.accessToken
        } catch {
            usageLogger.info("Factory token refresh failed: \(error.localizedDescription); using stored access token")
            return stored.accessToken
        }
    }

    private enum CredentialSource {
        case plainFile(path: String)
        case encryptedFile(filePath: String, keyPath: String)
        case keychain(service: String)
    }

    private struct StoredCredentials {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date?
        let source: CredentialSource
    }

    private func readStoredCredentials() throws -> StoredCredentials {
        let filePath = Self.factoryDir + "/auth.v2.file"
        let keyPath = Self.factoryDir + "/auth.v2.key"
        if FileManager.default.fileExists(atPath: filePath),
           FileManager.default.fileExists(atPath: keyPath),
           let raw = try? decryptAES256GCM(payloadPath: filePath, keyPath: keyPath),
           let creds = credentials(fromRaw: raw, source: .encryptedFile(filePath: filePath, keyPath: keyPath))
        {
            return creds
        }

        for path in [Self.factoryDir + "/auth.encrypted", Self.factoryDir + "/auth.json"]
            where FileManager.default.fileExists(atPath: path)
        {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let raw = String(data: data, encoding: .utf8),
               let creds = credentials(fromRaw: raw, source: .plainFile(path: path))
            {
                return creds
            }
        }

        for service in Self.keychainServices {
            guard let raw = AIUsageTokenReader.fromKeychain(service: service) else { continue }
            if let creds = credentials(fromRaw: raw, source: .keychain(service: service)) {
                return creds
            }
        }

        throw AIUsageAuthError.missingCredentials
    }

    private func credentials(fromRaw raw: String, source: CredentialSource) -> StoredCredentials? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            return extractFromDictionary(json, source: source)
        }

        if let hexDecoded = hexDecodedUTF8(trimmed),
           let data = hexDecoded.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            return extractFromDictionary(json, source: source)
        }

        if trimmed.split(separator: ".").count >= 3 {
            return StoredCredentials(
                accessToken: trimmed,
                refreshToken: nil,
                expiresAt: AIUsageOAuth.decodeJWTExpiry(trimmed),
                source: source
            )
        }

        return nil
    }

    private func extractFromDictionary(_ dict: [String: Any], source: CredentialSource) -> StoredCredentials? {
        let tokenContainer = (dict["tokens"] as? [String: Any]) ?? dict
        guard let accessToken = AIUsageParserSupport.string(
            in: tokenContainer,
            keys: ["access_token", "accessToken"]
        ), !accessToken.isEmpty
        else {
            return nil
        }
        let refreshToken = AIUsageParserSupport.string(in: tokenContainer, keys: ["refresh_token", "refreshToken"])
        let explicitExpiry = AIUsageParserSupport.number(in: tokenContainer, keys: ["expires_at", "expiresAt"])
            .map(AIUsageParserSupport.unixDate(from:))

        return StoredCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: explicitExpiry ?? AIUsageOAuth.decodeJWTExpiry(accessToken),
            source: source
        )
    }

    private func persistCredentials(
        to source: CredentialSource,
        accessToken: String,
        refreshToken: String?,
        expiresAt: Date?
    ) {
        guard case let .plainFile(path) = source else { return }
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return
        }

        if json["tokens"] is [String: Any] {
            var tokens = json["tokens"] as? [String: Any] ?? [:]
            tokens["access_token"] = accessToken
            if let refreshToken {
                tokens["refresh_token"] = refreshToken
            }
            if let expiresAt {
                tokens["expires_at"] = Int(expiresAt.timeIntervalSince1970)
            }
            json["tokens"] = tokens
        } else {
            json["access_token"] = accessToken
            if let refreshToken {
                json["refresh_token"] = refreshToken
            }
            if let expiresAt {
                json["expires_at"] = Int(expiresAt.timeIntervalSince1970)
            }
        }

        if let updated = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) {
            try? updated.write(to: url, options: .atomic)
        }
    }

    private func decryptAES256GCM(payloadPath: String, keyPath: String) throws -> String {
        let envelopeData = try Data(contentsOf: URL(fileURLWithPath: payloadPath))
        let keyData = try Data(contentsOf: URL(fileURLWithPath: keyPath))

        guard let envelope = try JSONSerialization.jsonObject(with: envelopeData) as? [String: Any],
              let ciphertextB64 = AIUsageParserSupport.string(in: envelope, keys: ["ciphertext", "data", "payload"]),
              let ivB64 = AIUsageParserSupport.string(in: envelope, keys: ["iv", "nonce"]),
              let tagB64 = AIUsageParserSupport.string(in: envelope, keys: ["tag", "authTag", "auth_tag"])
        else {
            throw AIUsageAuthError.missingCredentials
        }

        let rawKey = resolveKey(from: keyData)
        guard let ciphertext = base64Decode(ciphertextB64),
              let iv = base64Decode(ivB64),
              let tag = base64Decode(tagB64)
        else {
            throw AIUsageAuthError.missingCredentials
        }

        let key = SymmetricKey(data: rawKey)
        let nonce = try AES.GCM.Nonce(data: iv)
        let sealed = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        let plain = try AES.GCM.open(sealed, using: key)
        guard let string = String(data: plain, encoding: .utf8) else {
            throw AIUsageAuthError.missingCredentials
        }
        return string
    }

    private func resolveKey(from keyData: Data) -> Data {
        if let text = String(data: keyData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            if text.contains("{"),
               let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
               let encoded = AIUsageParserSupport.string(in: json, keys: ["key", "secret", "value"]),
               let decoded = base64Decode(encoded)
            {
                return decoded
            }
            if let decoded = base64Decode(text) {
                return decoded
            }
            if let decoded = hexToData(text) {
                return decoded
            }
            return Data(text.utf8)
        }
        return keyData
    }

    private func base64Decode(_ value: String) -> Data? {
        var normalized = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while !normalized.count.isMultiple(of: 4) {
            normalized.append("=")
        }
        return Data(base64Encoded: normalized)
    }

    private func hexToData(_ hex: String) -> Data? {
        let cleaned = hex.replacingOccurrences(of: " ", with: "")
        guard cleaned.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index ..< next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }

    private func hexDecodedUTF8(_ value: String) -> String? {
        guard let data = hexToData(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
