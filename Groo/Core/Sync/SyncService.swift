//
//  SyncService.swift
//  Groo
//
//  Network-aware sync service for offline-first architecture.
//  Handles push/pull sync with conflict resolution and file caching.
//

import Foundation
import Network

@MainActor
@Observable
class SyncService {
    // MARK: - Types

    enum Status: Equatable {
        case idle
        case syncing
        case offline
        case error(String)
    }

    // MARK: - Properties

    private(set) var status: Status = .idle
    private(set) var isOnline = true
    private(set) var lastSyncAt: Date?
    private(set) var pendingCount: Int = 0

    private let api: APIClient
    private let localStore: LocalStore
    private let conflictResolver = ConflictResolver()
    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "dev.groo.network-monitor")

    // MARK: - Initialization

    init(api: APIClient, localStore: LocalStore) {
        self.api = api
        self.localStore = localStore
        setupNetworkMonitoring()
        updatePendingCount()
    }

    deinit {
        networkMonitor.cancel()
    }

    // MARK: - Main Sync

    /// Perform full sync: push pending operations, pull remote state, download files
    func sync() async {
        guard isOnline else {
            status = .offline
            return
        }

        status = .syncing
        print("[SyncService] Starting sync...")

        do {
            // 1. Push pending operations first
            await pushPendingOperations()

            // 2. Pull latest state from server
            let state: PadUserState = try await api.get(APIClient.Endpoint.state)
            print("[SyncService] Fetched \(state.list.count) items from server")

            // 3. Upsert with conflict resolution
            localStore.upsertPadItems(state.list, using: conflictResolver)

            // 4. Download missing files in background
            await downloadMissingFiles(from: state.list)

            lastSyncAt = Date()
            status = .idle
            updatePendingCount()
            print("[SyncService] Sync completed successfully")
        } catch {
            print("[SyncService] Sync failed: \(error)")
            status = .error(error.localizedDescription)
        }
    }

    /// Sync only metadata (no file downloads) - faster for push notifications
    func syncMetadataOnly() async {
        guard isOnline else {
            status = .offline
            return
        }

        status = .syncing

        do {
            await pushPendingOperations()

            let state: PadUserState = try await api.get(APIClient.Endpoint.state)
            localStore.upsertPadItems(state.list, using: conflictResolver)

            lastSyncAt = Date()
            status = .idle
            updatePendingCount()
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    // MARK: - Push Operations

    private func pushPendingOperations() async {
        let operations = localStore.getAllPendingOperations()
        guard !operations.isEmpty else { return }

        print("[SyncService] Pushing \(operations.count) pending operations...")

        for operation in operations {
            do {
                switch operation.operationType {
                case .create:
                    try await pushCreate(operation)
                case .delete:
                    try await pushDelete(operation)
                }
                localStore.removePendingOperation(operation)
                print("[SyncService] Pushed operation: \(operation.type) for item \(operation.itemId)")
            } catch {
                // Increment retry count, keep in queue
                operation.retryCount += 1
                print("[SyncService] Failed to push operation \(operation.id): \(error)")

                // Remove if too many retries
                if operation.retryCount > 5 {
                    print("[SyncService] Removing operation after too many retries")
                    localStore.removePendingOperation(operation)
                }
            }
        }

        updatePendingCount()
    }

    private func pushCreate(_ operation: PendingOperation) async throws {
        guard let item = operation.getCreatePayload() else {
            throw SyncError.invalidPayload
        }

        let _: AddItemResponse = try await api.post(APIClient.Endpoint.list, body: item)

        // Mark local item as synced
        if let localItem = localStore.getPadItem(id: item.id) {
            localItem.isPendingSync = false
        }
    }

    private func pushDelete(_ operation: PendingOperation) async throws {
        try await api.delete(APIClient.Endpoint.listItem(operation.itemId))
    }

    // MARK: - File Downloads

    private func downloadMissingFiles(from items: [PadListItem]) async {
        for item in items {
            for file in item.files {
                // Skip if already cached
                if localStore.getCachedFile(id: file.id) != nil {
                    continue
                }

                do {
                    // Download from R2
                    let data = try await api.downloadFile(from: APIClient.Endpoint.file(file.r2Key))

                    // Cache locally
                    let cached = LocalFileCache(
                        id: file.id,
                        itemId: item.id,
                        encryptedData: data,
                        fileName: "", // Name is encrypted, will be decrypted on display
                        fileType: "", // Type is encrypted
                        fileSize: file.size
                    )
                    localStore.cacheFile(cached)
                    print("[SyncService] Cached file \(file.id) (\(data.count) bytes)")
                } catch {
                    // Non-fatal: file will be downloaded on-demand
                    print("[SyncService] Failed to cache file \(file.id): \(error)")
                }
            }
        }
    }

    /// Download a specific file on-demand
    func downloadFile(id: String, r2Key: String, itemId: String, size: Int) async throws -> Data {
        // Check cache first
        if let cached = localStore.getCachedFile(id: id) {
            return cached.encryptedData
        }

        // Download from server
        let data = try await api.downloadFile(from: APIClient.Endpoint.file(r2Key))

        // Cache for offline use
        let cached = LocalFileCache(
            id: id,
            itemId: itemId,
            encryptedData: data,
            fileName: "",
            fileType: "",
            fileSize: size
        )
        localStore.cacheFile(cached)

        return data
    }

    // MARK: - Network Monitoring

    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                let wasOffline = !self.isOnline
                self.isOnline = path.status == .satisfied

                print("[SyncService] Network status: \(path.status == .satisfied ? "online" : "offline")")

                // Auto-sync when coming back online
                if wasOffline && self.isOnline {
                    print("[SyncService] Coming back online, triggering sync...")
                    await self.sync()
                }
            }
        }
        networkMonitor.start(queue: monitorQueue)
    }

    // MARK: - Helpers

    private func updatePendingCount() {
        pendingCount = localStore.getPendingOperationsCount()
    }
}

// MARK: - Errors

enum SyncError: Error {
    case invalidPayload
    case networkUnavailable
}
