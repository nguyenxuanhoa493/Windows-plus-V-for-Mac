# OTP Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an integrated TOTP authenticator to the Clipboard menu-bar app — OTP entries (name + base32 secret) added by manual entry / QR image / screen-region capture, gated behind PIN or Touch ID, searchable by name, with encrypted manual export/import as "cloud sync".

**Architecture:** New `OTPManager.shared` singleton (parallel to `ClipboardManager.shared`) persists an `[OTPItem]` array as one JSON blob in macOS Keychain. TOTP codes are computed on demand with CryptoKit (RFC 6238). The OTP UI is a second tab inside the existing cursor popup (`ClipboardHistoryView`), guarded by a lock screen (Touch ID via `LAContext`, fallback 6-digit PIN). Add/edit/QR/export live in a separate management window (like Settings). Export/import is an AES-GCM file encrypted with a PBKDF2-derived key from the PIN.

**Tech Stack:** Swift / SwiftUI / AppKit. System frameworks only — CryptoKit (HMAC, AES-GCM), CommonCrypto (PBKDF2), CoreImage (`CIDetector` QR), LocalAuthentication (`LAContext`), Security (Keychain `SecItem`). No new SwiftPM dependency.

---

## Testing note (read first)

This repo has **no test target** — `swift test` does nothing and Package.swift defines only the executable. Do not add a test target (it would diverge from the build scripts). Instead:

- **Pure-logic correctness** (Base32, TOTP, PBKDF2+AES-GCM round-trip) is verified by `#if DEBUG` self-check functions that assert against known vectors and `print("DEBUG: …")` PASS/FAIL. They are called once from `applicationDidFinishLaunching` behind `#if DEBUG`.
- **Compile gate:** every task ends with `swift build` (must succeed) — this is the "run the test" step for UI/integration work.
- **Manual QA:** UI tasks list explicit click-through steps to run with `./run_debug.sh`.

Keep all comments and `print("DEBUG: …")` logs in **Vietnamese** per repo convention.

---

## File structure

| File | Responsibility |
|---|---|
| `Sources/KeychainHelper.swift` | Thin `SecItem` wrapper: save/load/delete a `Data` blob by service+account. |
| `Sources/OTPItem.swift` | `OTPItem` model, `OTPAlgorithm`, Base32 decode, RFC 6238 `code(at:)`, `otpauth://` parser. |
| `Sources/OTPCrypto.swift` | PBKDF2 (CommonCrypto) + AES-GCM (CryptoKit) encrypt/decrypt of the export blob, with file header. |
| `Sources/OTPAuth.swift` | PIN setup/verify (salted SHA256 in Keychain), Touch ID via `LAContext`, lockout after 5 fails. |
| `Sources/OTPManager.swift` | `OTPManager.shared`: persist list to Keychain, CRUD, search, unlock state + grace period, export/import. |
| `Sources/QRDecoder.swift` | Decode QR from `NSImage`/file URL; run `screencapture -i` then decode. |
| `Sources/OTPView.swift` | Popup OTP tab: lock screen → list + search + countdown. |
| `Sources/OTPManagerView.swift` | Management window content: list, add (manual/QR/screen), edit, delete, export, import. |
| `Sources/OTPManagerWindow.swift` | `NSWindow` host for `OTPManagerView` (singleton, like `SettingsWindow`). |
| `Sources/Settings.swift` (modify) | Add `enableOTP`, `otpGracePeriodMinutes`. |
| `Sources/Localization.swift` (modify) | Add vi/en strings for all OTP UI. |
| `Sources/SettingsView.swift` (modify) | Add `enableOTP` toggle + grace-period picker to Features tab. |
| `Sources/ClipboardHistoryView.swift` (modify) | Add top `Clipboard | OTP` tab switcher; render `OTPView` when on OTP tab. |
| `Sources/ClipboardApp.swift` (modify) | Wire OTP into `applyPanelContent`, status menu "Manage OTP", DEBUG self-checks. |

---

## Task 1: KeychainHelper

**Files:**
- Create: `Sources/KeychainHelper.swift`

- [ ] **Step 1: Create the wrapper**

```swift
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
```

- [ ] **Step 2: Compile gate**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/KeychainHelper.swift
git commit -m "feat(otp): thêm KeychainHelper wrapper cho generic password"
```

---

## Task 2: OTPItem model + Base32 + TOTP + otpauth parser

**Files:**
- Create: `Sources/OTPItem.swift`

- [ ] **Step 1: Create the model and logic**

```swift
import Foundation
import CryptoKit

enum OTPAlgorithm: String, Codable, CaseIterable {
    case sha1, sha256, sha512
}

