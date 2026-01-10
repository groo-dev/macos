//
//  EmptyState.swift
//  Groo
//
//  Reusable empty state view with icon, title, and optional subtitle.
//

import SwiftUI

struct EmptyState: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var action: (() -> Void)? = nil
    var actionLabel: String? = nil

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: Theme.Size.iconHero))
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }

            if let action, let actionLabel {
                Button(actionLabel, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, Theme.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Compact Empty State (for menu bar)

struct CompactEmptyState: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.xl)
    }
}

// MARK: - Preview

#Preview("Empty State") {
    EmptyState(
        icon: "tray",
        title: "No items yet",
        subtitle: "Add text or drop files above",
        action: {},
        actionLabel: "Add Item"
    )
    .frame(width: 300, height: 300)
}

#Preview("Compact") {
    CompactEmptyState(text: "No items")
        .frame(width: 280)
}
