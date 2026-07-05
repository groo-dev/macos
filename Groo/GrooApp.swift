//
//  GrooApp.swift
//  Groo
//
//  Main app entry point - delegates to AppDelegate for menu bar app.
//

import SwiftUI
import GrooAuth

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

    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if appDelegate.authService?.isAuthenticated == true {
                LabeledContent("Status") {
                    HStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text(appDelegate.authService?.currentUserEmail ?? "Signed In")
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
                        signOut()
                    }
                }
            } else {
                LabeledContent("Status") {
                    Text("Not signed in")
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    signIn()
                } label: {
                    if isSigningIn {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Sign in with Groo")
                    }
                }
                .disabled(isSigningIn)
            }
        }
        .padding()
    }

    private func signIn() {
        errorMessage = nil
        isSigningIn = true
        let anchor = NSApp.keyWindow ?? NSApp.windows.first
        Task {
            defer { isSigningIn = false }
            guard let authService = appDelegate.authService, let anchor else {
                errorMessage = "No window available to present sign-in."
                return
            }
            do {
                try await authService.startSignIn(anchor: anchor)
            } catch GrooAuthError.userCancelled {
                // User dismissed the sign-in sheet; nothing to report.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func signOut() {
        Task {
            await appDelegate.authService?.logout()
        }
    }
}
