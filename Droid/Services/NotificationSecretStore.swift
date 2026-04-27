import Foundation
import Security

struct NotificationSecretStore {
    func loadBearerToken(for destinationID: UUID) -> String {
        let query = baseQuery(for: destinationID)
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8)
        else { return "" }
        return token
    }

    func saveBearerToken(_ token: String, for destinationID: UUID) {
        let query = baseQuery(for: destinationID)
        if token.isEmpty {
            SecItemDelete(query as CFDictionary)
            return
        }

        let data = Data(token.utf8)
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard status != errSecItemNotFound else {
            var createQuery = query
            createQuery[kSecValueData as String] = data
            SecItemAdd(createQuery as CFDictionary, nil)
            return
        }
    }

    func deleteBearerToken(for destinationID: UUID) {
        SecItemDelete(baseQuery(for: destinationID) as CFDictionary)
    }

    private func baseQuery(for destinationID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.droid.notifications.destination",
            kSecAttrAccount as String: destinationID.uuidString.lowercased(),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
    }
}
