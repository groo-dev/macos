//
//  PushService.swift
//  Groo
//
//  APNs registration and push notification handling.
//  Device tokens are registered with accounts API.
//

import AppKit
import Foundation
import UserNotifications

// MARK: - Types

enum PushError: Error {
    case registrationFailed
    case notAuthorized
    case noAuthToken
    case apiError(Error)
}

struct DeviceRegistration: Encodable {
    let token: String
    let platform: String
    let environment: String
    let bundleId: String
    let name: String
}

// MARK: - PushService

@MainActor
@Observable
class PushService {
    private(set) var isRegistered = false
    private(set) var deviceToken: String?

    private let keychain = KeychainService()

    /// Wired up by `AppDelegate` after both services are constructed. Used to obtain
    /// the OAuth access token for device registration requests.
    weak var authService: AuthService?

    // Callback for when a sync notification is received
    var onSyncRequested: (() -> Void)?

    init() {
        // Load cached token
        deviceToken = try? keychain.loadString(for: KeychainService.Key.deviceToken)
        isRegistered = deviceToken != nil
    }

    // MARK: - Authorization

    func requestAuthorization() async throws -> Bool {
        let center = UNUserNotificationCenter.current()

        let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])

        if granted {
            // Register for remote notifications on main thread
            await MainActor.run {
                NSApplication.shared.registerForRemoteNotifications()
            }
        }

        return granted
    }

    // MARK: - Token Registration

    func registerDeviceToken(_ tokenData: Data) async throws {
        let tokenString = tokenData.map { String(format: "%02x", $0) }.joined()
        print("[PushService] registerDeviceToken called")
        print("[PushService] Token: \(tokenString.prefix(16))...")

        // Cache the token
        try keychain.save(tokenString, for: KeychainService.Key.deviceToken)
        deviceToken = tokenString

        guard let authService else {
            print("[PushService] ERROR: No AuthService wired, can't register device")
            throw PushError.noAuthToken
        }

        // Determine environment
        #if DEBUG
        let environment = "development"
        #else
        let environment = "production"
        #endif
        print("[PushService] Environment: \(environment)")

        // Register with accounts API
        let bundleId = Bundle.main.bundleIdentifier ?? "dev.groo.mac"
        let deviceName = Host.current().localizedName ?? "Mac"
        print("[PushService] Bundle ID: \(bundleId)")
        print("[PushService] Device name: \(deviceName)")

        let registration = DeviceRegistration(
            token: tokenString,
            platform: "macos",
            environment: environment,
            bundleId: bundleId,
            name: deviceName
        )

        let url = Config.accountsAPIBaseURL.appendingPathComponent("v1/devices")
        print("[PushService] URL: \(url.absoluteString)")

        let body = try JSONEncoder().encode(registration)

        func send(_ accessToken: String) async throws -> (Data, HTTPURLResponse) {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = body

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                print("[PushService] ERROR: Invalid response type")
                throw PushError.registrationFailed
            }
            return (data, httpResponse)
        }

        print("[PushService] Sending registration request...")
        var (data, httpResponse) = try await send(authService.accessToken())

        if httpResponse.statusCode == 401 {
            // Token looked valid but the server rejected it — force one refresh
            // and retry exactly once; a second 401 falls through and fails below.
            let refreshedToken = try await authService.forceRefreshAccessToken()
            (data, httpResponse) = try await send(refreshedToken)
        }

        let responseBody = String(data: data, encoding: .utf8) ?? "empty"
        print("[PushService] Response status: \(httpResponse.statusCode)")
        print("[PushService] Response body: \(responseBody)")

        guard (200...299).contains(httpResponse.statusCode) else {
            print("[PushService] Registration failed: \(responseBody)")
            throw PushError.registrationFailed
        }

        isRegistered = true
        print("[PushService] Device registered successfully")
    }

    func unregisterDeviceToken() async throws {
        guard let token = deviceToken else { return }

        guard let authService else {
            // Just clear local state if no auth
            try? keychain.delete(for: KeychainService.Key.deviceToken)
            deviceToken = nil
            isRegistered = false
            return
        }

        let url = Config.accountsAPIBaseURL.appendingPathComponent("v1/devices/\(token)")

        func send(_ accessToken: String) async throws -> HTTPURLResponse? {
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let (_, response) = try await URLSession.shared.data(for: request)
            return response as? HTTPURLResponse
        }

        do {
            let accessToken = try await authService.accessToken()
            var httpResponse = try await send(accessToken)

            if httpResponse?.statusCode == 401 {
                let refreshedToken = try await authService.forceRefreshAccessToken()
                httpResponse = try await send(refreshedToken)
            }
        } catch {
            // Ignore errors during unregistration
        }

        try? keychain.delete(for: KeychainService.Key.deviceToken)
        deviceToken = nil
        isRegistered = false
    }

    // MARK: - Notification Handling

    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) {
        print("[PushService] Received notification: \(userInfo)")

        // Check if this is a sync notification
        // The payload structure is: { "aps": {...}, "action": "sync" }
        if let action = userInfo["action"] as? String, action == "sync" {
            print("[PushService] Triggering sync")
            onSyncRequested?()
        }
    }

    func handleRegistrationFailure(_ error: Error) {
        print("Push registration failed: \(error)")
        isRegistered = false
    }
}
