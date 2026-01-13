//
//  MenuBarView.swift
//  Groo
//
//  Minimal menu bar popover - speed-first design.
//

import AppKit
import SwiftUI

// MARK: - Pending File Model

private struct PendingFile: Identifiable {
    let id = UUID()
    let name: String
    let data: Data
    let mimeType: String
    let isImage: Bool

    var icon: String {
        if isImage {
            return "photo"
        }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.fill"
        case "zip", "tar", "gz", "rar": return "doc.zipper"
        case "mp3", "wav", "m4a": return "music.note"
        case "mp4", "mov", "avi": return "film"
        case "txt", "md": return "doc.text"
        case "json", "xml", "html", "css", "js", "swift": return "doc.text.fill"
        default: return "doc"
        }
    }
}

struct MenuBarView: View {
    @Bindable var authService: AuthService
    @Bindable var padService: PadService
    var onOpenMainWindow: () -> Void

    @State private var newItemText = ""
    @State private var selectedIndex: Int? = nil
    @FocusState private var isTextFieldFocused: Bool
    @State private var showCopiedToast = false
    @State private var showErrorToast = false
    @State private var errorMessage = ""
    @State private var pendingFiles: [PendingFile] = []

    var body: some View {
        VStack(spacing: 0) {
            if !authService.isAuthenticated {
                LoginPromptView(authService: authService)
            } else if !padService.isUnlocked {
                PasswordPromptView(authService: authService, padService: padService)
            } else {
                contentView
            }
        }
        .frame(width: Theme.Size.popoverWidth, height: Theme.Size.popoverHeight)
    }

    // MARK: - Main Content

    @ViewBuilder
    private var contentView: some View {
        ZStack {
            VStack(spacing: 0) {
                // Add textarea at top
                addTextArea

                Divider()

                // Item list
                itemListView

                Divider()

                // Footer
                footerView
            }

            // Copied toast
            if showCopiedToast {
                VStack {
                    Spacer()
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Copied")
                            .font(.callout)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    .padding(.bottom, 50)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Error toast
            if showErrorToast {
                VStack {
                    Spacer()
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(errorMessage)
                            .font(.callout)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    .padding(.bottom, 50)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: showCopiedToast)
        .animation(.spring(duration: 0.3), value: showErrorToast)
        .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
        .onKeyPress(.downArrow) { moveSelection(1); return .handled }
        .onKeyPress(.return) {
            if selectedIndex != nil {
                copySelected()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(keys: [KeyEquivalent("r")]) { press in
            if press.modifiers.contains(.command) {
                Task { await padService.refresh() }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(keys: [KeyEquivalent("o")]) { press in
            if press.modifiers.contains(.command) {
                onOpenMainWindow()
                return .handled
            }
            return .ignored
        }
        .onAppear {
            isTextFieldFocused = true
        }
    }

    // MARK: - Add Text Area

    @State private var textEditorHeight: CGFloat = 22

    private var addTextArea: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
                CustomTextEditor(
                    text: $newItemText,
                    placeholder: "Add something...",
                    height: $textEditorHeight,
                    onSubmit: submitItem,
                    onPasteFiles: { urls in
                        addFilesToPending(urls)
                    },
                    onPasteImage: { data in
                        addImageToPending(data)
                    }
                )
                .focused($isTextFieldFocused)
                .frame(height: min(textEditorHeight, 80)) // Max 4 lines roughly

                Button {
                    pasteAndSubmit()
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Paste & add")
            }
            .padding(Theme.Spacing.md)

            // Pending files preview
            if !pendingFiles.isEmpty {
                pendingFilesPreview
            }
        }
    }

    private var pendingFilesPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(pendingFiles) { file in
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: file.icon)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Text(file.name)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 80)

                        Button {
                            pendingFiles.removeAll { $0.id == file.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Theme.Colors.surfaceHover)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.sm)
        }
    }

    private func pasteAndSubmit() {
        let pasteboard = NSPasteboard.general

        // Check for files first - upload all as one item
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            uploadFilesAsOneItem(urls)
            return
        }

        // Check for images
        if let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) {
            uploadImageDataAsItem(imageData)
            return
        }

        // Check for text
        if let string = pasteboard.string(forType: .string), !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let text = string.trimmingCharacters(in: .whitespacesAndNewlines)
            Task {
                do {
                    try await padService.addItem(text: text)
                } catch {
                    showError("Failed to add item")
                }
            }
        }
    }

    /// Upload multiple files as a single item (for paste button)
    private func uploadFilesAsOneItem(_ urls: [URL]) {
        Task {
            do {
                var attachments: [PadFileAttachment] = []
                for url in urls {
                    let data = try Data(contentsOf: url)
                    let name = url.lastPathComponent
                    let type = mimeType(for: url.pathExtension)
                    let attachment = try await padService.uploadFile(name: name, type: type, data: data)
                    attachments.append(attachment)
                }
                try await padService.addItemWithFiles(files: attachments)
            } catch {
                showError("Failed to upload files")
            }
        }
    }

