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
