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
        let ok = KeychainHelper.save(data, account: listAccount)
        if !ok {
            print("DEBUG: OTPManager persist thất bại — không ghi được Keychain")
            return   // state trên bộ nhớ ≠ Keychain → không post notification
        }
        NotificationCenter.default.post(name: .otpListChanged, object: nil)
    }

    // MARK: - CRUD
    /// Trả false nếu trùng secret (không thêm).
    @discardableResult
    func add(_ item: OTPItem) -> Bool {
        guard !items.contains(where: { $0.secret == item.secret }) else {
            print("DEBUG: OTP trùng secret, bỏ qua add")
            return false
        }
        items.insert(item, at: 0)
        persist()
        return true
    }

    /// Trả false nếu không tìm thấy id hoặc secret trùng với item khác.
    @discardableResult
    func update(_ item: OTPItem) -> Bool {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return false }
        // Chống trùng secret với item khác (không phải chính nó).
        guard !items.contains(where: { $0.secret == item.secret && $0.id != item.id }) else {
            print("DEBUG: OTP update — secret trùng với item khác, bỏ qua")
            return false
        }
        items[idx] = item
        persist()
        return true
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
        // Mở khóa cho tới khi thoát app (xác nhận 1 lần mỗi lần mở app).
        unlockedUntil = .distantFuture
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
