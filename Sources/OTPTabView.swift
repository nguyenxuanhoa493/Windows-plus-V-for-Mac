import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Toàn bộ trải nghiệm OTP nằm trong tab OTP của popup chính (không còn cửa sổ riêng):
/// khóa PIN/Touch ID, danh sách mã + đếm ngược, thêm/sửa/xóa, export/import.
struct OTPTabView: View {
    let onPasteCode: (String) -> Void
    var searchText: String = ""

    @ObservedObject private var otpManager = OTPManager.shared
    @ObservedObject private var settings = Settings.shared

    @State private var unlocked = OTPManager.shared.isUnlocked
    @State private var otpNow = Date()
    @State private var showingAdd = false
    @State private var pendingAddSource: OTPAddSource?
    @State private var editingItem: OTPItem?
    @State private var statusMessage = ""

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if unlocked { management } else { OTPLockView(onUnlocked: { unlocked = true }) }
        }
        .onReceive(ticker) { otpNow = $0 }
    }

    private var management: some View {
        VStack(spacing: 0) {
            header
            let list = otpManager.search(searchText)
            if list.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "lock.shield").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text(Localization.shared.localizedString("otp_empty"))
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }.frame(maxWidth: .infinity).padding()
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(list) { item in
                        OTPRowView(item: item, now: otpNow,
                                   onPaste: { onPasteCode($0) },
                                   onEdit: { editingItem = item },
                                   onDelete: { otpManager.delete(item) })
                    }
                }.padding(.horizontal, 10).padding(.vertical, 4)
            }
            if !statusMessage.isEmpty {
                Text(statusMessage).font(.system(size: 12)).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 8)
            }
        }
        .sheet(isPresented: $showingAdd, onDismiss: { pendingAddSource = nil }) {
            OTPEditSheet(item: nil, onSave: { otpManager.add($0) }, initialSource: pendingAddSource)
        }
        .sheet(item: $editingItem) { item in
            OTPEditSheet(item: item, onSave: { otpManager.update($0) })
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Menu {
                Button(Localization.shared.localizedString("otp_add_manual")) { showingAdd = true }
                Button(Localization.shared.localizedString("otp_add_qr_image")) { addFromQRImage() }
                Button(Localization.shared.localizedString("otp_add_clipboard")) { addFromClipboardImage() }
            } label: {
                Label(Localization.shared.localizedString("otp_add"), systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(settings.themedAccent)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .liquidGlass(cornerRadius: 12)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            Spacer()
        }.padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 6)
    }

    // MARK: - Thêm từ QR ảnh / vùng màn hình (thao tác trực tiếp, không mở form)
    private func addFromQRImage() {
        AppDelegate.suppressDismiss = true   // ghim popup khi đang chọn file QR
        defer { AppDelegate.suppressDismiss = false }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let msg = QRDecoder.decode(fileURL: url), let parsed = OTPItem.parse(otpauthURI: msg) else {
            statusMessage = Localization.shared.localizedString("otp_qr_not_found"); return
        }
        addParsed(parsed)
    }

    /// Thêm OTP từ ảnh QR đang nằm trong clipboard (vd chụp màn hình bằng ⌃⌘⇧4, hoặc copy ảnh).
    private func addFromClipboardImage() {
        guard let msg = QRDecoder.decodeFromClipboard(), let parsed = OTPItem.parse(otpauthURI: msg) else {
            statusMessage = Localization.shared.localizedString("otp_qr_not_found"); return
        }
        addParsed(parsed)
    }

    private func addParsed(_ item: OTPItem) {
        if otpManager.add(item) {
            statusMessage = String(format: Localization.shared.localizedString("otp_added"), item.name)
        } else {
            statusMessage = Localization.shared.localizedString("otp_secret_duplicate")
        }
    }
}

// MARK: - moved from OTPManagerView.swift

/// Nguồn thêm OTP được yêu cầu sẵn khi mở tab quản lý.
enum OTPAddSource { case manual, qrImage }

