import Cocoa
import SwiftUI
import Carbon
import HotKey

@main
struct ClipboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var virtualWindow: NSPanel?
    var eventMonitor: Any?
    var hotKey: HotKey?
    private var clipboardManager = ClipboardManager.shared
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ẩn cửa sổ chính của ứng dụng
        if let window = NSApplication.shared.windows.first {
            window.setFrame(NSRect(x: 0, y: 0, width: 0, height: 0), display: false)
            window.orderOut(nil)
        }
        NSApp.setActivationPolicy(.accessory)
        
        print("DEBUG: Ứng dụng đang khởi động...")

        #if DEBUG
        OTPItem.runSelfCheck()
        #endif

        // Detect stale TCC sau update: ad-hoc signed app có CDHash đổi mỗi build →
        // csreq trong TCC.db không match → toggle UI hiện ON nhưng AXIsProcessTrusted=false.
        // Reset entry để user cấp quyền lại từ đầu (consistent UX).
        let currentVersion = UpdateManager.shared.currentVersion
        let lastSeenVersion = UserDefaults.standard.string(forKey: "lastSeenVersion")
        let hasAccessibility = AXIsProcessTrusted()
        print("DEBUG: Trạng thái quyền truy cập: \(hasAccessibility), version: \(lastSeenVersion ?? "nil") → \(currentVersion)")

        if !hasAccessibility, let last = lastSeenVersion, last != currentVersion {
            print("DEBUG: Phát hiện stale TCC sau update \(last) → \(currentVersion), reset entry...")
            resetAccessibilityTCC()
        }
        UserDefaults.standard.set(currentVersion, forKey: "lastSeenVersion")

        if !AXIsProcessTrusted() {
            // Hiển thị popup yêu cầu quyền
            print("DEBUG: Không có quyền Accessibility, hiển thị popup...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showAccessibilityPermissionWindow()
            }
        }
        
        // Áp dụng theme đã lưu
        Settings.shared.applyTheme()
        
        // Khởi tạo clipboard manager
        clipboardManager.startMonitoring()
        
        // Tạo menu trên thanh trạng thái
        setupStatusItem()
        
        // Thiết lập menu
        setupMenu()
        
        // Thiết lập phím tắt
        setupHotKey()
        
        // Lưu phím tắt mặc định
        if UserDefaults.standard.string(forKey: "shortcutKey") == nil {
            UserDefaults.standard.set("Control + V", forKey: "shortcutKey")
        }
        
        // Đăng ký lắng nghe sự kiện thay đổi ngôn ngữ và phím tắt
        NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .languageChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(shortcutChanged), name: .shortcutChanged, object: nil)

        // Re-check Accessibility khi user mở lại app (sau khi grant/revoke từ System Settings)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification, object: nil)

        // Settings đã mở → mở popup chính ở chế độ anchored bên cạnh để xem live preview
        NotificationCenter.default.addObserver(self, selector: #selector(settingsWindowDidShow(_:)),
            name: .settingsWindowDidShow, object: nil)

        // Theme đổi → cập nhật backgroundColor (titlebar) cho popup nếu đang mở
        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange),
            name: .themeDidChange, object: nil)
        
        // Tự động kiểm tra cập nhật (silent)
        if Settings.shared.autoCheckForUpdates {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                UpdateManager.shared.checkForUpdates(silent: true)
            }
        }

        // Lần đầu mở app → mở luôn cửa sổ Cài đặt cho user.
        // Delay 0.6s để hiện sau popup Accessibility (0.5s) → Settings nằm trên cùng.
        if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.openSettings()
            }
        }

        print("DEBUG: Ứng dụng đã khởi động xong")
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            // SF Symbol "clipboard" chỉ có từ macOS 13 → trên macOS 12 trả về nil khiến
            // icon menu bar biến mất. Fallback "doc.on.clipboard" (có từ macOS 10.15),
            // cuối cùng dùng ký tự text để luôn hiển thị được icon.
            if let image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Clipboard")
                ?? NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard") {
                button.image = image
            } else {
                button.title = "📋"
            }
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }
    
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent {
            if event.type == .rightMouseUp {
                let menu = statusItem?.menu
                statusItem?.menu = menu
                menu?.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
            } else {
                showClipboardHistoryAtCursor()
            }
        }
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = true
        
        let settingsItem = NSMenuItem(title: Localization.shared.localizedString("settings"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        if Settings.shared.enableOTP {
            let otpItem = NSMenuItem(title: Localization.shared.localizedString("otp_manage"),
                                     action: #selector(openOTPManager), keyEquivalent: "o")
            otpItem.target = self
            menu.addItem(otpItem)
        }

        menu.addItem(NSMenuItem.separator())

        let updateItem = NSMenuItem(title: Localization.shared.localizedString("check_for_updates"), action: #selector(checkForUpdates), keyEquivalent: "u")
        updateItem.target = self
        menu.addItem(updateItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: Localization.shared.localizedString("quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    @objc private func languageChanged() {
        setupMenu() // Cập nhật lại menu khi ngôn ngữ thay đổi
    }

    @objc private func shortcutChanged() {
        setupHotKey() // Cập nhật lại phím tắt khi có thay đổi
    }

    /// Reset TCC entry cho Accessibility — dùng khi detect stale entry sau update
    /// (CDHash đổi → signature requirement không match → toggle UI ON nhưng kernel reject).
    /// Sau reset, user cấp lại quyền sẽ tạo entry mới với CDHash hiện tại.
    private func resetAccessibilityTCC() {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.xuanhoa.clipboard"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleId]
        do {
            try process.run()
            process.waitUntilExit()
            print("DEBUG: tccutil reset Accessibility \(bundleId) — exit \(process.terminationStatus)")
        } catch {
            print("DEBUG: tccutil reset error: \(error)")
        }
    }

    @objc private func themeDidChange() {
        virtualWindow?.backgroundColor = NSColor(Settings.shared.themedBackground)
    }

    @objc private func settingsWindowDidShow(_ note: Notification) {
        guard let settingsWindow = note.object as? NSWindow else { return }
        showAnchoredPopup(near: settingsWindow)
    }

    private var anchorObservers: [NSObjectProtocol] = []
    private let popoverSize = NSSize(width: 300, height: 450)

    /// Mở popup chính bên phải Settings window — không dismiss khi click outside,
    /// dùng làm live preview khi user chỉnh theme/font.
    func showAnchoredPopup(near anchor: NSWindow) {
        // Đóng popup hiện tại (nếu đang mở từ hotkey) + cleanup monitor cũ
        if let window = virtualWindow, window.isVisible {
            window.close()
        }
        removeEventMonitor()

        let panel = virtualWindow ?? createPanel()
        virtualWindow = panel

        // Anchored mode: lower level để Settings có thể front-most khi user click
        panel.level = .floating
        panel.backgroundColor = NSColor(Settings.shared.themedBackground)

        let origin = positionRight(of: anchor, panelSize: popoverSize)
        panel.setFrame(NSRect(origin: origin, size: popoverSize), display: false)

        applyPanelContent(to: panel)
        panel.orderFront(nil)

        // KHÔNG add global click monitor — popup giữ vị trí khi user click sang Settings
        setupAnchorObservers(for: anchor)
    }

    private func positionRight(of anchor: NSWindow, panelSize: NSSize) -> NSPoint {
        let frame = anchor.frame
        let gap: CGFloat = 12
        // Align tops: popup.maxY = anchor.maxY → top 2 cửa sổ thẳng hàng
        var origin = NSPoint(x: frame.maxX + gap, y: frame.maxY - panelSize.height)
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            // Hết chỗ bên phải → flip sang trái
            if origin.x + panelSize.width > visible.maxX {
                origin.x = frame.minX - gap - panelSize.width
            }
            if origin.x < visible.minX { origin.x = visible.minX }
            if origin.y < visible.minY { origin.y = visible.minY }
            if origin.y + panelSize.height > visible.maxY {
                origin.y = visible.maxY - panelSize.height
            }
        }
        return origin
    }

    private func setupAnchorObservers(for anchor: NSWindow) {
        tearDownAnchorObservers()
        let nc = NotificationCenter.default
        anchorObservers.append(nc.addObserver(
            forName: NSWindow.willCloseNotification, object: anchor, queue: .main
        ) { [weak self] _ in
            self?.virtualWindow?.close()
            self?.tearDownAnchorObservers()
        })
        let reposition: (Notification) -> Void = { [weak self, weak anchor] _ in
            guard let self = self, let anchor = anchor, let panel = self.virtualWindow else { return }
            let origin = self.positionRight(of: anchor, panelSize: self.popoverSize)
            panel.setFrame(NSRect(origin: origin, size: self.popoverSize), display: true)
        }
        anchorObservers.append(nc.addObserver(
            forName: NSWindow.didMoveNotification, object: anchor, queue: .main, using: reposition
        ))
        anchorObservers.append(nc.addObserver(
            forName: NSWindow.didResizeNotification, object: anchor, queue: .main, using: reposition
        ))
    }

    private func tearDownAnchorObservers() {
        anchorObservers.forEach { NotificationCenter.default.removeObserver($0) }
        anchorObservers.removeAll()
    }

    /// Build ClipboardHistoryView + set vào panel.contentView. Tái dùng cho cả cursor mode + anchored mode.
    private func applyPanelContent(to panel: NSPanel) {
        let items = clipboardManager.getHistory() ?? []
        let view = ClipboardHistoryView(items: items, onItemSelected: { [weak self, weak panel] item in
            self?.handleItemSelected(item)
            panel?.close()
        }, onClearAll: { [weak self, weak panel] includePinned, includeBookmarked in
            self?.clipboardManager.clearHistory(includePinned: includePinned, includeBookmarked: includeBookmarked)
            if let panel = panel { self?.applyPanelContent(to: panel) }
        }, onCopyOnly: { [weak panel] _ in
            panel?.close()
        }, onTogglePin: { [weak self, weak panel] item in
            self?.clipboardManager.togglePin(item)
            if let panel = panel { self?.applyPanelContent(to: panel) }
        }, onDeleteItem: { [weak self, weak panel] item in
            self?.clipboardManager.removeItem(item)
            if let panel = panel { self?.applyPanelContent(to: panel) }
        }, onToggleBookmark: { [weak self, weak panel] item in
            self?.clipboardManager.toggleBookmark(item)
            if let panel = panel { self?.applyPanelContent(to: panel) }
        }, onPasteOTP: { [weak self, weak panel] code in
            panel?.close()
            self?.handleOTPPaste(code)
        }, onManageOTP: { [weak panel] in
            panel?.close()
            OTPManagerWindow.shared.show()
        })
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: popoverSize)
        panel.contentView = hostingView
    }

    @objc private func appDidBecomeActive() {
        // Nếu user đã revoke quyền Accessibility trong System Settings → bật lại popup hướng dẫn
        if !AXIsProcessTrusted() && !AccessibilityPermissionWindow.shared.isVisible {
            print("DEBUG: Quyền Accessibility đã bị revoke runtime, hiển thị popup")
            showAccessibilityPermissionWindow()
        }
    }
    
    
    func setupHotKey() {
        // Hủy phím tắt cũ nếu có
        hotKey = nil
        
        // Lấy phím tắt từ Settings
        let shortcutKey = Settings.shared.shortcutKey
        print("DEBUG: Đang thiết lập phím tắt: \(shortcutKey)")
        
        // Phân tích phím tắt
        var modifiers: NSEvent.ModifierFlags = []
        var key = ""
        
        if shortcutKey.contains("⌘") { modifiers.insert(.command) }
        if shortcutKey.contains("⌥") { modifiers.insert(.option) }
        if shortcutKey.contains("⌃") { modifiers.insert(.control) }
        if shortcutKey.contains("⇧") { modifiers.insert(.shift) }
        
        // Lấy ký tự cuối cùng làm key
        key = String(shortcutKey.last ?? "V")
        
        print("DEBUG: Modifiers: \(modifiers), Key: \(key)")
        
        // Chuyển đổi key
        if let keyCode = keyToKeyCode(key) {
            print("DEBUG: Đã tìm thấy keyCode: \(keyCode) cho key: \(key)")
            if let key = Key(carbonKeyCode: UInt32(keyCode)) {
                hotKey = HotKey(key: key, modifiers: modifiers)
                
                hotKey?.keyDownHandler = { [weak self] in
                    print("DEBUG: Phím tắt được kích hoạt")
                    DispatchQueue.main.async {
                        self?.showClipboardHistoryAtCursor()
                    }
                }
            }
        } else {
            print("DEBUG: Không tìm thấy keyCode cho key: \(key)")
        }
    }
    
    func keyToKeyCode(_ key: String) -> UInt16? {
        let keyMap: [String: UInt16] = [
            "A": 0x00, "S": 0x01, "D": 0x02, "F": 0x03, "H": 0x04,
            "G": 0x05, "Z": 0x06, "X": 0x07, "C": 0x08, "V": 0x09,
            "B": 0x0B, "Q": 0x0C, "W": 0x0D, "E": 0x0E, "R": 0x0F,
            "Y": 0x10, "T": 0x11, "1": 0x12, "2": 0x13, "3": 0x14,
            "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18, "9": 0x19,
            "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E,
            "O": 0x1F, "U": 0x20, "[": 0x21, "I": 0x22, "P": 0x23,
            "L": 0x25, "J": 0x26, "'": 0x27, "K": 0x28, ";": 0x29,
            "\\": 0x2A, ",": 0x2B, "/": 0x2C, "N": 0x2D, "M": 0x2E,
            ".": 0x2F,
            // Function keys
            "F1": 0x7A, "F2": 0x78, "F3": 0x63, "F4": 0x76,
            "F5": 0x60, "F6": 0x61, "F7": 0x62, "F8": 0x64,
            "F9": 0x65, "F10": 0x6D, "F11": 0x67, "F12": 0x6F,
            "F13": 0x69, "F14": 0x6B, "F15": 0x71, "F16": 0x6A,
            "F17": 0x40, "F18": 0x4F, "F19": 0x50, "F20": 0x5A,
            // Arrows + space + tab/return
            "Space": 0x31, "←": 0x7B, "→": 0x7C, "↓": 0x7D, "↑": 0x7E,
            "Tab": 0x30, "Return": 0x24, "Enter": 0x4C
        ]
        return keyMap[key]
    }
    
    @objc func openSettings() {
        print("DEBUG: Đang mở cửa sổ cài đặt...")
        SettingsWindow.shared.show()
        print("DEBUG: Cửa sổ cài đặt đã được mở")
    }

    @objc func openOTPManager() {
        OTPManagerWindow.shared.show()
    }
    
    @objc func checkForUpdates() {
        UpdateManager.shared.checkForUpdates()
    }
    
    @objc func openFacebook() {
        if let url = URL(string: "https://www.facebook.com/xuanhoa493/") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    private func createPanel() -> NSPanel {
        let popoverSize = NSSize(width: 300, height: 450)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: popoverSize.width, height: popoverSize.height),
            styleMask: [.titled, .resizable, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Clipboard"
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        // Titlebar trong suốt → kế thừa backgroundColor → custom theme phủ luôn lên titlebar
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = false
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        return panel
    }
    
    @objc func showClipboardHistoryAtCursor() {
        // Đóng cửa sổ cũ + cleanup monitor
        if let window = virtualWindow, window.isVisible {
            window.close()
        }
        removeEventMonitor()
        tearDownAnchorObservers()

        let mouseLocation = NSEvent.mouseLocation

        // Vị trí popup so với con trỏ theo cấu hình của user (mặc định dưới-phải).
        // Sau đó vẫn kẹp lại trong màn hình bên dưới để không tràn ra ngoài.
        let anchorOrigin = Settings.shared.popupAnchor.origin(cursor: mouseLocation, size: popoverSize)
        var popoverOriginX = anchorOrigin.x
        var popoverOriginY = anchorOrigin.y

        // Giới hạn trong màn hình chứa con trỏ (dùng visibleFrame để tránh đè menu bar / dock)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        if let visibleFrame = screen?.visibleFrame {
            if popoverOriginX + popoverSize.width > visibleFrame.maxX {
                popoverOriginX = visibleFrame.maxX - popoverSize.width
            }
            if popoverOriginX < visibleFrame.minX {
                popoverOriginX = visibleFrame.minX
            }
            if popoverOriginY < visibleFrame.minY {
                popoverOriginY = visibleFrame.minY
            }
            if popoverOriginY + popoverSize.height > visibleFrame.maxY {
                popoverOriginY = visibleFrame.maxY - popoverSize.height
            }
        }

        // Tái sử dụng panel hoặc tạo mới
        let panel = virtualWindow ?? createPanel()
        virtualWindow = panel

        // Cursor mode: level cao để stay-on-top, click outside dismiss
        panel.level = .popUpMenu
        panel.backgroundColor = NSColor(Settings.shared.themedBackground)

        panel.setFrame(
            NSRect(x: popoverOriginX, y: popoverOriginY, width: popoverSize.width, height: popoverSize.height),
            display: false
        )

        applyPanelContent(to: panel)
        panel.makeKeyAndOrderFront(nil)

        let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak panel] event in
            if let panel = panel, panel.isVisible {
                let mouseLocation = NSEvent.mouseLocation
                if !panel.frame.contains(mouseLocation) {
                    panel.close()
                    self?.removeEventMonitor()
                }
            }
        }
        eventMonitor = monitor
    }
    
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
            // ⌘V synthesis — match ClipboardItem.paste() chính xác
            guard let source = CGEventSource(stateID: .hidSystemState) else { return }
            let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
            let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
            let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
            vDown?.flags = .maskCommand
            vUp?.flags = .maskCommand
            cmdDown?.post(tap: .cghidEventTap)
            vDown?.post(tap: .cghidEventTap)
            vUp?.post(tap: .cghidEventTap)
            cmdUp?.post(tap: .cghidEventTap)
        }
    }

    private func handleItemSelected(_ item: ClipboardItem) {
        // Đóng cửa sổ trước
        removeEventMonitor()
        if let window = virtualWindow {
            window.close()
        }
        
        // Đợi window đóng và app ban đầu được focus trở lại
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // Ignore clipboard change do paste gây ra
            self.clipboardManager.ignoreNextChange()
            // Paste nội dung
            item.paste()
            
            // Move item lên đầu sau khi paste xong (nếu user bật)
            if Settings.shared.moveToTopAfterPaste {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.clipboardManager.moveToTop(item)
                }
            }
        }
    }
    
    func showAccessibilityPermissionWindow() {
        AccessibilityPermissionWindow.shared.show {
            // Callback khi quyền được cấp
            print("DEBUG: Permission granted callback")
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        AccessibilityPermissionWindow.shared.close()
    }
    

} 