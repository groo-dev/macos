//
//  MainWindowView.swift
//  Groo
//
//  Main window with sidebar navigation.
//

import SwiftUI

struct MainWindowView: View {
    @Bindable var authService: AuthService
    @Bindable var padService: PadService

    @State private var selectedFeature: Feature? = .pad
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic

    enum Feature: String, CaseIterable, Identifiable {
        case pad = "Pad"
        // Future features:
        // case pass = "Pass"
        // case drive = "Drive"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .pad: return "list.clipboard"
            }
        }

        var description: String {
            switch self {
            case .pad: return "Clipboard & text sharing"
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
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        columnVisibility = columnVisibility == .detailOnly ? .automatic : .detailOnly
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                }
            }
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
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Refresh button
                Button {
                    Task {
                        await padService.refresh()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(padService.isLoading)
                .help("Refresh")

                // User menu
                Menu {
                    Button("Lock") {
                        padService.lock()
                    }
                    Divider()
                    Button("Sign Out") {
                        try? authService.logout()
                    }
                } label: {
                    Image(systemName: "person.crop.circle")
                }
            }
        }
    }

    @ViewBuilder
    private func featureView(for feature: Feature) -> some View {
        switch feature {
        case .pad:
            PadDetailView(padService: padService)
        }
    }
}

// MARK: - Pad Detail View

private struct PadDetailView: View {
    @Bindable var padService: PadService

    var body: some View {
        PadListView(padService: padService)
            .navigationTitle("Pad")
            .navigationSubtitle("\(padService.items.count) items")
    }
}

// MARK: - Login View

private struct LoginView: View {
    @Bindable var authService: AuthService

    @State private var patToken = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)

            Text("Welcome to Groo")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Sign in with a Personal Access Token")
                .font(.headline)
                .foregroundStyle(.secondary)

            // Instructions
            VStack(alignment: .leading, spacing: 8) {
                instructionRow(number: "1", text: "Click below to open account settings")
                instructionRow(number: "2", text: "Create a new Personal Access Token")
                instructionRow(number: "3", text: "Copy and paste the token below")
            }
            .frame(maxWidth: 350)

            // Open settings button
            Button {
                authService.openAccountSettings()
            } label: {
                Label("Open Account Settings", systemImage: "safari")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            // PAT input
            VStack(spacing: 12) {
                TextField("Paste your token here...", text: $patToken)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 350)
                    .onSubmit {
                        signIn()
                    }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    signIn()
                } label: {
                    Text("Sign In")
                        .frame(width: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(patToken.isEmpty)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func instructionRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor)
                .clipShape(Circle())

            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private func signIn() {
        errorMessage = nil
        do {
            try authService.login(patToken: patToken)
        } catch {
            errorMessage = "Invalid token. Please try again."
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
