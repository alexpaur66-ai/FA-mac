// Restore from Backup… (screens-flows.md §2h): after the file is picked, a preview of what the backup
// holds, then the alert, because a restore can't be undone [S25]. The data is local, so the restore
// itself is instant and needs no progress.

import InvoicingCore
import InvoicingData
import SwiftUI

struct RestorePreviewSheet: View {
    let candidate: AppModel.RestoreCandidate
    /// The data file can't be opened: it is kept beside the restored one rather than backed up.
    let unopenable: Bool
    let restore: @MainActor () -> Void
    let cancel: @MainActor () -> Void
    @State private var confirming = false
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(L.restoreTitle).textRole(.sectionTitle)
            Form {
                LabeledContent {
                    Text(verbatim: candidate.url.lastPathComponent).textSelection(.enabled)
                } label: {
                    Text(L.restoreFile)
                }
                LabeledContent {
                    Text(verbatim: madeAtText ?? String(localized: L.restoreNotRecorded))
                } label: {
                    Text(L.restoreMadeOn)
                }
                LabeledContent {
                    Text(verbatim: String(candidate.info.documents))
                } label: {
                    Text(L.documents)
                }
                LabeledContent {
                    Text(verbatim: String(candidate.info.clients))
                } label: {
                    Text(L.clients)
                }
                LabeledContent {
                    Text(verbatim: candidate.info.appVersion ?? String(localized: L.restoreNotRecorded))
                } label: {
                    Text(L.restoreAppVersion)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button { cancel() } label: { Text(L.cancel) }
                    .keyboardShortcut(.cancelAction)
                Button { confirming = true } label: { Text(L.restoreEllipsis) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.l)
        .frame(width: 440)
        .alert(Text(alertTitle), isPresented: $confirming) {
            Button(role: .cancel) {} label: { Text(L.cancel) }
            Button(role: .destructive) { restore() } label: { Text(L.restoreButton) }
        } message: {
            Text(unopenable ? L.restoreAlertMessageUnopenable : L.restoreAlertMessage)
        }
    }

    /// "today 9:02" or "3. 11. 2026 9:02".
    private var madeAtText: String? {
        candidate.info.madeAt.map { BackupStatus.when($0, locale: locale) }
    }

    private var alertTitle: LocalizedStringResource {
        guard let madeAt = candidate.info.madeAt else { return L.restoreAlertTitleNoDate }
        return L.restoreAlertTitle(CalendarDay(madeAt, in: .current).formatted(locale))
    }
}

extension View {
    /// The restore preview and the alert that says why a backup was not restored, for any window that
    /// can start Restore from Backup… (the main window and Settings).
    func restoreFlow(_ model: AppModel) -> some View {
        modifier(RestoreFlow(model: model))
    }
}

private struct RestoreFlow: ViewModifier {
    @Bindable var model: AppModel

    func body(content: Content) -> some View {
        content
            .sheet(item: $model.restoreCandidate) { candidate in
                RestorePreviewSheet(
                    candidate: candidate, unopenable: model.stores == nil,
                    restore: { model.restore(candidate) },
                    cancel: { model.restoreCandidate = nil })
            }
            .alert(Text(L.restoreProblemTitle), isPresented: problemShown) {
                Button {} label: { Text(L.okButton) }
            } message: {
                Text(verbatim: model.restoreProblem ?? "")
            }
    }

    private var problemShown: Binding<Bool> {
        Binding(get: { model.restoreProblem != nil }, set: { if !$0 { model.restoreProblem = nil } })
    }
}