/// Một mục OTP (TOTP). Secret lưu dạng base32 (không padding, in hoa).
struct OTPItem: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var issuer: String?
    var secret: String
    var algorithm: OTPAlgorithm
    var digits: Int
    var period: Int
    let createdAt: Date

    init(id: UUID = UUID(), name: String, issuer: String? = nil, secret: String,
         algorithm: OTPAlgorithm = .sha1, digits: Int = 6, period: Int = 30,
         createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.issuer = issuer
        self.secret = secret
        self.algorithm = algorithm
        self.digits = digits
        self.period = period
        self.createdAt = createdAt
    }

    /// Mã TOTP tại thời điểm `date`. Trả về chuỗi đã pad 0 đủ `digits`,
    /// hoặc nil nếu secret base32 không hợp lệ.
    func code(at date: Date = Date()) -> String? {
        guard let key = OTPItem.base32Decode(secret) else { return nil }
        let counter = UInt64(floor(date.timeIntervalSince1970 / Double(period)))
        var bigEndian = counter.bigEndian
        let counterData = Data(bytes: &bigEndian, count: 8)
        let symKey = SymmetricKey(data: key)

        let hash: [UInt8]
        switch algorithm {
        case .sha1:   hash = Array(HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: symKey))
        case .sha256: hash = Array(HMAC<SHA256>.authenticationCode(for: counterData, using: symKey))
        case .sha512: hash = Array(HMAC<SHA512>.authenticationCode(for: counterData, using: symKey))
        }

        let offset = Int(hash[hash.count - 1] & 0x0f)
        let binary = (UInt32(hash[offset] & 0x7f) << 24)
            | (UInt32(hash[offset + 1]) << 16)
            | (UInt32(hash[offset + 2]) << 8)
            | UInt32(hash[offset + 3])
        let mod = UInt32(pow(10.0, Double(digits)))
        let otp = binary % mod
        return String(format: "%0\(digits)u", otp)
    }

    /// Số giây còn lại của chu kỳ hiện tại (để vẽ countdown).
    func secondsRemaining(at date: Date = Date()) -> Int {
        let p = Double(period)
        return Int(p - date.timeIntervalSince1970.truncatingRemainder(dividingBy: p))
    }

    // MARK: - Base32 (RFC 4648, không padding, in hoa)
    static func base32Decode(_ string: String) -> Data? {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        var lookup = [Character: UInt8]()
        for (i, c) in alphabet.enumerated() { lookup[c] = UInt8(i) }

        let cleaned = string.uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "=", with: "")
        guard !cleaned.isEmpty else { return nil }

        var bits = 0
        var value = 0
        var output = [UInt8]()
        for c in cleaned {
            guard let v = lookup[c] else { return nil }
            value = (value << 5) | Int(v)
            bits += 5
            if bits >= 8 {
                bits -= 8
                output.append(UInt8((value >> bits) & 0xff))
            }
        }
        return Data(output)
    }

    // MARK: - otpauth:// parser
    /// Parse `otpauth://totp/Label?secret=...&issuer=...&algorithm=...&digits=...&period=...`
    static func parse(otpauthURI uri: String) -> OTPItem? {
        guard let comps = URLComponents(string: uri),
              comps.scheme?.lowercased() == "otpauth",
              comps.host?.lowercased() == "totp" else { return nil }

        let items = comps.queryItems ?? []
        func q(_ k: String) -> String? { items.first(where: { $0.name.lowercased() == k })?.value }

        guard let secret = q("secret"), !secret.isEmpty else { return nil }

        // Label = phần path sau "/", có thể là "Issuer:account".
        var label = comps.path
        if label.hasPrefix("/") { label.removeFirst() }
        label = label.removingPercentEncoding ?? label

        var issuer = q("issuer")
        var name = label
        if label.contains(":") {
            let parts = label.split(separator: ":", maxSplits: 1).map(String.init)
            if issuer == nil { issuer = parts[0].trimmingCharacters(in: .whitespaces) }
            name = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : label
        }
        if name.isEmpty { name = issuer ?? "OTP" }

        let algorithm = OTPAlgorithm(rawValue: (q("algorithm") ?? "sha1").lowercased()) ?? .sha1
        let digits = Int(q("digits") ?? "6") ?? 6
        let period = Int(q("period") ?? "30") ?? 30

        return OTPItem(name: name, issuer: issuer, secret: secret.uppercased(),
                       algorithm: algorithm, digits: digits, period: period)
    }

    #if DEBUG
    /// Self-check RFC 6238 + base32. Gọi 1 lần lúc launch (DEBUG). Log PASS/FAIL.
    static func runSelfCheck() {
        // Secret RFC 6238 SHA1 = ASCII "12345678901234567890" → base32:
        let secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
        let cases: [(TimeInterval, String)] = [
            (59, "94287082"),
            (1111111109, "07081804"),
            (1234567890, "89005924")
        ]
        let item = OTPItem(name: "test", secret: secret, algorithm: .sha1, digits: 8, period: 30)
        var ok = true
        for (t, expected) in cases {
            let got = item.code(at: Date(timeIntervalSince1970: t)) ?? "nil"
            if got != expected { ok = false; print("DEBUG: OTP self-check FAIL t=\(t) got=\(got) expected=\(expected)") }
        }
        print("DEBUG: OTP RFC6238 self-check: \(ok ? "PASS" : "FAIL")")
    }
    #endif
}
```

- [ ] **Step 2: Compile gate**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: Wire the self-check temporarily and verify**

Temporarily add to `AppDelegate.applicationDidFinishLaunching` (top of the method, after `print("DEBUG: Ứng dụng đang khởi động...")`):

```swift
#if DEBUG
OTPItem.runSelfCheck()
#endif
```

Run: `./run_debug.sh` then check console output.
Expected: `DEBUG: OTP RFC6238 self-check: PASS`

(Keep this DEBUG call — Task 11 adds the other self-checks beside it.)

- [ ] **Step 4: Commit**

```bash
git add Sources/OTPItem.swift Sources/ClipboardApp.swift
git commit -m "feat(otp): model OTPItem + base32 + TOTP RFC6238 + otpauth parser"
```

---

## Task 3: OTPCrypto (PBKDF2 + AES-GCM export blob)

**Files:**
- Create: `Sources/OTPCrypto.swift`

- [ ] **Step 1: Create the crypto box**

```swift
import Foundation
import CryptoKit
import CommonCrypto

/// Mã hóa/giải mã blob export OTP. Khóa AES-256 dẫn xuất từ passphrase (PIN)
/// bằng PBKDF2-HMAC-SHA256. File format (binary):
///   magic "COTP" (4B) | version 1 (1B) | iterations UInt32 BE (4B)
///   | salt (16B) | AES.GCM.combined (nonce 12B + ciphertext + tag 16B)
enum OTPCrypto {
    static let magic: [UInt8] = Array("COTP".utf8)
    static let version: UInt8 = 1
    static let iterations: UInt32 = 600_000
    static let saltLength = 16
    static let keyLength = 32

    enum CryptoError: Error { case badFormat, wrongPassphrase, derivation }

    static func deriveKey(passphrase: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        var derived = Data(count: keyLength)
        let pwData = Data(passphrase.utf8)
        let status = derived.withUnsafeMutableBytes { derivedPtr in
            salt.withUnsafeBytes { saltPtr in
                pwData.withUnsafeBytes { pwPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pwPtr.baseAddress, pwData.count,
                        saltPtr.bindMemory(to: UInt8.self).baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        derivedPtr.bindMemory(to: UInt8.self).baseAddress, keyLength
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw CryptoError.derivation }
        return SymmetricKey(data: derived)
    }

    static func encrypt(_ items: [OTPItem], passphrase: String) throws -> Data {
        let plaintext = try JSONEncoder().encode(items)
        var salt = Data(count: saltLength)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, saltLength, $0.baseAddress!) }
        let key = try deriveKey(passphrase: passphrase, salt: salt, iterations: iterations)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw CryptoError.badFormat }

