# CursorKit

[English](README.md) · [Tiếng Việt](README.vi.md) · [Changelog](CHANGELOG.vi.md)

**CursorKit** là app menu-bar cho macOS giúp mở những thứ bạn hay dùng nhất ngay cạnh con trỏ chuột: lịch sử clipboard, file/ảnh vừa copy, công cụ chuyển JSON/Excel, và mã OTP 2FA.

![Giao diện CursorKit](demo/main.png)

## Vì sao dùng CursorKit?

- **Mở ngay tại vị trí con trỏ**: bấm phím tắt, popup xuất hiện ở nơi bạn đang làm việc.
- **Dán nhanh hơn**: chọn item là dán, hoặc dùng `⌘1` đến `⌘9` để dán theo số thứ tự.
- **Nhớ nhiều loại nội dung**: văn bản, RTF/HTML, ảnh, file, folder và URL.
- **Tìm kiếm thông minh**: tìm theo nội dung, tên file, app nguồn; hỗ trợ tiếng Việt không dấu.
- **Lọc gọn**: Tất cả, Văn bản, Hình ảnh, Tệp tin, Bookmark, OTP.
- **Quản lý item**: ghim, bookmark, xoá từng mục, xoá theo loại, kéo thả file/ảnh ra app khác.
- **Công cụ dữ liệu**: xem JSON, chuyển JSON thành bảng, xuất Excel `.xlsx`, chuyển bảng/Excel về JSON.
- **OTP tích hợp**: lưu mã 2FA, mở khoá bằng PIN/Touch ID, import/export backup mã hoá.
- **Tuỳ biến giao diện**: theme sáng/tối, nhiều bảng màu, font, cỡ chữ, hiệu ứng hover, vị trí popup.
- **Tự cập nhật**: kiểm tra GitHub Releases và cài bản mới từ app.

## Tính năng chính

### Clipboard luôn trong tầm tay

CursorKit chạy trên menu-bar và mở bằng phím tắt mặc định `⌃V`. Popup có thể xuất hiện quanh con trỏ theo vị trí bạn chọn trong Settings, nên không cần rê chuột về một góc màn hình.

### Lịch sử clipboard đa định dạng

App lưu lịch sử cho:

- Text thường, RTF, HTML
- Ảnh
- File và folder
- URL
- Dữ liệu dạng bảng copy từ Excel/Numbers

Bạn có thể mở file, copy path, lưu ảnh, kéo thả file/ảnh, hoặc dán lại item vào app đang dùng.

### JSON, bảng và Excel

CursorKit nhận diện JSON và dữ liệu dạng bảng để thao tác nhanh:

- Hiển thị JSON dễ đọc
- Chuyển JSON sang table
- Xuất table sang Excel `.xlsx`
- Chuyển dữ liệu bảng/Excel về JSON

Tính năng này hữu ích khi bạn thường copy API response, payload, log hoặc dữ liệu từ spreadsheet.

### OTP 2FA

Tab OTP cho phép quản lý mã xác thực ngay trong cùng popup:

- Thêm OTP thủ công
- Thêm từ QR trong clipboard
- Tìm kiếm OTP
- Copy mã nhanh
- Khoá bằng PIN 6 số
- Mở khoá bằng Touch ID nếu máy hỗ trợ
- Export/import file backup đã mã hoá
- Tự động backup OTP theo thư mục và chu kỳ bạn chọn

## Yêu cầu hệ thống

- macOS 12.0 Monterey trở lên
- Apple Silicon hoặc Intel
- Quyền Accessibility để auto-paste và đặt popup theo con trỏ hoạt động ổn định

## Cài đặt

1. Tải `CursorKit-4.0.dmg` từ [Releases](https://github.com/nguyenxuanhoa493/Windows-plus-V-for-Mac/releases).
2. Mở DMG và kéo **CursorKit** vào thư mục **Applications**.
3. Nếu macOS chặn app vì chưa notarize, chạy một lần:

   ```bash
   xattr -cr /Applications/CursorKit.app
   ```

4. Mở CursorKit từ Launchpad hoặc Finder.
5. Cấp quyền Accessibility:

   `System Settings → Privacy & Security → Accessibility → CursorKit`

6. Khởi động lại app nếu macOS yêu cầu.

![Cấp quyền Accessibility](demo/image_2.png)

## Cách dùng nhanh

| Thao tác | Phím / hành động |
| --- | --- |
| Mở popup | `⌃V` |
| Chọn item | `↑` / `↓` |
| Dán item đang chọn | `Enter` |
| Dán nhanh theo số | `⌘1` đến `⌘9` |
| Đóng popup | `Esc` |
| Tìm kiếm | Gõ trực tiếp khi popup đang mở |
| Mở menu item | Right-click vào item |
| Kéo thả file/ảnh | Drag item ra Finder hoặc app khác |

Phím tắt có thể đổi trong **Settings → General**.

## Cài đặt nên xem

- **Popup position**: chọn popup xuất hiện ở trên/dưới/trái/phải con trỏ.
- **Appearance**: đổi theme, font, cỡ chữ, hiệu ứng giao diện.
- **Features**: bật/tắt JSON/Excel, URL, timestamp, search, drag-drop, phím số.
- **OTP**: bật/tắt OTP, thời gian tự khoá, backup tự động, mật khẩu backup.
- **Launch at login**: tự chạy CursorKit khi đăng nhập macOS.

## Dữ liệu và riêng tư

- Lịch sử clipboard được lưu cục bộ trên máy.
- Ảnh clipboard được lưu trong cache cục bộ để tránh giữ dữ liệu lớn trong RAM.
- Lịch sử clipboard không được mã hoá, nên không nên lưu mật khẩu hoặc bí mật nhạy cảm trong clipboard lâu dài.
- Dữ liệu OTP được lưu cục bộ và có lớp khoá trong app; file export/import OTP được mã hoá bằng mật khẩu/PIN bạn nhập.

## Build từ source

```bash
swift build
```

Tạo app bundle universal đã ký ad-hoc:

```bash
./create_app.sh
```

Tạo file phát hành:

```bash
./build_all.sh
```

Kết quả chính:

- `CursorKit.app`
- `CursorKit-4.0.dmg`
- `CursorKit-binary.zip`

## Ảnh nên bổ sung

Bạn có thể thay hoặc bổ sung các ảnh sau để README đẹp hơn:

- `demo/main.png`: popup CursorKit đang mở cạnh con trỏ
- `demo/settings.png`: màn Settings, nhất là phần chọn vị trí popup/theme
- `demo/otp.png`: tab OTP sau khi mở khoá
- `demo/json-excel.png`: item JSON với menu chuyển bảng/xuất Excel
- `demo/permission.png`: màn hướng dẫn cấp quyền Accessibility

## Liên hệ

- GitHub: [nguyenxuanhoa493/Windows-plus-V-for-Mac](https://github.com/nguyenxuanhoa493/Windows-plus-V-for-Mac)
- Telegram: [@xuanhoa493](https://t.me/xuanhoa493)
- Email: nguyenxuanhoa493@gmail.com

Nếu CursorKit hữu ích với bạn, có thể [mời tôi một ly cà phê](Sources/Resources/cafe.jpg).
