//
//  ConflictResolver.swift
//  Groo
//
//  Timestamp-based conflict resolution for offline sync.
//  When same item exists locally and remotely, newer timestamp wins.
//

import Foundation

struct ConflictResolver {
    enum Resolution {
        case keepLocal      // Local is newer
        case useRemote      // Remote is newer
        case merge          // For file attachments: union of both
    }

    /// Compare local and remote items, return resolution
    func resolve(local: LocalPadItem, remote: PadListItem) -> Resolution {
        // If local has pending changes, compare timestamps
        if local.isPendingSync {
            // Local was modified offline - compare updatedAt
            let localTime = local.updatedAt
            let remoteTime = Date(timeIntervalSince1970: Double(remote.createdAt) / 1000)

            if localTime > remoteTime {
                return .keepLocal
            } else {
                return .useRemote
            }
        }

        // No local changes - always use remote
        return .useRemote
    }

    /// Merge file attachments (union of local + remote)
    /// Remote wins for duplicate IDs
    func mergeFiles(local: [PadFileAttachment], remote: [PadFileAttachment]) -> [PadFileAttachment] {
        var merged = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for file in remote {
            merged[file.id] = file  // Remote wins for duplicates
        }
        return Array(merged.values)
    }

    /// Check if an item should trigger a merge (has both local and remote files)
    func shouldMerge(local: LocalPadItem, remote: PadListItem) -> Bool {
        // Only merge if both have files and local is pending sync
        guard local.isPendingSync else { return false }
        return !local.files.isEmpty && !remote.files.isEmpty
    }
}
