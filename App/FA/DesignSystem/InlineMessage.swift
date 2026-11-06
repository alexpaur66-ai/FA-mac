// An inline problem or note next to the thing it is about (design-system.md §8.3 states, §9 voice): an SF
// Symbol in the kind's hue and the words in the primary colour, never coloured text alone (§4.4). A problem
// uses the triangle in the caution hue; red is for Overdue only (§4.3). System error text goes in the
// optional detail, a second selectable caption line, so nothing is concatenated.

import SwiftUI

struct InlineMessage: View {
    typealias Kind = MessageKind

    let text: Text
    let kind: MessageKind
    let detail: String?

    init(_ text: String, kind: MessageKind = .problem, detail: String? = nil) {
        self.text = Text(verbatim: text)
        self.kind = kind
        self.detail = detail
    }

    init(_ resource: LocalizedStringResource, kind: MessageKind = .problem, detail: String? = nil) {
        self.text = Text(resource)
        self.kind = kind
        self.detail = detail
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                text.textRole(.inlineMessage).fixedSize(horizontal: false, vertical: true)
                if let detail, !detail.isEmpty {
                    Text(verbatim: detail)
                        .textRole(.caption)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } icon: {
            Image(systemName: kind.symbol)
                .foregroundStyle(kind.tint)
                .accessibilityHidden(true)
        }
    }
}
