import AppKit
import UniformTypeIdentifiers

/// Export/Import file OTP mã hóa (gọi từ menu ⚙️ của popup khi đang ở tab OTP).
enum OTPBackup {
    private static let customPassphraseAccount = "com.xuanhoa.cursorkit.otp.backup.customPassphrase"
    private static var observer: NSObjectProtocol?
    private static var timer: Timer?

    static var hasCustomPassphrase: Bool {
        guard let data = OTPStore.load(account: customPassphraseAccount) else { return false }
        return String(data: data, encoding: .utf8)?.isEmpty == false
    }

    static func setCustomPassphrase(_ passphrase: String) {
        let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            OTPStore.delete(account: customPassphraseAccount)
        } else {
            OTPStore.save(Data(trimmed.utf8), account: customPassphraseAccount)
        }
    }

    static func startAutoBackupMonitoring() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .otpListChanged,
            object: nil,
            queue: .main
        ) { _ in
            performAutoBackupIfNeeded()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { _ in
            performAutoBackupIfNeeded()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            performAutoBackupIfNeeded()
        }
    }

    static func performAutoBackupIfNeeded(force: Bool = false) {
        let settings = Settings.shared
        guard settings.enableOTP, settings.otpAutoBackupEnabled, !OTPManager.shared.items.isEmpty else { return }

        let now = Date()
        let last = UserDefaults.standard.double(forKey: "otpLastAutoBackupAt")
        let interval = TimeInterval(max(1, settings.otpAutoBackupIntervalHours) * 3600)
        guard force || last == 0 || now.timeIntervalSince1970 - last >= interval else { return }
        guard let passphrase = autoBackupPassphrase() else {
            print("DEBUG: OTP auto backup bỏ qua — chưa có mật khẩu backup tùy chỉnh")
            return
        }

        let directory = URL(fileURLWithPath: settings.otpAutoBackupDirectory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HH-mm"
            let fileURL = directory.appendingPathComponent("clipboard-otp-backup-\(formatter.string(from: now)).enc")
            let data = try OTPManager.shared.exportData(pin: passphrase)
            try data.write(to: fileURL, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: "otpLastAutoBackupAt")
        } catch {
            print("DEBUG: OTP auto backup lỗi: \(error)")
        }
    }

    static func exportInteractive() {
        AppDelegate.suppressDismiss = true   // ghim popup khi đang thao tác hộp thoại
        defer { AppDelegate.suppressDismiss = false }
        guard let passphrase = interactiveExportPassphrase() else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "clipboard-otp-backup.enc"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try OTPManager.shared.exportData(pin: passphrase)
            try data.write(to: url)
            info("✅")
        } catch {
            print("DEBUG: OTP export lỗi: \(error)")
            info(Localization.shared.localizedString("otp_export_failed"))
        }
    }

    static func importInteractive() {
        AppDelegate.suppressDismiss = true   // ghim popup khi đang thao tác hộp thoại
        defer { AppDelegate.suppressDismiss = false }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.data]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let passphrase = promptPassphrase(
            title: Localization.shared.localizedString("otp_import"),
            message: nil
        ) else { return }
        do {
            let data = try Data(contentsOf: url)
            let added = try OTPManager.shared.importData(data, pin: passphrase)
            info(String(format: Localization.shared.localizedString("otp_import_done"), added))
        } catch {
            info(Localization.shared.localizedString("otp_import_failed"))
        }
    }

    // MARK: - helpers
    private static func promptPassphrase(title: String, message: String?) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        if let m = message { alert.informativeText = m }
        alert.addButton(withTitle: title)
        alert.addButton(withTitle: Localization.shared.localizedString("otp_cancel"))
        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        input.placeholderString = Localization.shared.localizedString("otp_backup_custom_password_placeholder")
        alert.accessoryView = input
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return input.stringValue
    }

    private static func autoBackupPassphrase() -> String? {
        guard let data = OTPStore.load(account: customPassphraseAccount),
              let passphrase = String(data: data, encoding: .utf8),
              !passphrase.isEmpty else {
            return nil
        }
        return passphrase
    }

    private static func interactiveExportPassphrase() -> String? {
        guard let passphrase = autoBackupPassphrase() else {
            info(Localization.shared.localizedString("otp_backup_custom_password_not_set"))
            return nil
        }
        return passphrase
    }

    private static func info(_ text: String) {
        let a = NSAlert()
        a.messageText = text
        a.addButton(withTitle: "OK")
        a.runModal()
    }
}
