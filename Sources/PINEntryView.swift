import SwiftUI

/// Ô nhập PIN dạng N ô riêng (mặc định 6). Dùng 1 TextField ẩn để bắt phím,
/// overlay các ô hiển thị (chấm tròn khi đã nhập). Tự gọi onComplete khi đủ N số.
struct PINEntryView: View {
    @Binding var pin: String
    var length: Int = 6
    var autoFocus: Bool = true
    var onComplete: () -> Void = {}
    /// Parent đặt true để yêu cầu focus ô này (vd: sau khi ô PIN đầu nhập xong).
    var focusRequest: Binding<Bool>? = nil

    @ObservedObject private var settings = Settings.shared
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            // TextField ẩn: chỉ để nhận phím, gần như vô hình nhưng vẫn focus được.
            TextField("", text: Binding(
                get: { pin },
                set: { newValue in
                    let digits = String(newValue.filter { $0.isNumber }.prefix(length))
                    pin = digits
                    if digits.count == length { DispatchQueue.main.async { onComplete() } }
                }
            ))
            .textFieldStyle(.plain)
            .focused($focused)
            .frame(width: 1, height: 1)
            .opacity(0.01)

            HStack(spacing: 8) {
                ForEach(0..<length, id: \.self) { i in boxView(i) }
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
        }
        .onAppear {
            if autoFocus { DispatchQueue.main.async { focused = true } }
        }
        .onChange(of: focusRequest?.wrappedValue ?? false) { req in
            if req {
                focused = true
                focusRequest?.wrappedValue = false
            }
        }
    }

    private func boxView(_ i: Int) -> some View {
        let count = pin.count
        let filled = i < count
        let isCurrent = (i == count) && focused
        return Color.clear
            .frame(width: 42, height: 52)
            .liquidGlass(cornerRadius: 12)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isCurrent ? settings.themedAccent : Color.secondary.opacity(0.25),
                                  lineWidth: isCurrent ? 2.5 : 1)
            )
            .overlay {
                if filled {
                    Circle().fill(settings.themedAccent).frame(width: 12, height: 12)
                }
            }
    }
}
