import Foundation
import AppKit
import CoreImage

/// Giải mã QR từ ảnh hoặc từ vùng màn hình do người dùng chọn.
enum QRDecoder {
    /// Decode chuỗi QR đầu tiên trong ảnh. Trả nil nếu không có QR.
    static func decode(image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation,
              let ci = CIImage(data: tiff) else { return nil }
        return decode(ciImage: ci)
    }

    static func decode(fileURL: URL) -> String? {
        guard let ci = CIImage(contentsOf: fileURL) else { return nil }
        return decode(ciImage: ci)
    }

    private static func decode(ciImage: CIImage) -> String? {
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                  options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let features = detector?.features(in: ciImage) ?? []
        for f in features {
            if let qr = f as? CIQRCodeFeature, let msg = qr.messageString, !msg.isEmpty {
                return msg
            }
        }
        return nil
    }

    /// Chạy `screencapture -i` cho người dùng chọn vùng, rồi decode QR.
    /// Không cần quyền Screen Recording vì dùng tiện ích hệ thống.
    /// completion(nil) nếu người dùng hủy hoặc không thấy QR.
    static func captureScreenRegion(completion: @escaping (String?) -> Void) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("otp-qr-\(UUID().uuidString).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", tmp.path]
        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                defer { try? FileManager.default.removeItem(at: tmp) }
                guard FileManager.default.fileExists(atPath: tmp.path) else {
                    completion(nil); return   // người dùng nhấn Esc
                }
                completion(decode(fileURL: tmp))
            }
        }
        do {
            try process.run()
        } catch {
            print("DEBUG: screencapture lỗi: \(error)")
            DispatchQueue.main.async { completion(nil) }   // luôn callback trên main như nhánh thành công
        }
    }
}
