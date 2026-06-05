import SwiftUI
import Cocoa
import libxlsxwriter

enum ContentFilter: String, CaseIterable {
    case all
    case text
    case image
    case file
    case bookmark
    case otp

    var localizationKey: String {
        switch self {
        case .all: return "filter_all"
        case .text: return "filter_text"
        case .image: return "filter_image"
        case .file: return "filter_file"
        case .bookmark: return "filter_bookmark"
        case .otp: return "filter_otp"
        }
    }

    var displayName: String {
        Localization.shared.localizedString(localizationKey)
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .text: return "doc.text"
        case .image: return "photo"
        case .file: return "doc"
        case .bookmark: return "bookmark"
        case .otp: return "lock.shield"
        }
    }

    var color: Color {
        switch self {
        case .all: return .primary
        case .text: return .blue
        case .image: return .green
        case .file: return .orange
        case .bookmark: return .blue
        case .otp: return .purple
        }
    }
}

struct ClipboardHistoryView: View {
    let items: [ClipboardItem]
    let onItemSelected: (ClipboardItem) -> Void
    let onClearAll: (Bool, Bool) -> Void  // (includePinned, includeBookmarked)
    let onCopyOnly: ((ClipboardItem) -> Void)?
    let onTogglePin: ((ClipboardItem) -> Void)?
    let onDeleteItem: ((ClipboardItem) -> Void)?
    let onToggleBookmark: ((ClipboardItem) -> Void)?
    let onPasteOTP: ((String) -> Void)?
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var otpManager = OTPManager.shared
    @State private var selectedFilter: ContentFilter = .all
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchWorkItem: DispatchWorkItem?
    @State private var isSearchFieldFocused = false
    @State private var keyboardMonitor: Any?
    @State private var selectedIndex: Int = 0
    @State private var otpNow = Date()
    private let otpTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // Helper để check file có phải ảnh không
    private func isImageFile(_ item: ClipboardItem) -> Bool {
        guard item.type == .file, let fileURL = item.fileURL else { return false }
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "heic", "heif", "webp", "svg"]
        let fileExtension = URL(fileURLWithPath: fileURL).pathExtension.lowercased()
        return imageExtensions.contains(fileExtension)
    }
    
    // Bỏ dấu tiếng Việt
    private static func removeDiacritics(_ str: String) -> String {
        return str.folding(options: .diacriticInsensitive, locale: Locale(identifier: "vi"))
    }
    
    private func matchesSearch(_ item: ClipboardItem, _ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let normalizedQuery = ClipboardHistoryView.removeDiacritics(query.lowercased())

        if let text = item.text,
           ClipboardHistoryView.removeDiacritics(text.lowercased()).contains(normalizedQuery) {
            return true
        }
        if let fileName = item.fileName,
           ClipboardHistoryView.removeDiacritics(fileName.lowercased()).contains(normalizedQuery) {
            return true
        }
        if let appName = item.sourceAppName,
           ClipboardHistoryView.removeDiacritics(appName.lowercased()).contains(normalizedQuery) {
            return true
        }
        return false
    }
    
    var filteredItems: [ClipboardItem] {
        var result: [ClipboardItem]
        switch selectedFilter {
        case .all:
            result = items.filter { !$0.isBookmarked }
        case .text:
            result = items.filter { $0.type == .text && !$0.isBookmarked }
        case .image:
            result = items.filter { ($0.type == .image || isImageFile($0)) && !$0.isBookmarked }
        case .file:
            result = items.filter { $0.type == .file && !$0.isBookmarked }
        case .bookmark:
            result = items.filter { $0.isBookmarked }
        case .otp:
            result = []
        }
        
        if !debouncedSearchText.isEmpty {
            result = result.filter { matchesSearch($0, debouncedSearchText) }
        }
        return result
    }
    
    private func showClearDataDialog() {
        let loc = Localization.shared
        let alert = NSAlert()
        alert.messageText = loc.localizedString("clear_dialog_title")
        alert.informativeText = loc.localizedString("clear_dialog_message")
        alert.alertStyle = .warning

        // Accessory view: 2 checkbox (mặc định OFF)
        let pinCheck = NSButton(checkboxWithTitle: loc.localizedString("clear_dialog_include_pinned"),
                                target: nil, action: nil)
        pinCheck.state = .off
        let bmCheck = NSButton(checkboxWithTitle: loc.localizedString("clear_dialog_include_bookmarked"),
                               target: nil, action: nil)
        bmCheck.state = .off

        let stack = NSStackView(views: [pinCheck, bmCheck])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = true
        stack.frame = NSRect(x: 0, y: 0, width: 320, height: 50)
        alert.accessoryView = stack

        alert.addButton(withTitle: loc.localizedString("clear_dialog_confirm"))
        alert.addButton(withTitle: loc.localizedString("clear_dialog_cancel"))

        if alert.runModal() == .alertFirstButtonReturn {
            onClearAll(pinCheck.state == .on, bmCheck.state == .on)
        }
    }

    private func focusSearchField() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isSearchFieldFocused = true
        }
    }
    
    private func debounceSearch(_ text: String) {
        searchWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            debouncedSearchText = text
        }
        searchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }
    
    var body: some View {
        clipboardContent
            .onReceive(otpTicker) { otpNow = $0 }
    }

    private var clipboardContent: some View {
        VStack(spacing: 0) {
            // Filter bar - có thể kéo để move window
            HStack(spacing: 8) {
                ForEach(ContentFilter.allCases.filter { $0 != .otp || settings.enableOTP }, id: \.self) { filter in
                    PillIconButton(
                        systemImage: filter.icon,
                        isActive: selectedFilter == filter,
                        activeBackground: settings.themedAccent,
                        activeForeground: .white,
                        inactiveBackground: settings.themedSurface,
                        inactiveForeground: settings.isCustomThemeActive ? settings.themedForeground.opacity(0.7) : filter.color
                    ) {
                        selectedFilter = filter
                        if let window = NSApp.windows.first(where: { $0.isVisible && ($0 is NSPanel) && $0.title.hasPrefix("Clipboard") }) {
                            window.title = filter == .all ? "Clipboard" : "Clipboard - \(filter.displayName)"
                        }
                    }
                    .tooltip(filter.displayName)
                }
                
                Spacer()
                    .frame(minWidth: 12)
                    .contentShape(Rectangle())
                    // Drag move window CHỈ ở vùng trống giữa filter và search button.
                    // Để DragGesture trên Button parent sẽ nuốt mouseDown → click filter không fire.
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { value in
                                guard let window = NSApp.windows.first(where: { $0.isVisible && ($0 is NSPanel) && $0.title.hasPrefix("Clipboard") }) else {
                                    return
                                }
                                let currentLocation = NSEvent.mouseLocation
                                var newOrigin = NSPoint(
                                    x: currentLocation.x - value.startLocation.x,
                                    y: currentLocation.y + value.startLocation.y - window.frame.height
                                )
                                let screen = NSScreen.screens.first(where: { $0.frame.contains(currentLocation) }) ?? NSScreen.main
                                if let visible = screen?.visibleFrame {
                                    newOrigin.x = max(visible.minX, min(newOrigin.x, visible.maxX - window.frame.width))
                                    newOrigin.y = max(visible.minY, min(newOrigin.y, visible.maxY - window.frame.height))
                                }
                                window.setFrameOrigin(newOrigin)
                            }
                    )

                if settings.enableSearch {
                    PillIconButton(
                        systemImage: "magnifyingglass",
                        isActive: isSearching,
                        activeBackground: settings.themedAccent,
                        activeForeground: .white,
                        inactiveBackground: settings.themedSurface,
                        inactiveForeground: .secondary
                    ) {
                        if !isSearching {
                            isSearching = true
                        }
                        focusSearchField()
                    }
                    .tooltip(Localization.shared.localizedString("search_tooltip"))
                }
                
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(settings.themedBackground)
            // Filter bar phải paint trên cùng để tooltip (offset y+30) không bị list items đè
            .zIndex(2)

            // Search bar
            if isSearching {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    
                    FocusableTextField(text: $searchText, placeholder: Localization.shared.localizedString("search_placeholder"), isFocused: $isSearchFieldFocused)
                        .frame(height: 22)
                        .onChange(of: searchText) { newValue in
                            debounceSearch(newValue)
                        }
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            debouncedSearchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(settings.themedSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(settings.themedAccent.opacity(0.5), lineWidth: 1.5)
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    // Anchor cho scroll-to-top
                    Color.clear.frame(height: 0).id("__top__")
                    if settings.enableOTP && (selectedFilter == .otp || !debouncedSearchText.isEmpty) {
                        otpSection
                    }
                    if filteredItems.isEmpty {
                        if selectedFilter != .otp { emptyState }
                    } else {
                        LazyVStack(spacing: settings.useNativeUI ? 0 : 8) {
                            ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                                ClipboardItemView(
                                    item: item,
                                    index: index + 1,
                                    isSelected: index == selectedIndex,
                                    isNativeStyle: settings.useNativeUI,
                                    onItemSelected: onItemSelected,
                                    onCopyOnly: onCopyOnly,
                                    onTogglePin: onTogglePin,
                                    onDeleteItem: onDeleteItem,
                                    onToggleBookmark: onToggleBookmark
                                )
                            }
                        }
                        .padding(.horizontal, settings.useNativeUI ? 0 : 8)
                        .padding(.top, settings.useNativeUI ? 0 : 8)
                        .padding(.bottom, settings.useNativeUI ? 0 : 12)
                    }
                }
                .onChange(of: selectedFilter) { _ in
                    selectedIndex = 0
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("__top__", anchor: .top)
                    }
                }
                .onChange(of: debouncedSearchText) { _ in
                    selectedIndex = 0
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("__top__", anchor: .top)
                    }
                }
                .onChange(of: selectedIndex) { newIndex in
                    let current = filteredItems
                    if newIndex >= 0 && newIndex < current.count {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(current[newIndex].id, anchor: .center)
                        }
                    }
                }
            }

            shortcutHintBar
        }
        .frame(width: 300, height: 450)
        .background(settings.themedBackground)
        .modifier(ConditionalThemeModifier(theme: settings.appTheme, active: settings.isCustomThemeActive))
        .onAppear {
            installKeyboardMonitor()
        }
        .onDisappear {
            removeKeyboardMonitor()
        }
    }

    @ViewBuilder
    private var otpSection: some View {
        if selectedFilter == .otp {
            OTPTabView(onPasteCode: { onPasteOTP?($0) }, searchText: debouncedSearchText)
        } else {
            // Kết quả tìm kiếm ở filter khác: chỉ hiện OTP khớp từ khóa.
            let list = otpManager.search(debouncedSearchText)
            if !list.isEmpty {
                LazyVStack(spacing: 8) {
                    ForEach(list) { item in otpSearchRow(item) }
                }.padding(.horizontal, 8).padding(.vertical, 4)
            }
        }
    }

    /// Dòng OTP trong kết quả tìm kiếm: khóa thì chỉ hiện tên, mở khóa thì hiện mã + paste.
    private func otpSearchRow(_ item: OTPItem) -> some View {
        let unlocked = otpManager.isUnlocked
        return Button(action: {
            if unlocked, let c = item.code(at: otpNow) { onPasteOTP?(c) }
        }) {
            HStack {
                Image(systemName: "lock.shield").font(.system(size: 12)).foregroundColor(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.system(size: 12, weight: .medium)).foregroundColor(settings.themedForeground)
                    if let iss = item.issuer, !iss.isEmpty { Text(iss).font(.system(size: 10)).foregroundColor(.secondary) }
                }
                Spacer()
                if unlocked {
                    Text(item.code(at: otpNow) ?? "------")
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundColor(settings.themedAccent)
                    let remaining = item.secondsRemaining(at: otpNow)
                    ZStack {
                        Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                        Circle().trim(from: 0, to: CGFloat(remaining) / CGFloat(max(item.period, 1)))
                            .stroke(settings.themedAccent, lineWidth: 2)
                            .rotationEffect(.degrees(-90))
                        Text("\(remaining)").font(.system(size: 9))
                    }.frame(width: 22, height: 22)
                } else {
                    Image(systemName: "lock.fill").foregroundColor(.secondary)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(settings.themedSurface))
        }.buttonStyle(.plain).disabled(!unlocked)
    }

    @ViewBuilder
    private var shortcutHintBar: some View {
        HStack(spacing: 10) {
            shortcutHint(keys: "↑↓", label: Localization.shared.localizedString("hint_navigate"))
            Text("·").foregroundColor(.secondary.opacity(0.5))
            shortcutHint(keys: "⏎", label: Localization.shared.localizedString("hint_paste"))
            if settings.enableNumberShortcuts {
                Text("·").foregroundColor(.secondary.opacity(0.5))
                shortcutHint(keys: "⌘1-9", label: Localization.shared.localizedString("hint_quick_paste"))
            }
            Spacer(minLength: 4)
            // More menu (Settings + Clear data)
            MenuPillIconButton(
                systemImage: "gearshape",
                activeBackground: settings.themedAccent,
                inactiveBackground: Color.clear,
                inactiveForeground: .secondary,
                size: CGSize(width: 22, height: 20),
                cornerRadius: 4,
                fontSize: 11
            ) {
                Button {
                    SettingsWindow.shared.show()
                } label: {
                    Label(Localization.shared.localizedString("settings"), systemImage: "gearshape")
                }
                if selectedFilter == .otp {
                    Divider()
                    Button {
                        OTPBackup.exportInteractive()
                    } label: {
                        Label(Localization.shared.localizedString("otp_export"), systemImage: "square.and.arrow.up")
                    }
                    Button {
                        OTPBackup.importInteractive()
                    } label: {
                        Label(Localization.shared.localizedString("otp_import"), systemImage: "square.and.arrow.down")
                    }
                }
                Divider()
                Button {
                    showClearDataDialog()
                } label: {
                    Label(Localization.shared.localizedString("menu_clear_data"), systemImage: "trash")
                }
            }
            .tooltip(Localization.shared.localizedString("menu_more"))
        }
        .font(.system(size: 10))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            settings.themedBackground
                .overlay(
                    Rectangle()
                        .fill(Color(NSColor.separatorColor))
                        .frame(height: 0.5),
                    alignment: .top
                )
        )
    }

    @ViewBuilder
    private func shortcutHint(keys: String, label: String) -> some View {
        HStack(spacing: 3) {
            Text(keys)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary.opacity(0.8))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(settings.themedAccent.opacity(0.15))
                )
            Text(label)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let isSearchActive = !debouncedSearchText.isEmpty
        VStack(spacing: 8) {
            Spacer().frame(height: 60)
            Image(systemName: isSearchActive ? "magnifyingglass" : "tray")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text(Localization.shared.localizedString(isSearchActive ? "empty_search_no_results" : "empty_history"))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func installKeyboardMonitor() {
        // Đảm bảo không leak monitor cũ (View có thể onAppear lại sau khi onDisappear)
        removeKeyboardMonitor()
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // ESC luôn đóng popup
            if event.keyCode == 53 {
                if let window = NSApp.windows.first(where: { $0.isVisible && ($0 is NSPanel) && $0.title.hasPrefix("Clipboard") }) {
                    window.close()
                }
                return nil
            }

            // Tab OTP tự xử lý bàn phím (nhập PIN, ô tìm kiếm, sheet) — không can thiệp,
            // nếu không gõ PIN sẽ kích hoạt nhầm tìm kiếm.
            if selectedFilter == .otp { return event }

            let items = filteredItems
            let count = items.count

            // Cmd+1..9 → paste item thứ N (1-based)
            if Settings.shared.enableNumberShortcuts {
                let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if mods == .command, let idx = ClipboardHistoryView.numberKeyToIndex(event.keyCode) {
                    if idx < count {
                        onItemSelected(items[idx])
                    }
                    return nil
                }
            }

            // Khi search bar đang mở → TextField cần nhận chữ + delete + space.
            // Chỉ giữ lại arrow/enter cho điều hướng list, return event cho mọi phím khác.
            if isSearching {
                if event.keyCode == 125 || event.keyCode == 126 {
                    return handleArrowSelection(event: event, count: count)
                }
                if event.keyCode == 36 || event.keyCode == 76 {
                    if count > 0 { triggerSelectedPaste(items: items) }
                    return nil
                }
                return event
            }

            // ↓ (125) / ↑ (126)
            if event.keyCode == 125 || event.keyCode == 126 {
                return handleArrowSelection(event: event, count: count)
            }

            // Return (36) hoặc Enter (76) → paste item đang chọn
            if event.keyCode == 36 || event.keyCode == 76 {
                if count > 0 { triggerSelectedPaste(items: items) }
                return nil
            }

            // Delete (51) hoặc Forward Delete (117) → xoá item đang chọn
            if event.keyCode == 51 || event.keyCode == 117 {
                if count > 0, selectedIndex >= 0, selectedIndex < count {
                    let item = items[selectedIndex]
                    onDeleteItem?(item)
                    if selectedIndex >= count - 1, selectedIndex > 0 {
                        selectedIndex -= 1
                    }
                }
                return nil
            }

            // Nếu user đã tắt tính năng search thì bỏ qua phần auto-focus search
            if !Settings.shared.enableSearch { return event }
            // Nếu đang search rồi thì không xử lý
            if isSearching { return event }

            // Bỏ qua phím đặc biệt còn lại (Tab)
            let specialKeys: Set<UInt16> = [48]
            if specialKeys.contains(event.keyCode) { return event }

            // Bỏ qua nếu có modifier (Cmd, Ctrl) trừ Shift và CapsLock
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.shift, .capsLock])
            if !mods.isEmpty { return event }

            // Kích hoạt search khi gõ ký tự
            if let chars = event.characters, !chars.isEmpty {
                isSearching = true
                searchText = chars
                debounceSearch(chars)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isSearchFieldFocused = true
                }
                return nil
            }
            return event
        }
    }

    /// Map keyCode của số 1..9 trên top-row qua index 0..8.
    private static func numberKeyToIndex(_ keyCode: UInt16) -> Int? {
        switch keyCode {
        case 0x12: return 0  // 1
        case 0x13: return 1  // 2
        case 0x14: return 2  // 3
        case 0x15: return 3  // 4
        case 0x17: return 4  // 5
        case 0x16: return 5  // 6
        case 0x1A: return 6  // 7
        case 0x1C: return 7  // 8
        case 0x19: return 8  // 9
        default: return nil
        }
    }

    private func handleArrowSelection(event: NSEvent, count: Int) -> NSEvent? {
        guard count > 0 else { return nil }
        if event.keyCode == 125 {
            // ↓
            selectedIndex = min(selectedIndex + 1, count - 1)
        } else if event.keyCode == 126 {
            // ↑
            selectedIndex = max(selectedIndex - 1, 0)
        }
        return nil
    }

    private func triggerSelectedPaste(items: [ClipboardItem]) {
        guard selectedIndex >= 0, selectedIndex < items.count else { return }
        let item = items[selectedIndex]
        onItemSelected(item)
    }

    private func removeKeyboardMonitor() {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
    }

}

