//
//  IconButton.swift
//  Groo
//
//  Consistent icon button with proper hit target and hover state.
//

import SwiftUI

struct IconButton: View {
    let icon: String
    let action: () -> Void
    var size: Size = .regular
    var isDestructive: Bool = false
    var help: String? = nil

    enum Size {
        case small
        case regular

        var iconFont: Font {
            switch self {
            case .small: return .caption
            case .regular: return .body
            }
        }

        var frameSize: CGFloat {
            switch self {
            case .small: return 24
            case .regular: return Theme.Size.iconButtonSize
            }
        }
    }

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(size.iconFont)
                .foregroundStyle(isDestructive ? Color.red : .secondary)
                .frame(width: size.frameSize, height: size.frameSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(isHovering ? Theme.Colors.surfaceHover : Color.clear)
        )
        .onHover { isHovering = $0 }
        .help(help ?? "")
        .accessibilityLabel(help ?? icon)
    }
}

// MARK: - Loading Icon Button

struct LoadingIconButton: View {
    let icon: String
    let isLoading: Bool
    let action: () -> Void
    var size: IconButton.Size = .regular
    var help: String? = nil

    var body: some View {
        if isLoading {
            ProgressView()
                .scaleEffect(size == .small ? 0.5 : 0.6)
                .frame(width: size.frameSize, height: size.frameSize)
        } else {
            IconButton(icon: icon, action: action, size: size, help: help)
        }
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 16) {
        IconButton(icon: "arrow.clockwise", action: {}, help: "Refresh")
        IconButton(icon: "trash", action: {}, isDestructive: true, help: "Delete")
        IconButton(icon: "doc.on.doc", action: {}, size: .small, help: "Copy")
        LoadingIconButton(icon: "arrow.clockwise", isLoading: true, action: {})
        LoadingIconButton(icon: "arrow.clockwise", isLoading: false, action: {})
    }
    .padding()
}
