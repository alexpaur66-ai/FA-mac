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
        Group {
            if let stores = model.stores {
                // A restore bumps the generation: the content is rebuilt on the restored data.
                MainSplitView(stores: stores, restoreFromBackup: restoreAction, takeNotice: { model.takeNotice() })
                    .id(model.generation)
            } else {
                DatabaseErrorView(detail: model.openError ?? "", databaseURL: model.databaseURL,
                                  restoreFromBackup: restoreAction)
            }
        }
        .restoreFlow(model)
    }

    private var restoreAction: (@MainActor () -> Void)? {
        guard model.canRestore else { return nil }
        return { model.chooseBackupToRestore() }
    }
}

/// Shown instead of the content when the database cannot be opened (screens-flows.md §2a, Error): the
/// reason as selectable text, the data folder, and Restore from Backup…. Never an alert at launch.
struct DatabaseErrorView: View {
    let detail: String
    /// The file that could not be opened; nil for the in-memory database.
    var databaseURL: URL? = nil
    /// Restore from Backup…; nil for the in-memory database.
    var restoreFromBackup: (@MainActor () -> Void)? = nil

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
            Button { restoreFromBackup?() } label: { Text(L.restoreFromBackup) }
                .disabled(restoreFromBackup == nil)
        }
        .frame(minWidth: 480, minHeight: 320)
    }
}
