import SwiftUI

struct OTPView: View {
    /// Gọi khi người dùng chọn 1 mã để paste (đóng popup + auto-paste).
    let onPasteCode: (String) -> Void
    /// Mở cửa sổ quản lý OTP.
    let onManage: () -> Void

    @ObservedObject private var manager = OTPManager.shared
    @ObservedObject private var settings = Settings.shared

    @State private var unlocked = OTPManager.shared.isUnlocked
    @State private var searchText = ""
    @State private var now = Date()

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            if unlocked {
                unlockedContent
            } else {
                OTPLockView(onUnlocked: { unlocked = true })
            }
        }
        .background(settings.themedBackground)
        .onReceive(ticker) { date in now = date }
    }

    // MARK: - Unlocked list
    private var unlockedContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField(Localization.shared.localizedString("otp_search_placeholder"), text: $searchText)
                    .textFieldStyle(.plain)
                Button(action: { OTPManager.shared.lock(); unlocked = false }) {
                    Image(systemName: "lock")
                }.buttonStyle(.plain).tooltip(Localization.shared.localizedString("otp_unlock_title"))
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
}
