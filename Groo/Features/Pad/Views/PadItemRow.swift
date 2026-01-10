//
//  PadItemRow.swift
//  Groo
//
//  Single item row for the Pad list.
//

import SwiftUI

struct PadItemRow: View {
    let item: DecryptedListItem
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(item.text)
                    .font(.body)
                    .lineLimit(3)
                    .foregroundStyle(.primary)

                // File attachments indicator
                if !item.files.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "paperclip")
                            .font(.caption)
                        Text("\(item.files.count) file\(item.files.count == 1 ? "" : "s")")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }

                // Timestamp
                Text(item.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Action buttons (visible on hover)
            if isHovering {
                HStack(spacing: 8) {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .font(.body)
                    }
                    .buttonStyle(.borderless)
                    .help("Copy to clipboard")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.body)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .help("Delete")
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isHovering ? Color.primary.opacity(0.05) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        PadItemRow(
            item: DecryptedListItem(
                id: "1",
                text: "This is a sample text item that might be a bit longer",
                files: [],
                createdAt: Int(Date().timeIntervalSince1970 * 1000) - 3600000
            ),
            onCopy: {},
            onDelete: {}
        )

        Divider()

        PadItemRow(
            item: DecryptedListItem(
                id: "2",
                text: "Another item with files",
                files: [
                    DecryptedFileAttachment(id: "f1", name: "document.pdf", type: "application/pdf", size: 1024, r2Key: "key")
                ],
                createdAt: Int(Date().timeIntervalSince1970 * 1000)
            ),
            onCopy: {},
            onDelete: {}
        )
    }
    .frame(width: 300)
    .padding()
}
