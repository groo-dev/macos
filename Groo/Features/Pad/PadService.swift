//
//  PadService.swift
//  Groo
//
//  Pad feature service - handles state, encryption, and API calls.
//  Uses local cache for offline-first architecture.
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
    case offlineNoCache  // First unlock attempt while offline, no cached credentials
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
    private let localStore: LocalStore
    private(set) var syncService: SyncService!

    // Encryption key (derived from password)
    private var encryptionKey: SymmetricKey?
    private var encryptionSalt: Data?

    init(
        api: APIClient,
        crypto: CryptoService = CryptoService(),
        keychain: KeychainService = KeychainService(),
        localStore: LocalStore = LocalStore.shared
    ) {
        self.api = api
        self.crypto = crypto
        self.keychain = keychain
        self.localStore = localStore
        self.syncService = SyncService(api: api, localStore: localStore)
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
    /// Uses cached credentials when available, falls back to remote when needed
    func unlock(password: String) async throws -> Bool {
        // Check if we have cached credentials
        let hasCachedCredentials = keychain.exists(for: KeychainService.Key.encryptionSalt)
            && keychain.exists(for: KeychainService.Key.encryptionTest)

        if hasCachedCredentials {
            // Try local verification first
            let salt = try keychain.load(for: KeychainService.Key.encryptionSalt)
            let testJSON = try keychain.load(for: KeychainService.Key.encryptionTest)
            let testPayload = try JSONDecoder().decode(PadEncryptedPayload.self, from: testJSON)

            let key = try crypto.deriveKey(password: password, salt: salt)

            if crypto.verifyKey(key, with: testPayload.toEncryptedPayload()) {
                // Local verification succeeded
                encryptionKey = key
                encryptionSalt = salt
                return true
            }

            // Local verification failed - try remote if online
            if syncService.isOnline {
                return try await unlockWithRemote(password: password)
            }

            // Offline and local failed - wrong password
            return false

        } else {
            // No cached credentials - must be online for first unlock
            if !syncService.isOnline {
                throw PadError.offlineNoCache
            }

            return try await unlockWithRemote(password: password)
        }
    }

    /// Fetch credentials from API, verify, and cache for offline use
    private func unlockWithRemote(password: String) async throws -> Bool {
        let state: PadUserState = try await api.get(APIClient.Endpoint.state)

        guard let saltBase64 = state.encryptionSalt,
              let salt = Data(base64Encoded: saltBase64),
              let testPayload = state.encryptionTest else {
            throw PadError.encryptionNotSetup
        }

        let key = try crypto.deriveKey(password: password, salt: salt)

        if crypto.verifyKey(key, with: testPayload.toEncryptedPayload()) {
            // Cache credentials for future offline use
            try keychain.save(salt, for: KeychainService.Key.encryptionSalt)
            let testJSON = try JSONEncoder().encode(testPayload)
            try keychain.save(testJSON, for: KeychainService.Key.encryptionTest)

            encryptionKey = key
            encryptionSalt = salt
            return true
        }

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

    /// Sync from server (if online) and load from local cache
    func refresh() async {
        guard let key = encryptionKey else {
            error = PadError.noEncryptionKey
            return
        }

        isLoading = true
        error = nil

        // Sync from server first (if online)
        await syncService.sync()

        // Load from local cache
        do {
            try loadItemsFromCache(using: key)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    /// Load items from local cache without syncing (for when coming back online)
    func loadFromCache() {
        guard let key = encryptionKey else { return }
        do {
            try loadItemsFromCache(using: key)
        } catch {
            self.error = error
        }
    }

    /// Decrypt items from local cache
    private func loadItemsFromCache(using key: SymmetricKey) throws {
        let localItems = localStore.getAllPadItems()
        items = try decryptLocalItems(localItems, using: key)
    }

    private func decryptLocalItems(_ localItems: [LocalPadItem], using key: SymmetricKey) throws -> [DecryptedListItem] {
        var decrypted: [DecryptedListItem] = []

        for item in localItems {
            guard let encryptedText = item.encryptedText else { continue }

            do {
                let text = try crypto.decrypt(encryptedText.toEncryptedPayload(), using: key)
                let files = try decryptFileAttachments(item.files, using: key)

                var decryptedItem = DecryptedListItem(
                    id: item.id,
                    text: text,
                    files: files,
                    createdAt: Int(item.createdAt.timeIntervalSince1970 * 1000)
                )
                // Mark as pending if not synced
                decryptedItem.isPendingSync = item.isPendingSync
                decrypted.append(decryptedItem)
            } catch {
                print("Failed to decrypt item \(item.id): \(error)")
            }
        }

        return decrypted
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

    /// Add a new text item to the list (offline-first)
    func addItem(text: String) async throws {
        guard let key = encryptionKey else {
            throw PadError.noEncryptionKey
        }

        let encryptedText = try crypto.encrypt(text, using: key)
        let itemId = String(UUID().uuidString.prefix(8).lowercased())
        let createdAt = Date()
        let item = PadListItem(
            id: itemId,
            encryptedText: encryptedText.toPadEncryptedPayload(),
            files: [],
            createdAt: Int(createdAt.timeIntervalSince1970 * 1000)
        )

        // Save to local cache first (optimistic)
        let localItem = LocalPadItem(from: item)
        localItem.isPendingSync = true
        localStore.savePadItem(localItem)

        // Queue for sync
        localStore.addPendingOperation(PendingOperation.createItem(item))

        // Update UI immediately
        let decryptedItem = DecryptedListItem(
            id: item.id,
            text: text,
            files: [],
            createdAt: item.createdAt,
            isPendingSync: true
        )
        items.insert(decryptedItem, at: 0)

        // Try to sync immediately if online
        if syncService.isOnline {
            await syncService.sync()
            // Reload from cache to get updated sync status
            loadFromCache()
        }
    }

    /// Add a new item with file attachments (offline-first)
    func addItemWithFiles(text: String = "", files: [PadFileAttachment]) async throws {
        guard let key = encryptionKey else {
            throw PadError.noEncryptionKey
        }

        let encryptedText = try crypto.encrypt(text, using: key)
        let itemId = String(UUID().uuidString.prefix(8).lowercased())
        let createdAt = Date()
        let item = PadListItem(
            id: itemId,
            encryptedText: encryptedText.toPadEncryptedPayload(),
            files: files,
            createdAt: Int(createdAt.timeIntervalSince1970 * 1000)
        )

        // Save to local cache first
        let localItem = LocalPadItem(from: item)
        localItem.isPendingSync = true
        localStore.savePadItem(localItem)

        // Queue for sync
        localStore.addPendingOperation(PendingOperation.createItem(item))

        // Decrypt files for local state
        var decryptedFiles: [DecryptedFileAttachment] = []
        for file in files {
            let name = try crypto.decrypt(file.encryptedName.toEncryptedPayload(), using: key)
            let type = try crypto.decrypt(file.encryptedType.toEncryptedPayload(), using: key)
            decryptedFiles.append(DecryptedFileAttachment(
                id: file.id,
                name: name,
                type: type,
                size: file.size,
                r2Key: file.r2Key
            ))
        }

        let decryptedItem = DecryptedListItem(
            id: item.id,
            text: text,
            files: decryptedFiles,
            createdAt: item.createdAt,
            isPendingSync: true
        )
        items.insert(decryptedItem, at: 0)

        // Try to sync immediately if online
        if syncService.isOnline {
            await syncService.sync()
            loadFromCache()
        }
    }

    // MARK: - Delete Item

    /// Delete an item from the list (offline-first)
    func deleteItem(id: String) async throws {
        // Delete from local cache first
        localStore.deletePadItem(id: id)

        // Queue for sync
        localStore.addPendingOperation(PendingOperation.deleteItem(id: id))

        // Remove from UI immediately
        items = items.filter { $0.id != id }

        // Try to sync immediately if online
        if syncService.isOnline {
            await syncService.sync()
        }
    }

    // MARK: - File Operations

    /// Download and decrypt a file (uses cache if available)
    func downloadFile(_ file: DecryptedFileAttachment, itemId: String? = nil) async throws -> Data {
        guard let key = encryptionKey else {
            throw PadError.noEncryptionKey
        }

        // Check local cache first
        if let cached = localStore.getCachedFile(id: file.id) {
            print("[PadService] Using cached file \(file.id)")
            return try crypto.decryptData(cached.encryptedData, using: key)
        }

        // Download from server
        let encryptedData = try await api.downloadFile(from: APIClient.Endpoint.file(file.r2Key))

        // Cache for offline use (if we know the item ID)
        if let itemId = itemId {
            let cached = LocalFileCache(
                id: file.id,
                itemId: itemId,
                encryptedData: encryptedData,
                fileName: file.name,
                fileType: file.type,
                fileSize: file.size
            )
            localStore.cacheFile(cached)
        }

        return try crypto.decryptData(encryptedData, using: key)
    }

    /// Check if a file is cached locally
    func isFileCached(id: String) -> Bool {
        localStore.getCachedFile(id: id) != nil
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

    // MARK: - Cache Management

    /// Clear all local data (for logout)
    func clearLocalData() {
        localStore.clearAllPadItems()
        localStore.clearPendingOperations()
        localStore.clearFileCache()
        items = []
    }

    /// Get file cache statistics
    func getFileCacheStats() -> (count: Int, sizeBytes: Int64) {
        (localStore.getFileCacheCount(), localStore.getFileCacheSize())
    }

    /// Get pending operations count
    var pendingOperationsCount: Int {
        syncService.pendingCount
    }
}
