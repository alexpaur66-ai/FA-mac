// A debug-only gallery of the design system: text roles, status badges, amounts, the accent and
// the floating surface. Open it in Xcode's canvas to check light, dark and Increase Contrast.
// The amounts are sample values; 24,310 CZK/EUR is the ČNB rate for 4 Nov 2026.

#if DEBUG
import SwiftUI

struct DesignSystemGallery: View {
    private let czech = Locale(identifier: "cs_CZ")
    @State private var selectedRow: DocumentStateLabel? = .overdue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                textRoles
                documentBadges
                badgesInRows
                matchBadges
                amounts
                accent
                floating
            }
            .padding(Spacing.page)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 640, minHeight: 720)
    }

    private var textRoles: some View {
        section("Text roles") {
            ForEach(TextRole.allCases, id: \.self) { role in
                Text(verbatim: String(describing: role)).textRole(role)
            }
        }
    }

    private var documentBadges: some View {
        section("Document states") {
            ForEach(DocumentStateLabel.allCases, id: \.self) { label in
                StatusBadge(label)
            }
            StatusBadge(.overdue, detail: "+12 dní · zbývá 1 000,00 €")
            StatusBadge(.partlyPaid, compact: true)
            // Too narrow for the detail: the badge drops it by itself.
            StatusBadge(.overdue, detail: "+12 dní · zbývá 1 000,00 €")
                .frame(width: 140, alignment: .leading)
        }
    }

    /// Selected rows of a focused list: the badges go monochrome on the accent fill.
    private var badgesInRows: some View {
        section("Badges in list rows") {
            List(selection: $selectedRow) {
                ForEach([DocumentStateLabel.overdue, .partlyPaidTaxDocumentMissing, .paid], id: \.self) { label in
                    HStack {
                        Text(verbatim: label.rawValue)
                        Spacer()
                        StatusBadge(label)
                    }
                }
            }
            .frame(height: 120)
        }
    }

    private var matchBadges: some View {
        section("Bank match states") {
            ForEach(BankMatchState.allCases, id: \.self) { state in
                StatusBadge(state)
            }
        }
    }

    private var amounts: some View {
        section("Amounts") {
            // 4 840,00 € at 24,310 CZK/EUR = 117 660,40 Kč.
            MoneyText(amount: 4840, currency: "EUR", locale: czech, czk: Decimal(11_766_040) / 100)
            MoneyText(amount: Decimal(2_042_040) / 100, currency: "CZK", locale: czech, role: .total)
            MoneyText(amount: 18_400, currency: "EUR", locale: czech, role: .kpi)
        }
    }

    private var accent: some View {
        section("Accent") {
            Text(verbatim: "Vystavit…")
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.s)
                .foregroundStyle(.white)
                .background(Brand.accent, in: RoundedRectangle(cornerRadius: Radius.m))
        }
    }

    private var floating: some View {
        section("Floating surface") {
            Text(verbatim: "3 platby zaznamenány · Odvolat")
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.s)
                .floatingSurface()
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(verbatim: title).textRole(.sectionTitle)
            content()
        }
    }
}

#Preview("Light") {
    DesignSystemGallery()
}

#Preview("Dark") {
    DesignSystemGallery()
        .preferredColorScheme(.dark)
}

#Preview("Czech") {
    DesignSystemGallery()
        .environment(\.locale, Locale(identifier: "cs_CZ"))
}

#Preview("Bigger 150 %") {
    DesignSystemGallery()
        .environment(\.textScale, 1.5)
}
#endif
