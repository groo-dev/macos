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

    private let maxItems = 10

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Pad", systemImage: "list.clipboard")
                    .font(.headline)
                Spacer()
                if padService.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Quick add
            HStack(spacing: 8) {
                TextField("Add text...", text: $newItemText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .onSubmit {
                        addItem()
                    }

                if !newItemText.isEmpty {
                    Button(action: addItem) {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Recent items
            if padService.items.isEmpty {
                VStack(spacing: 4) {
                    Text("No items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(padService.items.prefix(maxItems)) { item in
                            MenuItemRow(item: item) {
                                padService.copyToClipboard(item.text)
                            }

                            if item.id != padService.items.prefix(maxItems).last?.id {
                                Divider()
                                    .padding(.horizontal, 8)
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 280)
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.text)
                        .font(.callout)
                        .lineLimit(2)
                        .foregroundStyle(.primary)

                    if !item.files.isEmpty {
                        HStack(spacing: 2) {
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
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isHovering ? Color.primary.opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Preview

#Preview {
    let mockService = PadService(
        api: APIClient(baseURL: URL(string: "https://pad.groo.dev")!)
    )

    return PadMenuView(padService: mockService)
        .padding()
}
