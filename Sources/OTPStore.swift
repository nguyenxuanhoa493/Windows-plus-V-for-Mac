import Foundation
import CryptoKit

/// Lưu dữ liệu OTP (danh sách + PIN) trong 1 file mã hóa ở Application Support,
/// THAY cho Keychain để macOS KHÔNG hỏi quyền truy cập (app ad-hoc signed → hỏi liên tục).
///
/// Mã hóa AES-GCM bằng khóa 256-bit sinh ngẫu nhiên, lưu base64 trong UserDefaults.
/// Đây là mức "obfuscation at rest" (khóa nằm cạnh dữ liệu) — đủ cho máy cá nhân,
/// không nhằm chống tấn công cục bộ quyết liệt. Giao diện giống KeychainHelper để thay 1:1.
enum OTPStore {
    private static let keyDefaultsKey = "otpStoreKey"

    private static let dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let d = base.appendingPathComponent("Clipboard", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        return d
    }()

    private static var fileURL: URL { dir.appendingPathComponent("otp-store.dat") }

    /// Khóa mã hóa: lấy từ UserDefaults, chưa có thì sinh mới (CryptoKit) và lưu lại.
    private static func key() -> SymmetricKey {
        let ud = UserDefaults.standard
        if let b64 = ud.string(forKey: keyDefaultsKey),
           let data = Data(base64Encoded: b64), data.count == 32 {
            return SymmetricKey(data: data)
        }
        let newKey = SymmetricKey(size: .bits256)
        let raw = newKey.withUnsafeBytes { Data($0) }
        ud.set(raw.base64EncodedString(), forKey: keyDefaultsKey)
        return newKey
    }

    private static func loadAll() -> [String: Data] {
        guard let blob = try? Data(contentsOf: fileURL), !blob.isEmpty else { return [:] }
        do {
            let box = try AES.GCM.SealedBox(combined: blob)
            let plain = try AES.GCM.open(box, using: key())
            return try JSONDecoder().decode([String: Data].self, from: plain)
        } catch {
            print("DEBUG: OTPStore đọc lỗi: \(error)")
            return [:]
        }
    }

    private static func saveAll(_ dict: [String: Data]) {
        do {
            let plain = try JSONEncoder().encode(dict)
            let sealed = try AES.GCM.seal(plain, using: key())
            guard let combined = sealed.combined else { return }
            try combined.write(to: fileURL, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            print("DEBUG: OTPStore ghi lỗi: \(error)")
        }
    }

    @discardableResult
    static func save(_ data: Data, account: String) -> Bool {
        var d = loadAll()
        d[account] = data
        saveAll(d)
        return true
    }

    static func load(account: String) -> Data? {
        loadAll()[account]
    }

    @discardableResult
    static func delete(account: String) -> Bool {
        var d = loadAll()
        d[account] = nil
        saveAll(d)
        return true
    }
}