        var out = Data()
        out.append(contentsOf: magic)
        out.append(version)
        var iterBE = iterations.bigEndian
        out.append(Data(bytes: &iterBE, count: 4))
        out.append(salt)
        out.append(combined)
        return out
    }

    static func decrypt(_ data: Data, passphrase: String) throws -> [OTPItem] {
        var idx = 0
        func take(_ n: Int) throws -> Data {
            guard idx + n <= data.count else { throw CryptoError.badFormat }
            defer { idx += n }
            return data.subdata(in: idx..<(idx + n))
        }
        guard Array(try take(4)) == magic else { throw CryptoError.badFormat }
        let ver = try take(1).first ?? 0
        guard ver == version else { throw CryptoError.badFormat }
        let iterBE = try take(4).withUnsafeBytes { $0.load(as: UInt32.self) }
        let iters = UInt32(bigEndian: iterBE)
        let salt = try take(saltLength)
        let combined = data.subdata(in: idx..<data.count)

        let key = try deriveKey(passphrase: passphrase, salt: salt, iterations: iters)
        let box: AES.GCM.SealedBox
        do { box = try AES.GCM.SealedBox(combined: combined) }
        catch { throw CryptoError.badFormat }
        let plaintext: Data
        do { plaintext = try AES.GCM.open(box, using: key) }
        catch { throw CryptoError.wrongPassphrase }
        return try JSONDecoder().decode([OTPItem].self, from: plaintext)
    }

    #if DEBUG
    static func runSelfCheck() {
        let items = [OTPItem(name: "acc", issuer: "Demo", secret: "JBSWY3DPEHPK3PXP")]
        do {
            let blob = try encrypt(items, passphrase: "123456")
            let back = try decrypt(blob, passphrase: "123456")
            let ok = back == items
            print("DEBUG: OTPCrypto round-trip self-check: \(ok ? "PASS" : "FAIL")")
            // Sai passphrase phải ném lỗi.
            var wrongRejected = false
            do { _ = try decrypt(blob, passphrase: "000000") } catch { wrongRejected = true }
            print("DEBUG: OTPCrypto wrong-passphrase reject: \(wrongRejected ? "PASS" : "FAIL")")
        } catch {
            print("DEBUG: OTPCrypto self-check FAIL: \(error)")
        }
    }
    #endif
}
```

- [ ] **Step 2: Compile gate**

Run: `swift build`
Expected: builds. If `import CommonCrypto` fails, confirm toolchain — modern Swift on macOS imports it directly; no bridging header needed.

- [ ] **Step 3: Commit**

```bash
git add Sources/OTPCrypto.swift
git commit -m "feat(otp): OTPCrypto PBKDF2 + AES-GCM export blob"
```

---

## Task 4: OTPAuth (PIN + Touch ID + lockout)

**Files:**
- Create: `Sources/OTPAuth.swift`

- [ ] **Step 1: Create auth helper**

```swift
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
```

- [ ] **Step 2: Compile gate**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/OTPAuth.swift
git commit -m "feat(otp): OTPAuth PIN salted-hash + Touch ID + lockout"
```

---

## Task 5: OTPManager (persist, CRUD, search, unlock, export/import)

**Files:**
- Create: `Sources/OTPManager.swift`

- [ ] **Step 1: Create the singleton**

```swift
import Foundation
import Combine

extension Notification.Name {
    static let otpListChanged = Notification.Name("otpListChanged")
}

/// Nguồn sự thật cho OTP. Lưu list mã hóa trong Keychain (1 blob JSON).
/// Quản lý trạng thái mở khóa (grace period) — chỉ ảnh hưởng khu vực OTP.
final class OTPManager: ObservableObject {
    static let shared = OTPManager()

    private let listAccount = "com.xuanhoa.clipboard.otp"
    @Published private(set) var items: [OTPItem] = []
    private var unlockedUntil: Date?

    private init() {
        loadList()
    }

    // MARK: - Persistence
    private func loadList() {
        guard let data = KeychainHelper.load(account: listAccount),
              let decoded = try? JSONDecoder().decode([OTPItem].self, from: data) else {
            items = []
            return
        }
        items = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        KeychainHelper.save(data, account: listAccount)
        NotificationCenter.default.post(name: .otpListChanged, object: nil)
    }

    // MARK: - CRUD
    func add(_ item: OTPItem) {
        // Chống trùng theo secret (bỏ qua nếu đã có secret giống hệt).
        guard !items.contains(where: { $0.secret == item.secret }) else {
            print("DEBUG: OTP trùng secret, bỏ qua add")
            return
        }
        items.insert(item, at: 0)
        persist()
    }

    func update(_ item: OTPItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx] = item
        persist()
    }

    func delete(_ item: OTPItem) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    /// Merge list import vào list hiện có, chống trùng theo secret. Trả số mục mới thêm.
    @discardableResult
    func merge(_ imported: [OTPItem]) -> Int {
        var added = 0
        for item in imported where !items.contains(where: { $0.secret == item.secret }) {
            items.append(item)
            added += 1
        }
        if added > 0 { persist() }
        return added
    }

    /// Tìm theo tên/issuer, bỏ dấu tiếng Việt.
    func search(_ query: String) -> [OTPItem] {
        guard !query.isEmpty else { return items }
        let q = query.folding(options: .diacriticInsensitive, locale: Locale(identifier: "vi")).lowercased()
        return items.filter { item in
            let name = item.name.folding(options: .diacriticInsensitive, locale: Locale(identifier: "vi")).lowercased()
            let iss = (item.issuer ?? "").folding(options: .diacriticInsensitive, locale: Locale(identifier: "vi")).lowercased()
            return name.contains(q) || iss.contains(q)
        }
    }

    // MARK: - Unlock state (grace period)
    var isUnlocked: Bool {
        if let until = unlockedUntil, until > Date() { return true }
        return false
    }

    func markUnlocked() {
        let minutes = Settings.shared.otpGracePeriodMinutes
        unlockedUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
    }

    func lock() { unlockedUntil = nil }

    // MARK: - Export / Import (dùng PIN làm passphrase)
    func exportData(pin: String) throws -> Data {
        try OTPCrypto.encrypt(items, passphrase: pin)
    }

    @discardableResult
    func importData(_ data: Data, pin: String) throws -> Int {
        let imported = try OTPCrypto.decrypt(data, passphrase: pin)
        return merge(imported)
    }
}
```

- [ ] **Step 2: Compile gate**

Run: `swift build`
Expected: fails — `Settings.shared.otpGracePeriodMinutes` does not exist yet. That is expected; Task 6 adds it. To keep this task self-contained, temporarily hardcode:

In `markUnlocked()`, replace `let minutes = Settings.shared.otpGracePeriodMinutes` with `let minutes = 5` for now, build to confirm the rest compiles, then revert to `Settings.shared.otpGracePeriodMinutes` after Task 6.

Run: `swift build` (with the temporary `let minutes = 5`)
Expected: builds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/OTPManager.swift
git commit -m "feat(otp): OTPManager persist/CRUD/search/unlock/export-import"
```

---

## Task 6: Settings + Localization

**Files:**
- Modify: `Sources/Settings.swift`
- Modify: `Sources/Localization.swift`

- [ ] **Step 1: Add Settings properties**

In `Sources/Settings.swift`, after the `showItemInfoLine` property block (ends at `Sources/Settings.swift:255`), add:

```swift
    /// Bật khu vực quản lý OTP (tab OTP trong popup + menu Quản lý OTP).
    @Published var enableOTP: Bool {
        didSet { UserDefaults.standard.set(enableOTP, forKey: "feature_enableOTP") }
    }

    /// Thời gian giữ mở khóa OTP (phút) trước khi hỏi lại PIN/Touch ID.
    @Published var otpGracePeriodMinutes: Int {
        didSet { UserDefaults.standard.set(otpGracePeriodMinutes, forKey: "otpGracePeriodMinutes") }
    }
