// The month bar "◀ October 2026 ▶" (screens-flows.md §2a): the Overview's month and the export sheet's
// (§2h) are the same component.

import InvoicingCore
import SwiftUI

struct MonthBar: View {
    @Binding var month: CalendarDay
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: Spacing.m) {
            Button { month = month.adding(months: -1).startOfMonth } label: {
                Label { Text(L.previousMonth) } icon: { Image(systemName: "chevron.left") }
            }
            .labelStyle(.iconOnly)
            .help(Text(L.previousMonth))
            Text(verbatim: Self.title(month, locale: locale)).textRole(.screenTitle).frame(minWidth: 160)
            Button { month = month.adding(months: 1).startOfMonth } label: {
                Label { Text(L.nextMonth) } icon: { Image(systemName: "chevron.right") }
            }
            .labelStyle(.iconOnly)
            .help(Text(L.nextMonth))
        }
    }

    /// "October 2026".
    static func title(_ day: CalendarDay, locale: Locale) -> String {
        day.midnight(in: .current).formatted(Date.FormatStyle(locale: locale).month(.wide).year())
    }
}