/// Icon button cùng style với filter/search/trash trong popup.
/// Khi hover nền hiện nhạt hơn (~18% opacity của activeBackground) để feedback "có thể click".
struct PillIconButton: View {
    let systemImage: String
    let isActive: Bool
    let activeBackground: Color
    let activeForeground: Color
    let inactiveBackground: Color
    let inactiveForeground: Color
    var size: CGSize = CGSize(width: 32, height: 28)
    var cornerRadius: CGFloat = 6
    var fontSize: CGFloat = 14
    var fontWeight: Font.Weight = .regular
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: fontSize, weight: fontWeight))
                .frame(width: size.width, height: size.height)
                .background(currentBackground)
                .foregroundColor(isActive ? activeForeground : inactiveForeground)
                .cornerRadius(cornerRadius)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private var currentBackground: Color {
        if isActive { return activeBackground }
        if isHovered { return activeBackground.opacity(0.18) }
        return inactiveBackground
    }
}

/// Pill icon button mở dropdown menu (style giống PillIconButton, không có active state).
struct MenuPillIconButton<Items: View>: View {
    let systemImage: String
    let activeBackground: Color
    let inactiveBackground: Color
    let inactiveForeground: Color
    var size: CGSize = CGSize(width: 32, height: 28)
    var cornerRadius: CGFloat = 6
    var fontSize: CGFloat = 14
    @ViewBuilder let menuContent: () -> Items
    @State private var isHovered = false

