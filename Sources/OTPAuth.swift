import Foundation
import CryptoKit
import LocalAuthentication

/// Quản lý PIN (salted SHA256 trong Keychain) + Touch ID + khóa tạm sau nhiều lần sai.
final class OTPAuth {
    static let shared = OTPAuth()
    private init() {}

    private let pinAccount = "com.xuanhoa.clipboard.otp.pin"
    private let maxFailures = 5
    private let lockoutSeconds: TimeInterval = 30

    private var failureCount = 0
    private var lockedUntil: Date?

    /// Cấu trúc lưu trong Keychain cho PIN.
    private struct PINRecord: Codable { var salt: Data; var hash: Data }

    var hasPIN: Bool { KeychainHelper.load(account: pinAccount) != nil }

    var isLockedOut: Bool {
        if let until = lockedUntil, until > Date() { return true }
        return false
    }

    var lockoutRemaining: Int {
        guard let until = lockedUntil, until > Date() else { return 0 }
        return Int(until.timeIntervalSinceNow.rounded(.up))
    }

    // MARK: - PIN
    func setPIN(_ pin: String) {
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let hash = Self.hash(pin: pin, salt: salt)
        let record = PINRecord(salt: salt, hash: hash)
        if let data = try? JSONEncoder().encode(record) {
            KeychainHelper.save(data, account: pinAccount)
        }
        failureCount = 0
        lockedUntil = nil
    }

    /// Trả true nếu PIN đúng. Sai quá nhiều lần → khóa tạm.
    func verifyPIN(_ pin: String) -> Bool {
        guard !isLockedOut,
              let data = KeychainHelper.load(account: pinAccount),
              let record = try? JSONDecoder().decode(PINRecord.self, from: data) else { return false }
        let candidate = Self.hash(pin: pin, salt: record.salt)
        let ok = candidate == record.hash
        if ok {
            failureCount = 0
            lockedUntil = nil
        } else {
            failureCount += 1
            if failureCount >= maxFailures {
                lockedUntil = Date().addingTimeInterval(lockoutSeconds)
                failureCount = 0
                print("DEBUG: OTP PIN sai \(maxFailures) lần → khóa tạm \(Int(lockoutSeconds))s")
            }
        }
        return ok
    }

    private static func hash(pin: String, salt: Data) -> Data {
        var data = salt
        data.append(Data(pin.utf8))
        return Data(SHA256.hash(data: data))
    }

    // MARK: - Touch ID
    var biometricsAvailable: Bool {
        let ctx = LAContext()
        var error: NSError?
        return ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// Gọi Touch ID. completion(true) nếu xác thực thành công.
    func authenticateBiometrics(reason: String, completion: @escaping (Bool) -> Void) {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            completion(false); return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
            DispatchQueue.main.async { completion(success) }
        }
    }
}
