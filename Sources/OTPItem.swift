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
        self.digits = max(1, min(8, digits))   // RFC: 6–8; chặn overflow UInt32 (digits>=10) và digits=0
        self.period = max(1, period)            // chặn chia cho 0 → crash
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
        guard !output.isEmpty else { return nil }   // "A" decode ra 0 byte → secret không hợp lệ
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
            let candidate = parts[0].trimmingCharacters(in: .whitespaces)
            if issuer == nil, !candidate.isEmpty { issuer = candidate }
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
