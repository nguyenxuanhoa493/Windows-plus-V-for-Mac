import Foundation
import AppKit
import CoreImage
import Vision

/// Giải mã QR từ ảnh hoặc từ vùng màn hình do người dùng chọn.
enum QRDecoder {
    // MARK: - Public API

    /// Decode chuỗi QR đầu tiên trong ảnh. Trả nil nếu không có QR.
    /// Thử Vision trước (mạnh hơn với QR dày), fallback sang CIDetector.
    static func decode(image: NSImage) -> String? {
        // Bước 1: Thử Vision
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            if let result = decode(cgImage: cg) {
                return result
            }
        }
        // Bước 2: Fallback CIDetector
        guard let tiff = image.tiffRepresentation,
              let ci = CIImage(data: tiff) else { return nil }
        return decode(ciImage: ci)
    }

    static func decode(fileURL: URL) -> String? {
        // Bước 1: Thử Vision qua CGImageSource
        if let cgImage = loadCGImage(from: fileURL) {
            if let result = decode(cgImage: cgImage) {
                return result
            }
        }
        // Bước 2: Fallback CIDetector
        guard let ci = CIImage(contentsOf: fileURL) else { return nil }
        return decode(ciImage: ci)
    }

    // MARK: - Vision (primary)

    /// Dùng VNDetectBarcodesRequest — đọc được QR dày hơn CIDetector.
    private static func decode(cgImage: CGImage) -> String? {
        let request = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("DEBUG: VNDetectBarcodesRequest lỗi: \(error)")
            return nil
        }
        for obs in (request.results ?? []) {
            if let payload = obs.payloadStringValue, !payload.isEmpty {
                return payload
            }
        }
        return nil
    }

    // MARK: - CIDetector (fallback)

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

    // MARK: - Helpers

    /// Load CGImage từ file URL dùng CGImageSource (hỗ trợ nhiều format hơn NSImage).
    private static func loadCGImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // MARK: - Screen capture

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
