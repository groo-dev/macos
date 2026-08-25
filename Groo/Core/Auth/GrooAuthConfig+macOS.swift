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
    ///
    /// Registered under the **Pad** application with `bundle_id = dev.groo.mac`,
    /// which is the whole of what this app does. The bundle id is not decoration:
    /// `runtime` issues `iss = <workspace origin>` for a bundle client and
    /// `iss = <origin>/oauth2/<slug>` for one without
    /// (`runtime/api/src/routes/oauth.ts:133`), and `issuer` below is the bare
    /// origin — so dropping the bundle id would make this app reject its own
    /// callback under RFC 9207.
    ///
    /// The previous value, `app_dcbbd7eec5dcfa934f633236fa1770e9`, belonged to the
    /// catch-all `Groo` application, DELETED on 2026-08-22 (`runtime/CLAUDE.md`,
    /// "The `Groo` catch-all application is DELETED"). It took `Groo macOS` with
    /// it and left this app unable to sign in at all — that file recorded the
    /// replacement as "none" until this client was registered on 2026-08-25.
    private static let clientId = "client_135a983bd857072b1adc5c9b5ebd2b3e"

    static func makeConfig() -> GrooAuthConfig {
        #if DEBUG
        let redirect = "dev.groo.mac.debug://oauth-callback"
        let service = "dev.groo.mac.debug"
        #else
        let redirect = "dev.groo.mac://oauth-callback"
        let service = "dev.groo.mac"
        #endif

        return GrooAuthConfig(
            issuer: URL(string: "https://me.groo.dev")!,
            clientId: clientId,
            redirectURI: redirect,
            scopes: [
                "openid", "profile", "email", "offline_access",
                "pad:read", "pad:write",
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
