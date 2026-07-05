//
//  GrooAuthConfig+macOS.swift
//  Groo
//
//  Wires the GrooAuth OAuth package to this app's concrete OAuth client,
//  redirect URIs, and Keychain configuration.
//

import Foundation
import GrooAuth

enum GrooAuthFactory {
    /// The macOS native OAuth client (shared by debug + release; only the redirect
    /// URI/keychain service vary by build configuration).
    private static let clientId = "app_dcbbd7eec5dcfa934f633236fa1770e9"

    static func makeConfig() -> GrooAuthConfig {
        #if DEBUG
        let redirect = "dev.groo.mac.debug://oauth-callback"
        let service = "dev.groo.mac.debug"
        #else
        let redirect = "dev.groo.mac://oauth-callback"
        let service = "dev.groo.mac"
        #endif

        return GrooAuthConfig(
            issuer: URL(string: "https://accounts.groo.dev")!,
            clientId: clientId,
            redirectURI: redirect,
            scopes: [
                "openid", "profile", "email", "offline_access",
                "pad:read", "pad:write",
                "pass:read", "pass:write",
                "tasks:read", "tasks:write",
                "drive:read", "drive:write",
            ],
            keychainService: service,
            // No AutoFill/Share-extension keychain sharing requirement on macOS —
            // the Share extension doesn't need OAuth tokens, so the app's default
            // (per-app) Keychain access group is fine.
            keychainAccessGroup: nil
        )
    }

    /// Builds a fully-wired `GrooAuthSession` using the real network transport
    /// and `ASWebAuthenticationSession`-backed web authenticator.
    static func makeSession() -> GrooAuthSession {
        let config = makeConfig()
        return GrooAuthSession(
            config: config,
            tokenStore: KeychainTokenStore(service: config.keychainService, accessGroup: nil),
            transport: URLSessionTransport(),
            webAuthenticator: ASWebAuthenticator()
        )
    }
}
