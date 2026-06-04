# Thiết kế: Quản lý OTP (TOTP authenticator) cho Clipboard

- **Ngày:** 2026-06-05
- **Trạng thái:** Đã chốt qua brainstorming, chờ review
- **Phạm vi:** Thêm trình xác thực TOTP tích hợp vào app menu-bar Clipboard, có khóa PIN/Touch ID và xuất/nhập file mã hóa.

## 1. Mục tiêu

Thêm tính năng quản lý mã OTP (TOTP) vào app:

- Mỗi OTP có **tên** và **key** (secret base32).
- Thêm OTP bằng 3 cách: **nhập tay**, **nhập từ ảnh QR**, **chọn vùng màn hình** để quét QR.
- Khóa khu vực OTP bằng **PIN 6 số hoặc Touch ID** mỗi lần truy cập (có grace period).
- **Tìm kiếm** OTP theo tên.
- **"Sync cloud" = Xuất/Nhập file mã hóa thủ công** (không có auto-sync chạy nền).

## 2. Ràng buộc & quyết định nền

- App **ad-hoc signed**, phân phối ngoài App Store. **Không dùng được iCloud / CloudKit / iCloud Keychain** (đòi Apple Developer Team ID + provisioning + ký hợp lệ). Đây là lý do "sync cloud" được hiện thực hóa dưới dạng export/import file mã hóa mà người dùng tự đặt vào thư mục cloud tùy ý.
- **Không thêm dependency mới** — chỉ dùng framework hệ thống (CryptoKit, CommonCrypto, CoreImage, LocalAuthentication, Security/Keychain).
- Bí mật OTP và mã sinh ra **không bao giờ** ghi vào UserDefaults hay lịch sử clipboard (vốn lưu plaintext — xem `feature_privacy_disclaimer`).
- Giữ nguyên UX menu-bar-only: không Dock icon, không đổi `LSUIElement`/`.accessory`.
- Comment và log `print("DEBUG: …")` viết tiếng Việt theo quy ước repo.

## 3. Quyết định thiết kế (đã chốt)

| Hạng mục | Quyết định |
|---|---|
| Phạm vi khóa | Chỉ khóa **khu vực OTP**; clipboard giữ nguyên không cần PIN. |
| Grace period unlock | Mở khóa giữ **5 phút** (chỉnh được ở Settings). Đóng popup **không** khóa ngay. |
| Truy cập OTP | **Tab trong popup clipboard** hiện có: `Clipboard | OTP`. |
| Thêm/sửa OTP | **Cửa sổ quản lý riêng** (giống Settings); tab OTP trong popup chỉ xem/copy + tìm kiếm. |
| Lưu secret + PIN | **macOS Keychain** (generic-password items). |
| Sinh mã TOTP | **CryptoKit** `HMAC` (SHA1/256/512), chuẩn RFC 6238. |
| Giải mã QR | **CoreImage `CIDetector(QRCode)`**. |
| Chọn vùng màn hình | **`/usr/sbin/screencapture -i`** (không cần quyền Screen Recording). |
| Sinh trắc | **LocalAuthentication `LAContext`**, fallback PIN. |
| Sync | **Export/Import file `.enc`** mã hóa AES-GCM, khóa dẫn xuất PBKDF2 từ **PIN**. |
| Chọn mã trong popup | **Auto-paste** (tái dùng cơ chế paste hiện có). |
| Tự xóa clipboard | **Không** (giữ mã đến khi bị ghi đè). |

## 4. Mô hình dữ liệu

```swift
enum OTPAlgorithm: String, Codable { case sha1, sha256, sha512 }   // default sha1

struct OTPItem: Codable, Identifiable {
    let id: UUID
    var name: String
    var issuer: String?
    var secret: String          // base32, KHÔNG padding
    var algorithm: OTPAlgorithm // default .sha1
    var digits: Int             // default 6
    var period: Int             // default 30 (giây)
    let createdAt: Date
}
```

- Toàn bộ `[OTPItem]` được encode JSON và lưu trong **1 item Keychain** key `com.xuanhoa.clipboard.otp`.
- PIN lưu dạng **salted SHA256 hash** (salt ngẫu nhiên 16 byte) trong item Keychain riêng `com.xuanhoa.clipboard.otp.pin`. Lưu kèm salt + số lần sai gần nhất.

## 5. Thành phần mới (file trong `Sources/`)

| File | Vai trò |
|---|---|
| `OTPItem.swift` | Model `OTPItem` + `currentCode(at:)` (RFC 6238) + parse `otpauth://` URI. |
| `OTPManager.swift` | Singleton `OTPManager.shared`: nạp/lưu Keychain, CRUD, tìm kiếm, trạng thái `isUnlocked` + grace period, sinh mã theo timer, export/import. |
| `KeychainHelper.swift` | Wrapper `save/load/delete` cho generic-password (SecItem API). |
| `OTPAuth.swift` | Touch ID qua `LAContext` + setup/verify PIN, đếm số lần sai → khóa tạm 30s sau 5 lần. |
| `QRDecoder.swift` | Decode QR từ `NSImage`/đường dẫn file; gọi `screencapture -i` lấy vùng màn hình rồi decode. |
| `OTPView.swift` | Nội dung tab OTP trong popup: lock screen → list + search + mã đếm ngược. |
| `OTPManagerWindow.swift` + `OTPManagerView.swift` | Cửa sổ riêng: list + thêm/sửa/xóa, nhập tay, "Nhập từ ảnh QR", "Chọn vùng màn hình", Export, Import. |

