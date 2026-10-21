import Foundation
import Security

struct OAuthCredentials: Equatable, Sendable {
    var accessToken: String
    var expiresAt: Date?
    var subscriptionType: String?

    func isExpired(at now: Date) -> Bool {
        expiresAt.map { $0 <= now } ?? false
    }
}

protocol CredentialSource: Sendable {
    func load() throws -> OAuthCredentials
}

enum CredentialParser {
    /// Claude Code stores `{"claudeAiOauth": {"accessToken": ..., "expiresAt": <ms since epoch>, ...}}`.
    static func parse(_ data: Data) throws -> OAuthCredentials {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { throw ProviderError.notSignedIn }

        let expiresAt = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return OAuthCredentials(
            accessToken: token,
            expiresAt: expiresAt,
            subscriptionType: oauth["subscriptionType"] as? String
        )
    }
}

/// Reads the login Claude Code already created, so the app needs no sign-in of its own.
/// macOS asks the user to approve Keychain access the first time.
struct ClaudeCodeCredentialSource: CredentialSource {
    static let keychainService = "Claude Code-credentials"

    var fallbackFile = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/.credentials.json")

    func load() throws -> OAuthCredentials {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.keychainService,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            guard let data = result as? Data else { throw ProviderError.notSignedIn }
            return try CredentialParser.parse(data)
        case errSecItemNotFound:
            // Some setups keep the login in a plain file instead of the Keychain.
            guard let data = try? Data(contentsOf: fallbackFile) else { throw ProviderError.notSignedIn }
            return try CredentialParser.parse(data)
        default:
            throw ProviderError.keychainDenied
        }
    }
}
