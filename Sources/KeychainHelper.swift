import Foundation
import Security

/// Wrapper tối giản cho Keychain (generic password). Lưu/đọc/xóa 1 blob Data
/// theo cặp service + account. Dùng cho list OTP và PIN — dữ liệu nhạy cảm,
/// KHÔNG để rơi vào UserDefaults plaintext.
enum KeychainHelper {
    static let service = "com.xuanhoa.clipboard"

    @discardableResult
    static func save(_ data: Data, account: String) -> Bool {
        // Xóa entry cũ trước (SecItemAdd lỗi nếu trùng).
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // Chỉ giải mã được khi máy đã mở khóa, không sync iCloud.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("DEBUG: Keychain save lỗi cho \(account): \(status)")
        }
        return status == errSecSuccess
    }

    static func load(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