## 6. Luồng & hành vi

### 6.1 Sinh mã TOTP (RFC 6238)
`T = floor(unixTime / period)`, đóng gói big-endian 8 byte, HMAC với secret (đã decode base32), truncation động lấy `digits` chữ số. Hỗ trợ SHA1/256/512 và `digits`/`period` tùy biến (mặc định 6/30) — các tham số này lấy từ `otpauth://` URI khi quét QR; nhập tay mặc định chuẩn, có mục "nâng cao" để chỉnh.

### 6.2 Khóa & mở khóa
- Mở tab OTP khi `!isUnlocked` → hiện lock screen: tự gọi Touch ID (`LAContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)`); song song có ô nhập PIN 6 số (fallback nếu máy không có Touch ID hoặc người dùng chọn).
- Lần đầu chưa có PIN → màn **thiết lập PIN 6 số** (nhập 2 lần xác nhận) trước khi vào.
- Unlock thành công → đặt `unlockedUntil = now + gracePeriod`. Trong grace period, mở tab OTP không hỏi lại.
- Sai PIN 5 lần → khóa tạm 30s (đếm ngược hiển thị).
- Popup là `.nonactivatingPanel`; khi mở tab OTP phải `makeKeyAndOrderFront` để nhập PIN/typing hoạt động (cursor-mode đã làm vậy; cần bảo đảm cả khi chuyển tab).

### 6.3 Xem & dùng mã
- List OTP: mỗi dòng = tên + issuer + **mã hiện tại** + vòng tròn/thanh **đếm ngược** tới chu kỳ kế. Timer 1s cập nhật UI khi popup mở.
- Ô tìm kiếm theo tên/issuer, **bỏ dấu tiếng Việt** (tái dùng `removeDiacritics` của `ClipboardHistoryView`).
- Chọn 1 OTP → copy mã vào clipboard → **`ignoreNextChange()`** (mã KHÔNG vào lịch sử clipboard) → **auto-paste** qua cơ chế `handleItemSelected`.

### 6.4 Thêm OTP (trong cửa sổ quản lý)
1. **Nhập tay:** form Tên, Secret (base32), (nâng cao: issuer/algorithm/digits/period). Validate base32.
2. **Nhập từ ảnh QR:** `NSOpenPanel` chọn ảnh → `CIDetector` decode → parse `otpauth://` → điền form.
3. **Chọn vùng màn hình:** chạy `screencapture -i -x <tmp.png>` → decode QR từ file tạm → parse → điền form → xóa file tạm.

### 6.5 Export / Import (sync thủ công)
- **Export:** xác thực (đang unlock), gói `[OTPItem]` → JSON → **AES-GCM** với khóa **PBKDF2-HMAC-SHA256 từ PIN** (salt 16 byte ngẫu nhiên, **iterations ~600.000**) → ghi file. Header file chứa: magic/version, salt, iterations, nonce, ciphertext+tag. `NSSavePanel` chọn nơi lưu (mặc định `clipboard-otp-backup.enc`). Hiện **cảnh báo**: "PIN 6 số là khóa yếu; giữ file ở nơi an toàn; mất PIN = mất dữ liệu."
- **Import:** `NSOpenPanel` chọn `.enc` → nhập PIN (hoặc PIN cũ nếu khác máy) → giải mã → **merge** vào list, chống trùng theo `secret` (giữ bản hiện có, bỏ qua trùng; mục mới được thêm).

## 7. Tích hợp UI hiện có

- `ClipboardHistoryView`: thêm thanh tab trên cùng `Clipboard | OTP` (ẩn nếu `enableOTP` tắt). Mặc định Clipboard → behavior cũ không đổi.
- `AppDelegate.applyPanelContent`: dựng cả hai view; khi đang ở tab OTP và chưa unlock, đảm bảo panel là key window.
- Menu status bar (phải-chuột): thêm mục **"Quản lý OTP"** mở `OTPManagerWindow`.
- `SettingsView` tab Features: thêm toggle **`enableOTP`** (mặc định bật) + chọn **grace period** (1/5/15 phút). Thêm khóa localization vi/en cho toàn bộ chuỗi OTP.

## 8. Bảo mật

- Secret & mã OTP chỉ tồn tại trong RAM và Keychain; không vào UserDefaults/clipboard history.
- File export E2E-encrypted (AES-GCM 256-bit); PBKDF2 iterations cao để bù PIN ngắn.
- PIN lưu dạng salted hash, không lưu plaintext.
- Khóa tạm sau nhiều lần sai PIN.
- Keychain & LocalAuthentication hoạt động với app ad-hoc signed; không cần entitlement đặc biệt cho Touch ID trên macOS. Sẽ kiểm tra `Clipboard.entitlements` xem có cần `keychain-access-groups` không (mặc định dùng default keychain thì không cần).

## 9. Kiểm thử

Không có test target. Thêm hàm self-check chạy ở DEBUG so mã với **vector chuẩn RFC 6238** (secret `GEZDGNBVGY3TQOJQ`, t=59 → `94287082`; t=1111111109 → `07081804`) và round-trip encrypt→decrypt export, log qua `print("DEBUG: …")`.

## 10. Ngoài phạm vi (YAGNI)

- Auto-sync chạy nền, tài khoản đám mây, iCloud/CloudKit.
- HOTP (counter-based), Steam Guard, các biến thể không chuẩn.
- Export dạng `otpauth://` plaintext (rủi ro bảo mật).
- Tự xóa clipboard sau khi copy (đã chọn không làm).
