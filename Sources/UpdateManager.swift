import Foundation
import AppKit

class UpdateManager: ObservableObject {
    static let shared = UpdateManager()
    
    private let githubOwner = "nguyenxuanhoa493"
    private let githubRepo = "Windown-plus-V-for-Mac"
    
    @Published var latestVersion: String?
    @Published var isChecking = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var updateAvailable = false
    @Published var updateError: String?
    
    var currentVersion: String {
        // Ưu tiên đọc từ Info.plist của app bundle (được cập nhật khi update)
        if let bundlePath = Bundle.main.bundlePath as String?,
           let plistPath = URL(fileURLWithPath: bundlePath)
            .appendingPathComponent("Contents/Info.plist").path as String?,
           FileManager.default.fileExists(atPath: plistPath),
           let plistData = FileManager.default.contents(atPath: plistPath),
           let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
           let version = plist["CFBundleShortVersionString"] as? String {
            return version
        }
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    }
    
    private var releaseDownloadURL: URL?
    private var releaseNotes: String?
    private var currentDownloadTask: URLSessionDownloadTask?
    
    // MARK: - Check for updates
    
    private let checkLock = NSLock()

    func checkForUpdates(silent: Bool = false) {
        // Atomic guard: tránh 2 click trùng (auto-check + manual) trong cửa sổ <100ms
        checkLock.lock()
        if isChecking {
            checkLock.unlock()
            return
        }
        isChecking = true
        checkLock.unlock()
        updateError = nil
        
        let urlString = "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/releases/latest"
        guard let url = URL(string: urlString) else {
            isChecking = false
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isChecking = false
                
                if let error = error {
                    if !silent {
                        self?.updateError = error.localizedDescription
                    }
                    return
                }
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String else {
                    if !silent {
                        self?.updateError = "Cannot parse release info"
                    }
                    return
                }
                
                // Remove 'v' prefix if present
                let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
                self?.latestVersion = version
                self?.releaseNotes = json["body"] as? String
                
                // Find binary asset (look for CursorKit-binary.zip or CursorKit.zip)
                if let assets = json["assets"] as? [[String: Any]] {
                    for asset in assets {
                        if let name = asset["name"] as? String,
                           let downloadURL = asset["browser_download_url"] as? String {
                            if name == "CursorKit-binary.zip" || name == "CursorKit.zip" {
                                self?.releaseDownloadURL = URL(string: downloadURL)
                                break
                            }
                        }
                    }
                    // Fallback: use first zip asset
                    if self?.releaseDownloadURL == nil {
                        for asset in assets {
                            if let name = asset["name"] as? String,
                               let downloadURL = asset["browser_download_url"] as? String,
                               name.hasSuffix(".zip") {
                                self?.releaseDownloadURL = URL(string: downloadURL)
                                break
                            }
                        }
                    }
                }
                
                if self?.isNewerVersion(version) == true {
                    self?.updateAvailable = true
                    self?.showUpdateAlert(version: version)
                } else if !silent {
                    self?.showNoUpdateAlert()
                }
            }
        }.resume()
    }
    
    // MARK: - Version comparison
    
    private func isNewerVersion(_ remote: String) -> Bool {
        let current = currentVersion.split(separator: ".").compactMap { Int($0) }
        let remote = remote.split(separator: ".").compactMap { Int($0) }
        
        let maxCount = max(current.count, remote.count)
        for i in 0..<maxCount {
            let c = i < current.count ? current[i] : 0
            let r = i < remote.count ? remote[i] : 0
            if r > c { return true }
            if r < c { return false }
        }
        return false
    }
    
    // MARK: - Download & Install (binary-only replacement)
    
    func downloadAndInstall() {
        guard let downloadURL = releaseDownloadURL else {
            updateError = "No download URL available"
            return
        }

        // Kiểm tra app bundle có ghi được không (case: chạy từ DMG read-only)
        let bundlePath = Bundle.main.bundlePath
        let parentDir = (bundlePath as NSString).deletingLastPathComponent
        if !FileManager.default.isWritableFile(atPath: parentDir) {
            let alert = NSAlert()
            alert.messageText = Localization.shared.localizedString("update_cannot_install")
            alert.informativeText = Localization.shared.localizedString("update_move_to_applications")
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        isDownloading = true
        downloadProgress = 0
        updateError = nil
        
        let task = URLSession.shared.downloadTask(with: downloadURL) { [weak self] tempURL, response, error in
            DispatchQueue.main.async {
                self?.isDownloading = false
                self?.currentDownloadTask = nil

                if let error = error {
                    let nsErr = error as NSError
                    if nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCancelled {
                        // User chủ động cancel, không hiện error
                        return
                    }
                    self?.updateError = error.localizedDescription
                    return
                }

                guard let tempURL = tempURL else {
                    self?.updateError = "Download failed"
                    return
                }

                // Verify integrity trước khi install:
                // 1. Kích thước phải khớp Content-Length (tránh download bị cắt)
                // 2. Magic bytes "PK" — file zip hợp lệ
                if !(self?.verifyZipIntegrity(at: tempURL, response: response) ?? false) {
                    self?.updateError = Localization.shared.localizedString("update_download_corrupted")
                    let alert = NSAlert()
                    alert.messageText = Localization.shared.localizedString("update_cannot_install")
                    alert.informativeText = Localization.shared.localizedString("update_download_corrupted")
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                    return
                }

                self?.installUpdate(from: tempURL)
            }
        }
        
        // Observe progress
        let observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            DispatchQueue.main.async {
                self?.downloadProgress = progress.fractionCompleted
            }
        }
        // Keep observation alive
        objc_setAssociatedObject(task, "progressObservation", observation, .OBJC_ASSOCIATION_RETAIN)

        currentDownloadTask = task
        task.resume()
    }

    func cancelDownload() {
        currentDownloadTask?.cancel()
        currentDownloadTask = nil
        isDownloading = false
        downloadProgress = 0
    }
    
    private func verifyZipIntegrity(at fileURL: URL, response: URLResponse?) -> Bool {
        // Size check
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let actualSize = attrs[.size] as? Int64, actualSize > 0 else {
            return false
        }
        if let expected = response?.expectedContentLength, expected > 0, actualSize != expected {
            print("DEBUG: Zip size mismatch — expected \(expected), got \(actualSize)")
            return false
        }
        // Magic bytes "PK\x03\x04" (zip header)
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return false }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 4), header.count == 4 else { return false }
        return header[0] == 0x50 && header[1] == 0x4B
            && (header[2] == 0x03 || header[2] == 0x05 || header[2] == 0x07)
    }

    private func installUpdate(from zipURL: URL) {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("CursorKitUpdate-\(UUID().uuidString)")
        
        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            let zipPath = tempDir.appendingPathComponent("update.zip")
            try fileManager.copyItem(at: zipURL, to: zipPath)
            
            // Unzip
            let unzipProcess = Process()
            unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzipProcess.arguments = ["-o", zipPath.path, "-d", tempDir.path]
            try unzipProcess.run()
            unzipProcess.waitUntilExit()
            
            // Tìm CursorKit.app trong package giải nén
            var newAppBundlePath: URL?
            let directApp = tempDir.appendingPathComponent("CursorKit.app")
            if fileManager.fileExists(atPath: directApp.path) {
                newAppBundlePath = directApp
            }
            
            // Tìm đệ quy nếu không thấy trực tiếp
            if newAppBundlePath == nil {
                if let enumerator = fileManager.enumerator(at: tempDir, includingPropertiesForKeys: [.isDirectoryKey]) {
                    while let fileURL = enumerator.nextObject() as? URL {
                        if fileURL.lastPathComponent == "CursorKit.app" {
                            newAppBundlePath = fileURL
                            break
                        }
                    }
                }
            }
            
            guard let appBundlePath = newAppBundlePath else {
                updateError = "CursorKit.app not found in update package"
                try? fileManager.removeItem(at: tempDir)
                return
            }
            
            let currentAppPath = Bundle.main.bundlePath

            // Replace TOÀN BỘ .app bundle (không swap từng file con).
            // Bundle mới đã được create_app.sh ad-hoc sign với entitlements →
            // cùng BundleIdentifier (com.xuanhoa.cursorkit) + cùng path →
            // TCC giữ nguyên quyền Accessibility.
            // Tuyệt đối KHÔNG xoá _CodeSignature: unsigned app TCC dùng CDHash,
            // CDHash đổi mỗi build → mất quyền.
            let script = """
            #!/bin/bash
            sleep 1

            APP_PATH="\(currentAppPath)"
            NEW_APP="\(appBundlePath.path)"
            BACKUP="${APP_PATH}.old-$$"

            # Atomic-ish replace: backup cũ, move mới vào, xoá backup
            mv "$APP_PATH" "$BACKUP" || exit 1
            mv "$NEW_APP" "$APP_PATH" || { mv "$BACKUP" "$APP_PATH"; exit 1; }
            rm -rf "$BACKUP"

            # Xóa extended attributes để tránh Gatekeeper block
            xattr -cr "$APP_PATH" 2>/dev/null

            # Dọn dẹp temp
            rm -rf "\(tempDir.path)"

            # Mở lại app
            open "$APP_PATH"
            """
            
            let scriptPath = tempDir.appendingPathComponent("update.sh")
            try script.write(to: scriptPath, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)
            
            // Hiển thị xác nhận
            let alert = NSAlert()
            alert.messageText = Localization.shared.localizedString("update_ready")
            alert.informativeText = Localization.shared.localizedString("update_restart_message")
            alert.alertStyle = .informational
            alert.addButton(withTitle: Localization.shared.localizedString("update_restart_now"))
            alert.addButton(withTitle: Localization.shared.localizedString("update_later"))
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let updateProcess = Process()
                updateProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
                updateProcess.arguments = [scriptPath.path]
                try updateProcess.run()
                
                NSApp.terminate(nil)
            } else {
                try? fileManager.removeItem(at: tempDir)
            }
            
        } catch {
            updateError = error.localizedDescription
            try? fileManager.removeItem(at: tempDir)
        }
    }
    
    // MARK: - Alerts
    
    private func showUpdateAlert(version: String) {
        let alert = NSAlert()
        alert.messageText = Localization.shared.localizedString("update_available")
        alert.informativeText = String(format: Localization.shared.localizedString("update_new_version"), version, currentVersion)
        if let notes = releaseNotes, !notes.isEmpty {
            alert.informativeText += "\n\n" + notes
        }
        alert.alertStyle = .informational
        alert.addButton(withTitle: Localization.shared.localizedString("update_download"))
        alert.addButton(withTitle: Localization.shared.localizedString("update_later"))
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            downloadAndInstall()
        }
    }
    
    private func showNoUpdateAlert() {
        let alert = NSAlert()
        alert.messageText = Localization.shared.localizedString("update_no_update")
        alert.informativeText = String(format: Localization.shared.localizedString("update_current_version"), currentVersion)
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
