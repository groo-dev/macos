//
//  LocalPadItem.swift
//  Groo
//
//  SwiftData model for locally cached Pad items.
//  Stores encrypted data (same format as server) for security.
//  Decryption happens on-demand in memory.
//

import Foundation
import SwiftData

@Model
final class LocalPadItem {
    @Attribute(.unique) var id: String

    /// Encrypted text payload as JSON string (contains ciphertext, iv, version)
    var encryptedTextJSON: String

    /// File attachments with encrypted metadata as JSON
    var filesJSON: Data?

    var createdAt: Date
    var updatedAt: Date
    var syncedAt: Date

    /// True if this item was created/modified offline and hasn't been synced yet
    var isPendingSync: Bool

    init(
        id: String,
        encryptedTextJSON: String,
        createdAt: Date,
        updatedAt: Date? = nil,
        syncedAt: Date = Date(),
        filesJSON: Data? = nil,
        isPendingSync: Bool = false
    ) {
        self.id = id
        self.encryptedTextJSON = encryptedTextJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.syncedAt = syncedAt
        self.filesJSON = filesJSON
        self.isPendingSync = isPendingSync
    }

    /// Get encrypted text payload
    var encryptedText: PadEncryptedPayload? {
        guard let data = encryptedTextJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PadEncryptedPayload.self, from: data)
    }

    /// Get encrypted file attachments
    var files: [PadFileAttachment] {
        get {
            guard let data = filesJSON else { return [] }
            return (try? JSONDecoder().decode([PadFileAttachment].self, from: data)) ?? []
        }
        set {
            filesJSON = try? JSONEncoder().encode(newValue)
        }
    }
}

// MARK: - Conversion from API Model

extension LocalPadItem {
    /// Create from API model (PadListItem) - stores encrypted data directly
    convenience init(from apiItem: PadListItem) {
        let encryptedJSON = (try? JSONEncoder().encode(apiItem.encryptedText))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        self.init(
            id: apiItem.id,
            encryptedTextJSON: encryptedJSON,
            createdAt: Date(timeIntervalSince1970: Double(apiItem.createdAt) / 1000),
            filesJSON: try? JSONEncoder().encode(apiItem.files),
            isPendingSync: false
        )
    }

    /// Convert back to API model for pending operations
    func toPadListItem() -> PadListItem? {
        guard let encryptedText = encryptedText else { return nil }
        return PadListItem(
            id: id,
            encryptedText: encryptedText,
            files: files,
            createdAt: Int(createdAt.timeIntervalSince1970 * 1000)
        )
    }
}
