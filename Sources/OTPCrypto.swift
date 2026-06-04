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
