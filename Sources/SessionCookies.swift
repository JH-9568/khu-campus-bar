import Foundation
import Security
import WebKit

enum SessionCookies {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.jh9568.CampusBar.session",
         kSecAttrAccount as String: "school"]
    }

    static func encode(_ cookies: [HTTPCookie]) throws -> Data {
        let properties = cookies.filter { $0.domain == "khu.ac.kr" || $0.domain.hasSuffix(".khu.ac.kr") }
            .compactMap(\.properties)
            .map { Dictionary(uniqueKeysWithValues: $0.map { ($0.key.rawValue, $0.value) }) }
        return try PropertyListSerialization.data(fromPropertyList: properties, format: .binary, options: 0)
    }

    static func decode(_ data: Data) -> [HTTPCookie] {
        guard let properties = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else { return [] }
        return properties.compactMap {
            HTTPCookie(properties: Dictionary(uniqueKeysWithValues: $0.map { (HTTPCookiePropertyKey($0.key), $0.value) }))
        }.filter { $0.expiresDate.map { $0 > Date() } ?? true }
    }

    static func load() -> [HTTPCookie] {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data else { return [] }
        return decode(data)
    }

    @discardableResult
    static func save(_ cookies: [HTTPCookie]) -> OSStatus {
        guard let data = try? encode(cookies) else { return errSecParam }
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status != errSecItemNotFound { return status }
        var entry = query
        entry[kSecValueData as String] = data
        entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(entry as CFDictionary, nil)
    }

    static func clear() { SecItemDelete(query as CFDictionary) }
}
