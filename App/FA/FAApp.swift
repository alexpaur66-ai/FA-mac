import SwiftUI

@main
struct FAApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        // One main window with an id, so Window ▸ Main Window can reopen it (screens-flows.md §1.1).
        WindowGroup(id: "main") {
            RootView(model: model)
                .environment(\.textScale, model.textScale)
        }
        .defaultSize(LayoutMetrics.windowDefault)
        .commands { AppCommands(model: model) }

        Settings {
            SettingsRoot(model: model)
                .environment(\.textScale, model.textScale)
        }
    }
}

/// The main window: the split view when the database is open, otherwise the inline error.
struct RootView: View {
    let model: AppModel

    var body: some View {
        if let stores = model.stores {
            MainSplitView(stores: stores)
        } else {
            DatabaseErrorView(detail: model.openError ?? "")
        }
    }
}

/// Shown instead of the content when the database cannot be opened. Never an alert at launch.
struct DatabaseErrorView: View {
    let detail: String

    var body: some View {
        ContentUnavailableView {
            Label { Text(L.dbCannotOpen) } icon: { Image(systemName: "externaldrive.badge.exclamationmark") }
        } description: {
            VStack(spacing: Spacing.s) {
                Text(L.dbCannotOpenDetail)
                Text(verbatim: detail)
                    .textRole(.caption)
                    .textSelection(.enabled)
            }
        }
        .frame(minWidth: 480, minHeight: 320)
    }
}
