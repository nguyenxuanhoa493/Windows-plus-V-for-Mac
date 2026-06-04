import Foundation
import SwiftUI
import ServiceManagement

enum ThemeMode: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    case custom = "custom"
}

enum AppFontDesign: String, CaseIterable {
    case system, monospaced, rounded, serif

    var swiftUIDesign: Font.Design {
        switch self {
        case .system: return .default
        case .monospaced: return .monospaced
        case .rounded: return .rounded
        case .serif: return .serif
        }
    }

    var localizationKey: String {
        switch self {
        case .system: return "font_design_system"
        case .monospaced: return "font_design_monospaced"
        case .rounded: return "font_design_rounded"
        case .serif: return "font_design_serif"
        }
    }
}

/// Vị trí hộp thoại lịch sử xuất hiện so với con trỏ chuột.
/// Con trỏ nằm ở tâm lưới 3x3, 8 case = 8 hướng xung quanh.
enum PopupAnchor: String, CaseIterable {
    case topLeft, top, topRight
    case left, right
    case bottomLeft, bottom, bottomRight

    enum Horizontal { case leading, center, trailing }
    enum Vertical { case top, middle, bottom }

    var horizontal: Horizontal {
        switch self {
        case .topLeft, .left, .bottomLeft: return .leading
        case .top, .bottom: return .center
        case .topRight, .right, .bottomRight: return .trailing
        }
    }

    var vertical: Vertical {
        switch self {
        case .topLeft, .top, .topRight: return .top
        case .left, .right: return .middle
        case .bottomLeft, .bottom, .bottomRight: return .bottom
        }
    }

    /// SF Symbol mũi tên minh họa hướng (đều có từ macOS 11).
    var iconName: String {
        switch self {
        case .topLeft: return "arrow.up.left"
        case .top: return "arrow.up"
        case .topRight: return "arrow.up.right"
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        case .bottomLeft: return "arrow.down.left"
        case .bottom: return "arrow.down"
        case .bottomRight: return "arrow.down.right"
        }
    }

    /// Tính origin (góc bottom-left của NSWindow — hệ toạ độ AppKit y hướng lên)
    /// từ vị trí con trỏ và kích thước popup.
    func origin(cursor: CGPoint, size: CGSize) -> CGPoint {
        let x: CGFloat
        switch horizontal {
        case .leading:  x = cursor.x - size.width
        case .center:   x = cursor.x - size.width / 2
        case .trailing: x = cursor.x
        }
        let y: CGFloat
        switch vertical {
        case .top:    y = cursor.y                   // popup nằm phía trên con trỏ
        case .middle: y = cursor.y - size.height / 2
        case .bottom: y = cursor.y - size.height      // popup nằm phía dưới con trỏ
        }
        return CGPoint(x: x, y: y)
    }
}

extension Notification.Name {
    static let shortcutChanged = Notification.Name("shortcutChanged")
    /// Posted sau khi Settings window đã hiển thị. `object` = NSWindow.
    /// AppDelegate dùng để mở popup chính ở chế độ anchored bên cạnh Settings.
    static let settingsWindowDidShow = Notification.Name("settingsWindowDidShow")
    /// Posted sau khi Settings.applyTheme() chạy — windows tự cập nhật backgroundColor titlebar.
    static let themeDidChange = Notification.Name("themeDidChange")
}

class Settings: ObservableObject {
    static let shared = Settings()
    
