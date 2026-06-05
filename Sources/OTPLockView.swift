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
        VStack(spacing: 18) {
            Spacer(minLength: 12)
            Image(systemName: "lock.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(settings.themedAccent)
                .frame(width: 64, height: 64)
                .liquidGlass(cornerRadius: 32)
            Text(Localization.shared.localizedString("otp_unlock_title"))
                .font(.system(size: 15, weight: .semibold))
            PINEntryView(pin: $pin, onComplete: submitPIN)
            if auth.biometricsAvailable {
                Button(action: attemptBiometrics) {
                    Label(Localization.shared.localizedString("otp_unlock_touchid"), systemImage: "touchid")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(settings.themedAccent)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .liquidGlass(cornerRadius: 12)
                }.buttonStyle(.plain)
            }
            if !errorMessage.isEmpty {
                Text(errorMessage).font(.system(size: 12)).foregroundStyle(.red)
            }
            if lockoutRemaining > 0 {
                Text(String(format: Localization.shared.localizedString("otp_locked_out"), lockoutRemaining))
                    .font(.system(size: 12)).foregroundStyle(.orange)
            }
            Spacer(minLength: 12)
        }.padding(24).frame(maxWidth: .infinity)
    }

    private var setupPinScreen: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 12)
            Image(systemName: "lock.shield")
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(settings.themedAccent)
                .frame(width: 64, height: 64)
                .liquidGlass(cornerRadius: 32)
            Text(Localization.shared.localizedString("otp_setup_pin_title"))
                .font(.system(size: 15, weight: .semibold))
            Text(Localization.shared.localizedString("otp_enter_pin"))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            PINEntryView(pin: $pin, onComplete: { requestConfirmFocus = true })
            Text(Localization.shared.localizedString("otp_setup_pin_confirm"))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            PINEntryView(pin: $confirmPin, autoFocus: false,
                         onComplete: submitNewPIN, focusRequest: $requestConfirmFocus)
            if !errorMessage.isEmpty {
                Text(errorMessage).font(.system(size: 12)).foregroundStyle(.red)
            }
            Button(Localization.shared.localizedString("otp_save")) { submitNewPIN() }
                .buttonStyle(.borderedProminent)
                .tint(settings.themedAccent)
                .disabled(pin.count != 6 || confirmPin.count != 6)
            Spacer(minLength: 12)
        }.padding(24).frame(maxWidth: .infinity)
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
