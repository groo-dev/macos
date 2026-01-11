//
//  Config.swift
//  Groo
//
//  Centralized configuration for URLs and settings.
//  Debug builds use local servers, Release uses production.
//

import Foundation

enum Config {
    // MARK: - URLs

    static var padAPIBaseURL: URL {
        #if DEBUG
        // Local development - update ports as needed
        URL(string: "http://localhost:13648")!
        #else
        URL(string: "https://pad.groo.dev")!
        #endif
    }

    static var accountsAPIBaseURL: URL {
        #if DEBUG
        URL(string: "http://localhost:37586")!
        #else
        URL(string: "https://accounts.groo.dev")!
        #endif
    }

    static var accountsWebURL: URL {
        #if DEBUG
        URL(string: "http://localhost:37586")!
        #else
        URL(string: "https://accounts.groo.dev")!
        #endif
    }

    static var accountsSettingsURL: URL {
        accountsWebURL.appendingPathComponent("settings")
    }
}
