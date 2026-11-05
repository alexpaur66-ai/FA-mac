// Design tokens for FA: spacing, corner radii, column widths, text roles and the brand accent.
// Specification: docs/design/design-system.md (§3 typography, §4.2 accent, §5 spacing and layout).
// Everything in this file exists on macOS 14.0, the app's deployment target.

import AppKit
import SwiftUI

// MARK: - Spacing

/// Spacing on a 4-point grid. `xxs` is a half step, for vertical badge padding and tight two-line stacks.
enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    /// The HIG asks for about 12 pt of padding around bezeled elements.
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    /// Content-pane margins.
    static let xl: CGFloat = 20
    /// The HIG asks for about 24 pt of padding around elements without a bezel.
    static let xxl: CGFloat = 24
    static let section: CGFloat = 32
    static let page: CGFloat = 40
}

// MARK: - Corner radii

/// Radii for standalone content shapes only. Windows, sheets, popovers, menus and system glass
/// draw their own corners, so never round them by hand.
enum Radius {
    /// Inline chips, the QR frame.
    static let s: CGFloat = 4
    /// Drop zone, small tiles.
    static let m: CGFloat = 8
    /// Overview tiles, empty-state cards.
    static let l: CGFloat = 12

    /// A concentric radius for a shape inset inside a rounded container.
    /// On macOS 26 and later `ConcentricRectangle` does this; this is the macOS 14 fallback.
    static func concentric(outer: CGFloat, inset: CGFloat) -> CGFloat {
        max(outer - inset, s)
    }
}

// MARK: - Window and column sizes

/// Minimum, ideal and maximum width of one split-view column.
/// Apply with `navigationSplitViewColumnWidth(min:ideal:max:)` or `inspectorColumnWidth(min:ideal:max:)`.
struct ColumnWidth: Equatable, Sendable {
    let min: CGFloat
    let ideal: CGFloat
    let max: CGFloat
}

/// Window and column sizes (design-system.md §5.3). They are starting values, to be tuned on Saša's display.
enum LayoutMetrics {
    static let sidebar = ColumnWidth(min: 180, ideal: 210, max: 280)
    static let content = ColumnWidth(min: 360, ideal: 560, max: 900)
    static let inspector = ColumnWidth(min: 260, ideal: 300, max: 400)

    /// The draft editor's minimum width in the detail column.
    static let detailMinWidth: CGFloat = 520

    static let windowDefault = CGSize(width: 1360, height: 860)
    /// The column minimums (180 + 360 + 520 = 1060) plus slack, so every divider stays visible.
    static let windowMin = CGSize(width: 1080, height: 640)

    /// Below this window width the app closes the inspector: the column minimums plus the inspector minimum.
    static let inspectorBreakpoint: CGFloat = sidebar.min + content.min + detailMinWidth + inspector.min

    /// The ČNB import review sheet is resizable within these sizes.
    static let importReviewMinSize = CGSize(width: 560, height: 400)
    static let importReviewIdealSize = CGSize(width: 640, height: 480)

    /// The command palette (⌘K) has a fixed width.
    static let paletteWidth: CGFloat = 560
}

// MARK: - Typography

/// The text roles of the app, mapped to the macOS text styles (design-system.md §3).
/// macOS has no Dynamic Type; the default size is 13 pt and the smallest is 10 pt.
/// View ▸ Bigger / Smaller scales every content surface through the `textScale` environment value,
/// which `textRole(_:scale:)`, `MoneyText` and `StatusBadge` read.
enum TextRole: CaseIterable, Sendable {
    case screenTitle, sectionTitle, documentNumber, body, label, rowSecondary, caption
    case amount, amountStrong, amountSecondary, total, kpi, legalNote, badge

    private struct Spec {
        let style: Font
        /// The HIG point size and line height of the text style at 100 %.
        let size: CGFloat
        let lineHeight: CGFloat
        let weight: Font.Weight
        var tabular = false
        var secondary = false
    }

