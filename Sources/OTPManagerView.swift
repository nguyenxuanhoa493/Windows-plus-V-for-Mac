import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct OTPManagerView: View {
    @ObservedObject private var manager = OTPManager.shared
    private let auth = OTPAuth.shared

    @State private var showingAdd = false
    @State private var editingItem: OTPItem?
    @State private var statusMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if manager.items.isEmpty {
                Spacer()
                Text(Localization.shared.localizedString("otp_empty"))
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(manager.items) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.name).font(.system(size: 13, weight: .medium))
                                if let iss = item.issuer, !iss.isEmpty {
                                    Text(iss).font(.system(size: 11)).foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Button(action: { editingItem = item }) { Image(systemName: "pencil") }
                                .buttonStyle(.plain)
                            Button(action: { manager.delete(item) }) { Image(systemName: "trash") }
                                .buttonStyle(.plain).foregroundColor(.red)
                        }
                    }
                }
            }
            if !statusMessage.isEmpty {
                Text(statusMessage).font(.system(size: 11)).foregroundColor(.secondary).padding(6)
            }
        }
        .frame(minWidth: 460, minHeight: 520)
        .sheet(isPresented: $showingAdd) {
            OTPEditSheet(item: nil) { newItem in manager.add(newItem) }
        }
        .sheet(item: $editingItem) { item in
            OTPEditSheet(item: item) { updated in manager.update(updated) }
        }
    }

    private var header: some View {
        HStack {
            Button(action: { showingAdd = true }) {
                Label(Localization.shared.localizedString("otp_add"), systemImage: "plus")
            }
            Spacer()
            Button(Localization.shared.localizedString("otp_export")) { exportTapped() }
            Button(Localization.shared.localizedString("otp_import")) { importTapped() }
        }.padding(10)
    }

    // MARK: - Export / Import
    private func exportTapped() {
        // Yêu cầu PIN (dùng làm passphrase). Nếu chưa có PIN, không cho export.
        guard auth.hasPIN else {
            statusMessage = Localization.shared.localizedString("otp_unlock_title"); return
        }
        let alert = NSAlert()
        alert.messageText = Localization.shared.localizedString("otp_export")
        alert.informativeText = Localization.shared.localizedString("otp_export_warning")
        alert.addButton(withTitle: Localization.shared.localizedString("otp_export"))
        alert.addButton(withTitle: Localization.shared.localizedString("otp_cancel"))
        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.placeholderString = Localization.shared.localizedString("otp_enter_pin")
        alert.accessoryView = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let pin = input.stringValue
        guard auth.verifyPIN(pin) else {
            statusMessage = Localization.shared.localizedString("otp_pin_wrong"); return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "clipboard-otp-backup.enc"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try manager.exportData(pin: pin)
            try data.write(to: url)
            statusMessage = "✅"
        } catch {
            print("DEBUG: OTP export lỗi: \(error)")
            statusMessage = Localization.shared.localizedString("otp_export_failed")
        }
    }

    private func importTapped() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.data]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let alert = NSAlert()
        alert.messageText = Localization.shared.localizedString("otp_import")
        alert.addButton(withTitle: Localization.shared.localizedString("otp_import"))
        alert.addButton(withTitle: Localization.shared.localizedString("otp_cancel"))
        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.placeholderString = Localization.shared.localizedString("otp_enter_pin")
        alert.accessoryView = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let data = try Data(contentsOf: url)
            let added = try manager.importData(data, pin: input.stringValue)
            statusMessage = String(format: Localization.shared.localizedString("otp_import_done"), added)
        } catch {
            statusMessage = Localization.shared.localizedString("otp_import_failed")
        }
    }
}

/// Sheet thêm/sửa OTP: nhập tay + nút nhập QR ảnh / chọn vùng màn hình.
struct OTPEditSheet: View {
    let item: OTPItem?
    let onSave: (OTPItem) -> Bool
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var issuer = ""
    @State private var secret = ""
    @State private var algorithm: OTPAlgorithm = .sha1
    @State private var digits = 6
    @State private var period = 30
    @State private var showAdvanced = false
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item == nil ? Localization.shared.localizedString("otp_add")
                             : Localization.shared.localizedString("otp_edit"))
                .font(.headline)

            if item == nil {
                HStack {
                    Button(Localization.shared.localizedString("otp_add_qr_image")) { importQRImage() }
                    Button(Localization.shared.localizedString("otp_add_screen")) { captureScreen() }
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
        .onAppear(perform: loadItem)
    }

    private func loadItem() {
        guard let item = item else { return }
        name = item.name; issuer = item.issuer ?? ""; secret = item.secret
        algorithm = item.algorithm; digits = item.digits; period = item.period
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

    private func captureScreen() {
        QRDecoder.captureScreenRegion { msg in
            guard let msg = msg, let parsed = OTPItem.parse(otpauthURI: msg) else {
                error = Localization.shared.localizedString("otp_qr_not_found"); return
            }
            applyParsed(parsed)
        }
    }

    private func save() {
        let trimmedSecret = secret.uppercased().replacingOccurrences(of: " ", with: "")
        guard OTPItem.base32Decode(trimmedSecret) != nil, !trimmedSecret.isEmpty else {
            error = Localization.shared.localizedString("otp_invalid_secret"); return
        }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            error = Localization.shared.localizedString("otp_name"); return
        }
        let result = OTPItem(
            id: item?.id ?? UUID(),
            name: name, issuer: issuer.isEmpty ? nil : issuer,
            secret: trimmedSecret, algorithm: algorithm, digits: digits, period: period,
            createdAt: item?.createdAt ?? Date()
        )
        if onSave(result) {
            dismiss()
        } else {
            error = Localization.shared.localizedString("otp_secret_duplicate")
        }
    }
}
