//
//  MainWindowView.swift
//  Groo
//
//  Main window with sidebar navigation.
//

import SwiftUI
import GrooAuth

struct MainWindowView: View {
    @Bindable var authService: AuthService
    @Bindable var padService: PadService

    @State private var selectedFeature: Feature? = .pad
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic

    enum Feature: String, CaseIterable, Identifiable {
        case pad = "Pad"
        case pass = "Pass"
        case drive = "Drive"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .pad: return "list.clipboard"
            case .pass: return "key.fill"
            case .drive: return "externaldrive.fill"
            }
        }

        var description: String {
            switch self {
            case .pad: return "Clipboard & text sharing"
            case .pass: return "Password manager"
            case .drive: return "File storage"
            }
        }
    }

    var body: some View {
        Group {
            if !authService.isAuthenticated {
                LoginView(authService: authService)
            } else if !padService.isUnlocked {
                UnlockView(padService: padService)
            } else {
                mainContent
            }
        }
    }

    private var mainContent: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar
            List(Feature.allCases, selection: $selectedFeature) { feature in
                NavigationLink(value: feature) {
                    Label(feature.rawValue, systemImage: feature.icon)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
        } detail: {
            // Detail view
            if let feature = selectedFeature {
                featureView(for: feature)
            } else {
                ContentUnavailableView(
                    "Select a Feature",
                    systemImage: "square.stack.3d.up",
                    description: Text("Choose a feature from the sidebar")
                )
            }
        }
    }

    @ViewBuilder
    private func featureView(for feature: Feature) -> some View {
        switch feature {
        case .pad:
            PadDetailView(authService: authService, padService: padService)
        case .pass:
            PassPlaceholderView()
        case .drive:
            DrivePlaceholderView()
        }
    }
}

// MARK: - Pass Placeholder

private struct PassPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Password Manager",
            systemImage: "key.fill",
            description: Text("Coming soon")
        )
        .navigationTitle("Pass")
    }
}

// MARK: - Drive Placeholder

private struct DrivePlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "File Storage",
            systemImage: "externaldrive.fill",
            description: Text("Coming soon")
        )
        .navigationTitle("Drive")
    }
}

// MARK: - Pad Detail View

private struct PadDetailView: View {
    @Bindable var authService: AuthService
    @Bindable var padService: PadService

    var body: some View {
        PadListView(padService: padService)
            .navigationTitle("Pad")
            .navigationSubtitle("\(padService.items.count) items")
            .toolbar {
                // Refresh button
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            await padService.refresh()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(padService.isLoading)
                    .help("Refresh (⌘R)")
                }

                // User menu
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Lock") {
                            padService.lock()
                        }
                        Divider()
                        Button("Sign Out") {
                            Task {
                                await authService.logout()
                            }
                        }
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .help("Account")
                }
            }
    }
}

// MARK: - Login View

private struct LoginView: View {
    @Bindable var authService: AuthService

    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)

            Text("Welcome to Groo")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Sign in with your Groo account to continue")
                .font(.headline)
                .foregroundStyle(.secondary)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                signIn()
            } label: {
                if isSigningIn {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 160)
                } else {
                    Text("Sign in with Groo")
                        .frame(width: 160)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isSigningIn)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func signIn() {
        errorMessage = nil
        isSigningIn = true
        let anchor = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first
        Task {
            defer { isSigningIn = false }
            guard let anchor else {
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
}

// MARK: - Unlock View

private struct UnlockView: View {
    @Bindable var padService: PadService

    @State private var password = ""
    @State private var isUnlocking = false
    @State private var errorMessage: String?
    @State private var isNewSetup = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)

            Text(isNewSetup ? "Set Up Encryption" : "Unlock Your Data")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(isNewSetup
                 ? "Create a password to encrypt your data. This password never leaves your device."
                 : "Enter your encryption password to access your data.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            VStack(spacing: 12) {
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                    .onSubmit {
                        unlock()
                    }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    unlock()
                } label: {
                    if isUnlocking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(isNewSetup ? "Set Password" : "Unlock")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(password.isEmpty || isUnlocking)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            // Check if encryption is set up
            do {
                isNewSetup = try await !padService.checkEncryptionSetup()
            } catch {
                // Assume existing setup if check fails
                isNewSetup = false
            }
        }
    }

    private func unlock() {
        isUnlocking = true
        errorMessage = nil

        Task {
            do {
                if isNewSetup {
                    try await padService.setupEncryption(password: password)
                } else {
                    let success = try await padService.unlock(password: password)
                    if !success {
                        errorMessage = "Incorrect password"
                        isUnlocking = false
                        return
                    }
                }
                await padService.refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
            isUnlocking = false
        }
    }
}

// MARK: - Preview

#Preview {
    let authService = AuthService()
    let apiClient = APIClient(baseURL: URL(string: "https://pad.groo.dev")!)
    let padService = PadService(api: apiClient)

    return MainWindowView(
        authService: authService,
        padService: padService
    )
    .frame(width: 800, height: 600)
}