/// Sheet thêm/sửa OTP: nhập tay + nút nhập QR từ ảnh file / ảnh trong clipboard.
struct OTPEditSheet: View {
    let item: OTPItem?
    let onSave: (OTPItem) -> Bool
    var initialSource: OTPAddSource? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var issuer = ""
    @State private var secret = ""
    @State private var algorithm: OTPAlgorithm = .sha1
    @State private var digits = 6
    @State private var period = 30
    @State private var showAdvanced = false
    @State private var error = ""
    @State private var didTriggerSource = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item == nil ? Localization.shared.localizedString("otp_add")
                             : Localization.shared.localizedString("otp_edit"))
                .font(.headline)

            if item == nil {
                HStack {
                    Button(Localization.shared.localizedString("otp_add_qr_image")) { importQRImage() }
                    Button(Localization.shared.localizedString("otp_add_clipboard")) { pasteFromClipboard() }
                }
            }

            TextField(Localization.shared.localizedString("otp_name"), text: $name)
            TextField(Localization.shared.localizedString("otp_issuer"), text: $issuer)
            TextField(Localization.shared.localizedString("otp_secret"), text: $secret)

            DisclosureGroup(Localization.shared.localizedString("otp_advanced"), isExpanded: $showAdvanced) {
                Picker(Localization.shared.localizedString("otp_algorithm"), selection: $algorithm) {
                    ForEach(OTPAlgorithm.allCases, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
                }
                Stepper("\(Localization.shared.localizedString("otp_digits")): \(digits)", value: $digits, in: 6...8)
                Stepper("\(Localization.shared.localizedString("otp_period")): \(period)", value: $period, in: 15...60, step: 15)
            }

            if !error.isEmpty { Text(error).foregroundColor(.red).font(.system(size: 11)) }

            HStack {
                Spacer()
                Button(Localization.shared.localizedString("otp_cancel")) { dismiss() }
                Button(Localization.shared.localizedString("otp_save")) { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16).frame(width: 380)
        .onAppear {
            loadItem()
            triggerInitialSourceIfNeeded()
        }
    }

    private func loadItem() {
        guard let item = item else { return }
        name = item.name; issuer = item.issuer ?? ""; secret = item.secret
        algorithm = item.algorithm; digits = item.digits; period = item.period
    }

    private func triggerInitialSourceIfNeeded() {
        guard item == nil, !didTriggerSource, let src = initialSource else { return }
        didTriggerSource = true
        DispatchQueue.main.async {
            switch src {
            case .manual: break               // chỉ hiện form nhập tay
            case .qrImage: importQRImage()
            }
        }
    }

    private func applyParsed(_ parsed: OTPItem) {
        name = parsed.name; issuer = parsed.issuer ?? ""; secret = parsed.secret
        algorithm = parsed.algorithm; digits = parsed.digits; period = parsed.period
    }

    private func importQRImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let msg = QRDecoder.decode(fileURL: url), let parsed = OTPItem.parse(otpauthURI: msg) else {
            error = Localization.shared.localizedString("otp_qr_not_found"); return
        }
        applyParsed(parsed)
    }

    private func pasteFromClipboard() {
        guard let msg = QRDecoder.decodeFromClipboard(), let parsed = OTPItem.parse(otpauthURI: msg) else {
            error = Localization.shared.localizedString("otp_qr_not_found"); return
        }
        applyParsed(parsed)
    }

    private func save() {
        // Cho phép dán thẳng otpauth:// vào ô secret → parse ra các trường.
        var n = name
        var iss: String? = issuer.isEmpty ? nil : issuer
        var sec = secret, alg = algorithm, dig = digits, per = period
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("otpauth://"), let parsed = OTPItem.parse(otpauthURI: trimmed) {
            n = parsed.name; iss = parsed.issuer; sec = parsed.secret
            alg = parsed.algorithm; dig = parsed.digits; per = parsed.period
            applyParsed(parsed)  // phản hồi lên UI
        }
        let trimmedSecret = sec.uppercased().replacingOccurrences(of: " ", with: "")
        guard OTPItem.base32Decode(trimmedSecret) != nil, !trimmedSecret.isEmpty else {
            error = Localization.shared.localizedString("otp_invalid_secret"); return
        }
        guard !n.trimmingCharacters(in: .whitespaces).isEmpty else {
            error = Localization.shared.localizedString("otp_name"); return
        }
        let result = OTPItem(
            id: item?.id ?? UUID(),
            name: n, issuer: iss,
            secret: trimmedSecret, algorithm: alg, digits: dig, period: per,
            createdAt: item?.createdAt ?? Date()
        )
        if onSave(result) {
            dismiss()
        } else {
            error = Localization.shared.localizedString("otp_secret_duplicate")
        }
    }
}

