//
//  PadMenuView.swift
//  Groo
//
//  Compact view for Pad in the menu bar popover.
//

import SwiftUI

struct PadMenuView: View {
    @Bindable var padService: PadService

    @State private var newItemText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Pad", systemImage: "list.clipboard")
                    .font(.headline)
                Spacer()
                LoadingIconButton(
                    icon: "arrow.clockwise",
                    isLoading: padService.isLoading,
                    action: { Task { await padService.refresh() } },
                    size: .small,
                    help: "Refresh"
                )
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)

            Divider()

            // Quick add
            HStack(spacing: Theme.Spacing.sm) {
                TextField("Add text...", text: $newItemText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .onSubmit { addItem() }

                if !newItemText.isEmpty {
                    IconButton(icon: "plus.circle.fill", action: addItem, size: .small)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)

            Divider()

            // Recent items
            if padService.items.isEmpty {
                CompactEmptyState(text: "No items")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(padService.items.prefix(Theme.Size.maxMenuItems)) { item in
                            MenuItemRow(item: item) {
                                padService.copyToClipboard(item.text)
                            }

                            if item.id != padService.items.prefix(Theme.Size.maxMenuItems).last?.id {
                                ListDivider()
                            }
                        }
                    }
                }
                .frame(maxHeight: Theme.Size.menuItemMaxHeight)
            }
        }
        .frame(width: Theme.Size.menuContentWidth)
    }

    private func addItem() {
        let text = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        Task {
            try? await padService.addItem(text: text)
            newItemText = ""
        }
    }
}

// MARK: - Menu Item Row

private struct MenuItemRow: View {
    let item: DecryptedListItem
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(item.text)
                        .font(.callout)
                        .lineLimit(Theme.LineLimit.menuItemPreview)
                        .foregroundStyle(.primary)

                    if !item.files.isEmpty {
                        HStack(spacing: Theme.Spacing.xxs) {
                            Image(systemName: "paperclip")
                                .font(.caption2)
                            Text("\(item.files.count)")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .opacity(isHovering ? 1 : 0)
            }
            .rowPadding()
            .hoverEffect(isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(Theme.Animation.fastSpring, value: isHovering)
        .accessibilityLabel("Copy: \(item.text)")
    }
}

// MARK: - Preview

#Preview {
    PadMenuView(padService: PadService(api: APIClient(baseURL: Config.padAPIBaseURL)))
        .padding()
}
