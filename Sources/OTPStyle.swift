import SwiftUI

/// Tiện ích style kiểu macOS 26 (Liquid Glass) cho khu vực OTP.
extension View {
    /// Nền "Liquid Glass": dùng glassEffect khi chạy macOS 26+, fallback material cho macOS cũ.
    @ViewBuilder
    func liquidGlass(cornerRadius: CGFloat = 14, tinted: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(tinted ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(.regularMaterial), in: shape)
        }
    }
}

/// Nhún + mờ nhẹ khi nhấn — hiệu ứng "chọn item".
struct PressDownButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
