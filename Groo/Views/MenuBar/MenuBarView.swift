//
//  MenuBarView.swift
//  Groo
//
//  Main menu bar popover view with feature tabs.
//

import SwiftUI

struct MenuBarView: View {
    @Bindable var authService: AuthService
    @Bindable var padService: PadService
    var onOpenMainWindow: () -> Void

    @State private var selectedTab: MenuTab = .pad

    enum MenuTab: String, CaseIterable {
        case pad = "Pad"
        // Future: case pass = "Pass"
        // Future: case drive = "Drive"

        var icon: String {
            switch self {
            case .pad: return "list.clipboard"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !authService.isAuthenticated {
                // Login view
                LoginPromptView(authService: authService)
            } else if !padService.isUnlocked {
                // Password prompt
                PasswordPromptView(padService: padService)
            } else {
                // Main content
                contentView
            }

            Divider()

            // Footer
            footerView
        }
        .frame(width: 300, height: 420)
    }

    @ViewBuilder
    private var contentView: some View {
        // Tab bar (for future multiple features)
        // For now, just show Pad
        VStack(spacing: 0) {
            // Header with tabs
            HStack(spacing: 0) {
                ForEach(MenuTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Label(tab.rawValue, systemImage: tab.icon)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                            .foregroundStyle(selectedTab == tab ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            // Tab content
            switch selectedTab {
            case .pad:
                PadMenuView(padService: padService)
            }
        }
    }

    private var footerView: some View {
        HStack {
            // User info
            if authService.isAuthenticated {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("Connected")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Open main window button
            Button {
                onOpenMainWindow()
            } label: {
                Image(systemName: "macwindow")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Open main window")

            // Settings menu
            Menu {
                if authService.isAuthenticated {
                    Button("Lock") {
                        padService.lock()
                    }
                    Divider()
                    Button("Sign Out") {
                        try? authService.logout()
                    }
                }
                Divider()
                Button("Quit Groo") {
                    NSApp.terminate(nil)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Login Prompt

private struct LoginPromptView: View {
    @Bindable var authService: AuthService

    @State private var patToken = ""
    @State private var showError = false

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text("Sign in to Groo")
                .font(.headline)

            Text("Create a Personal Access Token in your account settings")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                authService.openAccountSettings()
            } label: {
                Label("Open Settings", systemImage: "safari")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            TextField("Paste token here...", text: $patToken)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit {
                    signIn()
                }

            if showError {
                Text("Invalid token")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                signIn()
            } label: {
                Text("Sign In")
            }
            .buttonStyle(.borderedProminent)
            .disabled(patToken.isEmpty)

            Spacer()
        }
        .padding()
    }

    private func signIn() {
        showError = false
        do {
            try authService.login(patToken: patToken)
        } catch {
            showError = true
        }
    }
}

// MARK: - Password Prompt

private struct PasswordPromptView: View {
    @Bindable var padService: PadService

    @State private var password = ""
    @State private var isUnlocking = false
    @State private var showError = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("Enter Password")
                .font(.headline)

            Text("Your encryption password is required to access your data")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit {
                    unlock()
                }

            if showError {
                Text("Incorrect password")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                unlock()
            } label: {
                if isUnlocking {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Text("Unlock")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(password.isEmpty || isUnlocking)

            Spacer()
        }
        .padding()
    }

    private func unlock() {
        isUnlocking = true
        showError = false

        Task {
            do {
                let success = try await padService.unlock(password: password)
                if success {
                    await padService.refresh()
                } else {
                    showError = true
                }
            } catch {
                showError = true
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

    return MenuBarView(
        authService: authService,
        padService: padService,
        onOpenMainWindow: {}
    )
}
