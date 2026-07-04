import Foundation
import Security

/// Thin wrapper over the Keychain Services `SecItem*` APIs for persisting a single
/// secret string (the Conductor API key) keyed by service + account.
struct KeychainStore {
    enum KeychainError: Error, LocalizedError {
        case unexpectedStatus(OSStatus)
        case unexpectedData

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                let detail = SecCopyErrorMessageString(status, nil).map { $0 as String } ?? "unknown"
                return "Keychain error \(status): \(detail)"
            case .unexpectedData:
                return "Keychain returned data in an unexpected format."
            }
        }
    }

    let service: String
    let account: String

    init(service: String = "dev.mrbavio.nickel", account: String = "apiKey") {
        self.service = service
        self.account = account
    }

    /// Reads the stored secret, or `nil` if nothing is stored yet.
    func read() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
                throw KeychainError.unexpectedData
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Persists the secret, adding a new item or updating the existing one.
    func save(_ value: String) throws {
        let data = Data(value.utf8)

        if try read() != nil {
            let query = baseQuery()
            let attributes: [String: Any] = [kSecValueData as String: data]
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard status == errSecSuccess else {
                throw KeychainError.unexpectedStatus(status)
            }
        } else {
            var query = baseQuery()
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw KeychainError.unexpectedStatus(status)
            }
        }
    }

    /// Removes the stored secret. A no-op (not an error) if nothing is stored.
    func delete() throws {
        let query = baseQuery()
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
