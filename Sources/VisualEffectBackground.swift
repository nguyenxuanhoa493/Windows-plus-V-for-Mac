import SwiftUI
import AppKit

/// Nền vibrancy kiểu Liquid Glass: mờ xuyên qua cửa sổ (behind-window blur).
/// Cần cửa sổ đặt isOpaque=false + backgroundColor=.clear để thấy hiệu ứng.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
