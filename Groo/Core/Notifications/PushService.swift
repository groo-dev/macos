//
//  PushService.swift
//  Groo
//
//  APNs registration and push notification handling.
//

import AppKit
import Foundation
import UserNotifications

// MARK: - Types

enum PushError: Error {
    case registrationFailed
    case notAuthorized
    case apiError(Error)
}

struct DeviceRegistration: Encodable {
    let token: String
    let platform: String
    let environment: String
}

// MARK: - PushService

@MainActor
@Observable
class PushService {
    private(set) var isRegistered = false
    private(set) var deviceToken: String?

    private let keychain = KeychainService()

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

    func registerDeviceToken(_ tokenData: Data, api: APIClient) async throws {
        let tokenString = tokenData.map { String(format: "%02x", $0) }.joined()

        // Cache the token
        try keychain.save(tokenString, for: KeychainService.Key.deviceToken)
        deviceToken = tokenString

        // Determine environment
        #if DEBUG
        let environment = "development"
        #else
        let environment = "production"
        #endif

        // Register with server
        let registration = DeviceRegistration(
            token: tokenString,
            platform: "macos",
            environment: environment
        )

        do {
            let _: [String: Bool] = try await api.post(APIClient.Endpoint.devices, body: registration)
            isRegistered = true
        } catch {
            throw PushError.apiError(error)
        }
    }

    func unregisterDeviceToken(api: APIClient) async throws {
        guard let token = deviceToken else { return }

        do {
            try await api.delete(APIClient.Endpoint.device(token))
        } catch {
            // Ignore errors during unregistration
        }

        try? keychain.delete(for: KeychainService.Key.deviceToken)
        deviceToken = nil
        isRegistered = false
    }

    // MARK: - Notification Handling

    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) {
        // Check if this is a sync notification
        if let type = userInfo["type"] as? String, type == "sync" {
            onSyncRequested?()
        }
    }

    func handleRegistrationFailure(_ error: Error) {
        print("Push registration failed: \(error)")
        isRegistered = false
    }
}
