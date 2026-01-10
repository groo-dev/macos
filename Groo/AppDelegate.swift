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

    // MARK: - Services Setup

    private func setupServices() {
        // TODO: Switch to production URLs before release
        let baseURL = URL(string: "http://localhost:13648")!  // Local: http://localhost:13648, Prod: https://pad.groo.dev
        apiClient = APIClient(baseURL: baseURL)
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
            button.image = NSImage(systemSymbolName: "square.stack.3d.up.fill", accessibilityDescription: "Groo")
            button.action = #selector(togglePopover)
            button.target = self

            // Enable drag and drop
            button.window?.registerForDraggedTypes([.fileURL, .string])
        }

        // Create popover
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 300, height: 400)
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

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }

        if popover.isShown {
            closePopover()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
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
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Groo"
            window.contentViewController = NSHostingController(rootView: contentView)
            window.center()
            window.setFrameAutosaveName("MainWindow")
            window.minSize = NSSize(width: 600, height: 400)

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
            try? await pushService.registerDeviceToken(deviceToken, api: apiClient)
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
