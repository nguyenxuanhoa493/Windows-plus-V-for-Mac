import SwiftUI
import Cocoa

struct AccessibilityPermissionView: View {
    @Environment(\.dismiss) var dismiss
    let onOpenSettings: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with gradient
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.7)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                VStack(spacing: 16) {
                    // Icon with background
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 90, height: 90)
                        
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.white)
                    }
                    
                    // Title
                    Text(Localization.shared.localizedString("perm_request_title"))
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text(Localization.shared.localizedString("perm_request_subtitle"))
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.95))
                }
                .padding(.vertical, 30)
            }
            .frame(height: 200)
            
            // Content
            VStack(spacing: 24) {
                // Features
                VStack(alignment: .leading, spacing: 16) {
                    FeatureRow(
                        icon: "doc.on.clipboard.fill",
                        iconColor: .green,
                        title: Localization.shared.localizedString("perm_feature_paste_title"),
                        description: Localization.shared.localizedString("perm_feature_paste_desc")
                    )

                    FeatureRow(
                        icon: "cursorarrow.click.2",
                        iconColor: .blue,
                        title: Localization.shared.localizedString("perm_feature_cursor_title"),
                        description: Localization.shared.localizedString("perm_feature_cursor_desc")
                    )

                    FeatureRow(
                        icon: "keyboard.fill",
                        iconColor: .orange,
                        title: Localization.shared.localizedString("perm_feature_keyboard_title"),
                        description: Localization.shared.localizedString("perm_feature_keyboard_desc")
                    )
                }
                .padding(20)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)

                // Instructions
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text(Localization.shared.localizedString("perm_quick_guide"))
                            .font(.headline)
                            .foregroundColor(.primary)
                    }

                    InstructionStep(number: "1", text: Localization.shared.localizedString("perm_step_1"))
                    InstructionStep(number: "2", text: Localization.shared.localizedString("perm_step_2"))
                    InstructionStep(number: "3", text: Localization.shared.localizedString("perm_step_3"))

                    // Stale entry hint (sau update có thể cần xoá-add lại)
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 12))
                        Text(Localization.shared.localizedString("perm_stale_hint"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 4)
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                
                // Buttons
                VStack(spacing: 12) {
                    // Primary button
                    Button(action: onOpenSettings) {
                        HStack(spacing: 8) {
                            Image(systemName: "gearshape.fill")
                            Text(Localization.shared.localizedString("perm_open_settings"))
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    
                    // Exit button
                    Button(action: {
                        NSApplication.shared.terminate(nil)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle")
                            Text(Localization.shared.localizedString("perm_quit_app"))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Color(NSColor.controlBackgroundColor))
                        .foregroundColor(.secondary)
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    
                    // Auto check info
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                        Text(Localization.shared.localizedString("perm_auto_close"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(24)
        }
        .frame(width: 520, height: 620)
    }
}

// Feature row component
struct FeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(iconColor)
                .cornerRadius(10)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

// Instruction step component
struct InstructionStep: View {
    let number: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.blue)
                .cornerRadius(14)
            
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

class AccessibilityPermissionWindow: NSWindow {
    static let shared = AccessibilityPermissionWindow()
    private var checkTimer: Timer?
    private var onPermissionGranted: (() -> Void)?
    
    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        self.title = Localization.shared.localizedString("perm_window_title")
        self.isReleasedWhenClosed = false
        self.center()
        self.level = .floating
        self.titlebarAppearsTransparent = true
        self.backgroundColor = NSColor(Settings.shared.themedBackground)
        
        // Lắng nghe khi app được focus trở lại
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    deinit {
        stopCheckingPermission()
        NotificationCenter.default.removeObserver(self)
    }
    
    func show(onPermissionGranted: @escaping () -> Void) {
        self.onPermissionGranted = onPermissionGranted

        let contentView = AccessibilityPermissionView(
            onOpenSettings: {
                self.openAccessibilitySettings()
            }
        )

        // Cập nhật màu theme mỗi lần show (nếu user vừa đổi)
        self.backgroundColor = NSColor(Settings.shared.themedBackground)

        self.contentView = NSHostingView(rootView: contentView)
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Bắt đầu check quyền định kỳ mỗi 2 giây
        startCheckingPermission()
    }
    
    private func startCheckingPermission() {
        checkTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkPermission()
        }
    }
    
    private func stopCheckingPermission() {
        checkTimer?.invalidate()
        checkTimer = nil
    }
    
    @objc private func appDidBecomeActive() {
        // Khi app được focus lại, check quyền ngay lập tức
        if self.isVisible {
            checkPermission()
        }
    }
    
    private func checkPermission() {
        let hasAccessibility = AXIsProcessTrusted()
        print("DEBUG: Auto checking permission: \(hasAccessibility)")
        
        if hasAccessibility {
            print("DEBUG: Permission granted! Closing window...")
            stopCheckingPermission()
            
            DispatchQueue.main.async {
                // Show alert TRƯỚC khi close window (để app vẫn còn active)
                NSApp.activate(ignoringOtherApps: true)
                
                let alert = NSAlert()
                alert.messageText = Localization.shared.localizedString("perm_granted_title")
                alert.informativeText = Localization.shared.localizedString("perm_granted_message")
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
                
                // Đóng window sau khi user bấm OK
                self.close()
                
                // Gọi callback nếu có
                self.onPermissionGranted?()
            }
        }
    }
    
    private func openAccessibilitySettings() {
        // Open System Settings to Privacy & Security > Accessibility
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
    
    override func close() {
        stopCheckingPermission()
        super.close()
    }
}
