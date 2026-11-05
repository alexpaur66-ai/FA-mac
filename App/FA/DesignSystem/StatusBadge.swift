// StatusBadge: symbol + word + optional detail in a tinted capsule (design-system.md §8.1).

import SwiftUI

struct StatusBadge: View {
    let style: StatusStyle
    /// Already localized and formatted by the caller, for example "+12 dní · zbývá 1 000,00 €".
    var detail: String?
    /// Symbol only, for narrow columns. The word and detail move to the tooltip and VoiceOver.
    var compact = false

    @Environment(\.backgroundProminence) private var prominence
    @Environment(\.colorSchemeContrast) private var contrast

    init(_ label: DocumentStateLabel, detail: String? = nil, compact: Bool = false) {
        self.init(style: label.style, detail: detail, compact: compact)
    }

    init(_ inputs: DocumentStateInputs, detail: String? = nil, compact: Bool = false) {
        self.init(inputs.label, detail: detail, compact: compact)
    }

    init(_ state: BankMatchState, detail: String? = nil, compact: Bool = false) {
        self.init(style: state.style, detail: detail, compact: compact)
    }

    private init(style: StatusStyle, detail: String?, compact: Bool) {
        self.style = style
        self.detail = detail
        self.compact = compact
    }

    var body: some View {
        // Selected rows in a focused list have an accent fill, so the badge drops its tint there.
        let onSelection = prominence == .increased
        let spoken = [String(localized: style.label), detail].compactMap { $0 }.joined(separator: ", ")

        HStack(spacing: Spacing.xs) {
            Image(systemName: style.symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                    onSelection ? AnyShapeStyle(HierarchicalShapeStyle.primary) : AnyShapeStyle(style.tone.tint))
            if !compact {
                // The word stays in the label colour for contrast; the symbol and capsule carry the tone.
                Text(style.label)
                if let detail {
                    Text(verbatim: detail)
                        .foregroundStyle(HierarchicalShapeStyle.secondary)
                }
            }
        }
        .font(TextRole.badge.font)
        .padding(.horizontal, compact ? Spacing.xs : Spacing.s)
        .padding(.vertical, Spacing.xxs)
        .background(style.tone.tint.opacity(onSelection ? 0 : 0.14), in: Capsule())
        .overlay {
            if contrast == .increased && !onSelection {
                Capsule().strokeBorder(style.tone.tint, lineWidth: 1)
            }
        }
        .fixedSize()
        .help(Text(verbatim: spoken))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spoken))
    }
}
