import SwiftUI
import Combine
import Foundation
import Carbon

class ShortcutViewModel: ObservableObject {
    @Published var isCapturing = false
    private var eventMonitor: Any?
    
    func startCaptureShortcut(completion: @escaping (String) -> Void) {
        isCapturing = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if self.isCapturing {
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                var shortcutString = ""
                
                if modifiers.contains(.command) { shortcutString += "⌘" }
                if modifiers.contains(.option) { shortcutString += "⌥" }
                if modifiers.contains(.control) { shortcutString += "⌃" }
                if modifiers.contains(.shift) { shortcutString += "⇧" }
                
                if event.type == .keyDown {
                    let key = event.charactersIgnoringModifiers?.uppercased() ?? ""
                    if !key.isEmpty {
                        shortcutString += key
                        completion(shortcutString)
                        self.stopCaptureShortcut()
                    }
                }
            }
            return nil
        }
    }
    
    func stopCaptureShortcut() {
        isCapturing = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var localization = Localization.shared
    @StateObject private var shortcutViewModel = ShortcutViewModel()
    @ObservedObject private var updateManager = UpdateManager.shared
    @State private var maxHistoryText: String
    @State private var selectedLanguage: Language
    @State private var autoCheckForUpdates: Bool
    
    @State private var useNativeUI: Bool
    @State private var selectedTab: Int = 0

    init() {
        _maxHistoryText = State(initialValue: String(Settings.shared.maxHistoryItems))
        _selectedLanguage = State(initialValue: Localization.shared.currentLanguage)
        _autoCheckForUpdates = State(initialValue: Settings.shared.autoCheckForUpdates)
        _useNativeUI = State(initialValue: Settings.shared.useNativeUI)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(alignment: .leading, spacing: 2) {
                sidebarItem(tag: 0, icon: "gearshape", titleKey: "tab_general")
                sidebarItem(tag: 1, icon: "paintpalette", titleKey: "tab_appearance")
                sidebarItem(tag: 2, icon: "switch.2", titleKey: "tab_features")
                sidebarItem(tag: 3, icon: "info.circle", titleKey: "tab_info")
                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .frame(width: 150)
            .background(settings.themedSurface.opacity(0.4))

            Divider()

            // Content
            Group {
                switch selectedTab {
                case 0: generalTab
                case 1: appearanceTab
                case 2: featuresTab
                case 3: infoTab
                default: generalTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 580, height: 500)
        .background(settings.themedBackground)
        .modifier(ConditionalThemeModifier(theme: settings.appTheme, active: settings.isCustomThemeActive))
        .onDisappear {
            shortcutViewModel.stopCaptureShortcut()
        }
    }

    @ViewBuilder
    private func sidebarItem(tag: Int, icon: String, titleKey: String) -> some View {
        let isSelected = selectedTab == tag
        Button {
            selectedTab = tag
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                Text(localization.localizedString(titleKey))
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? settings.themedAccent.opacity(0.2) : Color.clear)
            )
            .foregroundColor(isSelected ? settings.themedAccent : .primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private var generalTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                    // Language
                    settingsCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(localization.localizedString("language"), systemImage: "globe")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)

                            HStack(spacing: 6) {
                                languageButton(flag: "🇻🇳", label: "VI", language: .vietnamese)
                                languageButton(flag: "🇺🇸", label: "EN", language: .english)
                            }
                        }
                    }

                    // Launch at login
                    settingsCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Label(localization.localizedString("launch_at_login"), systemImage: "power")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Text(localization.localizedString("launch_at_login_hint"))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary.opacity(0.8))
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { settings.launchAtLogin },
                                set: { settings.launchAtLogin = $0 }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                        }
                    }

                    // Shortcut
                    settingsCard {
                        HStack {
                            Label(localization.localizedString("shortcut"), systemImage: "keyboard")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Button(action: {
                                shortcutViewModel.startCaptureShortcut { newShortcut in
                                    settings.shortcutString = newShortcut
                                    settings.shortcutKey = newShortcut
                                }
                            }) {
                                Text(shortcutViewModel.isCapturing ? "..." : (settings.shortcutString ?? "⌃V"))
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(settings.themedAccent.opacity(0.1))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(settings.themedAccent.opacity(0.3), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    // History
                    settingsCard {
                        HStack {
                            Label(localization.localizedString("history"), systemImage: "clock.arrow.circlepath")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            HStack(spacing: 4) {
                                Text(localization.localizedString("max_history_items") + ":")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                TextField("", text: $maxHistoryText)
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .multilineTextAlignment(.center)
                                    .frame(width: 50)
                                    .textFieldStyle(.roundedBorder)
                                    .help(localization.localizedString("max_history_hint"))
                                    .onSubmit {
                                        if let value = Int(maxHistoryText), value >= 1 && value <= 500 {
                                            settings.maxHistoryItems = value
                                        } else {
                                            maxHistoryText = String(settings.maxHistoryItems)
                                        }
                                    }
                            }
                        }
                    }
                    
                    // Updates
                    settingsCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(localization.localizedString("check_for_updates"), systemImage: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Text("v\(updateManager.currentVersion)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.secondary.opacity(0.1))
                                    )
                            }
                            
                            HStack(spacing: 8) {
                                Toggle(localization.localizedString("update_auto_check"), isOn: $autoCheckForUpdates)
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                                    .font(.system(size: 12))
                                    .onChange(of: autoCheckForUpdates) { newValue in
                                        settings.autoCheckForUpdates = newValue
                                    }
                                
                                Spacer()
                                
                                if updateManager.isChecking {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                } else if updateManager.isDownloading {
                                    ProgressView(value: updateManager.downloadProgress)
                                        .frame(width: 80)
                                    Button(action: { updateManager.cancelDownload() }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                    .help(localization.localizedString("update_cancel"))
                                } else {
                                    Button(action: { updateManager.checkForUpdates() }) {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 11))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            
                            if updateManager.updateAvailable, let version = updateManager.latestVersion {
                                HStack {
                                    Text("🎉 \(String(format: localization.localizedString("update_new_version"), version, updateManager.currentVersion))")
                                        .font(.system(size: 11))
                                        .foregroundColor(.green)
                                    Spacer()
                                    Button(localization.localizedString("update_download")) {
                                        updateManager.downloadAndInstall()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                            
                            if let error = updateManager.updateError {
                                Text(error)
                                    .font(.system(size: 11))
                                    .foregroundColor(.red)
                            }
                        }
                    }
            }
            .padding(16)
        }
    }

    private var appearanceTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Theme picker — bao gồm System/Light/Dark + các theme nổi tiếng
                settingsCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(localization.localizedString("color_theme"), systemImage: "paintpalette")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(settings.appTheme.displayName)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                        Text(localization.localizedString("color_theme_hint"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.7))

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                            ForEach(AppTheme.allCases, id: \.self) { theme in
                                themeSwatch(theme: theme)
                            }
                        }
                        .padding(.top, 4)
                    }
                }

                // Font design
                settingsCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(localization.localizedString("font_design"), systemImage: "textformat")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)

                        HStack(spacing: 6) {
                            ForEach(AppFontDesign.allCases, id: \.self) { design in
                                fontDesignButton(design: design)
                            }
                        }
                    }
                }

                // Font size
                settingsCard {
                    HStack {
                        Label(localization.localizedString("font_size"), systemImage: "textformat.size")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        HStack(spacing: 6) {
                            Text(settings.appFontDesign == .system ? "Aa" : "Aa")
                                .font(.system(
                                    size: CGFloat(settings.appFontSize),
                                    design: settings.appFontDesign.swiftUIDesign
                                ))
                                .foregroundColor(.secondary)
                            Stepper(value: Binding(
                                get: { settings.appFontSize },
                                set: { settings.appFontSize = $0 }
                            ), in: 10...16, step: 1) {
                                Text("\(settings.appFontSize)pt")
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(minWidth: 36, alignment: .trailing)
                            }
                        }
                    }
                }

                // Native UI toggle
                settingsCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(localization.localizedString("use_native_ui"), systemImage: "rectangle.3.offgrid")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                            Text(localization.localizedString("use_native_ui_hint"))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                        Spacer()
                        Toggle("", isOn: $useNativeUI)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                            .onChange(of: useNativeUI) { newValue in
                                settings.useNativeUI = newValue
                            }
                    }
                }

                // Vị trí popup so với con trỏ — lưới 3x3 + live preview
                settingsCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(localization.localizedString("popup_position"), systemImage: "macwindow")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text(localization.localizedString("popup_position_hint"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.7))

                        HStack(alignment: .center, spacing: 18) {
                            popupPositionGrid
                            PopupAnchorPreview(anchor: settings.popupAnchor, accent: settings.themedAccent)
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 4)
                    }
                }

                // Toggle hiện/ẩn dòng thông tin dưới mỗi item
                settingsCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(localization.localizedString("show_item_info_line"), systemImage: "info.circle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                            Text(localization.localizedString("show_item_info_line_hint"))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { settings.showItemInfoLine },
                            set: { settings.showItemInfoLine = $0 }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Popup position picker

    /// Ánh xạ (hàng, cột) của lưới 3x3 sang hướng. (1,1) = nil = con trỏ ở tâm.
    private func popupAnchorAt(row: Int, col: Int) -> PopupAnchor? {
        switch (row, col) {
        case (0, 0): return .topLeft
        case (0, 1): return .top
        case (0, 2): return .topRight
        case (1, 0): return .left
        case (1, 2): return .right
        case (2, 0): return .bottomLeft
        case (2, 1): return .bottom
        case (2, 2): return .bottomRight
        default: return nil
        }
    }

    private var popupPositionGrid: some View {
        VStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { col in
                        popupGridCell(row: row, col: col)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func popupGridCell(row: Int, col: Int) -> some View {
        let cell: CGFloat = 30
        if let anchor = popupAnchorAt(row: row, col: col) {
            let isSelected = settings.popupAnchor == anchor
            Button(action: { settings.popupAnchor = anchor }) {
                Image(systemName: anchor.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .secondary)
                    .frame(width: cell, height: cell)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? settings.themedAccent : Color(NSColor.controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? settings.themedAccent : Color(NSColor.separatorColor),
                                    lineWidth: isSelected ? 1.5 : 0.5)
                    )
            }
            .buttonStyle(.plain)
        } else {
            // Ô trung tâm = con trỏ chuột
            Image(systemName: "cursorarrow")
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.6))
                .frame(width: cell, height: cell)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor).opacity(0.5),
                                style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                )
        }
    }

    private func fontDesignButton(design: AppFontDesign) -> some View {
        let isSelected = settings.appFontDesign == design
        return Button(action: { settings.appFontDesign = design }) {
            VStack(spacing: 2) {
                Text("Aa")
                    .font(.system(size: 14, weight: .medium, design: design.swiftUIDesign))
                Text(localization.localizedString(design.localizationKey))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? settings.themedAccent.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? settings.themedAccent : Color(NSColor.separatorColor),
                            lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var infoTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Author
                settingsCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(localization.localizedString("info_author"), systemImage: "person.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        HStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(settings.themedAccent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Nguyễn Xuân Hoà")
                                    .font(.system(size: 13, weight: .medium))
                                Text("v\(updateManager.currentVersion)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Links
                settingsCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(localization.localizedString("info_links"), systemImage: "link")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)

                        infoLinkRow(
                            icon: "chevron.left.forwardslash.chevron.right",
                            label: localization.localizedString("info_github"),
                            url: "https://github.com/nguyenxuanhoa493/Windows-plus-V-for-Mac"
                        )
                        infoLinkRow(
                            icon: "f.circle.fill",
                            label: "Facebook: @xuanhoa493",
                            url: "https://www.facebook.com/xuanhoa493/"
                        )
                        infoLinkRow(
                            icon: "paperplane.fill",
                            label: "Telegram: @xuanhoa493",
                            url: "https://t.me/xuanhoa493"
                        )
                    }
                }

                // Buy me a coffee — QR Techcombank
                settingsCard {
                    VStack(alignment: .center, spacing: 10) {
                        HStack {
                            Label(localization.localizedString("info_support"), systemImage: "heart.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        Text(localization.localizedString("info_buy_coffee_text"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let img = SettingsView.loadResourceImage(named: "cafe", ext: "jpg") {
                            Image(nsImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 260, maxHeight: 320)
                                .cornerRadius(8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(16)
        }
    }

    /// Load resource từ cả 2 bundle: SwiftPM module bundle (dev build) + main app bundle (release Clipboard.app).
    static func loadResourceImage(named name: String, ext: String) -> NSImage? {
        if let url = Bundle.module.url(forResource: name, withExtension: ext),
           let img = NSImage(contentsOf: url) {
            return img
        }
        if let path = Bundle.main.path(forResource: name, ofType: ext),
           let img = NSImage(contentsOfFile: path) {
            return img
        }
        return nil
    }

    @ViewBuilder
    private func infoLinkRow(icon: String, label: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 18)
                    .foregroundColor(settings.themedAccent)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private var featuresTab: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Privacy disclaimer (plaintext storage)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 14))
                    Text(localization.localizedString("feature_privacy_disclaimer"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 0.5)
                )

                featureToggleRow(
                    icon: "arrow.up.to.line",
                    titleKey: "feature_move_to_top",
                    isOn: Binding(
                        get: { settings.moveToTopAfterPaste },
                        set: { settings.moveToTopAfterPaste = $0 }
                    )
                )
                featureToggleRow(
                    icon: "tablecells",
                    titleKey: "feature_json_to_table",
                    isOn: Binding(
                        get: { settings.enableJSONToTable },
                        set: { settings.enableJSONToTable = $0 }
                    )
                )
                featureToggleRow(
                    icon: "tablecells.badge.ellipsis",
                    titleKey: "feature_json_to_excel",
                    isOn: Binding(
                        get: { settings.enableJSONToExcel },
                        set: { settings.enableJSONToExcel = $0 }
                    )
                )
                featureToggleRow(
                    icon: "curlybraces",
                    titleKey: "feature_table_to_json",
                    isOn: Binding(
                        get: { settings.enableTableToJSON },
                        set: { settings.enableTableToJSON = $0 }
                    )
                )
                featureToggleRow(
                    icon: "arrow.up.forward.square",
                    titleKey: "feature_open_url",
                    isOn: Binding(
                        get: { settings.enableOpenURLInBrowser },
                        set: { settings.enableOpenURLInBrowser = $0 }
                    )
                )
                featureToggleRow(
                    icon: "calendar.badge.clock",
                    titleKey: "feature_timestamp",
                    isOn: Binding(
                        get: { settings.enableTimestampConvert },
                        set: { settings.enableTimestampConvert = $0 }
                    )
                )
                featureToggleRow(
                    icon: "magnifyingglass",
                    titleKey: "feature_search",
                    isOn: Binding(
                        get: { settings.enableSearch },
                        set: { settings.enableSearch = $0 }
                    )
                )
                featureToggleRow(
                    icon: "hand.draw",
                    titleKey: "feature_drag_drop",
                    isOn: Binding(
                        get: { settings.enableDragAndDrop },
                        set: { settings.enableDragAndDrop = $0 }
                    )
                )
                featureToggleRow(
                    icon: "number.square",
                    titleKey: "feature_number_shortcuts",
                    isOn: Binding(
                        get: { settings.enableNumberShortcuts },
                        set: { settings.enableNumberShortcuts = $0 }
                    )
                )
                featureToggleRow(
                    icon: "rectangle.portrait.and.arrow.right",
                    titleKey: "feature_hide_popup_after_drag",
                    isOn: Binding(
                        get: { settings.hidePopupAfterDrag },
                        set: { settings.hidePopupAfterDrag = $0 }
                    )
                )
                featureToggleRow(
                    icon: "lock.shield",
                    titleKey: "otp_feature_enable",
                    isOn: Binding(
                        get: { settings.enableOTP },
                        set: { settings.enableOTP = $0 }
                    )
                )
                if settings.enableOTP {
                    settingsCard {
                        HStack {
                            Label(localization.localizedString("otp_grace_period"), systemImage: "clock")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Picker("", selection: Binding(
                                get: { settings.otpGracePeriodMinutes },
                                set: { settings.otpGracePeriodMinutes = $0 }
                            )) {
                                Text(localization.localizedString("otp_grace_1")).tag(1)
                                Text(localization.localizedString("otp_grace_5")).tag(5)
                                Text(localization.localizedString("otp_grace_15")).tag(15)
                            }
                            .labelsHidden().frame(width: 120)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func featureToggleRow(icon: String, titleKey: String, isOn: Binding<Bool>) -> some View {
        settingsCard {
            HStack {
                Label(localization.localizedString(titleKey), systemImage: icon)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Toggle("", isOn: isOn)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
        }
    }

    // MARK: - Components
    
    @ViewBuilder
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(settings.themedSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
            )
    }
    
    private func languageButton(flag: String, label: String, language: Language) -> some View {
        Button(action: {
            selectedLanguage = language
            localization.currentLanguage = language
            NotificationCenter.default.post(name: .languageChanged, object: nil)
        }) {
            HStack(spacing: 4) {
                Text(flag)
                    .font(.system(size: 14))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectedLanguage == language ? settings.themedAccent.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(selectedLanguage == language ? settings.themedAccent : Color(NSColor.separatorColor), lineWidth: selectedLanguage == language ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func themeSwatch(theme: AppTheme) -> some View {
        let isSelected = settings.appTheme == theme
        return Button(action: { settings.appTheme = theme }) {
            ZStack {
                Circle()
                    .fill(theme.swatchColor)
                    .frame(width: 28, height: 28)
                if theme == .system {
                    // System theme = pattern conic gradient để nhận biết
                    Circle()
                        .fill(AngularGradient(
                            gradient: Gradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red]),
                            center: .center
                        ))
                        .frame(width: 28, height: 28)
                }
                if isSelected {
                    Circle()
                        .stroke(Color.primary, lineWidth: 2)
                        .frame(width: 32, height: 32)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.4), radius: 1)
                }
            }
            .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .help(theme.displayName)
    }

}

/// Khung minh họa động: con trỏ ở tâm, hộp thoại vẽ theo hướng đang chọn.
/// Toạ độ SwiftUI có y hướng xuống nên "trên" = y nhỏ hơn tâm.
struct PopupAnchorPreview: View {
    let anchor: PopupAnchor
    let accent: Color

    private let boardW: CGFloat = 150
    private let boardH: CGFloat = 104

    var body: some View {
        let pw = boardW * 0.42
        let ph = boardH * 0.42
        let cx = boardW / 2
        let cy = boardH / 2

        let px: CGFloat = {
            switch anchor.horizontal {
            case .leading:  return cx - pw
            case .center:   return cx - pw / 2
            case .trailing: return cx
            }
        }()
        let py: CGFloat = {
            switch anchor.vertical {
            case .top:    return cy - ph   // hộp thoại phía trên con trỏ
            case .middle: return cy - ph / 2
            case .bottom: return cy        // hộp thoại phía dưới con trỏ
            }
        }()

        return ZStack {
            // Nền tượng trưng cho màn hình
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                )

            // Hộp thoại lịch sử
            RoundedRectangle(cornerRadius: 5)
                .fill(accent.opacity(0.22))
                .overlay(
                    RoundedRectangle(cornerRadius: 5).stroke(accent, lineWidth: 1.2)
                )
                .frame(width: pw, height: ph)
                .position(x: px + pw / 2, y: py + ph / 2)

            // Con trỏ chuột ở tâm
            Image(systemName: "cursorarrow")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.primary)
                .shadow(color: Color(NSColor.windowBackgroundColor), radius: 1)
                .position(x: cx, y: cy)
        }
        .frame(width: boardW, height: boardH)
        .animation(.easeInOut(duration: 0.18), value: anchor)
    }
}
