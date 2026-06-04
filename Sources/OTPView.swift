import SwiftUI

struct OTPView: View {
    /// Gọi khi người dùng chọn 1 mã để paste (đóng popup + auto-paste).
    let onPasteCode: (String) -> Void
    /// Mở cửa sổ quản lý OTP.
    let onManage: () -> Void

    @ObservedObject private var manager = OTPManager.shared
    @ObservedObject private var settings = Settings.shared
    private let auth = OTPAuth.shared

    @State private var unlocked = OTPManager.shared.isUnlocked
    @State private var searchText = ""
    @State private var pin = ""
    @State private var confirmPin = ""
    @State private var errorMessage = ""
    @State private var now = Date()
    @State private var lockoutRemaining = 0

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            if unlocked {
                unlockedContent
            } else if !auth.hasPIN {
                setupPinScreen
            } else {
                lockScreen
            }
        }
        .background(settings.themedBackground)
        .onReceive(ticker) { date in
            now = date
            lockoutRemaining = auth.lockoutRemaining
        }
        .onAppear { attemptBiometrics() }
    }

    // MARK: - Unlocked list
    private var unlockedContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField(Localization.shared.localizedString("otp_search_placeholder"), text: $searchText)
                    .textFieldStyle(.plain)
                Button(action: onManage) {
                    Image(systemName: "gearshape")
                }.buttonStyle(.plain).tooltip(Localization.shared.localizedString("otp_manage"))
            }
            .padding(10)

            let list = manager.search(searchText)
            if list.isEmpty {
                Spacer()
                Text(Localization.shared.localizedString("otp_empty"))
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .multilineTextAlignment(.center).padding()
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(list) { item in
                            otpRow(item)
                        }
                    }.padding(.horizontal, 8).padding(.bottom, 8)
                }
            }
        }
    }

    private func otpRow(_ item: OTPItem) -> some View {
        let code = item.code(at: now) ?? "------"
        let remaining = item.secondsRemaining(at: now)
        return Button(action: { onPasteCode(code) }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.system(size: 12, weight: .medium))
                        .foregroundColor(settings.themedForeground)
                    if let iss = item.issuer, !iss.isEmpty {
                        Text(iss).font(.system(size: 10)).foregroundColor(.secondary)
                    }
                }
                Spacer()
                Text(code)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundColor(settings.themedAccent)
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: CGFloat(remaining) / CGFloat(item.period))
                        .stroke(settings.themedAccent, lineWidth: 2)
                        .rotationEffect(.degrees(-90))
                    Text("\(remaining)").font(.system(size: 9))
                }.frame(width: 22, height: 22)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(settings.themedSurface))
        }.buttonStyle(.plain)
    }

    // MARK: - Lock screen
    private var lockScreen: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lock.fill").font(.system(size: 32)).foregroundColor(.secondary)
            Text(Localization.shared.localizedString("otp_unlock_title")).font(.system(size: 13, weight: .medium))

            SecureField(Localization.shared.localizedString("otp_enter_pin"), text: $pin)
                .textFieldStyle(.roundedBorder).frame(width: 180)
                .onChange(of: pin) { v in
                    if v.count >= 6 { submitPIN() }
                }

            if auth.biometricsAvailable {
                Button(action: attemptBiometrics) {
                    Label(Localization.shared.localizedString("otp_unlock_touchid"), systemImage: "touchid")
                }
            }
            if !errorMessage.isEmpty {
                Text(errorMessage).font(.system(size: 11)).foregroundColor(.red)
            }
            if lockoutRemaining > 0 {
                Text(String(format: Localization.shared.localizedString("otp_locked_out"), lockoutRemaining))
                    .font(.system(size: 11)).foregroundColor(.orange)
            }
            Spacer()
        }.padding()
    }

    // MARK: - Setup PIN
    private var setupPinScreen: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lock.shield").font(.system(size: 32)).foregroundColor(.secondary)
            Text(Localization.shared.localizedString("otp_setup_pin_title")).font(.system(size: 13, weight: .medium))
            SecureField(Localization.shared.localizedString("otp_enter_pin"), text: $pin)
                .textFieldStyle(.roundedBorder).frame(width: 180)
            SecureField(Localization.shared.localizedString("otp_setup_pin_confirm"), text: $confirmPin)
                .textFieldStyle(.roundedBorder).frame(width: 180)
            if !errorMessage.isEmpty {
                Text(errorMessage).font(.system(size: 11)).foregroundColor(.red)
            }
            Button(Localization.shared.localizedString("otp_save")) { submitNewPIN() }
                .disabled(pin.count != 6 || confirmPin.count != 6)
            Spacer()
        }.padding()
    }

    // MARK: - Actions
    private func attemptBiometrics() {
        guard !unlocked, auth.hasPIN, auth.biometricsAvailable else { return }
        auth.authenticateBiometrics(reason: Localization.shared.localizedString("otp_unlock_reason")) { ok in
            if ok { unlockSucceeded() }
        }
    }

    private func submitPIN() {
        if auth.isLockedOut {
            lockoutRemaining = auth.lockoutRemaining
            pin = ""
            return
        }
        if auth.verifyPIN(pin) {
            unlockSucceeded()
        } else {
            errorMessage = Localization.shared.localizedString("otp_pin_wrong")
            pin = ""
        }
    }

    private func submitNewPIN() {
        guard pin == confirmPin else {
            errorMessage = Localization.shared.localizedString("otp_pin_mismatch"); return
        }
        auth.setPIN(pin)
        unlockSucceeded()
    }

    private func unlockSucceeded() {
        manager.markUnlocked()
        unlocked = true
        pin = ""; confirmPin = ""; errorMessage = ""
    }
}
