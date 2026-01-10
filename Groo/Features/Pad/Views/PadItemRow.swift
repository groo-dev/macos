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
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            // Text content
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(item.text)
                    .font(.body)
                    .lineLimit(Theme.LineLimit.itemPreview)
                    .foregroundStyle(.primary)

                // File attachments indicator
                if !item.files.isEmpty {
                    HStack(spacing: Theme.Spacing.xs) {
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
            HStack(spacing: Theme.Spacing.xs) {
                IconButton(
                    icon: "doc.on.doc",
                    action: onCopy,
                    size: .small,
                    help: "Copy to clipboard"
                )

                IconButton(
                    icon: "trash",
                    action: onDelete,
                    size: .small,
                    isDestructive: true,
                    help: "Delete"
                )
            }
            .opacity(isHovering ? 1 : 0)
        }
        .rowPadding()
        .hoverEffect(isHovering)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .onHover { hovering in
            withAnimation(Theme.Animation.fastSpring) {
                isHovering = hovering
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.text). \(item.files.count) files attached.")
        .accessibilityHint("Double-tap to copy")
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

        ListDivider()

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