/// Dòng OTP (tab OTP) — card Liquid Glass + hover tráng gương + nhún khi chọn.
struct OTPRowView: View {
    let item: OTPItem
    let now: Date
    let onPaste: (String) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @ObservedObject private var settings = Settings.shared
    @State private var hovered = false
    @State private var shine: CGFloat = -1

    var body: some View {
        let code = item.code(at: now) ?? "------"
        let remaining = item.secondsRemaining(at: now)
        let effectsEnabled = settings.enableVisualEffects
        return Button(action: { onPaste(code) }) {
            VStack(alignment: .leading, spacing: 7) {
                // Hàng 1: tên + issuer
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.system(size: 14, weight: .semibold))
                        .foregroundColor(settings.themedForeground)
                    if let iss = item.issuer, !iss.isEmpty {
                        Text(iss).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                // Hàng 2: mã OTP + đếm ngược
                HStack(spacing: 10) {
                    Text(code).font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit().foregroundColor(settings.themedAccent)
                    Spacer()
                    ZStack {
                        Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 3)
                        Circle().trim(from: 0, to: CGFloat(remaining)/CGFloat(max(item.period, 1)))
                            .stroke(settings.themedAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(remaining)").font(.system(size: 11, weight: .medium)).monospacedDigit()
                    }.frame(width: 30, height: 30)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(cornerRadius: 18)
            .overlay(shineOverlay)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(settings.themedAccent.opacity(hovered ? 0.45 : 0.15), lineWidth: 1))
            .scaleEffect(effectsEnabled && hovered ? 1.015 : 1.0)
            .shadow(color: settings.themedAccent.opacity(effectsEnabled && hovered ? 0.22 : 0),
                    radius: effectsEnabled && hovered ? 8 : 0, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .buttonStyle(PressDownButtonStyle(effectsEnabled: effectsEnabled))
        .onHover { h in
            withAnimation(.easeOut(duration: 0.18)) { hovered = h }
            if effectsEnabled && h {
                // Reset không animation ở tick này, rồi quét ở tick sau → lặp lại mỗi lần hover.
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { shine = -1 }
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.75)) { shine = 1 }
                }
            } else if !effectsEnabled {
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { shine = -1 }
            }
        }
        .contextMenu {
            Button(action: onEdit) {
                Label(Localization.shared.localizedString("otp_edit"), systemImage: "pencil")
            }
            Button(role: .destructive, action: onDelete) {
                Label(Localization.shared.localizedString("otp_delete"), systemImage: "trash")
            }
        }
    }

    /// Vệt sáng chéo quét ngang khi hover (hiệu ứng tráng gương).
    private var shineOverlay: some View {
        GeometryReader { geo in
            let w = geo.size.width
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: [.clear, .white.opacity(0.4), .clear],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: w * 0.30)
                .rotationEffect(.degrees(22))
                .offset(x: shine * w * 1.2)
                .blendMode(.plusLighter)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .opacity(settings.enableVisualEffects && hovered ? 1 : 0)
        .allowsHitTesting(false)
    }
}
