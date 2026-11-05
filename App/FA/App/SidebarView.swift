// The main window sidebar (screens-flows.md §1.2): six sections, the document filters with their badges.

import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    let counts: [DocumentSmartFilter: Int]

    var body: some View {
        List(selection: $selection) {
            row(.overview)
            Section {
                ForEach(DocumentSmartFilter.allCases) { filter in
                    Label { Text(filter.title) } icon: { Image(systemName: filter.symbol) }
                        .badge(badge(for: filter))
                        .listItemTint(filter == .overdue ? ListItemTint.fixed(.red) : nil)
                        .tag(SidebarItem.filter(filter))
                }
            } header: {
                Text(L.documents)
            }
            Section {
                row(.clients)
                row(.payments)
                row(.rates)
                row(.exports)
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ section: AppSection) -> some View {
        Label { Text(section.title) } icon: { Image(systemName: section.symbol) }
            .tag(SidebarItem.section(section))
    }

    private func badge(for filter: DocumentSmartFilter) -> Text? {
        guard filter.showsBadge, let count = counts[filter], count > 0 else { return nil }
        return Text(verbatim: String(count))
    }
}