    @Published var isAccessibilityEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAccessibilityEnabled, forKey: "isAccessibilityEnabled")
        }
    }
    
    @Published var maxHistoryItems: Int {
        didSet {
            UserDefaults.standard.set(maxHistoryItems, forKey: "maxHistoryItems")
        }
    }
    
    @Published var shortcutKey: String {
        didSet {
            UserDefaults.standard.set(shortcutKey, forKey: "shortcutKey")
            // Cập nhật shortcutString khi shortcutKey thay đổi.
            // Lưu ý: didSet của shortcutString sẽ tự ghi UserDefaults — không cần ghi 2 lần ở đây.
            shortcutString = shortcutKey
            NotificationCenter.default.post(name: .shortcutChanged, object: nil)
        }
    }

    @Published var shortcutString: String? {
        didSet {
            UserDefaults.standard.set(shortcutString, forKey: "shortcutString")
        }
    }
    
    @Published var shortcutKeyCode: UInt32 {
        didSet {
            UserDefaults.standard.set(shortcutKeyCode, forKey: "shortcutKeyCode")
        }
    }
    
    @Published var shortcutModifiers: NSEvent.ModifierFlags {
        didSet {
            UserDefaults.standard.set(shortcutModifiers.rawValue, forKey: "shortcutModifiers")
        }
    }
    
    @Published var autoCheckForUpdates: Bool {
        didSet {
            UserDefaults.standard.set(autoCheckForUpdates, forKey: "autoCheckForUpdates")
        }
    }

    /// Tự khởi động cùng macOS — dùng SMAppService (macOS 13+).
    /// Trên macOS 12, toggle vẫn lưu UserDefaults nhưng không có hiệu lực thực sự.
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            applyLaunchAtLogin()
        }
    }

    private func applyLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if launchAtLogin {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status != .notRegistered {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                print("DEBUG: applyLaunchAtLogin lỗi: \(error)")
            }
        }
    }
    
    @Published var themeMode: ThemeMode {
        didSet {
            UserDefaults.standard.set(themeMode.rawValue, forKey: "themeMode")
            applyTheme()
        }
    }

    /// `true` → popup dùng style "native macOS list" (gọn, không card, dùng system selection color).
    /// `false` (default) → custom card UI với hover effect, action buttons.
    @Published var useNativeUI: Bool {
        didSet {
            UserDefaults.standard.set(useNativeUI, forKey: "useNativeUI")
        }
    }

    /// Bộ màu — System theme dùng accent + appearance hệ thống; các theme khác override appearance + accent + background.
    @Published var appTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(appTheme.rawValue, forKey: "appTheme")
            applyTheme()
        }
    }

    /// Phông chữ cho text content trong popup item (system/monospaced/rounded/serif).
    @Published var appFontDesign: AppFontDesign {
        didSet {
            UserDefaults.standard.set(appFontDesign.rawValue, forKey: "appFontDesign")
        }
    }

    /// Cỡ chữ cho text content trong popup item (10-16, default 11).
    @Published var appFontSize: Int {
        didSet {
            UserDefaults.standard.set(appFontSize, forKey: "appFontSize")
        }
    }

    // MARK: - Feature toggles
    @Published var moveToTopAfterPaste: Bool {
        didSet { UserDefaults.standard.set(moveToTopAfterPaste, forKey: "feature_moveToTopAfterPaste") }
    }
    @Published var enableJSONToTable: Bool {
        didSet { UserDefaults.standard.set(enableJSONToTable, forKey: "feature_enableJSONToTable") }
    }
    @Published var enableJSONToExcel: Bool {
        didSet { UserDefaults.standard.set(enableJSONToExcel, forKey: "feature_enableJSONToExcel") }
    }
    @Published var enableTableToJSON: Bool {
        didSet { UserDefaults.standard.set(enableTableToJSON, forKey: "feature_enableTableToJSON") }
    }
    @Published var enableOpenURLInBrowser: Bool {
        didSet { UserDefaults.standard.set(enableOpenURLInBrowser, forKey: "feature_enableOpenURLInBrowser") }
    }
    @Published var enableTimestampConvert: Bool {
        didSet { UserDefaults.standard.set(enableTimestampConvert, forKey: "feature_enableTimestampConvert") }
    }
    @Published var enableSearch: Bool {
        didSet { UserDefaults.standard.set(enableSearch, forKey: "feature_enableSearch") }
    }
    @Published var enableDragAndDrop: Bool {
        didSet { UserDefaults.standard.set(enableDragAndDrop, forKey: "feature_enableDragAndDrop") }
    }
    @Published var enableNumberShortcuts: Bool {
        didSet { UserDefaults.standard.set(enableNumberShortcuts, forKey: "feature_enableNumberShortcuts") }
    }
    @Published var hidePopupAfterDrag: Bool {
        didSet { UserDefaults.standard.set(hidePopupAfterDrag, forKey: "feature_hidePopupAfterDrag") }
    }

    /// Vị trí popup so với con trỏ chuột (mặc định dưới-phải = giữ behavior cũ).
    @Published var popupAnchor: PopupAnchor {
        didSet { UserDefaults.standard.set(popupAnchor.rawValue, forKey: "popupAnchor") }
    }

    /// Hiện dòng thông tin (số thứ tự, badge, app nguồn, thời gian) dưới mỗi item.
    @Published var showItemInfoLine: Bool {
        didSet { UserDefaults.standard.set(showItemInfoLine, forKey: "feature_showItemInfoLine") }
    }

    func applyTheme() {
        // Áp dụng appearance theo appTheme (nil = system, .aqua/.darkAqua = ép cứng)
        if let preferred = appTheme.preferredAppearance {
            NSApp.appearance = NSAppearance(named: preferred)
        } else {
            NSApp.appearance = nil
        }
        // Báo các NSWindow tự cập nhật backgroundColor (titlebar)
        NotificationCenter.default.post(name: .themeDidChange, object: nil)
    }

    /// `true` khi appTheme có signature colors (Dracula, Nord, ...) — áp dụng background/surface/foreground/accent overrides.
    /// `false` cho System/Light/Dark — chỉ ép appearance, dùng system colors.
    var isCustomThemeActive: Bool {
        switch appTheme {
        case .system, .light, .dark: return false
        default: return true
        }
    }

    // MARK: - Theme-aware color helpers (fallback về system colors khi không custom)

    var themedBackground: Color {
        if isCustomThemeActive, let bg = appTheme.background { return bg }
        return Color(.windowBackgroundColor)
    }

    var themedSurface: Color {
        if isCustomThemeActive, let surface = appTheme.surface { return surface }
        return Color(.controlBackgroundColor)
    }

    var themedForeground: Color {
        if isCustomThemeActive, let fg = appTheme.foreground { return fg }
        return .primary
    }

    var themedAccent: Color {
        if isCustomThemeActive, let accent = appTheme.accent { return accent }
        return .accentColor
    }
    
    init() {
        // Khởi tạo các thuộc tính cơ bản
        self.isAccessibilityEnabled = UserDefaults.standard.bool(forKey: "isAccessibilityEnabled")
        self.shortcutKeyCode = UInt32(UserDefaults.standard.integer(forKey: "shortcutKeyCode"))
        self.shortcutModifiers = NSEvent.ModifierFlags(rawValue: UInt(UserDefaults.standard.integer(forKey: "shortcutModifiers")))
        
        // Auto check for updates (default: true)
        if UserDefaults.standard.object(forKey: "autoCheckForUpdates") == nil {
            self.autoCheckForUpdates = true
        } else {
            self.autoCheckForUpdates = UserDefaults.standard.bool(forKey: "autoCheckForUpdates")
        }

        // Launch at login — đồng bộ với SMAppService nếu có thể (macOS 13+)
        if #available(macOS 13.0, *) {
            let registered = SMAppService.mainApp.status == .enabled
            self.launchAtLogin = registered
        } else {
            self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        }
        
        // Khởi tạo maxHistoryItems với giá trị mặc định
        let savedMaxHistoryItems = UserDefaults.standard.integer(forKey: "maxHistoryItems")
        self.maxHistoryItems = savedMaxHistoryItems == 0 ? 50 : savedMaxHistoryItems
        
        // Khởi tạo themeMode
        if let savedTheme = UserDefaults.standard.string(forKey: "themeMode"),
           let mode = ThemeMode(rawValue: savedTheme) {
            self.themeMode = mode
        } else {
            self.themeMode = .system
        }

        // Native UI toggle (default: false → custom card UI)
        if UserDefaults.standard.object(forKey: "useNativeUI") == nil {
            self.useNativeUI = false
        } else {
            self.useNativeUI = UserDefaults.standard.bool(forKey: "useNativeUI")
        }

        // App theme — ưu tiên đọc appTheme đã lưu; nếu chưa có thì migrate từ legacy themeMode
        if let savedTheme = UserDefaults.standard.string(forKey: "appTheme"),
           let theme = AppTheme(rawValue: savedTheme) {
            self.appTheme = theme
        } else if let legacyMode = UserDefaults.standard.string(forKey: "themeMode") {
            switch legacyMode {
            case "light": self.appTheme = .light
            case "dark": self.appTheme = .dark
            default: self.appTheme = .system  // "system" + "custom"
            }
        } else {
            // Mặc định cho cài đặt mới: theme tím Dracula
            self.appTheme = .dracula
        }

        // Font design (default: system)
        if let savedFont = UserDefaults.standard.string(forKey: "appFontDesign"),
           let design = AppFontDesign(rawValue: savedFont) {
            self.appFontDesign = design
        } else {
            self.appFontDesign = .system
        }

        // Font size (default: 13, range 10-16)
        let savedSize = UserDefaults.standard.integer(forKey: "appFontSize")
        self.appFontSize = (10...16).contains(savedSize) ? savedSize : 13

        // Vị trí popup so với con trỏ (default: dưới-phải)
        if let raw = UserDefaults.standard.string(forKey: "popupAnchor"),
           let anchor = PopupAnchor(rawValue: raw) {
            self.popupAnchor = anchor
        } else {
            self.popupAnchor = .bottomRight
        }
        
        // Khởi tạo shortcutKey và shortcutString
        self.shortcutKey = UserDefaults.standard.string(forKey: "shortcutKey") ?? "⌘V"
        if let savedString = UserDefaults.standard.string(forKey: "shortcutString") {
            self.shortcutString = savedString
        } else {
            self.shortcutString = "⌃V" // Mặc định Control + V
        }

        // Feature toggles — mặc định bật để giữ behavior cũ.
        // Dùng object(forKey:) để phân biệt "chưa set" vs "đã set false".
        func loadBool(_ key: String, default defaultValue: Bool) -> Bool {
            if UserDefaults.standard.object(forKey: key) == nil { return defaultValue }
            return UserDefaults.standard.bool(forKey: key)
        }
        self.moveToTopAfterPaste = loadBool("feature_moveToTopAfterPaste", default: true)
        self.enableJSONToTable = loadBool("feature_enableJSONToTable", default: true)
        self.enableJSONToExcel = loadBool("feature_enableJSONToExcel", default: true)
        self.enableTableToJSON = loadBool("feature_enableTableToJSON", default: true)
        self.enableOpenURLInBrowser = loadBool("feature_enableOpenURLInBrowser", default: true)
        self.enableTimestampConvert = loadBool("feature_enableTimestampConvert", default: true)
        self.enableSearch = loadBool("feature_enableSearch", default: true)
        self.enableDragAndDrop = loadBool("feature_enableDragAndDrop", default: true)
        self.enableNumberShortcuts = loadBool("feature_enableNumberShortcuts", default: true)
        self.hidePopupAfterDrag = loadBool("feature_hidePopupAfterDrag", default: true)
        self.showItemInfoLine = loadBool("feature_showItemInfoLine", default: true)
    }
    
    func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
        AXIsProcessTrustedWithOptions(options)
    }
    
    func saveSettings() {
        UserDefaults.standard.synchronize()
    }
} 