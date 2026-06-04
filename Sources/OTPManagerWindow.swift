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
