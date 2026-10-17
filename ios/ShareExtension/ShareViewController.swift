// ShareViewController for receive_sharing_intent
// Handles inbound audio shares (audio/* and application/* for m4b/m4a) on iOS.
// Copies shared files to App Group container so host app can import via LibraryService.importFiles.

import UIKit
import Social
import UniformTypeIdentifiers
import MobileCoreServices

class ShareViewController: SLComposeServiceViewController {

    private let appGroupId = "group.com.crispstrobe.crisperplayer"
    private let hostAppUrlScheme = "crisperplayer"
    // key used by receive_sharing_intent plugin to read shared files
    private let userDefaultsKey = "SharedMediaFiles"

    private var hasHandled = false

    override func isContentValid() -> Bool { true }

    override func didSelectPost() {
        handleSharedFiles()
    }

    override func configurationItems() -> [Any]! { [] }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Auto-handle without showing compose UI for file shares
        if !hasHandled {
            hasHandled = true
            handleSharedFiles()
        }
    }

    private func handleSharedFiles() {
        guard let extensionContext = extensionContext,
              let inputItems = extensionContext.inputItems as? [NSExtensionItem] else {
            completeRequest()
            return
        }

        let group = DispatchGroup()
        var sharedFiles: [[String: String]] = []
        let syncQueue = DispatchQueue(label: "crisperplayer.share.sync")

        for item in inputItems {
            guard let providers = item.attachments else { continue }
            for provider in providers {
                group.enter()
                // Prefer fileURL, fallback to data
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
                        defer { group.leave() }
                        var url: URL?
                        if let u = item as? URL { url = u }
                        else if let s = item as? String { url = URL(string: s) }
                        if let srcUrl = url {
                            if let dest = self.copyToAppGroup(srcUrl: srcUrl) {
                                let entry: [String: String] = [
                                    "path": dest.path,
                                    "type": self.mimeType(for: srcUrl),
                                    "fileName": srcUrl.lastPathComponent
                                ]
                                syncQueue.sync { sharedFiles.append(entry) }
                            }
                        }
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.audio.identifier)
                            || provider.hasItemConformingToTypeIdentifier(UTType.data.identifier)
                            || provider.hasItemConformingToTypeIdentifier(kUTTypeMPEG4Audio as String)
                            || provider.hasItemConformingToTypeIdentifier("public.audio") {
                    // Try to get file representation for audio types
                    let typeId = provider.registeredTypeIdentifiers.first ?? UTType.data.identifier
                    provider.loadItem(forTypeIdentifier: typeId, options: nil) { (item, error) in
                        defer { group.leave() }
                        var url: URL?
                        if let u = item as? URL { url = u }
                        else if let d = item as? Data {
                            // Create temp file from data
                            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4b")
                            try? d.write(to: tmp)
                            url = tmp
                        }
                        if let srcUrl = url, let dest = self.copyToAppGroup(srcUrl: srcUrl) {
                            let entry: [String: String] = [
                                "path": dest.path,
                                "type": self.mimeType(for: srcUrl),
                                "fileName": srcUrl.lastPathComponent
                            ]
                            syncQueue.sync { sharedFiles.append(entry) }
                        }
                    }
                } else {
                    // Try generic data fallback
                    let typeId = provider.registeredTypeIdentifiers.first ?? UTType.data.identifier
                    provider.loadItem(forTypeIdentifier: typeId, options: nil) { (item, error) in
                        defer { group.leave() }
                        if let u = item as? URL, let dest = self.copyToAppGroup(srcUrl: u) {
                            let entry: [String: String] = [
                                "path": dest.path,
                                "type": self.mimeType(for: u),
                                "fileName": u.lastPathComponent
                            ]
                            syncQueue.sync { sharedFiles.append(entry) }
                        }
                    }
                }
            }
        }

        group.notify(queue: .main) {
            if !sharedFiles.isEmpty {
                self.saveToUserDefaults(files: sharedFiles)
            }
            self.openHostAppOrComplete()
        }
    }

    private func copyToAppGroup(srcUrl: URL) -> URL? {
        let fm = FileManager.default
        // Resolve source: handle security-scoped, file copy, or already in tmp
        var srcToCopy = srcUrl
        let needsAccess = srcUrl.startAccessingSecurityScopedResource()
        defer { if needsAccess { srcUrl.stopAccessingSecurityScopedResource() } }

        // If src is inside Inbox or tmp, we need to copy; also handle URL that may not exist yet
        // Try to get destination in App Group container
        guard let containerUrl = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            // Fallback to temp
            return copyFile(src: srcToCopy)
        }
        let destDir = containerUrl.appendingPathComponent("ShareExtension", isDirectory: true)
        try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        // Generate unique filename preserving extension
        let ext = srcUrl.pathExtension.isEmpty ? "m4b" : srcUrl.pathExtension
        let fileName = UUID().uuidString + "." + ext
        let destUrl = destDir.appendingPathComponent(fileName)

        do {
            if fm.fileExists(at: srcToCopy) {
                try fm.copyItem(at: srcToCopy, to: destUrl)
                return destUrl
            } else {
                // Try data copy
                let data = try Data(contentsOf: srcToCopy)
                try data.write(to: destUrl)
                return destUrl
            }
        } catch {
            // Fallback to temp copy
            return copyFile(src: srcToCopy)
        }
    }

    private func copyFile(src: URL) -> URL? {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory
        let ext = src.pathExtension.isEmpty ? "m4b" : src.pathExtension
        let dest = tmpDir.appendingPathComponent(UUID().uuidString + "." + ext)
        do {
            if fm.fileExists(at: src) {
                try fm.copyItem(at: src, to: dest)
            } else {
                let data = try Data(contentsOf: src)
                try data.write(to: dest)
            }
            return dest
        } catch {
            return nil
        }
    }

    private func saveToUserDefaults(files: [[String: String]]) {
        guard let defaults = UserDefaults(suiteName: appGroupId) else { return }
        // receive_sharing_intent expects JSON array of SharedMediaFile-like dicts
        // We store as JSON string; plugin reads UserDefaults(suiteName:) with key "SharedMediaFiles"
        if let existing = defaults.string(forKey: userDefaultsKey),
           let data = existing.data(using: .utf8),
           var arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for f in files { arr.append(f as [String: Any]) }
            if let newData = try? JSONSerialization.data(withJSONObject: arr),
               let newStr = String(data: newData, encoding: .utf8) {
                defaults.set(newStr, forKey: userDefaultsKey)
            }
        } else {
            if let data = try? JSONSerialization.data(withJSONObject: files),
               let str = String(data: data, encoding: .utf8) {
                defaults.set(str, forKey: userDefaultsKey)
            }
        }
        defaults.synchronize()
    }

    private func mimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "m4b", "m4a": return "audio/mp4"
        case "mp3": return "audio/mpeg"
        case "flac": return "audio/flac"
        case "ogg", "opus": return "audio/ogg"
        case "wav": return "audio/wav"
        case "aac": return "audio/aac"
        case "wma": return "audio/x-ms-wma"
        case "aiff", "aif": return "audio/aiff"
        default: return "audio/*"
        }
    }

    private func openHostAppOrComplete() {
        // Try to open host app via custom URL scheme so it can process imports immediately
        // Fallback to completeRequest if not available (iOS 18+ may restrict)
        if let url = URL(string: "\(hostAppUrlScheme)://share") {
            // Use private API via NSExtensionContext openURL if available
            // extensionContext.open(url) is not public; use selector hack
            let selector = sel_registerName("openURL:completionHandler:")
            if extensionContext?.responds(to: selector) == true {
                extensionContext?.perform(selector, with: url, with: nil)
            }
        }
        completeRequest()
    }

    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    override func didSelectCancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: "crisperplayer", code: 0))
    }
}
