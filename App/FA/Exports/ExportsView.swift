// Exports & Backup (screens-flows.md §2h): the two cards. The CSV export, Back Up Now and Restore arrive
// with the export step; until then the card shows where the one data file lives.

import AppKit
import SwiftUI

struct ExportsView: View {
    let stores: Stores

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                card(symbol: "square.and.arrow.up", title: L.exportAccountant, note: L.exportAccountantNote) {
                    Button {} label: { Text(L.exportAccountant) }.disabled(true)
                }
                card(symbol: "externaldrive", title: L.backupTitle, note: L.backupNote) {
                    if let url = stores.databaseURL {
                        Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Text(L.showDataFolder) }
                    }
                }
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(Text(L.exports))
    }

    private func card<Actions: View>(symbol: String, title: LocalizedStringResource, note: LocalizedStringResource,
                                     @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Label { Text(title) } icon: { Image(systemName: symbol) }
                .textRole(.sectionTitle)
            Text(note).textRole(.body)
            HStack { actions() }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: Radius.l))
    }
}

struct ExportsDetailView: View {
    let stores: Stores

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(L.dataFolder).textRole(.sectionTitle)
            Text(verbatim: stores.databaseURL?.path ?? "—")
                .textRole(.caption)
                .textSelection(.enabled)
            Text(L.comingLater).textRole(.caption)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
