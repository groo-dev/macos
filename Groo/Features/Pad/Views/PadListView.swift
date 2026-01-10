//
//  PadListView.swift
//  Groo
//
//  Main list view for Pad items.
//

import SwiftUI

struct PadListView: View {
    @Bindable var padService: PadService

    @State private var newItemText = ""
    @State private var showingDeleteConfirmation = false
    @State private var itemToDelete: DecryptedListItem?

    var body: some View {
        VStack(spacing: 0) {
            // Quick add field
            HStack(spacing: Theme.Spacing.sm) {
                TextField("Add text or drop files...", text: $newItemText)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .onSubmit { addItem() }

                if !newItemText.isEmpty {
                    Button(action: addItem) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.accentColor)
                }

                // Refresh button
                LoadingIconButton(
                    icon: "arrow.clockwise",
                    isLoading: padService.isLoading,
                    action: { Task { await padService.refresh() } },
                    help: "Refresh (⌘R)"
                )
                .keyboardShortcut("r", modifiers: .command)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surfaceSubtle)

            Divider()

            // Items list
            if padService.isLoading && padService.items.isEmpty {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                Spacer()
            } else if padService.items.isEmpty {
                EmptyState(
                    icon: "tray",
                    title: "No items yet",
                    subtitle: "Add text or drop files above"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(padService.items) { item in
                            PadItemRow(
                                item: item,
                                onCopy: {
                                    padService.copyToClipboard(item.text)
                                },
                                onDelete: {
                                    itemToDelete = item
                                    showingDeleteConfirmation = true
                                }
                            )

                            if item.id != padService.items.last?.id {
                                ListDivider()
                            }
                        }
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                }
                .refreshable {
                    await padService.refresh()
                }
            }
        }
        .alert("Delete Item?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                itemToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let item = itemToDelete {
                    Task {
                        try? await padService.deleteItem(id: item.id)
                    }
                }
                itemToDelete = nil
            }
        } message: {
            if let item = itemToDelete {
                Text("This will permanently delete \"\(item.text.prefix(50))\"")
            }
        }
        .task {
            if padService.items.isEmpty && padService.isUnlocked {
                await padService.refresh()
            }
        }
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

// MARK: - Preview

#Preview {
    PadListView(padService: PadService(api: APIClient(baseURL: Config.padAPIBaseURL)))
        .frame(width: 350, height: 500)
}
