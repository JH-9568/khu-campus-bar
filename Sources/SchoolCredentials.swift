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

struct AutoLoginPolicy: Codable {
    // /login supplies the school's SSO return_url and callback chain.
    // Direct GETs to /xn-sso/login.php render a form without that context.
    static let entryURL = URL(string: "https://e-campus.khu.ac.kr/login")!
    private(set) var attempted = false
    private(set) var verifiedSession = false
    private(set) var paused: Bool
    private(set) var retryAfter: Date?
    private(set) var transientFailures = 0
    init(paused: Bool = false) { self.paused = paused }

    static func restored(from data: Data?) -> Self {
        guard let data, var policy = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        // An interrupted process must wait for its cooldown, not remain in-flight forever.
        policy.attempted = false
        policy.verifiedSession = false
        return policy
    }
    var savedData: Data? { try? JSONEncoder().encode(self) }
    func canRetry(at now: Date = Date()) -> Bool { !paused && (retryAfter == nil || retryAfter! <= now) }
    mutating func prepareRefresh(userInitiated: Bool, now: Date = Date()) -> Bool {
        guard !paused else { return false }
        if userInitiated { retryAfter = nil }
        guard canRetry(at: now) else { return false }
        attempted = false
        verifiedSession = false
        return true
    }
    static func isLoginPage(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme == "https" && url.host == "e-campus.khu.ac.kr"
            && (url.port == nil || url.port == 443) && url.path == "/xn-sso/login.php"
            && url.user == nil && url.password == nil
    }
    mutating func begin(now: Date = Date()) -> Bool {
        guard canRetry(at: now), !attempted else { return false }
        attempted = true
        // Persist a bounded cooldown before submitting, in case the app exits mid-login.
        retryAfter = now.addingTimeInterval(300)
        return true
    }
    mutating func beginSessionVerification() -> Bool {
        guard attempted, !paused, !verifiedSession else { return false }
        verifiedSession = true
        return true
    }
    mutating func fail(retryable: Bool = false, now: Date = Date()) {
        attempted = false
        verifiedSession = false
        paused = !retryable
        if retryable {
            transientFailures += 1
            retryAfter = now.addingTimeInterval(transientFailures == 1 ? 300 : 1800)
        } else { retryAfter = nil }
    }
    mutating func reset() { self = Self() }
}
