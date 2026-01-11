//
//  AppDelegate.swift
//  Groo
//
//  App lifecycle, menu bar, and push notifications.
//

import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    // Menu bar
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    // Services (shared across the app)
    private(set) var authService: AuthService!
    private(set) var padService: PadService!
    private(set) var pushService: PushService!
    private(set) var apiClient: APIClient!

    // Window management
    private var mainWindow: NSWindow?

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize services
        setupServices()

        // Setup menu bar
        setupMenuBar()

        // Setup push notifications
        setupPushNotifications()

        // Hide dock icon (menu bar app)
        // NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    // MARK: - URL Handling

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleURL(url)
        }
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == "groo" else { return }

        switch url.host {
        case "share":
            handleShareExtensionContent()
        default:
            break
        }
    }

    private func handleShareExtensionContent() {
        // Get shared container URL
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.dev.groo.mac"
        ) else {
            print("Could not access shared container")
            return
        }

        let shareDir = containerURL.appendingPathComponent("ShareExtension", isDirectory: true)
        let dataURL = shareDir.appendingPathComponent("pending.json")

        guard FileManager.default.fileExists(atPath: dataURL.path) else {
            print("No pending share data")
            return
        }

        // Read and process share data
        do {
            let data = try Data(contentsOf: dataURL)
            let shareData = try JSONDecoder().decode(ShareExtensionData.self, from: data)

            // Process items
            Task { @MainActor in
                await processSharedItems(shareData.items, in: shareDir)

                // Clean up
                try? FileManager.default.removeItem(at: dataURL)
            }
        } catch {
            print("Failed to process share data: \(error)")
        }
    }

    @MainActor
    private func processSharedItems(_ items: [ShareExtensionItem], in shareDir: URL) async {
        guard padService.isUnlocked else {
            // Show popover for authentication
            if let button = statusItem?.button {
                popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
            }
            return
        }

        for item in items {
            do {
                switch item.type {
                case "text":
                    try await padService.addItem(text: item.content)

                case "url":
                    try await padService.addItem(text: item.content)

                case "file":
                    if let filePath = item.filePath {
                        let fileURL = URL(fileURLWithPath: filePath)
                        let data = try Data(contentsOf: fileURL)
                        let name = item.content
                        let ext = (name as NSString).pathExtension
                        let type = ext.isEmpty ? "application/octet-stream" : "application/\(ext)"

                        _ = try await padService.uploadFile(name: name, type: type, data: data)

                        // Clean up copied file
                        try? FileManager.default.removeItem(at: fileURL)
                    }

                default:
                    break
                }
            } catch {
                print("Failed to process shared item: \(error)")
            }
        }

        // Refresh to show new items
        await padService.refresh()
    }

    // MARK: - Services Setup

    @MainActor
    private func setupServices() {
        apiClient = APIClient(baseURL: Config.padAPIBaseURL)
        authService = AuthService()
        padService = PadService(api: apiClient)
        pushService = PushService()

        // Connect push service to pad service for sync
        pushService.onSyncRequested = { [weak self] in
            Task { @MainActor in
                await self?.padService.refresh()
            }
        }
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            let icon = NSImage(named: "MenuBarIcon")
            icon?.isTemplate = true
            button.image = icon
            button.action = #selector(togglePopover)
            button.target = self

            // Enable drag and drop
            button.window?.registerForDraggedTypes([.fileURL, .string])
        }

        // Create popover
        popover = NSPopover()
        popover?.contentSize = NSSize(width: Theme.Size.popoverWidth, height: Theme.Size.popoverHeight)
        popover?.behavior = .transient
        popover?.animates = true

        // Set popover content
        let menuBarView = MenuBarView(
            authService: authService,
            padService: padService,
            onOpenMainWindow: { [weak self] in
                self?.closePopover()
                self?.showMainWindow()
            }
        )
        popover?.contentViewController = NSHostingController(rootView: menuBarView)
    }

    @MainActor @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }

        if popover.isShown {
            closePopover()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)

            // Auto-refresh when popover opens (if unlocked)
            if padService.isUnlocked {
                Task { @MainActor in
                    await padService.refresh()
                }
            }
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
    }

    // MARK: - Main Window

    func showMainWindow() {
        if mainWindow == nil {
            let contentView = MainWindowView(
                authService: authService,
                padService: padService
            )

            let window = NSWindow(
                contentRect: NSRect(
                    x: 0, y: 0,
                    width: Theme.Size.mainWindowWidth,
                    height: Theme.Size.mainWindowHeight
                ),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.titlebarAppearsTransparent = false
            window.toolbarStyle = .unified
            window.title = "Groo"
            window.contentViewController = NSHostingController(rootView: contentView)
            window.center()
            window.setFrameAutosaveName("MainWindow")
            window.minSize = NSSize(
                width: Theme.Size.mainWindowMinWidth,
                height: Theme.Size.mainWindowMinHeight
            )
            window.isReleasedWhenClosed = false
            window.delegate = self

            mainWindow = window
        }

        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Push Notifications

    private func setupPushNotifications() {
        Task {
            do {
                let granted = try await pushService.requestAuthorization()
                if granted {
                    print("Push notifications authorized")
                }
            } catch {
                print("Push authorization failed: \(error)")
            }
        }
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task {
            try? await pushService.registerDeviceToken(deviceToken)
        }
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        pushService.handleRegistrationFailure(error)
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        pushService.handleRemoteNotification(userInfo)
    }
}

// MARK: - Drag and Drop (for menu bar icon)

extension AppDelegate: NSDraggingDestination {
    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard

        // Handle files
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls {
                handleDroppedFile(url)
            }
            return true
        }

        // Handle text
        if let string = pasteboard.string(forType: .string) {
            handleDroppedText(string)
            return true
        }

        return false
    }

    @MainActor
    private func handleDroppedFile(_ url: URL) {
        guard padService.isUnlocked else {
            // Show main window for authentication
            showMainWindow()
            return
        }

        Task {
            do {
                let data = try Data(contentsOf: url)
                let name = url.lastPathComponent
                let type = url.pathExtension.isEmpty ? "application/octet-stream" : "application/\(url.pathExtension)"

                _ = try await padService.uploadFile(name: name, type: type, data: data)
                // TODO: Add file to current item or create new item
            } catch {
                print("Failed to upload dropped file: \(error)")
            }
        }
    }

    @MainActor
    private func handleDroppedText(_ text: String) {
        guard padService.isUnlocked else {
            showMainWindow()
            return
        }

        Task {
            try? await padService.addItem(text: text)
        }
    }
}

// MARK: - Window Delegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Window will be reused, no cleanup needed
    }
}

// MARK: - Share Extension Models

struct ShareExtensionData: Codable {
    let items: [ShareExtensionItem]
}

struct ShareExtensionItem: Codable {
    let type: String  // "text", "url", "file"
    let content: String
    let filePath: String?
}
