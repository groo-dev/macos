//
//  AuthService.swift
//  Groo
//
//  OAuth authentication via GrooAuth ("Sign in with Groo").
//  Wraps a GrooAuthSession actor and republishes its state for SwiftUI.
//

import AppKit
import Foundation
import os
import AuthenticationServices
import GrooAuth

// MARK: - AuthService

@MainActor
@Observable
final class AuthService {
    private(set) var isAuthenticated = false
    var currentUserEmail: String?

    private let session: GrooAuthSession
    private let legacyKeychain = KeychainService()
    private var stateObservationTask: Task<Void, Never>?
    private let log = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "dev.groo.mac", category: "auth")

    init() {
        let session = GrooAuthFactory.makeSession()
        self.session = session

        stateObservationTask = Task { [weak self] in
            guard let self else { return }
            for await state in await session.stateStream {
                self.apply(state)
            }
        }

        Task { [weak self] in
            await self?.migrateLegacyPATIfNeeded()
        }
    }

    private func apply(_ state: GrooAuthState) {
        switch state {
        case .signedOut:
            isAuthenticated = false
            currentUserEmail = nil
        case .signedIn(let user):
            isAuthenticated = true
            currentUserEmail = user.email
        }
    }

    /// One-time migration away from the old pasted-PAT flow: if a legacy
    /// `pat_token` is still in the Keychain and OAuth hasn't produced a signed-in
    /// session, the PAT is dead weight — delete it and require a fresh
    /// "Sign in with Groo".
    private func migrateLegacyPATIfNeeded() async {
        guard case .signedOut = await session.currentState() else { return }
        guard legacyKeychain.exists(for: KeychainService.Key.patToken) else { return }
        do {
            try legacyKeychain.delete(for: KeychainService.Key.patToken)
        } catch {
            log.fault("Legacy PAT migration: failed to delete pat_token: \(String(describing: error), privacy: .private)")
        }
    }

    // MARK: - Open Settings

    /// Open accounts settings page (account management outside of sign-in).
    func openAccountSettings() {
        NSWorkspace.shared.open(Config.accountsSettingsURL)
    }

    // MARK: - Sign in / out

    /// Presents the OAuth web sign-in flow anchored to `anchor`. On success,
    /// `isAuthenticated`/`currentUserEmail` update via `stateStream`.
    func startSignIn(anchor: NSWindow) async throws {
        do {
            // `prompt: .login` because every caller of this is a sign-in control
            // shown only while signed out. Without it the issuer answers the
            // cookie the system browser still holds and returns a code with no
            // screen at all — so signing out and back in silently returned the
            // same account, with no way to be anybody else. Reported on iOS
            // 2026-08-31; this app had the identical defect.
            _ = try await session.signIn(presentationAnchor: anchor, prompt: .login)
        } catch {
            // Keep the error payload .private — it can carry a server message or
            // URL. The error is rethrown so the UI still surfaces it to the user.
            log.error("startSignIn failed: \(String(describing: error), privacy: .private)")
            throw error
        }
    }

    /// Signs out locally and attempts server-side revocation. Never throws —
    /// the app is always signed out locally afterward regardless of whether
    /// revocation succeeded.
    func logout() async {
        _ = await session.signOut()

        // Clear locally-cached encryption data; it's meaningless without a session.
        try? legacyKeychain.delete(for: KeychainService.Key.encryptionKey)
        try? legacyKeychain.delete(for: KeychainService.Key.encryptionSalt)
    }

    // MARK: - Access token (for authenticated API calls)

    /// Returns a valid access token, refreshing transparently if it's within
    /// 60s of expiry. Throws `GrooAuthError.signedOut` if there's no session.
    func accessToken() async throws -> String {
        try await session.accessToken()
    }

    /// Forces a token refresh (bypassing the expiry check `accessToken()`
    /// uses) and returns the new access token. Callers use this exactly once
    /// after an API call comes back `401` despite holding a token
    /// `accessToken()` considered valid, then retry the request. If the
    /// refresh itself is rejected (e.g. revoked), this throws and
    /// `isAuthenticated` flips to `false` via `stateStream`.
    func forceRefreshAccessToken() async throws -> String {
        try await session.forceRefreshAccessToken()
    }
}
