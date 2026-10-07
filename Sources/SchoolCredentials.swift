import Foundation
import Security

struct SchoolLogin: Codable, Sendable {
    let username: String
    let password: String
}

// Only the explicit Settings form writes credentials. Never capture website input.
actor SchoolCredentials {
    static let shared = SchoolCredentials()
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.jh9568.CampusBar.autologin",
         kSecAttrAccount as String: "school"]
    }
    func load() throws -> SchoolLogin? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let result = SecItemCopyMatching(request as CFDictionary, &value)
        if result == errSecItemNotFound { return nil }
        guard result == errSecSuccess, let data = value as? Data else { throw LoginError.keychain(result) }
        return try JSONDecoder().decode(SchoolLogin.self, from: data)
    }
    func save(_ login: SchoolLogin) throws {
        guard !login.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !login.password.isEmpty else { throw LoginError.empty }
        let data = try JSONEncoder().encode(login)
        var result = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if result == errSecItemNotFound {
            var entry = query
            entry[kSecValueData as String] = data
            entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            result = SecItemAdd(entry as CFDictionary, nil)
        }
        guard result == errSecSuccess else { throw LoginError.keychain(result) }
    }
    func clear() throws {
        let result = SecItemDelete(query as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw LoginError.keychain(result) }
    }
}

enum LoginError: LocalizedError {
    case empty, keychain(OSStatus)
    var errorDescription: String? {
        switch self {
        case .empty: "학교 ID와 비밀번호를 입력해 주세요."
        case .keychain(let code): "키체인 접근을 확인해 주세요 (\(code))."
        }
    }
}

struct AutoLoginPolicy {
    private(set) var attempted = false
    private(set) var paused: Bool
    init(paused: Bool = false) { self.paused = paused }
    static func isLoginPage(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme == "https" && url.host == "e-campus.khu.ac.kr"
            && (url.port == nil || url.port == 443) && url.path == "/xn-sso/login.php"
            && url.user == nil && url.password == nil
    }
    mutating func begin() -> Bool {
        guard !paused, !attempted else { return false }
        attempted = true
        return true
    }
    mutating func fail() { paused = true }
    mutating func reset() { attempted = false; paused = false }
}
