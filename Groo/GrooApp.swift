//
//  GrooApp.swift
//  Groo
//
//  Main app entry point - delegates to AppDelegate for menu bar app.
//

import SwiftUI

@main
struct GrooApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty WindowGroup - AppDelegate manages windows
        // This is needed to satisfy the App protocol requirement
        Settings {
            SettingsView(appDelegate: appDelegate)
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    let appDelegate: AppDelegate

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(0)

            AccountSettingsView(appDelegate: appDelegate)
                .tabItem {
                    Label("Account", systemImage: "person.crop.circle")
                }
                .tag(1)
        }
        .frame(width: 450, height: 250)
    }
}

// MARK: - General Settings

private struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showDockIcon") private var showDockIcon = false

    var body: some View {
        Form {
            Toggle("Launch at Login", isOn: $launchAtLogin)
            Toggle("Show Dock Icon", isOn: $showDockIcon)
                .onChange(of: showDockIcon) { _, newValue in
                    NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                }
        }
        .padding()
    }
}

// MARK: - Account Settings

private struct AccountSettingsView: View {
    let appDelegate: AppDelegate

    @State private var patToken = ""
    @State private var showError = false

    var body: some View {
        Form {
            if appDelegate.authService?.isAuthenticated == true {
                LabeledContent("Status") {
                    HStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Signed In")
                    }
                }

                LabeledContent("Encryption") {
                    Text(appDelegate.padService?.isUnlocked == true ? "Unlocked" : "Locked")
                }

                Divider()

                HStack {
                    Button("Lock") {
                        appDelegate.padService?.lock()
                    }
                    .disabled(appDelegate.padService?.isUnlocked != true)

                    Button("Sign Out") {
                        try? appDelegate.authService?.logout()
                    }
                }
            } else {
                LabeledContent("Status") {
                    Text("Not signed in")
                        .foregroundStyle(.secondary)
                }

                Button("Open Account Settings") {
                    appDelegate.authService?.openAccountSettings()
                }

                TextField("Paste PAT here...", text: $patToken)
                    .textFieldStyle(.roundedBorder)

                if showError {
                    Text("Invalid token")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button("Sign In") {
                    signIn()
                }
                .disabled(patToken.isEmpty)
            }
        }
        .padding()
    }

    private func signIn() {
        showError = false
        do {
            try appDelegate.authService?.login(patToken: patToken)
        } catch {
            showError = true
        }
    }
}
