// StatusBadge: symbol + word + optional detail in a tinted capsule (design-system.md §8.1).

import SwiftUI

struct StatusBadge: View {
    let style: StatusStyle
    /// Already localized and formatted by the caller, for example "+12 days · 1 000,00 € left".
    var detail: String?
    /// Symbol only, whatever the width. The word and detail move to the tooltip and VoiceOver.
    /// Without it the badge drops the detail, then the word, when its column is too narrow.
    var compact = false

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.locale) private var locale
    @Environment(\.textScale) private var textScale

    init(_ label: DocumentStateLabel, detail: String? = nil, compact: Bool = false) {
        self.init(style: label.style, detail: detail, compact: compact)
    }

    init(_ inputs: DocumentStateInputs, detail: String? = nil, compact: Bool = false) {
        self.init(inputs.label, detail: detail, compact: compact)
    }

    init(_ state: BankMatchState, detail: String? = nil, compact: Bool = false) {
        self.init(style: state.style, detail: detail, compact: compact)
    }

    init(style: StatusStyle, detail: String? = nil, compact: Bool = false) {
        self.style = style
        self.detail = detail
        self.compact = compact
    }

    /// The word in the view's locale, so the visible word, the tooltip and VoiceOver always agree.
    private var word: String {
        var resource = style.label
        resource.locale = locale
        return String(localized: resource)
    }

    var body: some View {
        let word = self.word
        let spoken = [word, detail].compactMap { $0 }.joined(separator: ", ")

        Group {
            if compact {
                capsule(word: nil, detail: nil)
            } else {
                // A resizable Table column can't tell the badge its width, so the badge falls back by itself:
                // full, then word only, then symbol only. The tooltip and VoiceOver keep the full text.
                ViewThatFits(in: .horizontal) {
                    capsule(word: word, detail: detail)
                    capsule(word: word, detail: nil)
                    capsule(word: nil, detail: nil)
                }
            }
        }
        .help(Text(verbatim: spoken))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spoken))
    }

    private func capsule(word: String?, detail: String?) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: style.symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                    BadgeToneStyle(tint: style.tone.tint, opacity: 1,
                                   onSelection: AnyShapeStyle(HierarchicalShapeStyle.primary)))
            if let word {
                // The word stays in the label colour for contrast; the symbol and capsule carry the tone.
                Text(verbatim: word)
            }
            if let detail {
                Text(verbatim: detail)
                    .foregroundStyle(HierarchicalShapeStyle.secondary)
            }
        }
        .font(textScale == 1 ? TextRole.badge.font : TextRole.badge.scaledFont(textScale))
        .padding(.horizontal, word == nil ? Spacing.xs : Spacing.s)
        .padding(.vertical, Spacing.xxs)
        .background(BadgeToneStyle(tint: style.tone.tint, opacity: 0.14), in: Capsule())
        .overlay {
            if contrast == .increased {
                Capsule().strokeBorder(BadgeToneStyle(tint: style.tone.tint, opacity: 1), lineWidth: 1)
            }
        }
        .fixedSize()
    }
}

/// The badge tint, resolved where it is drawn. On a selected row of a focused list or table
/// (increased background prominence, an accent fill) it gives `onSelection` instead, so the badge
/// goes monochrome. Apple recommends reading `backgroundProminence` in a custom `ShapeStyle`,
/// because a cell's top-level view may not see the row's value.
private struct BadgeToneStyle: ShapeStyle {
    let tint: Color
    let opacity: Double
    var onSelection = AnyShapeStyle(Color.clear)

    func resolve(in environment: EnvironmentValues) -> AnyShapeStyle {
        environment.backgroundProminence == .increased ? onSelection : AnyShapeStyle(tint.opacity(opacity))
    }
}