```

- [ ] **Step 2: Initialize them**

In `Sources/Settings.swift`, in `init()` after the line `self.showItemInfoLine = loadBool("feature_showItemInfoLine", default: true)` (`Sources/Settings.swift:398`), add:

```swift
        self.enableOTP = loadBool("feature_enableOTP", default: true)
        let savedGrace = UserDefaults.standard.integer(forKey: "otpGracePeriodMinutes")
        self.otpGracePeriodMinutes = [1, 5, 15].contains(savedGrace) ? savedGrace : 5
```

- [ ] **Step 3: Revert the Task 5 temporary hardcode**

In `Sources/OTPManager.swift` `markUnlocked()`, change `let minutes = 5` back to:

```swift
        let minutes = Settings.shared.otpGracePeriodMinutes
```

- [ ] **Step 4: Add localization strings**

In `Sources/Localization.swift`, inside the `translations` dictionary, before the final entry `"clear_dialog_cancel"` (`Sources/Localization.swift:164`), insert:

```swift
        // OTP
        "otp_tab": [.english: "OTP", .vietnamese: "OTP"],
        "clipboard_tab": [.english: "Clipboard", .vietnamese: "Clipboard"],
        "otp_feature_enable": [.english: "OTP manager (2FA codes)", .vietnamese: "Quản lý OTP (mã 2FA)"],
        "otp_grace_period": [.english: "OTP unlock duration", .vietnamese: "Thời gian giữ mở khóa OTP"],
        "otp_grace_1": [.english: "1 minute", .vietnamese: "1 phút"],
        "otp_grace_5": [.english: "5 minutes", .vietnamese: "5 phút"],
        "otp_grace_15": [.english: "15 minutes", .vietnamese: "15 phút"],
        "otp_unlock_title": [.english: "OTP is locked", .vietnamese: "OTP đang khóa"],
        "otp_unlock_touchid": [.english: "Unlock with Touch ID", .vietnamese: "Mở khóa bằng Touch ID"],
        "otp_unlock_reason": [.english: "Unlock your OTP codes", .vietnamese: "Mở khóa danh sách mã OTP"],
        "otp_enter_pin": [.english: "Enter 6-digit PIN", .vietnamese: "Nhập mã PIN 6 số"],
        "otp_setup_pin_title": [.english: "Set a 6-digit PIN", .vietnamese: "Đặt mã PIN 6 số"],
        "otp_setup_pin_confirm": [.english: "Confirm PIN", .vietnamese: "Xác nhận PIN"],
        "otp_pin_mismatch": [.english: "PINs do not match", .vietnamese: "PIN không khớp"],
        "otp_pin_wrong": [.english: "Wrong PIN", .vietnamese: "Sai PIN"],
        "otp_locked_out": [.english: "Too many attempts. Try again in %ds", .vietnamese: "Sai quá nhiều lần. Thử lại sau %d giây"],
        "otp_search_placeholder": [.english: "Search OTP...", .vietnamese: "Tìm OTP..."],
        "otp_empty": [.english: "No OTP yet. Use 'Manage OTP' to add.", .vietnamese: "Chưa có OTP. Dùng 'Quản lý OTP' để thêm."],
        "otp_copied": [.english: "Code copied", .vietnamese: "Đã copy mã"],
        "otp_manage": [.english: "Manage OTP", .vietnamese: "Quản lý OTP"],
        "otp_add": [.english: "Add OTP", .vietnamese: "Thêm OTP"],
        "otp_name": [.english: "Name", .vietnamese: "Tên"],
        "otp_issuer": [.english: "Issuer (optional)", .vietnamese: "Nhà cung cấp (tùy chọn)"],
        "otp_secret": [.english: "Secret key (base32)", .vietnamese: "Khóa bí mật (base32)"],
        "otp_advanced": [.english: "Advanced", .vietnamese: "Nâng cao"],
        "otp_algorithm": [.english: "Algorithm", .vietnamese: "Thuật toán"],
        "otp_digits": [.english: "Digits", .vietnamese: "Số chữ số"],
        "otp_period": [.english: "Period (s)", .vietnamese: "Chu kỳ (giây)"],
        "otp_add_manual": [.english: "Manual entry", .vietnamese: "Nhập tay"],
        "otp_add_qr_image": [.english: "From QR image", .vietnamese: "Từ ảnh QR"],
        "otp_add_screen": [.english: "Capture screen region", .vietnamese: "Chọn vùng màn hình"],
        "otp_save": [.english: "Save", .vietnamese: "Lưu"],
        "otp_cancel": [.english: "Cancel", .vietnamese: "Hủy"],
        "otp_delete": [.english: "Delete", .vietnamese: "Xóa"],
        "otp_edit": [.english: "Edit", .vietnamese: "Sửa"],
        "otp_invalid_secret": [.english: "Invalid base32 secret", .vietnamese: "Khóa base32 không hợp lệ"],
        "otp_qr_not_found": [.english: "No valid QR code found", .vietnamese: "Không tìm thấy mã QR hợp lệ"],
        "otp_export": [.english: "Export (encrypted)", .vietnamese: "Xuất (mã hóa)"],
        "otp_import": [.english: "Import", .vietnamese: "Nhập"],
        "otp_export_warning": [.english: "The file is encrypted with your 6-digit PIN. Keep it safe; losing the PIN means losing the data.", .vietnamese: "File được mã hóa bằng PIN 6 số của bạn. Giữ file an toàn; mất PIN là mất dữ liệu."],
        "otp_import_done": [.english: "Imported %d new item(s)", .vietnamese: "Đã nhập %d mục mới"],
        "otp_import_failed": [.english: "Import failed: wrong PIN or corrupt file", .vietnamese: "Nhập thất bại: sai PIN hoặc file hỏng"],
```

- [ ] **Step 5: Compile gate**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 6: Commit**

```bash
git add Sources/Settings.swift Sources/Localization.swift Sources/OTPManager.swift
git commit -m "feat(otp): Settings enableOTP/gracePeriod + localization strings"
```

---

## Task 7: QRDecoder

**Files:**
- Create: `Sources/QRDecoder.swift`

- [ ] **Step 1: Create the decoder**

```swift
import Foundation
import AppKit
import CoreImage

/// Giải mã QR từ ảnh hoặc từ vùng màn hình do người dùng chọn.
enum QRDecoder {
    /// Decode chuỗi QR đầu tiên trong ảnh. Trả nil nếu không có QR.
    static func decode(image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation,
              let ci = CIImage(data: tiff) else { return nil }
        return decode(ciImage: ci)
    }

    static func decode(fileURL: URL) -> String? {
        guard let ci = CIImage(contentsOf: fileURL) else { return nil }
        return decode(ciImage: ci)
    }

    private static func decode(ciImage: CIImage) -> String? {
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                  options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let features = detector?.features(in: ciImage) ?? []
        for f in features {
            if let qr = f as? CIQRCodeFeature, let msg = qr.messageString, !msg.isEmpty {
                return msg
            }
        }
        return nil
    }