    /// Upload image data as a single item (for paste button)
    private func uploadImageDataAsItem(_ data: Data) {
        Task {
            do {
                let name = "image-\(Date().timeIntervalSince1970).png"
                let attachment = try await padService.uploadFile(name: name, type: "image/png", data: data)
                try await padService.addItemWithFiles(files: [attachment])
            } catch {
                showError("Failed to upload image")
            }
        }
    }

    /// Add file URLs to pending list (for textbox paste)
    private func addFilesToPending(_ urls: [URL]) {
        for url in urls {
            if let data = try? Data(contentsOf: url) {
                let name = url.lastPathComponent
                let type = mimeType(for: url.pathExtension)
                let isImage = type.hasPrefix("image/")
                pendingFiles.append(PendingFile(name: name, data: data, mimeType: type, isImage: isImage))
            }
        }
    }

    /// Add image data to pending list (for textbox paste)
    private func addImageToPending(_ data: Data) {
        let name = "image-\(Date().timeIntervalSince1970).png"
        pendingFiles.append(PendingFile(name: name, data: data, mimeType: "image/png", isImage: true))
    }

    private func mimeType(for ext: String) -> String {
        let ext = ext.lowercased()
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "pdf": return "application/pdf"
        case "json": return "application/json"
        case "txt": return "text/plain"
        case "html": return "text/html"
        case "css": return "text/css"
        case "js": return "application/javascript"
        case "zip": return "application/zip"
        case "mp3": return "audio/mpeg"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        default: return "application/octet-stream"
        }
    }

    /// Submit item with text and/or pending files
    private func submitItem() {
        let text = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filesToUpload = pendingFiles

        // Need either text or files
        guard !text.isEmpty || !filesToUpload.isEmpty else { return }

        // Clear UI immediately
        let textToAdd = text
        newItemText = ""
        textEditorHeight = 22
        pendingFiles = []

        Task {
            do {
                if filesToUpload.isEmpty {
                    // Text only
                    try await padService.addItem(text: textToAdd)
                } else {
                    // Upload files first
                    var attachments: [PadFileAttachment] = []
                    for file in filesToUpload {
                        let attachment = try await padService.uploadFile(
                            name: file.name,
                            type: file.mimeType,
                            data: file.data
                        )
                        attachments.append(attachment)
                    }
                    // Create item with files and optional text
                    try await padService.addItemWithFiles(text: textToAdd, files: attachments)
                }
            } catch {
                // Restore on failure
                newItemText = textToAdd
                pendingFiles = filesToUpload
                showError("Failed to add item")
            }
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        showErrorToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showErrorToast = false
        }
    }

    // MARK: - Item List

    private var items: [DecryptedListItem] {
        padService.items
    }

    @ViewBuilder
    private var itemListView: some View {
        if padService.isLoading && padService.items.isEmpty {
            Spacer()
            ProgressView()
                .scaleEffect(0.8)
            Spacer()
        } else if items.isEmpty {
            emptyStateView
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            let index = items.firstIndex(where: { $0.id == item.id }) ?? 0
                            ItemRow(
                                item: item,
                                isSelected: selectedIndex == index,
                                onCopy: { [item] in copyItem(item) },
                                onDelete: { [item] in deleteItem(item) },
                                onPreviewFile: { file in previewFile(file) },
                                onDownloadFile: { file in downloadFile(file) }
                            )
                            .id(item.id)
                            .transition(.asymmetric(
                                insertion: .opacity,
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                        }
                    }
                    .animation(.spring(duration: 0.3), value: items.map(\.id))
                }
                .onChange(of: selectedIndex) { _, newIndex in
                    if let idx = newIndex, idx < items.count {
                        withAnimation {
                            proxy.scrollTo(items[idx].id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: Theme.Spacing.md) {
            Spacer()

            Image(systemName: "clipboard")
                .font(.system(size: Theme.Size.iconXL))
                .foregroundStyle(.tertiary)

            Text("No items yet")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // Refresh button
            Button {
                Task { await padService.refresh() }
            } label: {
                if padService.isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.borderless)
            .disabled(padService.isLoading)
            .help("Refresh (⌘R)")

            Spacer()

            // Settings menu
            Menu {
                Button("Lock") {
                    padService.lock()
                }
                Divider()
                Button("Sign Out") {
                    try? authService.logout()
                }
                Divider()
                Button("Quit Groo") {
                    NSApp.terminate(nil)
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .menuStyle(.borderlessButton)
            .help("Settings")

            // Open main window
            Button {
                onOpenMainWindow()
            } label: {
                Image(systemName: "macwindow")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Open window (⌘O)")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }

    // MARK: - Actions

    private func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }

        if let current = selectedIndex {
            let newIndex = max(0, min(items.count - 1, current + delta))
            selectedIndex = newIndex
        } else {
            selectedIndex = delta > 0 ? 0 : items.count - 1
        }
    }

    private func copySelected() {
        guard let index = selectedIndex,
              index < items.count else { return }
        copyItem(items[index])
    }

    private func copyItem(_ item: DecryptedListItem) {
        padService.copyToClipboard(item.text)
        showCopiedFeedback()
    }

    private func showCopiedFeedback() {
        showCopiedToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            showCopiedToast = false
        }
    }

    private func deleteItem(_ item: DecryptedListItem) {
        Task {
            try? await padService.deleteItem(id: item.id)
        }
    }

    private func downloadFile(_ file: DecryptedFileAttachment) {
        Task {
            do {
                let data = try await padService.downloadFile(file)

                // Show save panel so user chooses where to save
                let savePanel = NSSavePanel()
                savePanel.nameFieldStringValue = file.name
                savePanel.canCreateDirectories = true

                let response = await savePanel.beginSheetModal(for: NSApp.keyWindow ?? NSApp.windows.first!)

                guard response == .OK, let url = savePanel.url else {
                    return  // User cancelled
                }

                try data.write(to: url)

                // Open in Finder
                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
            } catch {
                print("Failed to download file: \(error)")
            }
        }
    }

    private func previewFile(_ file: DecryptedFileAttachment) {
        Task {
            do {
                let data = try await padService.downloadFile(file)
                await MainActor.run {
                    AppDelegate.shared?.showQuickLookPreview(name: file.name, data: data)
                }
            } catch {
                print("Failed to preview file: \(error)")
            }
        }
    }
}

// MARK: - Item Row

private struct ItemRow: View {
    let item: DecryptedListItem
    let isSelected: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onPreviewFile: (DecryptedFileAttachment) -> Void
    let onDownloadFile: (DecryptedFileAttachment) -> Void

    @State private var isHoveringText = false
    @State private var isHoveringDelete = false

    private var hasText: Bool {
        !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var rowBackground: Color {
        if isHoveringDelete {
            return Color.red.opacity(0.8)
        } else if isSelected {
            return Theme.Colors.surfaceSelected
        } else {
            return Color.clear
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Text (clickable to copy)
            if hasText {
                Text(item.text)
                    .font(.callout)
                    .lineLimit(3)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(isHoveringText && !isHoveringDelete && !isSelected ? Theme.Colors.surfaceHover : Color.clear)
                    .contentShape(Rectangle())
                    .onHover { isHoveringText = $0 }
                    .onTapGesture { onCopy() }
            }

            // Files as icons
            if !item.files.isEmpty {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(item.files) { file in
                        FileIcon(file: file) {
                            onPreviewFile(file)
                        }
                        .contextMenu {
                            Button {
                                onDownloadFile(file)
                            } label: {
                                Label("Save to...", systemImage: "square.and.arrow.down")
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs)
            }

            // Bottom row: timestamp + delete
            HStack(spacing: Theme.Spacing.xs) {
                Text(item.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(isHoveringDelete ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.tertiary))

                Spacer()

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption2)
                        .foregroundStyle(isHoveringDelete ? AnyShapeStyle(.white) : AnyShapeStyle(.tertiary))
                }
                .buttonStyle(.borderless)
                .onHover { isHoveringDelete = $0 }
                .help("Delete")
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if isSelected && !isHoveringDelete {
                Rectangle()
                    .fill(Theme.Colors.selectedBorder)
                    .frame(width: Theme.Size.selectedBorderWidth)
            }
        }
        .animation(Theme.Animation.fastSpring, value: isHoveringText)
        .animation(Theme.Animation.fastSpring, value: isHoveringDelete)
        .animation(Theme.Animation.fastSpring, value: isSelected)
    }
}

// MARK: - File Icon

private struct FileIcon: View {
    let file: DecryptedFileAttachment
    let onTap: () -> Void

    @State private var isHovering = false

    private var iconName: String {
        let ext = (file.name as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.fill"
        case "png", "jpg", "jpeg", "gif", "webp", "heic": return "photo.fill"
        case "mp4", "mov", "avi": return "video.fill"
        case "mp3", "wav", "m4a": return "music.note"
        case "zip", "tar", "gz", "rar": return "doc.zipper"
        case "txt", "md": return "doc.text.fill"
        case "json", "xml", "html", "css", "js", "ts", "swift", "py": return "doc.text.fill"
        default: return "doc.fill"
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Image(systemName: iconName)
                    .font(.system(size: 20))
                    .foregroundStyle(isHovering ? .primary : .secondary)

                Text(file.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 60)
            }
            .padding(Theme.Spacing.xs)
            .background(isHovering ? Theme.Colors.surfaceHover : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Preview \(file.name) (right-click to save)")
    }
}

// MARK: - Custom Text Editor (Enter to submit, Shift+Enter for newline)

// MARK: - Custom NSTextView with paste handling

private class PasteHandlingTextView: NSTextView {
    var onPasteFiles: (([URL]) -> Void)?
    var onPasteImage: ((Data) -> Void)?

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general

        // Check for file URLs first
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            onPasteFiles?(urls)
            return
        }

        // Check for image data
        if let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) {
            onPasteImage?(imageData)
            return
        }

        // Fall back to default text paste
        super.paste(sender)
    }
}

private struct CustomTextEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    @Binding var height: CGFloat
    var onSubmit: () -> Void
    var onPasteFiles: (([URL]) -> Void)?
    var onPasteImage: ((Data) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PasteHandlingTextView()
        textView.onPasteFiles = onPasteFiles
        textView.onPasteImage = onPasteImage

        let scrollView = NSScrollView()
        scrollView.documentView = textView

        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.autoresizingMask = [.width]

        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        // Placeholder
        textView.setValue(
            NSAttributedString(
                string: placeholder,
                attributes: [.foregroundColor: NSColor.tertiaryLabelColor]
            ),
            forKey: "placeholderAttributedString"
        )

        // Initial height calculation
        DispatchQueue.main.async {
            context.coordinator.updateHeight(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PasteHandlingTextView else { return }
        if textView.string != text {
            textView.string = text
            context.coordinator.updateHeight(textView)
        }
        context.coordinator.onSubmit = onSubmit
        context.coordinator.height = $height
        textView.onPasteFiles = onPasteFiles
        textView.onPasteImage = onPasteImage
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, height: $height, onSubmit: onSubmit)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var height: Binding<CGFloat>
        var onSubmit: () -> Void

        init(text: Binding<String>, height: Binding<CGFloat>, onSubmit: @escaping () -> Void) {
            _text = text
            self.height = height
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            updateHeight(textView)
        }

        func updateHeight(_ textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let newHeight = usedRect.height + textView.textContainerInset.height * 2

            DispatchQueue.main.async {
                self.height.wrappedValue = max(22, newHeight)
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Enter without shift = submit
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let event = NSApp.currentEvent
                if event?.modifierFlags.contains(.shift) == true {
                    // Shift+Enter = insert newline
                    return false
                } else {
                    // Enter = submit
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onSubmit()
                    }
                    return true
                }
            }
            return false
        }
    }
}

// MARK: - Login Prompt

private struct LoginPromptView: View {
    @Bindable var authService: AuthService

    @State private var patToken = ""
    @State private var showError = false

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)

            Text("Sign in to Groo")
                .font(.headline)

            Button {
                authService.openAccountSettings()
            } label: {
                Text("Open Account Settings")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            TextField("Paste PAT token...", text: $patToken)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onSubmit { signIn() }

            if showError {
                Text("Invalid token")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.error)
            }

            Button("Sign In") { signIn() }
                .buttonStyle(.borderedProminent)
                .disabled(patToken.isEmpty)

            Spacer()
        }
        .padding(Theme.Spacing.lg)
    }

    private func signIn() {
        showError = false
        do {
            try authService.login(patToken: patToken)
        } catch {
            showError = true
        }
    }
}

