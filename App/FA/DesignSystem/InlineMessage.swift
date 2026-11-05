// An inline error, warning or note next to the thing it is about (design-system.md §8.3 states, §9 voice):
// an SF Symbol in the status hue and the words in the primary colour, never coloured text alone (§4.4).

import SwiftUI

struct InlineMessage: View {
    enum Kind {
        case error, warning, info
    }

    let text: Text
    let kind: Kind

    init(_ text: String, kind: Kind = .error) {
        self.text = Text(verbatim: text)
        self.kind = kind
    }

    init(_ resource: LocalizedStringResource, kind: Kind = .error) {
        self.text = Text(resource)
        self.kind = kind
    }

    var body: some View {
        Label {
            text.textRole(.inlineMessage).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
        }
    }

    private var symbol: String {
        switch kind {
        case .error: "xmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info: "info.circle"
        }
    }

    private var tint: Color {
        switch kind {
        case .error: .red
        case .warning: .orange
        case .info: .secondary
        }
    }
}
