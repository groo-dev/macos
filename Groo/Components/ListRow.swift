//
//  ListRow.swift
//  Groo
//
//  Standardized list row with hover state and consistent styling.
//

import SwiftUI

struct ListRow<Content: View, Actions: View>: View {
    let content: () -> Content
    let actions: () -> Actions
    var onTap: (() -> Void)? = nil

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            content()
            Spacer(minLength: 0)
            actions()
                .opacity(isHovering ? 1 : 0)
        }
        .rowPadding()
        .hoverEffect(isHovering)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            onTap?()
        }
        .animation(Theme.Animation.fastSpring, value: isHovering)
    }
}

// MARK: - Simple tap row (for menu items)

struct TapRow<Content: View>: View {
    let action: () -> Void
    let content: () -> Content

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                content()
                Spacer(minLength: 0)
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
    }
}

// MARK: - Divider with consistent inset

struct ListDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, Theme.Spacing.md)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        ListRow {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Sample item text")
                    .font(.body)
                Text("12:34 PM")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        } actions: {
            HStack(spacing: Theme.Spacing.xs) {
                IconButton(icon: "doc.on.doc", action: {}, size: .small, help: "Copy")
                IconButton(icon: "trash", action: {}, size: .small, isDestructive: true, help: "Delete")
            }
        }

        ListDivider()

        TapRow(action: {}) {
            Text("Tappable row for menu")
                .font(.callout)
        }
    }
    .frame(width: 300)
}