// MARK: - Password Prompt

private struct PasswordPromptView: View {
    @Bindable var authService: AuthService
    @Bindable var padService: PadService

    @State private var password = ""
    @State private var isUnlocking = false
    @State private var showError = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Theme.Spacing.lg) {
                Spacer()

                Image(systemName: "lock")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)

                Text("Enter Password")
                    .font(.headline)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .focused($isFocused)
                    .onSubmit { unlock() }

                if showError {
                    Text("Incorrect password")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.error)
                }

                Button {
                    unlock()
                } label: {
                    if isUnlocking {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Text("Unlock")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty || isUnlocking)

                Spacer()
            }
            .padding(Theme.Spacing.lg)

            Divider()

            // Footer with actions
            HStack(spacing: Theme.Spacing.sm) {
                Button("Sign Out") {
                    try? authService.logout()
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
        }
        .onAppear { isFocused = true }
    }

    private func unlock() {
        isUnlocking = true
        showError = false

        Task {
            do {
                let success = try await padService.unlock(password: password)
                if success {
                    await padService.refresh()
                } else {
                    showError = true
                }
            } catch {
                showError = true
            }
            isUnlocking = false
        }
    }
}

// MARK: - Preview

#Preview {
    let authService = AuthService()
    let padService = PadService(api: APIClient(baseURL: Config.padAPIBaseURL))

    return MenuBarView(
        authService: authService,
        padService: padService,
        onOpenMainWindow: {}
    )
}
