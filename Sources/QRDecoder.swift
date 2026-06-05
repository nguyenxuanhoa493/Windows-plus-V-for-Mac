import Foundation
import AppKit
import CoreImage
import Vision

/// Giải mã QR từ ảnh (file hoặc trong clipboard).
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

    // MARK: - Clipboard

    /// Decode QR từ ảnh đang nằm trong clipboard (ảnh data hoặc file ảnh được copy).
    static func decodeFromClipboard() -> String? {
        let pb = NSPasteboard.general
        if let image = NSImage(pasteboard: pb), let msg = decode(image: image) {
            return msg
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls {
                if let msg = decode(fileURL: url) { return msg }
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
}
