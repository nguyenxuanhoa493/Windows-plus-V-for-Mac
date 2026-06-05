import SwiftUI

/// Màn khóa dùng chung cho khu vực OTP (tab popup + cửa sổ quản lý).
/// Hiện setup-PIN (nếu chưa có PIN) hoặc lock screen; gọi onUnlocked() khi mở khóa thành công.
struct OTPLockView: View {
    let onUnlocked: () -> Void

    @ObservedObject private var settings = Settings.shared
    private let auth = OTPAuth.shared

    @State private var pin = ""
    @State private var confirmPin = ""
    @State private var errorMessage = ""
    @State private var lockoutRemaining = OTPAuth.shared.lockoutRemaining
    @State private var requestConfirmFocus = false

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            if !auth.hasPIN { setupPinScreen } else { lockScreen }
        }
        .background(settings.themedBackground)
        .onReceive(ticker) { _ in lockoutRemaining = auth.lockoutRemaining }
        .onAppear { attemptBiometrics() }
    }

    private var lockScreen: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lock.fill").font(.system(size: 32)).foregroundColor(.secondary)
            Text(Localization.shared.localizedString("otp_unlock_title")).font(.system(size: 13, weight: .medium))
            PINEntryView(pin: $pin, onComplete: submitPIN)
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

    private var setupPinScreen: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lock.shield").font(.system(size: 32)).foregroundColor(.secondary)
            Text(Localization.shared.localizedString("otp_setup_pin_title")).font(.system(size: 13, weight: .medium))
            Text(Localization.shared.localizedString("otp_enter_pin"))
                .font(.system(size: 11)).foregroundColor(.secondary)
            PINEntryView(pin: $pin, onComplete: { requestConfirmFocus = true })
            Text(Localization.shared.localizedString("otp_setup_pin_confirm"))
                .font(.system(size: 11)).foregroundColor(.secondary)
            PINEntryView(pin: $confirmPin, autoFocus: false,
                         onComplete: submitNewPIN, focusRequest: $requestConfirmFocus)
            if !errorMessage.isEmpty {
                Text(errorMessage).font(.system(size: 11)).foregroundColor(.red)
            }
            Button(Localization.shared.localizedString("otp_save")) { submitNewPIN() }
                .disabled(pin.count != 6 || confirmPin.count != 6)
            Spacer()
        }.padding()
    }

    private func attemptBiometrics() {
        guard auth.hasPIN, auth.biometricsAvailable else { return }
        auth.authenticateBiometrics(reason: Localization.shared.localizedString("otp_unlock_reason")) { ok in
            if ok { unlockSucceeded() }
        }
    }

    private func submitPIN() {
        if auth.isLockedOut {
            lockoutRemaining = auth.lockoutRemaining
            errorMessage = ""
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
        guard auth.setPIN(pin) else {
            errorMessage = Localization.shared.localizedString("otp_pin_wrong"); return
        }
        unlockSucceeded()
    }

    private func unlockSucceeded() {
        OTPManager.shared.markUnlocked()
        pin = ""; confirmPin = ""; errorMessage = ""
        onUnlocked()
    }
}
