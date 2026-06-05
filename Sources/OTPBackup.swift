import AppKit
import UniformTypeIdentifiers

/// Export/Import file OTP mã hóa (gọi từ menu ⚙️ của popup khi đang ở tab OTP).
enum OTPBackup {
    static func exportInteractive() {
        AppDelegate.suppressDismiss = true   // ghim popup khi đang thao tác hộp thoại
        defer { AppDelegate.suppressDismiss = false }
        let auth = OTPAuth.shared
        guard auth.hasPIN else { info(Localization.shared.localizedString("otp_setup_pin_title")); return }
        guard let pin = promptPIN(title: Localization.shared.localizedString("otp_export"),
                                  message: Localization.shared.localizedString("otp_export_warning")) else { return }
        guard auth.verifyPIN(pin) else { info(Localization.shared.localizedString("otp_pin_wrong")); return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "clipboard-otp-backup.enc"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try OTPManager.shared.exportData(pin: pin)
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
        guard let pin = promptPIN(title: Localization.shared.localizedString("otp_import"), message: nil) else { return }
        do {
            let data = try Data(contentsOf: url)
            let added = try OTPManager.shared.importData(data, pin: pin)
            info(String(format: Localization.shared.localizedString("otp_import_done"), added))
        } catch {
            info(Localization.shared.localizedString("otp_import_failed"))
        }
    }

    // MARK: - helpers
    private static func promptPIN(title: String, message: String?) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        if let m = message { alert.informativeText = m }
        alert.addButton(withTitle: title)
        alert.addButton(withTitle: Localization.shared.localizedString("otp_cancel"))
        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.placeholderString = Localization.shared.localizedString("otp_enter_pin")
        alert.accessoryView = input
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return input.stringValue
    }

    private static func info(_ text: String) {
        let a = NSAlert()
        a.messageText = text
        a.addButton(withTitle: "OK")
        a.runModal()
    }
}
