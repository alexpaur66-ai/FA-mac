// MoneyListText: amounts per currency, never summed across currencies (screens-flows.md §2a). Each
// amount is a MoneyText, so the digits are tabular and VoiceOver reads full currency names; a "+" sits
// between the currencies. A dash when there is nothing.

import InvoicingCore
import SwiftUI

struct MoneyListText: View {
    let monies: [Money]
    /// Always passed explicitly, like MoneyText's.
    let locale: Locale
    var role: TextRole = .amount

    var body: some View {
        let sums = MoneyList.sums(monies)
        if sums.isEmpty {
            Text(verbatim: "—").textRole(role)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                ForEach(Array(sums.enumerated()), id: \.offset) { index, money in
                    if index > 0 {
                        Text(verbatim: "+").textRole(role).accessibilityHidden(true)
                    }
                    MoneyText(amount: money.amount, currency: money.currency.code, locale: locale, role: role)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
