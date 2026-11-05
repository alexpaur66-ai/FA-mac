// FloatingSurface: the one custom glass element, the v0.2 Undo toast for bulk actions
// (design-system.md §6 and §8.17). v0.1 uses an opaque inline result line instead. Never time-boxed.
//
// Liquid Glass (`glassEffect(_:in:)`) is macOS 26.0 and needs the macOS 26 SDK (Swift 6.2 or later).
// The deployment target is macOS 14.0, so older systems, older compilers and Reduce Transparency
// all get the same opaque capsule.

import AppKit
import SwiftUI

struct FloatingSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            opaque(content)
        } else {
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                content.glassEffect(.regular, in: Capsule())
            } else {
                opaque(content)
            }
            #else
            opaque(content)
            #endif
        }
    }

    private func opaque(_ content: Content) -> some View {
        content
            .background(Color(nsColor: .windowBackgroundColor), in: Capsule())
            .overlay {
                Capsule().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            }
    }
}

extension View {
    /// Draws the view on the floating surface: Liquid Glass where available, otherwise opaque.
    func floatingSurface() -> some View {
        modifier(FloatingSurface())
    }
}
