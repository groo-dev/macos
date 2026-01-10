//
//  PadService.swift
//  Groo
//
//  Pad feature service - handles state, encryption, and API calls.
//

import AppKit
import CryptoKit
import Foundation

// MARK: - Errors

enum PadError: Error {
    case notAuthenticated
    case noEncryptionKey
    case encryptionNotSetup
    case decryptionFailed
    case apiError(Error)
}

// MARK: - PadService

@MainActor
@Observable
class PadService {
    // State
    private(set) var items: [DecryptedListItem] = []
    private(set) var isLoading = false
    private(set) var error: Error?
    private(set) var hasEncryptionSetup = false

    // Dependencies
    private let api: APIClient
    private let crypto: CryptoService
    private let keychain: KeychainService

    // Encryption key (derived from password)
    private var encryptionKey: SymmetricKey?
    private var encryptionSalt: Data?

    init(api: APIClient, crypto: CryptoService = CryptoService(), keychain: KeychainService = KeychainService()) {
        self.api = api
        self.crypto = crypto
        self.keychain = keychain
    }

    // MARK: - Encryption Setup

    /// Check if encryption is already set up for this user
    func checkEncryptionSetup() async throws -> Bool {
        let state: PadUserState = try await api.get(APIClient.Endpoint.state)
        hasEncryptionSetup = state.encryptionSalt != nil && state.encryptionTest != nil
        return hasEncryptionSetup
    }

    /// Set up encryption with a new password (first time setup)
    func setupEncryption(password: String) async throws {
        let salt = crypto.generateSalt()
        let key = try crypto.deriveKey(password: password, salt: salt)
        let testPayload = try crypto.createTestPayload(using: key)

        // Store locally
        encryptionKey = key
        encryptionSalt = salt

        // Save to keychain
        try keychain.save(salt, for: KeychainService.Key.encryptionSalt)

        // Note: The salt and test payload need to be sent to server via WebSocket
        // For now, we'll store them locally and sync when WebSocket is implemented
        hasEncryptionSetup = true
    }

    /// Unlock with existing password
    func unlock(password: String) async throws -> Bool {
        print("[PadService] unlock() started")
        print("[PadService] Fetching state from API...")

        let state: PadUserState
        do {
            state = try await api.get(APIClient.Endpoint.state)
            print("[PadService] State fetched successfully")
            print("[PadService] encryptionSalt: \(state.encryptionSalt ?? "nil")")
            print("[PadService] encryptionTest: \(state.encryptionTest != nil ? "present" : "nil")")
            print("[PadService] list items count: \(state.list.count)")
        } catch {
            print("[PadService] ERROR fetching state: \(error)")
            throw error
        }

        guard let saltBase64 = state.encryptionSalt,
              let salt = Data(base64Encoded: saltBase64),
              let testPayload = state.encryptionTest else {
            print("[PadService] ERROR: Encryption not setup - missing salt or test payload")
            throw PadError.encryptionNotSetup
        }

        print("[PadService] Salt decoded, length: \(salt.count) bytes")
        print("[PadService] Test payload - ciphertext length: \(testPayload.ciphertext.count), iv: \(testPayload.iv)")

        print("[PadService] Deriving key from password...")
        let key = try crypto.deriveKey(password: password, salt: salt)
        print("[PadService] Key derived successfully")

        // Verify the key by decrypting the test payload
        print("[PadService] Verifying key with test payload...")
        let encPayload = testPayload.toEncryptedPayload()
        print("[PadService] EncryptedPayload - ciphertext: \(encPayload.ciphertext.prefix(20))..., iv: \(encPayload.iv.prefix(20))...")

        if crypto.verifyKey(key, with: encPayload) {
            print("[PadService] Key verification SUCCESS!")
            encryptionKey = key
            encryptionSalt = salt
            try keychain.save(salt, for: KeychainService.Key.encryptionSalt)
            return true
        }

        print("[PadService] Key verification FAILED - incorrect password")
        return false
    }

    /// Lock the service (clear encryption key from memory)
    func lock() {
        encryptionKey = nil
        items = []
    }

    var isUnlocked: Bool {
        encryptionKey != nil
    }