    /// Chạy `screencapture -i` cho người dùng chọn vùng, rồi decode QR.
    /// Không cần quyền Screen Recording vì dùng tiện ích hệ thống.
    /// completion(nil) nếu người dùng hủy hoặc không thấy QR.
    static func captureScreenRegion(completion: @escaping (String?) -> Void) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("otp-qr-\(UUID().uuidString).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", tmp.path]
        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                defer { try? FileManager.default.removeItem(at: tmp) }
                guard FileManager.default.fileExists(atPath: tmp.path) else {
                    completion(nil); return   // người dùng nhấn Esc
                }
                completion(decode(fileURL: tmp))
            }
        }
        do {
            try process.run()
        } catch {
            print("DEBUG: screencapture lỗi: \(error)")
            completion(nil)
        }
    }
}
```

- [ ] **Step 2: Compile gate**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/QRDecoder.swift
git commit -m "feat(otp): QRDecoder ảnh + chọn vùng màn hình qua screencapture"
```

---

## Task 8: OTPView (popup OTP tab)

**Files:**
- Create: `Sources/OTPView.swift`

This view is shown inside the popup when the OTP tab is active. It owns the lock screen and the unlocked list. It calls `onPasteCode` to paste a selected code (wired in Task 10).

- [ ] **Step 1: Create the view**

```swift
import SwiftUI

struct OTPView: View {
    /// Gọi khi người dùng chọn 1 mã để paste (đóng popup + auto-paste).
    let onPasteCode: (String) -> Void
    /// Mở cửa sổ quản lý OTP.
    let onManage: () -> Void

    @ObservedObject private var manager = OTPManager.shared
    @ObservedObject private var settings = Settings.shared
    private let auth = OTPAuth.shared

    @State private var unlocked = OTPManager.shared.isUnlocked
    @State private var searchText = ""
    @State private var pin = ""
    @State private var confirmPin = ""
    @State private var errorMessage = ""
    @State private var now = Date()
    @State private var lockoutRemaining = 0

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            if unlocked {
                unlockedContent
            } else if !auth.hasPIN {
                setupPinScreen
            } else {
                lockScreen
            }
        }
        .background(settings.themedBackground)
        .onReceive(ticker) { date in
            now = date
            lockoutRemaining = auth.lockoutRemaining
        }
        .onAppear { attemptBiometrics() }
    }

    // MARK: - Unlocked list
    private var unlockedContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField(Localization.shared.localizedString("otp_search_placeholder"), text: $searchText)
                    .textFieldStyle(.plain)
                Button(action: onManage) {
                    Image(systemName: "gearshape")
                }.buttonStyle(.plain).tooltip(Localization.shared.localizedString("otp_manage"))
            }
            .padding(10)

            let list = manager.search(searchText)
            if list.isEmpty {
                Spacer()
                Text(Localization.shared.localizedString("otp_empty"))
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .multilineTextAlignment(.center).padding()
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(list) { item in
                            otpRow(item)
                        }
                    }.padding(.horizontal, 8).padding(.bottom, 8)
                }
            }
        }
    }

    private func otpRow(_ item: OTPItem) -> some View {
        let code = item.code(at: now) ?? "------"
        let remaining = item.secondsRemaining(at: now)
        return Button(action: { onPasteCode(code) }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.system(size: 12, weight: .medium))
                        .foregroundColor(settings.themedForeground)
                    if let iss = item.issuer, !iss.isEmpty {
                        Text(iss).font(.system(size: 10)).foregroundColor(.secondary)
                    }
                }
                Spacer()
                Text(code)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundColor(settings.themedAccent)
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: CGFloat(remaining) / CGFloat(item.period))
                        .stroke(settings.themedAccent, lineWidth: 2)
                        .rotationEffect(.degrees(-90))
                    Text("\(remaining)").font(.system(size: 9))
                }.frame(width: 22, height: 22)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(settings.themedSurface))
        }.buttonStyle(.plain)
    }

    // MARK: - Lock screen
    private var lockScreen: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lock.fill").font(.system(size: 32)).foregroundColor(.secondary)
            Text(Localization.shared.localizedString("otp_unlock_title")).font(.system(size: 13, weight: .medium))

            SecureField(Localization.shared.localizedString("otp_enter_pin"), text: $pin)
                .textFieldStyle(.roundedBorder).frame(width: 180)
                .onChange(of: pin) { v in
                    if v.count >= 6 { submitPIN() }
                }

            if auth.biometricsAvailable {
                Button(action: attemptBiometrics) {
                    Label(Localization.shared.localizedString("otp_unlock_touchid"), systemImage: "touchid")
                }
            }
            if !errorMessage.isEmpty {
                Text(errorMessage).font(.system(size: 11)).foregroundColor(.red)
            }
            if lockoutRemaining > 0 {
                Text(String(format: Localization.shared.localizedString("otp_locked_out"), lockoutRemaining))
                    .font(.system(size: 11)).foregroundColor(.orange)
            }
            Spacer()
        }.padding()
    }

    // MARK: - Setup PIN
    private var setupPinScreen: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lock.shield").font(.system(size: 32)).foregroundColor(.secondary)
            Text(Localization.shared.localizedString("otp_setup_pin_title")).font(.system(size: 13, weight: .medium))
            SecureField(Localization.shared.localizedString("otp_enter_pin"), text: $pin)
                .textFieldStyle(.roundedBorder).frame(width: 180)
            SecureField(Localization.shared.localizedString("otp_setup_pin_confirm"), text: $confirmPin)
                .textFieldStyle(.roundedBorder).frame(width: 180)
            if !errorMessage.isEmpty {
                Text(errorMessage).font(.system(size: 11)).foregroundColor(.red)
            }
            Button(Localization.shared.localizedString("otp_save")) { submitNewPIN() }
                .disabled(pin.count != 6 || confirmPin.count != 6)
            Spacer()
        }.padding()
    }

    // MARK: - Actions
    private func attemptBiometrics() {
        guard !unlocked, auth.hasPIN, auth.biometricsAvailable else { return }
        auth.authenticateBiometrics(reason: Localization.shared.localizedString("otp_unlock_reason")) { ok in
            if ok { unlockSucceeded() }
        }
    }

    private func submitPIN() {
        if auth.isLockedOut {
            lockoutRemaining = auth.lockoutRemaining
            pin = ""
            return
        }
        if auth.verifyPIN(pin) {
            unlockSucceeded()
        } else {
            errorMessage = Localization.shared.localizedString("otp_pin_wrong")
            pin = ""
        }
    }

    private func submitNewPIN() {
        guard pin == confirmPin else {
            errorMessage = Localization.shared.localizedString("otp_pin_mismatch"); return
        }
        auth.setPIN(pin)
        unlockSucceeded()
    }

    private func unlockSucceeded() {
        manager.markUnlocked()
        unlocked = true
        pin = ""; confirmPin = ""; errorMessage = ""
    }
}
```

- [ ] **Step 2: Compile gate**

