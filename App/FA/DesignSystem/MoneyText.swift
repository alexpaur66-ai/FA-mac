// MoneyText: a read-only amount with its currency, tabular digits and an optional CZK line
// (design-system.md §8.2). Editable amounts never use the currency format style (§8.3).

import SwiftUI

struct MoneyText: View {
    let amount: Decimal
    /// ISO 4217 code, such as "EUR" or "CZK".
    let currency: String
    /// Always passed explicitly: the UI locale in the app, the document's PDF locale in the PDF preview.
    let locale: Locale
    /// The CZK equivalent (VAT in CZK, totals). Shown only when `currency` is not CZK.
    var czk: Decimal?
    var role: TextRole = .amount

    var body: some View {
        VStack(alignment: .trailing, spacing: Spacing.xxs) {
            Text(verbatim: Self.format(amount, currency: currency, locale: locale))
                .textRole(role)
            if let czk, currency != "CZK" {
                Text(verbatim: Self.format(czk, currency: "CZK", locale: locale))
                    .textRole(.amountSecondary)
            }
        }
        .multilineTextAlignment(.trailing)
        .textSelection(.enabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spoken))
    }

    /// Full currency names for VoiceOver, such as "1 234,50 eura".
    private var spoken: String {
        let main = Self.format(amount, currency: currency, locale: locale, fullName: true)
        guard let czk, currency != "CZK" else { return main }
        return main + ", " + Self.format(czk, currency: "CZK", locale: locale, fullName: true)
    }

    /// Formats an amount with the system currency style for `locale`. No hand-built formats.
    nonisolated static func format(
        _ value: Decimal, currency: String, locale: Locale, fullName: Bool = false
    ) -> String {
        let style = Decimal.FormatStyle.Currency(code: currency, locale: locale)
        return value.formatted(fullName ? style.presentation(.fullName) : style)
    }
}
