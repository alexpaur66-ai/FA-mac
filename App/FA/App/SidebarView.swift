// The main window sidebar (screens-flows.md §1.2): Overview, Documents with its three filters indented
// under it, Clients and Payments. Drafts carries its count; Unpaid turns red with the overdue count while
// something is overdue. No other row has a badge.

import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    let badges: SidebarBadges
    /// Stock's badge: the items running low; nothing at 0, no tint (§2n).
    var stockLow = 0

    /// The Documents row starts expanded; whether it is kept per window.
    @SceneStorage("sidebar.documentsExpanded") private var documentsExpanded = true

    var body: some View {
        List(selection: $selection) {
            row(.overview)
            // The parent row is itself selectable: it shows all documents. If a macOS 14 sidebar does not
            // select a tagged DisclosureGroup label, the fallback is a plain row with the filters at the
            // same level (screens-flows.md §1.2, UNVERIFIED on device).
            DisclosureGroup(isExpanded: $documentsExpanded) {
                filterRow(.drafts, badge: badges.drafts)
                unpaidRow
                filterRow(.openAdvances)
            } label: {
                Label { Text(L.documents) } icon: { Image(systemName: Symbols.document) }
                    .tag(SidebarItem.filter(.all))
            }
            row(.clients)
            row(.payments)
            Label { Text(AppSection.stock.title) } icon: { Image(systemName: AppSection.stock.symbol) }
                .badge(stockLow)
                .accessibilityValue(stockLow > 0 ? Text(L.stockRunningLow(stockLow)) : Text(verbatim: ""))
                .tag(SidebarItem.section(.stock))
        }
        .listStyle(.sidebar)
    }

    private func row(_ section: AppSection) -> some View {
        Label { Text(section.title) } icon: { Image(systemName: section.symbol) }
            .tag(SidebarItem.section(section))
    }

    /// A filter row; a badge of 0 shows nothing.
    private func filterRow(_ filter: DocumentSmartFilter, badge: Int = 0) -> some View {
        Label { Text(filter.title) } icon: { Image(systemName: filter.symbol) }
            .badge(badge)
            .tag(SidebarItem.filter(filter))
    }

    /// Unpaid: clock and no badge while nothing is overdue; otherwise the overdue count, a red
    /// exclamation mark and "3 overdue" for VoiceOver and the tooltip.
    @ViewBuilder private var unpaidRow: some View {
        if badges.overdue > 0 {
            Label { Text(L.filterUnpaid) } icon: { Image(systemName: "exclamationmark.circle") }
                .badge(badges.overdue)
                .listItemTint(ListItemTint.fixed(.red))
                .accessibilityValue(Text(verbatim: Count.overdue(badges.overdue)))
                .help(Text(verbatim: Count.overdue(badges.overdue)))
                .tag(SidebarItem.filter(.unpaid))
        } else {
            filterRow(.unpaid)
        }
    }
}
