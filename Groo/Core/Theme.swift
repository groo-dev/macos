//
//  Theme.swift
//  Groo
//
//  Centralized design tokens following Apple HIG.
//

import SwiftUI

enum Theme {
    // MARK: - Spacing Scale (4pt base)

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Sizes

    enum Size {
        // Popover
        static let popoverWidth: CGFloat = 320
        static let popoverHeight: CGFloat = 420

        // Item rows
        static let rowHeight: CGFloat = 52
        static let selectedBorderWidth: CGFloat = 3

        // Menu
        static let menuContentWidth: CGFloat = 296  // popoverWidth - 24 padding
        static let menuItemMaxHeight: CGFloat = 320
        static let maxMenuItems: Int = 15

        // Window
        static let mainWindowWidth: CGFloat = 800
        static let mainWindowHeight: CGFloat = 600
        static let mainWindowMinWidth: CGFloat = 600
        static let mainWindowMinHeight: CGFloat = 400

        // Sidebar
        static let sidebarWidth: CGFloat = 200
        static let sidebarMinWidth: CGFloat = 180
        static let sidebarMaxWidth: CGFloat = 250

        // Icons
        static let iconXS: CGFloat = 12
        static let iconSM: CGFloat = 16
        static let iconMD: CGFloat = 20
        static let iconLG: CGFloat = 24
        static let iconXL: CGFloat = 32
        static let iconHero: CGFloat = 48

        // Hit targets
        static let minTapTarget: CGFloat = 44
        static let iconButtonSize: CGFloat = 28

        // Status
        static let statusDot: CGFloat = 8
    }

    // MARK: - Corner Radius

    enum Radius {
        static let xs: CGFloat = 2
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
    }

    // MARK: - Animation

    enum Animation {
        static let fast: Double = 0.15
        static let normal: Double = 0.25
        static let slow: Double = 0.35

        static var fastSpring: SwiftUI.Animation {
            .easeInOut(duration: fast)
        }

        static var normalSpring: SwiftUI.Animation {
            .easeInOut(duration: normal)
        }
    }

    // MARK: - Colors (Semantic)

    enum Colors {
        // Backgrounds
        static let surfaceHover = Color.primary.opacity(0.04)
        static let surfacePressed = Color.primary.opacity(0.08)
        static let surfaceSubtle = Color.primary.opacity(0.02)
        static let surfaceSelected = Color.accentColor.opacity(0.1)

        // Status
        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red
        static let info = Color.blue

        // Dividers
        static let divider = Color.primary.opacity(0.08)

        // Selection
        static let selectedBorder = Color.accentColor
    }

    // MARK: - Text Line Limits

    enum LineLimit {
        static let itemPreview: Int = 3
        static let menuItemPreview: Int = 2
        static let singleLine: Int = 1
    }
}

// MARK: - View Extensions

extension View {
    /// Standard horizontal padding for content
    func contentPadding() -> some View {
        padding(.horizontal, Theme.Spacing.md)
    }

    /// Standard list row padding
    func rowPadding() -> some View {
        padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
    }

    /// Hover background effect
    func hoverEffect(_ isHovering: Bool) -> some View {
        background(isHovering ? Theme.Colors.surfaceHover : Color.clear)
    }

    /// Selected row styling with left border
    func selectedStyle(_ isSelected: Bool) -> some View {
        self
            .background(isSelected ? Theme.Colors.surfaceSelected : Color.clear)
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle()
                        .fill(Theme.Colors.selectedBorder)
                        .frame(width: Theme.Size.selectedBorderWidth)
                }
            }
    }

    /// Combined hover and selection effect
    func rowStyle(isHovering: Bool, isSelected: Bool) -> some View {
        self
            .background {
                if isSelected {
                    Theme.Colors.surfaceSelected
                } else if isHovering {
                    Theme.Colors.surfaceHover
                } else {
                    Color.clear
                }
            }
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle()
                        .fill(Theme.Colors.selectedBorder)
                        .frame(width: Theme.Size.selectedBorderWidth)
                }
            }
    }
}
