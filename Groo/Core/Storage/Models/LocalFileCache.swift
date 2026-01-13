//
//  LocalFileCache.swift
//  Groo
//
//  SwiftData model for locally cached file data.
//  Files are stored encrypted (same format as server).
//  Decryption happens on-demand in memory.
//

import Foundation
import SwiftData

@Model
final class LocalFileCache {
    /// File attachment ID (from PadFileAttachment)
    @Attribute(.unique) var id: String

    /// Parent list item ID
    var itemId: String

    /// Encrypted file contents (raw Data, not base64)
    @Attribute(.externalStorage) var encryptedData: Data

    /// Original file name (encrypted on server, but we cache the decrypted name for display)
    var fileName: String

    /// File MIME type
    var fileType: String

    /// File size in bytes (encrypted size)
    var fileSize: Int

    /// When this file was downloaded to cache
    var downloadedAt: Date

    init(
        id: String,
        itemId: String,
        encryptedData: Data,
        fileName: String,
        fileType: String,
        fileSize: Int
    ) {
        self.id = id
        self.itemId = itemId
        self.encryptedData = encryptedData
        self.fileName = fileName
        self.fileType = fileType
        self.fileSize = fileSize
        self.downloadedAt = Date()
    }
}