    var body: some View {
        Menu {
            menuContent()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: fontSize))
                .frame(width: size.width, height: size.height)
                .background(isHovered ? activeBackground.opacity(0.18) : inactiveBackground)
                .foregroundColor(inactiveForeground)
                .cornerRadius(cornerRadius)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: size.width, height: size.height)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

/// Action button trong item row (open, copy, save, json↔table...).
/// Background màu khi default; hover làm nhạt để feedback "có thể click".
/// Khi custom theme đang active → background = accent của theme thay vì semantic color.
struct ActionIconButton: View {
    let systemImage: String
    let background: Color
    var size: CGSize = CGSize(width: 24, height: 24)
    var fontSize: CGFloat = 12
    let action: () -> Void
    @State private var isHovered = false
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: fontSize))
                .foregroundColor(.white)
                .frame(width: size.width, height: size.height)
                .background(isHovered ? effectiveBackground.opacity(0.7) : effectiveBackground)
                .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private var effectiveBackground: Color {
        // Khi custom theme active, đồng bộ tất cả action button về accent của theme
        if settings.isCustomThemeActive, let accent = settings.appTheme.accent {
            return accent
        }
        return background
    }
}

struct FocusableTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    @Binding var isFocused: Bool
    
    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.font = NSFont.systemFont(ofSize: 12)
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.focusRingType = .none
        textField.delegate = context.coordinator
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if isFocused {
            DispatchQueue.main.async {
                if let window = nsView.window {
                    window.makeFirstResponder(nsView)
                    // Di chuyển cursor về cuối
                    if let editor = nsView.currentEditor() {
                        editor.selectedRange = NSRange(location: nsView.stringValue.count, length: 0)
                    }
                    isFocused = false
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FocusableTextField
        
        init(_ parent: FocusableTextField) {
            self.parent = parent
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }
    }
}

struct ClipboardItemView: View {
    private static let fileIconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 256
        return cache
    }()

    /// Export image clipboard item ra file PNG tạm để hỗ trợ drag-drop ra Finder/app khác.
    /// Tên file dựa hash của fileName để dedup → 2 lần drag cùng ảnh không tạo 2 file trùng.
    static func exportImageToTempFile(_ item: ClipboardItem) -> URL? {
        guard item.type == .image, let imageData = item.imageData else { return nil }
        let fileName = "Clipboard_\(item.timeString.replacingOccurrences(of: ":", with: "-")).png"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: tempURL.path) {
            return tempURL  // reuse
        }
        guard let nsImage = NSImage(data: imageData),
              let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        do {
            try pngData.write(to: tempURL)
            return tempURL
        } catch {
            print("DEBUG: exportImageToTempFile lỗi: \(error)")
            return nil
        }
    }

    static func cachedFileIcon(for path: String) -> NSImage {
        let key = path as NSString
        if let cached = fileIconCache.object(forKey: key) {
            return cached
        }
        // NSWorkspace có thể trả về instance dùng chung — copy trước khi mutate size
        let raw = NSWorkspace.shared.icon(forFile: path)
        let icon = (raw.copy() as? NSImage) ?? raw
        icon.size = NSSize(width: 32, height: 32)
        fileIconCache.setObject(icon, forKey: key)
        return icon
    }
    
    let item: ClipboardItem
    let index: Int
    var isSelected: Bool = false
    var isNativeStyle: Bool = false
    let onItemSelected: (ClipboardItem) -> Void
    let onCopyOnly: ((ClipboardItem) -> Void)?
    let onTogglePin: ((ClipboardItem) -> Void)?
    let onDeleteItem: ((ClipboardItem) -> Void)?
    let onToggleBookmark: ((ClipboardItem) -> Void)?
    @State private var isHovered = false
    @State private var showAsDateTime = false
    @State private var showAsTable = false
    @State private var showAsJSON = false
    @State private var displayText: String = ""
    @State private var cachedImage: NSImage? = nil
    @ObservedObject private var settings = Settings.shared
    
    var typeIcon: String {
        switch item.type {
        case .text: return "doc.text"
        case .image: return "photo"
        case .file:
            if item.isDirectory == true {
                return "folder"
            } else {
                return "doc"
            }
        }
    }
    
    var typeColor: Color {
        switch item.type {
        case .text: return .blue
        case .image: return .green
        case .file:
            if item.isDirectory == true {
                return .blue
            } else {
                return .orange
            }
        }
    }
    
    // Check if file is an image
    private func isImageFile(_ fileURL: String) -> Bool {
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "heic", "heif", "webp", "svg"]
        let fileExtension = URL(fileURLWithPath: fileURL).pathExtension.lowercased()
        return imageExtensions.contains(fileExtension)
    }
    
    // Check if text is a URL
    private func isURL(_ text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmedText),
           let scheme = url.scheme,
           (scheme == "http" || scheme == "https") {
            return true
        }
        return false
    }
    
    // Get URL from text
    private func getURL() -> URL? {
        guard let text = item.text else { return nil }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: trimmedText)
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 6) {
                if item.type == .image, let image = cachedImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 50)
                        .clipped()
                } else if item.type == .file, let fileName = item.fileName, let fileURL = item.fileURL {
                    if isImageFile(fileURL), let image = cachedImage {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 50)
                            .clipped()
                    } else {
                        HStack(spacing: 8) {
                            Image(nsImage: ClipboardItemView.cachedFileIcon(for: fileURL))
                                .resizable()
                                .frame(width: 24, height: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(fileName)
                                    .font(.system(
                                        size: CGFloat(settings.appFontSize),
                                        design: settings.appFontDesign.swiftUIDesign
                                    ))
                                    .foregroundColor(settings.themedForeground)
                                    .lineLimit(1)

                                Text(URL(fileURLWithPath: fileURL).deletingLastPathComponent().path)
                                    .font(.system(
                                        size: max(CGFloat(settings.appFontSize) - 2, 8),
                                        design: settings.appFontDesign.swiftUIDesign
                                    ))
                                    .foregroundColor(settings.themedForeground.opacity(0.65))
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                        }
                    }
                } else if item.text != nil {
                    HStack(spacing: 8) {
                        Text(displayText)
                            .lineLimit(3)
                            .font(.system(
                                size: CGFloat(settings.appFontSize),
                                design: settings.appFontDesign.swiftUIDesign
                            ))
                            .foregroundColor(settings.themedForeground)

                        if item.isTimestamp && Settings.shared.enableTimestampConvert {
                            Button(action: {
                                toggleTimestampDisplay()
                            }) {
                                Image(systemName: showAsDateTime ? "clock.arrow.circlepath" : "calendar.badge.clock")
                                    .font(.system(size: 12))
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .tooltip(Localization.shared.localizedString(showAsDateTime ? "action_show_timestamp" : "action_show_datetime"))
                            .onHover { hovering in
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                        }
                    }
                }
                
                if settings.showItemInfoLine {
                HStack(spacing: 6) {
                    Text("\(index)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(settings.themedAccent.opacity(0.8))
                        .cornerRadius(3)

                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                    
                    if item.isBookmarked {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.blue)
                    }
                    
                    if item.isJSON {
                        Image(systemName: "curlybraces")
                            .font(.system(size: 10))
                            .foregroundColor(.purple)
                    }
                    
                    if item.isExcelData {
                        Image(systemName: "tablecells")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                    }
                    
                    Image(systemName: typeIcon)
                        .font(.system(size: 10))
                        .foregroundColor(typeColor)

                    if let icon = item.appIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 12, height: 12)
                    }

                    if let appName = item.sourceAppName {
                        Text(appName)
                            .font(.system(size: 10))
                            .foregroundColor(settings.themedForeground.opacity(0.65))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Text(item.timeString)
                        .font(.system(size: 11))
                        .foregroundColor(settings.themedForeground.opacity(0.65))
                }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, isNativeStyle ? 6 : 8)
            .padding(.horizontal, isNativeStyle ? 10 : 8)

            if isHovered {
                HStack(spacing: 4) {
                    // Open button cho file/folder/URL/image
                    if item.type == .file, let fileURL = item.fileURL {
                        ActionIconButton(systemImage: "arrow.up.forward.square", background: .green) {
                            NSWorkspace.shared.open(URL(fileURLWithPath: fileURL))
                            if let window = NSApp.windows.first(where: { $0.isVisible && ($0 is NSPanel) && $0.title.hasPrefix("Clipboard") }) {
                                window.close()
                            }
                        }
                        .tooltip(Localization.shared.localizedString("action_open"))
                    } else if item.type == .text, let text = item.text, isURL(text), let url = getURL(), Settings.shared.enableOpenURLInBrowser {
                        ActionIconButton(systemImage: "arrow.up.forward.square", background: .green) {
                            NSWorkspace.shared.open(url)
                            if let window = NSApp.windows.first(where: { $0.isVisible && ($0 is NSPanel) && $0.title.hasPrefix("Clipboard") }) {
                                window.close()
                            }
                        }
                        .tooltip(Localization.shared.localizedString("action_open_url_browser"))
                    } else if item.type == .image {
                        ActionIconButton(systemImage: "arrow.up.forward.square", background: .green) {
                            openImageInPreview()
                        }
                        .tooltip(Localization.shared.localizedString("action_open"))
                    }
                    
                    // Conversion and Export buttons for JSON data
                    if item.type == .text && item.isJSON {
                        HStack(spacing: 4) {
                            if Settings.shared.enableJSONToTable {
                                ActionIconButton(
                                    systemImage: showAsTable ? "curlybraces" : "tablecells",
                                    background: .purple
                                ) {
                                    toggleJSONDisplay()
                                }
                                .tooltip(Localization.shared.localizedString(showAsTable ? "action_show_json" : "action_show_table"))
                            }

                            if Settings.shared.enableJSONToExcel {
                                ActionIconButton(
                                    systemImage: "tablecells.badge.ellipsis",
                                    background: .green
                                ) {
                                    exportJSONToExcelAndOpen()
                                }
                                .tooltip(Localization.shared.localizedString("action_export_excel_open"))
                            }
                        }
                    }

                    // Conversion button for Excel data
                    if item.type == .text && item.isExcelData && Settings.shared.enableTableToJSON {
                        ActionIconButton(
                            systemImage: showAsJSON ? "tablecells" : "curlybraces",
                            background: .green
                        ) {
                            toggleExcelDisplay()
                        }
                        .tooltip(Localization.shared.localizedString(showAsJSON ? "action_show_table" : "action_show_json"))
                    }

                    // Save image button (chỉ hiện cho ảnh không phải tệp tin)
                    if item.type == .image {
                        ActionIconButton(systemImage: "square.and.arrow.down", background: .green) {
                            saveImageToFile()
                        }
                        .tooltip(Localization.shared.localizedString("action_save_image"))
                    }

                    // Copy button
                    ActionIconButton(systemImage: "doc.on.doc", background: .accentColor) {
                        item.copyOnly(displayText: displayText)
                        onCopyOnly?(item)
                    }
                    .tooltip(Localization.shared.localizedString("action_copy"))
                }
                .padding(8)
            }
        }
        .background(rowBackground)
        .cornerRadius(isNativeStyle ? 0 : 8)
        .overlay(rowOverlay)
        .contentShape(Rectangle())
        .contextMenu {
            // Copy
            Button(action: {
                item.copyOnly(displayText: displayText)
                onCopyOnly?(item)
            }) {
                HStack {
                    Image(systemName: "doc.on.doc")
                    Text(Localization.shared.localizedString("action_copy"))
                }
            }

            // Save image (chỉ hiện cho ảnh không phải tệp tin)
            if item.type == .image {
                Button(action: {
                    saveImageToFile()
                }) {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text(Localization.shared.localizedString("action_save_image"))
                    }
                }
            }

            // Open
            if item.type == .file, let fileURL = item.fileURL {
                Button(action: {
                    NSWorkspace.shared.open(URL(fileURLWithPath: fileURL))
                    // Đóng window
                    if let window = NSApp.windows.first(where: { $0.isVisible && ($0 is NSPanel) && $0.title.hasPrefix("Clipboard") }) {
                        window.close()
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.up.forward.square")
                        Text(Localization.shared.localizedString("action_open"))
                    }
                }
            } else if item.type == .text, let text = item.text, isURL(text), let url = getURL() {
                Button(action: {
                    NSWorkspace.shared.open(url)
                    // Đóng window
                    if let window = NSApp.windows.first(where: { $0.isVisible && ($0 is NSPanel) && $0.title.hasPrefix("Clipboard") }) {
                        window.close()
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.up.forward.square")
                        Text(Localization.shared.localizedString("action_open_in_browser"))
                    }
                }
            } else if item.type == .image {
                Button(action: {
                    openImageInPreview()
                }) {
                    HStack {
                        Image(systemName: "arrow.up.forward.square")
                        Text(Localization.shared.localizedString("action_open"))
                    }
                }
            }

            Divider()

            // JSON/Excel conversion menu items
            if item.isJSON {
                Button(action: {
                    toggleJSONDisplay()
                }) {
                    HStack {
                        Image(systemName: showAsTable ? "curlybraces" : "tablecells")
                        Text(Localization.shared.localizedString(showAsTable ? "action_show_json" : "action_show_table"))
                    }
                }

                Button(action: {
                    exportJSONToExcelAndOpen()
                }) {
                    HStack {
                        Image(systemName: "tablecells.badge.ellipsis")
                        Text(Localization.shared.localizedString("action_export_excel_open"))
                    }
                }

                Divider()
            }

            if item.isExcelData {
                Button(action: {
                    toggleExcelDisplay()
                }) {
                    HStack {
                        Image(systemName: showAsJSON ? "tablecells" : "curlybraces")
                        Text(Localization.shared.localizedString(showAsJSON ? "action_show_table" : "action_show_json"))
                    }
                }
                
                Button(action: {
                    pasteExcelAsImage()
                }) {
                    HStack {
                        Image(systemName: "photo")
                        Text(Localization.shared.localizedString("action_paste_as_image"))
                    }
                }

                Divider()
            }

            Button(action: {
                onTogglePin?(item)
            }) {
                HStack {
                    Image(systemName: item.isPinned ? "pin.slash" : "pin")
                    Text(Localization.shared.localizedString(item.isPinned ? "action_unpin" : "action_pin"))
                }
            }

            Button(action: {
                onToggleBookmark?(item)
            }) {
                HStack {
                    Image(systemName: item.isBookmarked ? "bookmark.slash" : "bookmark")
                    Text(Localization.shared.localizedString(item.isBookmarked ? "action_unbookmark" : "action_bookmark"))
                }
            }

            if item.type == .file {
                Divider()

                Button(action: {
                    item.copyPath()
                }) {
                    HStack {
                        Image(systemName: "doc.on.clipboard")
                        Text(Localization.shared.localizedString("action_copy_path"))
                    }
                }
            }

            Divider()

            Button(action: {
                onDeleteItem?(item)
            }) {
                HStack {
                    Image(systemName: "trash")
                    Text(Localization.shared.localizedString("action_delete"))
                }
            }
        }
        .onDrag {
            guard Settings.shared.enableDragAndDrop else { return NSItemProvider() }

            let provider: NSItemProvider
            if item.type == .file, let url = item.getFileURL(),
               FileManager.default.fileExists(atPath: url.path) {
                provider = NSItemProvider(object: url as NSURL)
            } else if item.type == .image, let url = ClipboardItemView.exportImageToTempFile(item) {
                provider = NSItemProvider(object: url as NSURL)
            } else {
                provider = NSItemProvider()
            }

            // Auto-hide popup khi user bắt đầu drag (nếu toggle bật)
            if Settings.shared.hidePopupAfterDrag {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if let window = NSApp.windows.first(where: { $0.isVisible && ($0 is NSPanel) && $0.title.hasPrefix("Clipboard") }) {
                        window.close()
                    }
                }
            }
            return provider
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onTapGesture {
            // If item has been converted (JSON→Table, Excel→JSON, or Timestamp→DateTime), paste and close
            if showAsTable || showAsJSON || showAsDateTime {
                item.paste(displayText: displayText)
                if let window = NSApp.windows.first(where: { $0.isVisible && ($0 is NSPanel) && $0.title.hasPrefix("Clipboard") }) {
                    window.close()
                }
            } else if item.type == .text && displayText != item.text {
                // Fallback: if displayText is different, paste it
                item.paste(displayText: displayText)
                if let window = NSApp.windows.first(where: { $0.isVisible && ($0 is NSPanel) && $0.title.hasPrefix("Clipboard") }) {
                    window.close()
                }
            } else {
                onItemSelected(item)
            }
        }
        .onAppear {
            updateDisplayText()
        }
    }
    
    private var rowBackground: Color {
        let accent = settings.themedAccent
        if isNativeStyle {
            if isSelected { return accent.opacity(0.45) }
            if isHovered { return accent.opacity(0.18) }
            if index % 2 == 1 {
                return settings.isCustomThemeActive ? settings.themedSurface : Color.primary.opacity(0.05)
            }
            return Color.clear
        }
        if isSelected { return accent.opacity(0.35) }
        if isHovered { return accent.opacity(0.15) }
        return settings.themedSurface
    }

    @ViewBuilder
    private var rowOverlay: some View {
        if isNativeStyle {
            // Thin separator dưới mỗi row, style Finder/Mail
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(height: 0.5)
                .frame(maxHeight: .infinity, alignment: .bottom)
        } else {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? settings.themedAccent : Color.gray.opacity(0.3),
                        lineWidth: isSelected ? 1.5 : 1)
        }
    }

    private func updateDisplayText() {
        if let text = item.text {
            displayText = text
        }
        loadThumbnailIfNeeded()
    }

    private func loadThumbnailIfNeeded() {
        guard cachedImage == nil else { return }
        // Image trong clipboard
        if item.type == .image, let fileName = item.imageFileName {
            DispatchQueue.global(qos: .userInitiated).async {
                guard let data = ClipboardManager.shared.loadImageFromDisk(fileName) else { return }
                let thumb = ImageThumbnail.load(data: data, maxPixelSize: 200)
                DispatchQueue.main.async {
                    self.cachedImage = thumb
                }
            }
            return
        }
        // File ảnh
        if item.type == .file, let fileURL = item.fileURL, isImageFile(fileURL) {
            let url = URL(fileURLWithPath: fileURL)
            DispatchQueue.global(qos: .userInitiated).async {
                let thumb = ImageThumbnail.load(fileURL: url, maxPixelSize: 200)
                DispatchQueue.main.async {
                    self.cachedImage = thumb
                }
            }
        }
    }
    
    private func exportJSONToExcelAndOpen() {
        guard let text = item.text, item.isJSON else { return }
        guard let data = text.data(using: .utf8) else { return }

        // Đẩy việc parse JSON + ghi xlsx (libxlsxwriter chạy đồng bộ đĩa) ra background
        DispatchQueue.global(qos: .userInitiated).async {
            self._exportJSONToExcelSync(data: data)
        }
    }

    private func _exportJSONToExcelSync(data: Data) {
        do {
            let json = try JSONSerialization.jsonObject(with: data)
            
            func flattenJSON(_ json: Any, prefix: String = "") -> [String: Any] {
                var result: [String: Any] = [:]
                if let dict = json as? [String: Any] {
                    for (key, value) in dict {
                        let newKey = prefix.isEmpty ? key : "\(prefix).\(key)"
                        if let subDict = value as? [String: Any] {
                            result.merge(flattenJSON(subDict, prefix: newKey)) { (_, new) in new }
                        } else if let subArray = value as? [Any] {
                            if subArray.allSatisfy({ $0 is [String: Any] == false && $0 is [Any] == false }) {
                                result[newKey] = subArray.map { "\($0)" }.joined(separator: ", ")
                            } else {
                                if let jsonData = try? JSONSerialization.data(withJSONObject: subArray, options: []),
                                   let jsonString = String(data: jsonData, encoding: .utf8) {
                                    result[newKey] = jsonString
                                }
                            }
                        } else {
                            result[newKey] = value
                        }
                    }
                } else if prefix.isEmpty, let array = json as? [Any] {
                    if array.allSatisfy({ $0 is [String: Any] == false && $0 is [Any] == false }) {
                        result["Value"] = array.map { "\($0)" }.joined(separator: ", ")
                    }
                }
                return result
            }
            
            let fileName = "clipboard_\(Int(Date().timeIntervalSince1970)).xlsx"
            let tempPath = (FileManager.default.temporaryDirectory.appendingPathComponent(fileName).path as NSString).utf8String
            
            let workbook = workbook_new(tempPath)
            let worksheet = workbook_add_worksheet(workbook, nil)
            
            // Format cho header
            let headerFormat = workbook_add_format(workbook)
            format_set_bold(headerFormat)
            format_set_bg_color(headerFormat, 0xD7E4BC) // Màu xanh nhạt
            format_set_border(headerFormat, 1) // LXW_BORDER_THIN
            
            if let array = json as? [Any] {
                if array.first is [String: Any] {
                    let flattenedArray = array.map { flattenJSON($0) }
                    var allKeys = Set<String>()
                    for item in flattenedArray {
                        allKeys.formUnion(item.keys)
                    }
                    let headers = Array(allKeys).sorted()
                    
                    // Ghi header
                    for (col, header) in headers.enumerated() {
                        worksheet_write_string(worksheet, 0, UInt16(col), header, headerFormat)
                        worksheet_set_column(worksheet, UInt16(col), UInt16(col), 20, nil)
                    }
                    
                    // Ghi data
                    for (row, item) in flattenedArray.enumerated() {
                        for (col, header) in headers.enumerated() {
                            let value = "\(item[header] ?? "")"
                            worksheet_write_string(worksheet, UInt32(row + 1), UInt16(col), value, nil)
                        }
                    }
                } else {
                    // Mảng các giá trị đơn giản
                    worksheet_write_string(worksheet, 0, 0, "Value", headerFormat)
                    worksheet_set_column(worksheet, 0, 0, 40, nil)
                    for (row, value) in array.enumerated() {
                        worksheet_write_string(worksheet, UInt32(row + 1), 0, "\(value)", nil)
                    }
                }
            } else if let dict = json as? [String: Any] {
                let flattened = flattenJSON(dict)
                let sortedKeys = flattened.keys.sorted()
                
                worksheet_write_string(worksheet, 0, 0, "Key", headerFormat)
                worksheet_write_string(worksheet, 0, 1, "Value", headerFormat)
                worksheet_set_column(worksheet, 0, 0, 25, nil)
                worksheet_set_column(worksheet, 1, 1, 40, nil)
                
                for (row, key) in sortedKeys.enumerated() {
                    worksheet_write_string(worksheet, UInt32(row + 1), 0, key, nil)
                    worksheet_write_string(worksheet, UInt32(row + 1), 1, "\(flattened[key] ?? "")", nil)
                }
            }
            
            workbook_close(workbook)

            let outURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            DispatchQueue.main.async {
                NSWorkspace.shared.open(outURL)
            }
        } catch {
            print("Error exporting JSON to XLSX: \(error)")
        }
    }
    
    private func toggleTimestampDisplay() {
        showAsDateTime.toggle()
        
        if showAsDateTime {
            // Convert timestamp to datetime
            if let text = item.text?.trimmingCharacters(in: .whitespaces),
               let dateString = item.timestampToDateString(text) {
                displayText = dateString
            }
        } else {
            // Show original timestamp
            if let text = item.text {
                displayText = text
            }
        }
    }
    
    private func openImageInPreview() {
        guard let url = ClipboardItemView.exportImageToTempFile(item) else { return }
        NSWorkspace.shared.open(url)
        if let window = NSApp.windows.first(where: { $0.isVisible && ($0 is NSPanel) && $0.title.hasPrefix("Clipboard") }) {
            window.close()
        }
    }

    private func saveImageToFile() {
        guard item.type == .image, let imageData = item.imageData else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "Clipboard_\(item.timeString.replacingOccurrences(of: ":", with: "-")).png"
        savePanel.level = .floating
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
            if let image = NSImage(data: imageData),
               let tiffData = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                try? pngData.write(to: url)
            }
        }
    }
    
    private func toggleJSONDisplay() {
        showAsTable.toggle()
        
        if showAsTable {
            // Convert JSON to table format (TSV) for display only
            guard let text = item.text, item.isJSON else { return }
            guard let data = text.data(using: .utf8) else { return }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data)
                var tsvContent = ""
                
                if let array = json as? [[String: Any]] {
                    guard let firstItem = array.first else { return }
                    let headers = Array(firstItem.keys).sorted()
                    
                    tsvContent += headers.joined(separator: "\t") + "\n"
                    
                    for item in array {
                        let values = headers.map { key -> String in
                            if let value = item[key] {
                                let stringValue = "\(value)"
                                return stringValue.replacingOccurrences(of: "\t", with: " ")
                                                 .replacingOccurrences(of: "\n", with: " ")
                            }
                            return ""
                        }
                        tsvContent += values.joined(separator: "\t") + "\n"
                    }
                } else if let dict = json as? [String: Any] {
                    tsvContent += "Key\tValue\n"
                    for (key, value) in dict.sorted(by: { $0.key < $1.key }) {
                        let stringValue = "\(value)".replacingOccurrences(of: "\t", with: " ")
                                                    .replacingOccurrences(of: "\n", with: " ")
                        tsvContent += "\(key)\t\(stringValue)\n"
                    }
                } else if let array = json as? [Any] {
                    tsvContent += "Value\n"
                    for value in array {
                        let stringValue = "\(value)".replacingOccurrences(of: "\t", with: " ")
                                                    .replacingOccurrences(of: "\n", with: " ")
                        tsvContent += "\(stringValue)\n"
                    }
                }
                
                displayText = tsvContent
            } catch {
                print("Error converting JSON to table: \(error)")
            }
        } else {
            // Show original JSON
            if let text = item.text {
                displayText = text
            }
        }
    }
    
    private func toggleExcelDisplay() {
        showAsJSON.toggle()
        
        if showAsJSON {
            // Convert Excel to JSON for display only (don't copy to clipboard yet)
            guard let text = item.text, item.isExcelData else { return }
            
            let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            
            let lines = cleanedText.components(separatedBy: .newlines).filter { line in
                let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
                                 .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                return !cleaned.isEmpty
            }
            
            guard lines.count >= 2 else { return }
            
            let headerLine = lines[0].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let headers = headerLine.components(separatedBy: "\t").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            var jsonArray: [[String: Any]] = []
            
            for i in 1..<lines.count {
                let valueLine = lines[i].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                let values = valueLine.components(separatedBy: "\t")
                var dict: [String: Any] = [:]
                
                for j in 0..<min(headers.count, values.count) {
                    let header = headers[j]
                    let value = values[j].trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if header.isEmpty { continue }
                    
                    if !value.isEmpty && value.hasPrefix("0") && value.count > 1 {
                        dict[header] = value
                    } else if let intValue = Int(value) {
                        dict[header] = intValue
                    } else if let doubleValue = Double(value) {
                        dict[header] = doubleValue
                    } else {
                        dict[header] = value
                    }
                }
                
                if !dict.isEmpty {
                    jsonArray.append(dict)
                }
            }
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: jsonArray, options: [.prettyPrinted, .sortedKeys])
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    displayText = jsonString
                }
            } catch {
                print("Error converting Excel to JSON: \(error)")
            }
        } else {
            // Show original Excel data
            if let text = item.text {
                displayText = text
            }
        }
    }
    
    private func pasteExcelAsImage() {
        // Đóng popup ngay để app trước được focus
        if let window = NSApp.windows.first(where: { $0.isVisible && ($0 is NSPanel) && $0.title.hasPrefix("Clipboard") }) {
            window.close()
        }
        // Render image off-main (drawing có thể nặng với bảng lớn)
        DispatchQueue.global(qos: .userInitiated).async {
            guard let imageData = self.generateExcelImageData() else { return }
            DispatchQueue.main.async {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setData(imageData, forType: .tiff)
                ClipboardManager.shared.ignoreNextChange()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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
        }
    }

    private func generateExcelImageData() -> Data? {
        guard let text = item.text, item.isExcelData else { return nil }
        
        // If we have the original image from Excel copy, use it
        if let imageData = item.imageData {
            return imageData
        }
        
        // Otherwise, render the table as image
        // Parse Excel data
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        
        let lines = cleanedText.components(separatedBy: .newlines).filter { line in
            let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
                             .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return !cleaned.isEmpty
        }
        
        guard !lines.isEmpty else { return nil }
        
        // Create table image
        let cellPadding: CGFloat = 8
        let fontSize: CGFloat = 11
        let font = NSFont.systemFont(ofSize: fontSize)
        let headerFont = NSFont.boldSystemFont(ofSize: fontSize)
        
        // Calculate column widths
        var columnWidths: [CGFloat] = []
        let maxColumns = lines.map { $0.components(separatedBy: "\t").count }.max() ?? 0
        
        for colIndex in 0..<maxColumns {
            var maxWidth: CGFloat = 0
            for (rowIndex, line) in lines.enumerated() {
                let cells = line.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    .components(separatedBy: "\t")
                if colIndex < cells.count {
                    let cellText = cells[colIndex]
                    let cellFont = rowIndex == 0 ? headerFont : font
                    let size = (cellText as NSString).size(withAttributes: [.font: cellFont])
                    maxWidth = max(maxWidth, size.width)
                }
            }
            columnWidths.append(maxWidth + cellPadding * 2)
        }
        
        let totalWidth = columnWidths.reduce(0, +)
        let rowHeight: CGFloat = fontSize + cellPadding * 2
        let totalHeight = CGFloat(lines.count) * rowHeight
        
        // Create image
        let imageSize = NSSize(width: totalWidth, height: totalHeight)
        let image = NSImage(size: imageSize)
        
        image.lockFocus()
        
        // Draw background
        NSColor.white.setFill()
        NSRect(origin: .zero, size: imageSize).fill()
        
        // Draw cells (from top to bottom, accounting for flipped coordinates)
        for (rowIndex, line) in lines.enumerated() {
            let cells = line.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                .components(separatedBy: "\t")
            
            // Calculate Y position from top (flip coordinate system)
            let yOffset = totalHeight - CGFloat(rowIndex + 1) * rowHeight
            
            var xOffset: CGFloat = 0
            for (colIndex, cell) in cells.enumerated() {
                let cellWidth = colIndex < columnWidths.count ? columnWidths[colIndex] : 100
                let cellRect = NSRect(x: xOffset, y: yOffset, width: cellWidth, height: rowHeight)
                
                // Draw cell border
                NSColor.gray.setStroke()
                let path = NSBezierPath(rect: cellRect)
                path.lineWidth = 0.5
                path.stroke()
                
                // Draw header background
                if rowIndex == 0 {
                    NSColor(white: 0.9, alpha: 1.0).setFill()
                    cellRect.fill()
                    NSColor.gray.setStroke()
                    path.stroke()
                }
                
                // Draw text
                let cellFont = rowIndex == 0 ? headerFont : font
                let textColor = NSColor.black
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .left
                
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: cellFont,
                    .foregroundColor: textColor,
                    .paragraphStyle: paragraphStyle
                ]
                
                let textRect = NSRect(
                    x: xOffset + cellPadding,
                    y: yOffset + cellPadding,
                    width: cellWidth - cellPadding * 2,
                    height: rowHeight - cellPadding * 2
                )
                
                (cell as NSString).draw(in: textRect, withAttributes: attributes)
                
                xOffset += cellWidth
            }
        }
        
        image.unlockFocus()
        
        return image.tiffRepresentation
    }
} 