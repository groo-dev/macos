//
//  LocalStore.swift
//  Groo
//
//  SwiftData container stored in App Group for extension access.
//  Manages local cache for offline-first sync.
//

import Foundation
import SwiftData

@MainActor
final class LocalStore {
    static let shared = LocalStore()

    let container: ModelContainer

    private init() {
        let schema = Schema([
            LocalPadItem.self,
            PendingOperation.self,
            LocalFileCache.self,
        ])

        // Configure for App Group storage
        let config = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier(Config.appGroupIdentifier)
        )

        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var context: ModelContext {
        container.mainContext
    }

    // MARK: - Pad Items

    func getAllPadItems() -> [LocalPadItem] {
        let descriptor = FetchDescriptor<LocalPadItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func getPadItem(id: String) -> LocalPadItem? {
        let descriptor = FetchDescriptor<LocalPadItem>(
            predicate: #Predicate { $0.id == id }
        )
        return try? context.fetch(descriptor).first
    }

    func savePadItem(_ item: LocalPadItem) {
        context.insert(item)
        try? context.save()
    }

    func deletePadItem(id: String) {
        if let item = getPadItem(id: id) {
            // Also delete cached files for this item
            deleteCachedFilesForItem(itemId: id)
            context.delete(item)
            try? context.save()
        }
    }

    /// Upsert encrypted items from API with conflict resolution
    func upsertPadItems(_ items: [PadListItem], using resolver: ConflictResolver) {
        // Build a map of remote items by ID
        let remoteMap = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let remoteIds = Set(remoteMap.keys)

        // Get existing local items
        let localItems = getAllPadItems()
        let localMap = Dictionary(uniqueKeysWithValues: localItems.map { ($0.id, $0) })
        let localIds = Set(localMap.keys)

        // Items to delete (in local but not in remote, and not pending sync)
        let toDelete = localIds.subtracting(remoteIds)
        for id in toDelete {
            if let item = localMap[id], !item.isPendingSync {
                // Also delete cached files
                deleteCachedFilesForItem(itemId: id)
                context.delete(item)
            }
        }

        // Items to add (in remote but not in local)
        let toAdd = remoteIds.subtracting(localIds)
        for id in toAdd {
            if let remoteItem = remoteMap[id] {
                context.insert(LocalPadItem(from: remoteItem))
            }
        }

        // Items to potentially update (in both local and remote)
        let toCheck = localIds.intersection(remoteIds)
        for id in toCheck {
            guard let local = localMap[id], let remote = remoteMap[id] else { continue }

            let resolution = resolver.resolve(local: local, remote: remote)
            switch resolution {
            case .keepLocal:
                // Local is newer, don't update
                break
            case .useRemote:
                // Remote is newer, update local
                updateLocalItem(local, from: remote)
            case .merge:
                // Merge file attachments
                let mergedFiles = resolver.mergeFiles(
                    local: local.files,
                    remote: remote.files
                )
                local.files = mergedFiles
                local.syncedAt = Date()
            }
        }

        try? context.save()
    }

    private func updateLocalItem(_ local: LocalPadItem, from remote: PadListItem) {
        let encryptedJSON = (try? JSONEncoder().encode(remote.encryptedText))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        local.encryptedTextJSON = encryptedJSON
        local.filesJSON = try? JSONEncoder().encode(remote.files)
        local.updatedAt = Date(timeIntervalSince1970: Double(remote.createdAt) / 1000)
        local.syncedAt = Date()
        local.isPendingSync = false
    }

    func clearAllPadItems() {
        let items = getAllPadItems()
        for item in items {
            context.delete(item)
        }
        // Also clear file cache
        clearFileCache()
        try? context.save()
    }

    // MARK: - Pending Operations

    func getAllPendingOperations() -> [PendingOperation] {
        let descriptor = FetchDescriptor<PendingOperation>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func getPendingOperationsCount() -> Int {
        let descriptor = FetchDescriptor<PendingOperation>()
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    func addPendingOperation(_ operation: PendingOperation) {
        context.insert(operation)
        try? context.save()
    }

    func removePendingOperation(_ operation: PendingOperation) {
        context.delete(operation)
        try? context.save()
    }

    func removePendingOperation(id: String) {
        let descriptor = FetchDescriptor<PendingOperation>(
            predicate: #Predicate { $0.id == id }
        )
        if let operation = try? context.fetch(descriptor).first {
            context.delete(operation)
            try? context.save()
        }
    }

    func clearPendingOperations() {
        let operations = getAllPendingOperations()
        for op in operations {
            context.delete(op)
        }
        try? context.save()
    }

    // MARK: - File Cache

    func getCachedFile(id: String) -> LocalFileCache? {
        let descriptor = FetchDescriptor<LocalFileCache>(
            predicate: #Predicate { $0.id == id }
        )
        return try? context.fetch(descriptor).first
    }

    func getCachedFilesForItem(itemId: String) -> [LocalFileCache] {
        let descriptor = FetchDescriptor<LocalFileCache>(
            predicate: #Predicate { $0.itemId == itemId }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func cacheFile(_ file: LocalFileCache) {
        // Delete existing if present (update)
        if let existing = getCachedFile(id: file.id) {
            context.delete(existing)
        }
        context.insert(file)
        try? context.save()
    }

    func deleteCachedFile(id: String) {
        if let file = getCachedFile(id: id) {
            context.delete(file)
            try? context.save()
        }
    }

    func deleteCachedFilesForItem(itemId: String) {
        let files = getCachedFilesForItem(itemId: itemId)
        for file in files {
            context.delete(file)
        }
        try? context.save()
    }

    func clearFileCache() {
        let descriptor = FetchDescriptor<LocalFileCache>()
        if let files = try? context.fetch(descriptor) {
            for file in files {
                context.delete(file)
            }
            try? context.save()
        }
    }

    /// Get total size of cached files in bytes
    func getFileCacheSize() -> Int64 {
        let descriptor = FetchDescriptor<LocalFileCache>()
        guard let files = try? context.fetch(descriptor) else { return 0 }
        return files.reduce(0) { $0 + Int64($1.encryptedData.count) }
    }

    /// Get count of cached files
    func getFileCacheCount() -> Int {
        let descriptor = FetchDescriptor<LocalFileCache>()
        return (try? context.fetchCount(descriptor)) ?? 0
    }
}
