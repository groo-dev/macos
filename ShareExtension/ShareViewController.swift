//
//  ShareViewController.swift
//  ShareExtension
//
//  Share extension to add text/files to Groo Pad.
//

import Cocoa
import SwiftUI
import UniformTypeIdentifiers

class ShareViewController: NSViewController {

    private var sharedItems: [SharedItem] = []
    private var isProcessing = false
    private var errorMessage: String?

    override var nibName: NSNib.Name? {
        return nil
    }

    override func loadView() {
        // Create SwiftUI view
        let hostingView = NSHostingView(
            rootView: ShareView(
                items: sharedItems,
                isProcessing: isProcessing,
                errorMessage: errorMessage,
                onSend: { [weak self] in self?.send() },
                onCancel: { [weak self] in self?.cancel() }
            )
        )
        self.view = hostingView
        self.view.frame = NSRect(x: 0, y: 0, width: 320, height: 200)

        // Process input items
        processInputItems()
    }

    private func processInputItems() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments else {
            return
        }

        let group = DispatchGroup()
        var items: [SharedItem] = []

        for attachment in attachments {
            group.enter()

            // Check for plain text
            if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier) { data, error in
                    defer { group.leave() }
                    if let text = data as? String {
                        items.append(.text(text))
                    }
                }
            }
            // Check for URL
            else if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                attachment.loadItem(forTypeIdentifier: UTType.url.identifier) { data, error in
                    defer { group.leave() }
                    if let url = data as? URL {
                        if url.isFileURL {
                            items.append(.file(url))
                        } else {
                            items.append(.url(url))
                        }
                    }
                }
            }
            // Check for file URL
            else if attachment.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                attachment.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
                    defer { group.leave() }
                    if let url = data as? URL {
                        items.append(.file(url))
                    }
                }
            }
            else {
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.sharedItems = items
            self?.updateView()
        }
    }

    private func updateView() {
        let hostingView = NSHostingView(
            rootView: ShareView(
                items: sharedItems,
                isProcessing: isProcessing,
                errorMessage: errorMessage,
                onSend: { [weak self] in self?.send() },
                onCancel: { [weak self] in self?.cancel() }
            )
        )
        self.view = hostingView
        self.view.frame = NSRect(x: 0, y: 0, width: 320, height: 200)
    }

    private func send() {
        isProcessing = true
        updateView()

        // Save to shared container and open main app
        Task {
            do {
                try await saveAndOpenApp()
                await MainActor.run {
                    self.extensionContext?.completeRequest(returningItems: nil)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isProcessing = false
                    self.updateView()
                }
            }
        }
    }

    private func saveAndOpenApp() async throws {
        // Get shared container URL
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.dev.groo.mac"
        ) else {
            throw ShareError.noSharedContainer
        }

        let shareDir = containerURL.appendingPathComponent("ShareExtension", isDirectory: true)
        try FileManager.default.createDirectory(at: shareDir, withIntermediateDirectories: true)

        // Create share data
        var shareData = ShareData(items: [])

        for item in sharedItems {
            switch item {
            case .text(let text):
                shareData.items.append(ShareDataItem(type: "text", content: text, filePath: nil))

            case .url(let url):
                shareData.items.append(ShareDataItem(type: "url", content: url.absoluteString, filePath: nil))

            case .file(let url):
                // Copy file to shared container
                let fileName = url.lastPathComponent
                let destURL = shareDir.appendingPathComponent(UUID().uuidString + "_" + fileName)
                try FileManager.default.copyItem(at: url, to: destURL)
                shareData.items.append(ShareDataItem(type: "file", content: fileName, filePath: destURL.path))
            }
        }

        // Save share data as JSON
        let dataURL = shareDir.appendingPathComponent("pending.json")
        let encoder = JSONEncoder()
        let data = try encoder.encode(shareData)
        try data.write(to: dataURL)

        // Open main app via URL scheme
        let grooURL = URL(string: "groo://share")!
        NSWorkspace.shared.open(grooURL)
    }

    private func cancel() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        extensionContext?.cancelRequest(withError: error)
    }
}

// MARK: - Models

enum SharedItem {
    case text(String)
    case url(URL)
    case file(URL)

    var displayText: String {
        switch self {
        case .text(let text):
            return text.prefix(100) + (text.count > 100 ? "..." : "")
        case .url(let url):
            return url.absoluteString
        case .file(let url):
            return url.lastPathComponent
        }
    }

    var icon: String {
        switch self {
        case .text: return "doc.text"
        case .url: return "link"
        case .file: return "doc"
        }
    }
}

struct ShareData: Codable {
    var items: [ShareDataItem]
}

struct ShareDataItem: Codable {
    let type: String  // "text", "url", "file"
    let content: String
    let filePath: String?
}

enum ShareError: Error, LocalizedError {
    case noSharedContainer

    var errorDescription: String? {
        switch self {
        case .noSharedContainer:
            return "Could not access shared container. Please ensure App Groups is enabled."
        }
    }
}

// MARK: - SwiftUI View

struct ShareView: View {
    let items: [SharedItem]
    let isProcessing: Bool
    let errorMessage: String?
    let onSend: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "square.and.arrow.up")
                    .font(.title2)
                Text("Share to Groo")
                    .font(.headline)
                Spacer()
            }
            .padding(.bottom, 4)

            Divider()

            // Items preview
            if items.isEmpty {
                Text("Loading...")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(spacing: 8) {
                                Image(systemName: item.icon)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                Text(item.displayText)
                                    .lineLimit(2)
                                    .font(.callout)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 80)
            }

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            Divider()

            // Buttons
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Add to Groo") {
                    onSend()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(items.isEmpty || isProcessing)
            }
        }
        .padding()
        .frame(width: 320, height: 200)
    }
}
