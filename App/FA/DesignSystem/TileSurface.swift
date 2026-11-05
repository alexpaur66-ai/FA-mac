// TileSurface: the quaternary fill of the Overview tiles, the Getting started card, the client figure
// tiles and the Exports cards (design-system.md §8.10), with a 1 pt separator border under Increase
// Contrast, so a tile keeps an edge when the fill alone is too faint.

import AppKit
import SwiftUI

struct TileSurface: ViewModifier {
    var radius: CGFloat = Radius.l

    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background(.quaternary, in: RoundedRectangle(cornerRadius: radius))
            .overlay {
                if contrast == .increased {
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: radius))
    }
}

extension View {
    /// Draws the view on a tile: the quaternary fill, and a separator border under Increase Contrast.
    func tileSurface(radius: CGFloat = Radius.l) -> some View {
        modifier(TileSurface(radius: radius))
    }
}