Run: `swift build`
Expected: builds with no errors. (`.tooltip` is the repo's existing `View` extension in `ViewExtensions.swift`.)

- [ ] **Step 3: Commit**

```bash
git add Sources/OTPView.swift
git commit -m "feat(otp): OTPView tab popup (lock screen + list + countdown)"
```

---

## Task 9: OTPManagerView + OTPManagerWindow

**Files:**
- Create: `Sources/OTPManagerView.swift`
- Create: `Sources/OTPManagerWindow.swift`

- [ ] **Step 1: Create the management window host**

Mirror the existing `SettingsWindow` pattern (`Sources/SettingsWindow.swift`). Create `Sources/OTPManagerWindow.swift`:

```swift
import Cocoa
import SwiftUI

/// Cửa sổ riêng quản lý OTP (thêm/sửa/xóa, nhập QR, export/import). Giống SettingsWindow.
final class OTPManagerWindow {
    static let shared = OTPManagerWindow()
    private var window: NSWindow?
    private init() {}

    func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false
        )
        win.title = Localization.shared.localizedString("otp_manage")
        win.center()
        win.isReleasedWhenClosed = false
        win.contentView = NSHostingView(rootView: OTPManagerView())
        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 2: Create the management view**

Create `Sources/OTPManagerView.swift`. The view requires the OTP area to be unlocked (export uses the PIN). If locked, it shows a hint to unlock from the popup first.

```swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct OTPManagerView: View {
    @ObservedObject private var manager = OTPManager.shared
    private let auth = OTPAuth.shared

    @State private var showingAdd = false
    @State private var editingItem: OTPItem?
    @State private var statusMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if manager.items.isEmpty {
                Spacer()
                Text(Localization.shared.localizedString("otp_empty"))
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(manager.items) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.name).font(.system(size: 13, weight: .medium))
                                if let iss = item.issuer, !iss.isEmpty {
                                    Text(iss).font(.system(size: 11)).foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Button(action: { editingItem = item }) { Image(systemName: "pencil") }
                                .buttonStyle(.plain)
                            Button(action: { manager.delete(item) }) { Image(systemName: "trash") }
                                .buttonStyle(.plain).foregroundColor(.red)
                        }
                    }
                }
            }
            if !statusMessage.isEmpty {
                Text(statusMessage).font(.system(size: 11)).foregroundColor(.secondary).padding(6)
            }
        }
        .frame(minWidth: 460, minHeight: 520)
        .sheet(isPresented: $showingAdd) {
            OTPEditSheet(item: nil) { newItem in manager.add(newItem) }
        }
        .sheet(item: $editingItem) { item in
            OTPEditSheet(item: item) { updated in manager.update(updated) }
        }
    }

    private var header: some View {
        HStack {
            Button(action: { showingAdd = true }) {
                Label(Localization.shared.localizedString("otp_add"), systemImage: "plus")
            }
            Spacer()
            Button(Localization.shared.localizedString("otp_export")) { exportTapped() }
            Button(Localization.shared.localizedString("otp_import")) { importTapped() }
        }.padding(10)
    }

    // MARK: - Export / Import
    private func exportTapped() {
        // Yêu cầu PIN (dùng làm passphrase). Nếu chưa có PIN, không cho export.
        guard auth.hasPIN else {
            statusMessage = Localization.shared.localizedString("otp_unlock_title"); return
        }
        let alert = NSAlert()
        alert.messageText = Localization.shared.localizedString("otp_export")
        alert.informativeText = Localization.shared.localizedString("otp_export_warning")
        alert.addButton(withTitle: Localization.shared.localizedString("otp_export"))
        alert.addButton(withTitle: Localization.shared.localizedString("otp_cancel"))
        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.placeholderString = Localization.shared.localizedString("otp_enter_pin")
        alert.accessoryView = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let pin = input.stringValue
        guard auth.verifyPIN(pin) else {
            statusMessage = Localization.shared.localizedString("otp_pin_wrong"); return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "clipboard-otp-backup.enc"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try manager.exportData(pin: pin)
            try data.write(to: url)
            statusMessage = "✅"
        } catch {
            statusMessage = "\(error)"
        }
    }

    private func importTapped() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.data]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let alert = NSAlert()
        alert.messageText = Localization.shared.localizedString("otp_import")
        alert.addButton(withTitle: Localization.shared.localizedString("otp_import"))
        alert.addButton(withTitle: Localization.shared.localizedString("otp_cancel"))
        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.placeholderString = Localization.shared.localizedString("otp_enter_pin")
        alert.accessoryView = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let data = try Data(contentsOf: url)
            let added = try manager.importData(data, pin: input.stringValue)
            statusMessage = String(format: Localization.shared.localizedString("otp_import_done"), added)
        } catch {
            statusMessage = Localization.shared.localizedString("otp_import_failed")
        }
    }
}