    // MARK: - Data Loading

    /// Fetch and decrypt all list items
    func refresh() async {
        guard let key = encryptionKey else {
            error = PadError.noEncryptionKey
            return
        }

        isLoading = true
        error = nil

        do {
            let state: PadUserState = try await api.get(APIClient.Endpoint.state)
            items = try decryptListItems(state.list, using: key)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    private func decryptListItems(_ encryptedItems: [PadListItem], using key: SymmetricKey) throws -> [DecryptedListItem] {
        var decrypted: [DecryptedListItem] = []

        for item in encryptedItems {
            do {
                let text = try crypto.decrypt(item.encryptedText.toEncryptedPayload(), using: key)
                let files = try decryptFileAttachments(item.files, using: key)
                decrypted.append(DecryptedListItem(
                    id: item.id,
                    text: text,
                    files: files,
                    createdAt: item.createdAt
                ))
            } catch {
                // Skip items that fail to decrypt
                print("Failed to decrypt item \(item.id): \(error)")
            }
        }

        return decrypted
    }

    private func decryptFileAttachments(_ files: [PadFileAttachment], using key: SymmetricKey) throws -> [DecryptedFileAttachment] {
        var decrypted: [DecryptedFileAttachment] = []

        for file in files {
            let name = try crypto.decrypt(file.encryptedName.toEncryptedPayload(), using: key)
            let type = try crypto.decrypt(file.encryptedType.toEncryptedPayload(), using: key)
            decrypted.append(DecryptedFileAttachment(
                id: file.id,
                name: name,
                type: type,
                size: file.size,
                r2Key: file.r2Key
            ))
        }

        return decrypted
    }

    // MARK: - Add Item

    /// Add a new text item to the list
    func addItem(text: String) async throws {
        guard let key = encryptionKey else {
            throw PadError.noEncryptionKey
        }

        let encryptedText = try crypto.encrypt(text, using: key)
        let item = PadListItem(
            id: String(UUID().uuidString.prefix(8).lowercased()),
            encryptedText: encryptedText.toPadEncryptedPayload(),
            files: [],
            createdAt: Int(Date().timeIntervalSince1970 * 1000)
        )

        // Send to API
        let _: AddItemResponse = try await api.post(APIClient.Endpoint.list, body: item)

        // Add to local state on success
        let decryptedItem = DecryptedListItem(
            id: item.id,
            text: text,
            files: [],
            createdAt: item.createdAt
        )
        items.insert(decryptedItem, at: 0)
    }

    // MARK: - Delete Item

    /// Delete an item from the list
    func deleteItem(id: String) async throws {
        // Delete via API
        try await api.delete(APIClient.Endpoint.listItem(id))

        // Remove from local state on success (reassign to trigger observation)
        items = items.filter { $0.id != id }
    }

    // MARK: - File Operations

    /// Download and decrypt a file
    func downloadFile(_ file: DecryptedFileAttachment) async throws -> Data {
        guard let key = encryptionKey else {
            throw PadError.noEncryptionKey
        }

        let encryptedData = try await api.downloadFile(from: APIClient.Endpoint.file(file.r2Key))
        return try crypto.decryptData(encryptedData, using: key)
    }

    /// Encrypt and upload a file
    func uploadFile(name: String, type: String, data: Data) async throws -> PadFileAttachment {
        guard let key = encryptionKey else {
            throw PadError.noEncryptionKey
        }

        // Encrypt the file data
        let encryptedData = try crypto.encryptData(data, using: key)

        // Encrypt the metadata
        let encryptedName = try crypto.encrypt(name, using: key)
        let encryptedType = try crypto.encrypt(type, using: key)

        // Upload
        let response = try await api.uploadFile(encryptedData, to: APIClient.Endpoint.files)

        return PadFileAttachment(
            id: response.id,
            encryptedName: encryptedName.toPadEncryptedPayload(),
            size: response.size,
            encryptedType: encryptedType.toPadEncryptedPayload(),
            r2Key: response.r2Key
        )
    }

    // MARK: - Copy to Clipboard

    /// Copy text to system clipboard
    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
