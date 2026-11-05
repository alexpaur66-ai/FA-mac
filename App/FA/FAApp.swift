import AppKit
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
            DatabaseErrorView(detail: model.openError ?? "", databaseURL: model.databaseURL)
        }
    }
}

/// Shown instead of the content when the database cannot be opened (screens-flows.md §2a, Error): the
/// reason as selectable text, the data folder, and Restore from Backup… (disabled until backups exist).
/// Never an alert at launch.
struct DatabaseErrorView: View {
    let detail: String
    /// The file that could not be opened; nil for the in-memory database.
    var databaseURL: URL? = nil

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
        } actions: {
            if let databaseURL {
                Button { NSWorkspace.shared.activateFileViewerSelecting([databaseURL]) } label: { Text(L.showDataFolder) }
            }
            Button {} label: { Text(L.restoreFromBackup) }
                .disabled(true)
        }
        .frame(minWidth: 480, minHeight: 320)
    }
}