/// Sheet thêm/sửa OTP: nhập tay + nút nhập QR ảnh / chọn vùng màn hình.
struct OTPEditSheet: View {
    let item: OTPItem?
    let onSave: (OTPItem) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var issuer = ""
    @State private var secret = ""
    @State private var algorithm: OTPAlgorithm = .sha1
    @State private var digits = 6
    @State private var period = 30
    @State private var showAdvanced = false
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item == nil ? Localization.shared.localizedString("otp_add")
                             : Localization.shared.localizedString("otp_edit"))
                .font(.headline)

            if item == nil {
                HStack {
                    Button(Localization.shared.localizedString("otp_add_qr_image")) { importQRImage() }
                    Button(Localization.shared.localizedString("otp_add_screen")) { captureScreen() }
                }
            }

            TextField(Localization.shared.localizedString("otp_name"), text: $name)
            TextField(Localization.shared.localizedString("otp_issuer"), text: $issuer)
            TextField(Localization.shared.localizedString("otp_secret"), text: $secret)

            DisclosureGroup(Localization.shared.localizedString("otp_advanced"), isExpanded: $showAdvanced) {
                Picker(Localization.shared.localizedString("otp_algorithm"), selection: $algorithm) {
                    ForEach(OTPAlgorithm.allCases, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
                }
                Stepper("\(Localization.shared.localizedString("otp_digits")): \(digits)", value: $digits, in: 6...8)
                Stepper("\(Localization.shared.localizedString("otp_period")): \(period)", value: $period, in: 15...60, step: 15)
            }

            if !error.isEmpty { Text(error).foregroundColor(.red).font(.system(size: 11)) }

            HStack {
                Spacer()
                Button(Localization.shared.localizedString("otp_cancel")) { dismiss() }
                Button(Localization.shared.localizedString("otp_save")) { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16).frame(width: 380)
        .onAppear(perform: loadItem)
    }

    private func loadItem() {
        guard let item = item else { return }
        name = item.name; issuer = item.issuer ?? ""; secret = item.secret
        algorithm = item.algorithm; digits = item.digits; period = item.period
    }

    private func applyParsed(_ parsed: OTPItem) {
        name = parsed.name; issuer = parsed.issuer ?? ""; secret = parsed.secret
        algorithm = parsed.algorithm; digits = parsed.digits; period = parsed.period
    }

    private func importQRImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let msg = QRDecoder.decode(fileURL: url), let parsed = OTPItem.parse(otpauthURI: msg) else {
            error = Localization.shared.localizedString("otp_qr_not_found"); return
        }
        applyParsed(parsed)
    }

    private func captureScreen() {
        QRDecoder.captureScreenRegion { msg in
            guard let msg = msg, let parsed = OTPItem.parse(otpauthURI: msg) else {
                error = Localization.shared.localizedString("otp_qr_not_found"); return
            }
            applyParsed(parsed)
        }
    }

    private func save() {
        let trimmedSecret = secret.uppercased().replacingOccurrences(of: " ", with: "")
        guard OTPItem.base32Decode(trimmedSecret) != nil, !trimmedSecret.isEmpty else {
            error = Localization.shared.localizedString("otp_invalid_secret"); return
        }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            error = Localization.shared.localizedString("otp_name"); return
        }
        let result = OTPItem(
            id: item?.id ?? UUID(),
            name: name, issuer: issuer.isEmpty ? nil : issuer,
            secret: trimmedSecret, algorithm: algorithm, digits: digits, period: period,
            createdAt: item?.createdAt ?? Date()
        )
        onSave(result)
        dismiss()
    }
}
```

- [ ] **Step 3: Compile gate**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 4: Commit**

```bash
git add Sources/OTPManagerView.swift Sources/OTPManagerWindow.swift
git commit -m "feat(otp): cửa sổ quản lý OTP (thêm/sửa/xóa, QR, export/import)"
```

---

## Task 10: Integrate the tab + wire AppDelegate + status menu

**Files:**
- Modify: `Sources/ClipboardHistoryView.swift`
- Modify: `Sources/ClipboardApp.swift`

- [ ] **Step 1: Add the tab switcher to ClipboardHistoryView**

In `Sources/ClipboardHistoryView.swift`, add two stored properties to the `ClipboardHistoryView` struct (after `let onToggleBookmark: ...` at `Sources/ClipboardHistoryView.swift:54`):

```swift
    let onPasteOTP: ((String) -> Void)?
    let onManageOTP: (() -> Void)?
```

Add a tab-selection state next to the other `@State` (after `@State private var selectedIndex: Int = 0` at `Sources/ClipboardHistoryView.swift:63`):

```swift
    @State private var showOTPTab = false
```

Wrap the existing body content with the tab switcher. Change `var body: some View {` (`Sources/ClipboardHistoryView.swift:164`) so the outer `VStack(spacing: 0) {` first renders the tab bar, then branches:

```swift
    var body: some View {
        VStack(spacing: 0) {
            if settings.enableOTP {
                HStack(spacing: 0) {
                    tabButton(titleKey: "clipboard_tab", active: !showOTPTab) { showOTPTab = false }
                    tabButton(titleKey: "otp_tab", active: showOTPTab) { showOTPTab = true }
                }
                .padding(.horizontal, 8).padding(.top, 6)
            }

            if showOTPTab && settings.enableOTP {
                OTPView(
                    onPasteCode: { code in onPasteOTP?(code) },
                    onManage: { onManageOTP?() }
                )
            } else {
                clipboardContent
            }
        }
    }

    @ViewBuilder
    private func tabButton(titleKey: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(Localization.shared.localizedString(titleKey))
                .font(.system(size: 12, weight: active ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(active ? settings.themedAccent.opacity(0.2) : Color.clear)
                .foregroundColor(active ? settings.themedAccent : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain)
    }

    private var clipboardContent: some View {
        VStack(spacing: 0) {
            // ... toàn bộ nội dung cũ của body (filter bar, search bar, ScrollView) chuyển vào đây ...
        }
    }
```

Move the **entire previous content** of `body`'s `VStack(spacing: 0) { ... }` (the filter bar `HStack`, the search bar `if isSearching`, and the `ScrollViewReader`) into `clipboardContent`'s `VStack`. Do not change that inner content — only relocate it.

- [ ] **Step 2: Update all ClipboardHistoryView call sites**

The compiler will flag missing arguments. In `Sources/ClipboardApp.swift`, `applyPanelContent(to:)` (`Sources/ClipboardApp.swift:276-299`) constructs `ClipboardHistoryView(...)`. Add the two new closures to that initializer call, before the closing `)`:

```swift
        }, onPasteOTP: { [weak self, weak panel] code in
            panel?.close()
            self?.handleOTPPaste(code)
        }, onManageOTP: { [weak panel] in
            panel?.close()
            OTPManagerWindow.shared.show()
        })
```

(Adjust so the previous last closure `onToggleBookmark:` ends with `}` and the new ones follow as additional labeled arguments.)

- [ ] **Step 3: Add handleOTPPaste to AppDelegate**

In `Sources/ClipboardApp.swift`, add this method to `AppDelegate` (next to `handleItemSelected`, after `Sources/ClipboardApp.swift:501`):

```swift
    /// Paste 1 mã OTP: copy vào pasteboard rồi auto-paste. ignoreNextChange()
    /// để mã KHÔNG lọt vào lịch sử clipboard (vốn lưu plaintext).
    private func handleOTPPaste(_ code: String) {
        removeEventMonitor()
        if let window = virtualWindow { window.close() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.clipboardManager.ignoreNextChange()
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(code, forType: .string)
            // Giả lập ⌘V (giống ClipboardItem.paste()).
            let src = CGEventSource(stateID: .combinedSessionState)
            let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
            vDown?.flags = .maskCommand
            let vUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
            vUp?.flags = .maskCommand
            vDown?.post(tap: .cghidEventTap)
            vUp?.post(tap: .cghidEventTap)
        }
    }
