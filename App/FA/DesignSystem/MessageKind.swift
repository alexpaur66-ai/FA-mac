// The one message vocabulary of InlineMessage and ResultLine (design-system.md §8.3, §8.17): a problem, a
// note, or a done action. The symbol carries the kind; the words stay in the primary colour. No green.

import SwiftUI

enum MessageKind: Sendable {
    /// Something to fix, said next to the thing it is about.
    case problem
    case info
    /// An action finished (the result line only).
    case done

    var symbol: String {
        switch self {
        case .problem: "exclamationmark.triangle.fill"
        case .info: "info.circle"
        case .done: "checkmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .problem: .orange
        case .info, .done: .secondary
        }
    }
}
