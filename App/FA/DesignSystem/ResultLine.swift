// ResultLine: the inline result or error of the last action, at the top of the content pane
// (design-system.md §8.17): a symbol, the words, Undo when the action registered one, and a close button.
// Never time-boxed: the pane clears it on its next action, or the user closes it. VoiceOver hears the
// text once, when the line appears.

import SwiftUI

struct ResultLineModel: Identifiable, Equatable {
    enum Kind {
        case success, error, info
    }

    let id = UUID()
    let text: String
    let kind: Kind
    /// Takes the action back; the button runs it and clears the line.
    let undo: (@MainActor () -> Void)?

    init(_ text: String, kind: Kind = .success, undo: (@MainActor () -> Void)? = nil) {
        self.text = text
        self.kind = kind
        self.undo = undo
    }

    /// Two lines are the same line only when they are the same posting: the same text posted twice
    /// (two deletions in a row) must announce and animate again.
    static func == (lhs: ResultLineModel, rhs: ResultLineModel) -> Bool {
        lhs.id == rhs.id
    }
}

struct ResultLine: View {
    let model: ResultLineModel
    let close: @MainActor () -> Void

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(verbatim: model.text)
                .textRole(.body)
                .textSelection(.enabled)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Spacing.s)
            if let undo = model.undo {
                Button {
                    undo()
                    close()
                } label: {
                    Text(L.undo)
                }
                .buttonStyle(.borderless)
            }
            Button { close() } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text(L.close))
                .help(Text(L.close))
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .onAppear {
            AccessibilityNotification.Announcement(model.text).post()
        }
        .id(model.id)
    }

    private var symbol: String {
        switch model.kind {
        case .success: "checkmark.circle"
        case .error: "xmark.octagon.fill"
        case .info: "info.circle"
        }
    }

    private var tint: Color {
        switch model.kind {
        case .success: .green
        case .error: .red
        case .info: .secondary
        }
    }
}