```

Before writing this, open `Sources/ClipboardItem.swift` and confirm the exact ⌘V synthesis it uses (virtual key, event source, flags). **Match it exactly** so behavior is consistent; if `ClipboardItem` exposes a reusable static paste helper, call that instead of duplicating.

- [ ] **Step 4: Add "Manage OTP" to the status menu**

In `Sources/ClipboardApp.swift`, `setupMenu()` (`Sources/ClipboardApp.swift:142-162`), after the `settingsItem` is added and before the separator, add (guarded by the toggle):

```swift
        if Settings.shared.enableOTP {
            let otpItem = NSMenuItem(title: Localization.shared.localizedString("otp_manage"),
                                     action: #selector(openOTPManager), keyEquivalent: "o")
            otpItem.target = self
            menu.addItem(otpItem)
        }
```

And add the action method to `AppDelegate`:

```swift
    @objc func openOTPManager() {
        OTPManagerWindow.shared.show()
    }
```

- [ ] **Step 5: Compile gate**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 6: Manual QA**

Run: `./run_debug.sh`
Verify:
1. Popup shows `Clipboard | OTP` tabs.
2. OTP tab → setup PIN screen (first run) → set PIN → list appears (empty).
3. Right-click status bar → "Manage OTP" opens window. Add a manual OTP with secret `JBSWY3DPEHPK3PXP`, name "Demo".
4. Back in popup OTP tab → code appears, countdown ticks.
5. Click the OTP row → popup closes, code pastes into the focused field.
6. Close & reopen popup OTP tab within grace period → no PIN asked. (Manual: to test lock, set grace to 1 min in Settings and wait.)

- [ ] **Step 7: Commit**

```bash
git add Sources/ClipboardHistoryView.swift Sources/ClipboardApp.swift
git commit -m "feat(otp): tab OTP trong popup + wire paste/manage + menu status bar"
```

---

## Task 11: Settings UI toggle + grace picker, DEBUG self-checks, QA polish

**Files:**
- Modify: `Sources/SettingsView.swift`
- Modify: `Sources/ClipboardApp.swift`

- [ ] **Step 1: Add the OTP toggle + grace picker to the Features tab**

In `Sources/SettingsView.swift`, in `featuresTab` after the last `featureToggleRow(... "feature_hide_popup_after_drag" ...)` block (ends `Sources/SettingsView.swift:757`), add:

```swift
                featureToggleRow(
                    icon: "lock.shield",
                    titleKey: "otp_feature_enable",
                    isOn: Binding(
                        get: { settings.enableOTP },
                        set: { settings.enableOTP = $0 }
                    )
                )
                if settings.enableOTP {
                    settingsCard {
                        HStack {
                            Label(localization.localizedString("otp_grace_period"), systemImage: "clock")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Picker("", selection: Binding(
                                get: { settings.otpGracePeriodMinutes },
                                set: { settings.otpGracePeriodMinutes = $0 }
                            )) {
                                Text(localization.localizedString("otp_grace_1")).tag(1)
                                Text(localization.localizedString("otp_grace_5")).tag(5)
                                Text(localization.localizedString("otp_grace_15")).tag(15)
                            }
                            .labelsHidden().frame(width: 120)
                        }
                    }
                }
```

- [ ] **Step 2: Wire the remaining DEBUG self-checks**

In `Sources/ClipboardApp.swift`, replace the temporary single self-check from Task 2 with the full block (same location):

```swift
#if DEBUG
OTPItem.runSelfCheck()
OTPCrypto.runSelfCheck()
#endif
```

- [ ] **Step 3: Compile gate**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 4: Run full self-checks**

Run: `./run_debug.sh`
Expected console lines:
```
DEBUG: OTP RFC6238 self-check: PASS
DEBUG: OTPCrypto round-trip self-check: PASS
DEBUG: OTPCrypto wrong-passphrase reject: PASS
```

- [ ] **Step 5: Manual QA — full feature pass**

1. Settings → Features → toggle OTP off → popup hides the OTP tab and status menu hides "Manage OTP". Toggle back on.
2. Add OTP via **QR image**: save a known `otpauth://` QR as PNG, import it — fields auto-fill.
3. Add OTP via **screen region**: display a QR on screen, "Capture screen region", select it — fields auto-fill.
4. **Export**: enter PIN, save `.enc` file. **Import** on the same machine — "Imported 0 new" (dedup) or N for new file.
5. Search OTP by name (Vietnamese diacritics-insensitive).
6. Wrong PIN ×5 → lockout countdown shown.

- [ ] **Step 6: Commit**

```bash
git add Sources/SettingsView.swift Sources/ClipboardApp.swift
git commit -m "feat(otp): Settings toggle + grace picker, DEBUG self-checks"
```

---

## Task 12: Release-bundle verification (entitlements / signing)

**Files:**
- Inspect: `create_app.sh`, `Clipboard.entitlements`

Keychain + Touch ID + `screencapture` all work under the existing ad-hoc signing; no entitlement is strictly required for Touch ID on macOS, and the default keychain needs no `keychain-access-groups`. This task confirms the **bundled** build (not just debug) behaves.

- [ ] **Step 1: Build the real bundle**

Run: `./create_app.sh`
Expected: `Clipboard.app` built and ad-hoc signed with no errors.

- [ ] **Step 2: Manual QA on the bundle**

Launch the built `Clipboard.app`:
1. OTP setup PIN, add an item, get a code, paste it.
2. Touch ID prompt appears on a Touch-ID Mac (skip if hardware absent — PIN path must still work).
3. Export then import round-trips.

If Touch ID fails to present in the bundled app (it works in `run_debug.sh`), add `NSFaceIDUsageDescription` to the generated `Info.plist` in `create_app.sh` (string: "Unlock your OTP codes") and re-test. Only add it if observed necessary.

- [ ] **Step 3: Commit (only if create_app.sh changed)**

```bash
git add -f create_app.sh
git commit -m "chore(otp): Info.plist usage string cho Touch ID (nếu cần)"
```

Note: `.gitignore` excludes `*.sh`; use `git add -f` only if you actually modified `create_app.sh`.

---

## Self-review (completed by plan author)

**Spec coverage:**
- OTP name + key → `OTPItem` (Task 2) ✔
- Manual / QR image / screen region entry → `OTPEditSheet` + `QRDecoder` (Tasks 7, 9) ✔
- PIN or Touch ID on access → `OTPAuth` + `OTPView` lock screen (Tasks 4, 8) ✔
- Grace period (lock only OTP area) → `OTPManager.isUnlocked`/`markUnlocked` + Settings (Tasks 5, 6, 11) ✔
- Search by name (diacritics-insensitive) → `OTPManager.search` + OTPView search field (Tasks 5, 8) ✔
- "Cloud sync" = encrypted export/import → `OTPCrypto` + management window (Tasks 3, 9) ✔
- Auto-paste selected code, no clipboard auto-clear, ignoreNextChange → `handleOTPPaste` (Task 10) ✔
- Keychain storage, secrets never in UserDefaults/history → `KeychainHelper` + `OTPManager` (Tasks 1, 5) ✔
- Tab in existing popup → `ClipboardHistoryView` integration (Task 10) ✔
- Separate management window → `OTPManagerWindow` (Task 9) ✔
- Settings toggle → Task 11 ✔
- Localization vi/en → Task 6 ✔

**Type consistency:** `OTPItem`, `OTPAlgorithm`, `OTPManager.shared` (`add/update/delete/merge/search/markUnlocked/isUnlocked/exportData/importData`), `OTPAuth.shared` (`hasPIN/verifyPIN/setPIN/biometricsAvailable/authenticateBiometrics/isLockedOut/lockoutRemaining`), `OTPCrypto.encrypt/decrypt`, `QRDecoder.decode/captureScreenRegion`, `KeychainHelper.save/load/delete` — names match across all tasks.

**Placeholders:** none — the only intentionally-relocated (not rewritten) code is the existing clipboard body content moved into `clipboardContent` in Task 10 Step 1, explicitly described.