    private var spec: Spec {
        switch self {
        case .screenTitle:
            return Spec(style: .title2.bold(), size: 17, lineHeight: 22, weight: .bold)
        case .sectionTitle:
            return Spec(style: .headline, size: 13, lineHeight: 16, weight: .bold)
        case .documentNumber:
            return Spec(style: .title3.weight(.semibold), size: 15, lineHeight: 20, weight: .semibold, tabular: true)
        case .body, .label:
            return Spec(style: .body, size: 13, lineHeight: 16, weight: .regular)
        case .rowSecondary:
            return Spec(style: .subheadline, size: 11, lineHeight: 14, weight: .regular, secondary: true)
        case .caption:
            return Spec(style: .caption, size: 10, lineHeight: 13, weight: .regular, secondary: true)
        case .amount:
            return Spec(style: .body, size: 13, lineHeight: 16, weight: .regular, tabular: true)
        case .amountStrong:
            return Spec(style: .body.weight(.semibold), size: 13, lineHeight: 16, weight: .semibold, tabular: true)
        case .amountSecondary:
            // The CZK line under a foreign-currency amount.
            return Spec(style: .subheadline, size: 11, lineHeight: 14, weight: .regular, tabular: true, secondary: true)
        case .total:
            return Spec(style: .title3.weight(.semibold), size: 15, lineHeight: 20, weight: .semibold, tabular: true)
        case .kpi:
            return Spec(style: .largeTitle.bold(), size: 26, lineHeight: 32, weight: .bold, tabular: true)
        case .legalNote:
            // Legal and tax wording is never drawn in the secondary colour.
            return Spec(style: .callout, size: 12, lineHeight: 15, weight: .regular)
        case .badge:
            return Spec(style: .callout.weight(.medium), size: 12, lineHeight: 15, weight: .medium)
        }
    }

    /// The system text style for the role, with tabular digits where amounts must line up.
    var font: Font {
        spec.tabular ? spec.style.monospacedDigit() : spec.style
    }

    var isSecondary: Bool { spec.secondary }

    /// The HIG line height at 100 %, used to size table rows when the content is scaled.
    var lineHeight: CGFloat { spec.lineHeight }

    /// The role at an app-wide scale (1 to 2), for View ▸ Bigger / Smaller.
    func scaledFont(_ scale: CGFloat) -> Font {
        let font = Font.system(size: spec.size * scale, weight: spec.weight)
        return spec.tabular ? font.monospacedDigit() : font
    }

    /// A table row height for a scaled role: the scaled line height plus vertical padding.
    func scaledRowHeight(_ scale: CGFloat, padding: CGFloat = Spacing.s) -> CGFloat {
        lineHeight * scale + padding
    }
}

private struct TextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    /// The app-wide View ▸ Bigger / Smaller scale, from 1 to 2. The scene root sets it once;
    /// 1 uses the system text styles themselves.
    var textScale: CGFloat {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
}

struct TextRoleModifier: ViewModifier {
    let role: TextRole
    /// nil follows the app-wide `textScale`.
    var scale: CGFloat?

    @Environment(\.textScale) private var environmentScale

    func body(content: Content) -> some View {
        let scale = self.scale ?? environmentScale
        return content
            .font(scale == 1 ? role.font : role.scaledFont(scale))
            // Hierarchical styles follow selected rows and inactive windows.
            .foregroundStyle(role.isSecondary ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.primary)
    }
}

extension View {
    /// Applies a text role's font and colour, at the app-wide scale unless `scale` is given.
    func textRole(_ role: TextRole, scale: CGFloat? = nil) -> some View {
        modifier(TextRoleModifier(role: role, scale: scale))
    }
}

// MARK: - Brand accent

/// The app accent "Inkoust" (ink indigo), design-system.md §4.2.
///
/// It is a fill under white labels, such as the prominent Issue button. Links and accent-coloured
/// text use `NSColor.linkColor`, never this colour. White text contrast: 7.04:1 light, 4.60:1 dark,
/// 9.84:1 and 5.36:1 with Increase Contrast.
enum Brand {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        let match = appearance.bestMatch(from: [
            .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
        ]) ?? .aqua
        switch match {
        case .darkAqua:
            return Brand.srgb(0x6A5FF5)
        case .accessibilityHighContrastAqua:
            return Brand.srgb(0x372BB0)
        case .accessibilityHighContrastDarkAqua:
            return Brand.srgb(0x5F54E8)
        default:
            return Brand.srgb(0x4B3FD6)
        }
    })

    private static func srgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
