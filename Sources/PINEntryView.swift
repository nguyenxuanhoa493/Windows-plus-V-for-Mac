import SwiftUI

/// Ô nhập PIN dạng N ô riêng (mặc định 6). Dùng 1 TextField ẩn để bắt phím,
/// overlay các ô hiển thị (chấm tròn khi đã nhập). Tự gọi onComplete khi đủ N số.
struct PINEntryView: View {
    @Binding var pin: String
    var length: Int = 6
    var autoFocus: Bool = true
    var onComplete: () -> Void = {}

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
                    if digits.count == length { onComplete() }
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
    }

    private func boxView(_ i: Int) -> some View {
        let count = pin.count
        let filled = i < count
        let isCurrent = (i == count) && focused
        return RoundedRectangle(cornerRadius: 8)
            .stroke(isCurrent ? settings.themedAccent : Color.secondary.opacity(0.4),
                    lineWidth: isCurrent ? 2 : 1)
            .frame(width: 36, height: 44)
            .overlay(
                Group {
                    if filled {
                        Circle().fill(settings.themedForeground).frame(width: 10, height: 10)
                    }
                }
            )
    }
}
