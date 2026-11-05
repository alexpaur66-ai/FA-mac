# Design

The UI design for FA: how the app looks, how it is laid out, and how it stays fast to use from the keyboard.

| File | What it holds |
| --- | --- |
| [design-system.md](design-system.md) | Principles, platform baseline, typography, colour and status styles, spacing and layout, Liquid Glass rules, icons, components, writing and localisation, accessibility checklist, sources. |
| [screens-flows.md](screens-flows.md) | Information architecture, menus, every screen and flow (Overview, Documents, draft editor and Issue, Clients, payments, ČNB rates, bank import, Settings, iPhone companion), the keyboard map, speed budgets, open questions. |
| [review-log.md](review-log.md) | The review findings on both specs and what was changed for each. |
| `App/FA/DesignSystem/` | The code: tokens, status styles, `StatusBadge`, `MoneyText`, `FloatingSurface`, a debug gallery, and the `DesignSystem` string table (English and Czech). |

The interactive mockups (a design canvas with sample data) are linked from the project thread.

## Markers in the specs

- **RECOMMENDATION** is a design decision, not an Apple rule.
- **UNVERIFIED** was not confirmed on any page. Check it in Xcode or on the Mac before relying on it.
- **ACCT** is wording or a rule for the accountant to confirm.
- **[S#]** points to the numbered source list at the end of each spec.

## Platform policy (agreed with the build)

The specs recommend targeting macOS 27.0, with macOS 26.1 as the fallback (design-system.md §2). That recommendation
waits for Saša's macOS version. Until then the code follows the policy agreed for the repository:

- The deployment target stays **macOS 14.0**.
- CI builds with the default Xcode of the `macos-15` runner, so any API from a newer SDK sits behind
  `#if compiler(>=6.2)` (Swift 6.2 ships with the macOS 26 SDK; a macOS 27 API needs the Swift version of that SDK)
  and an `if #available(macOS NN, *)` check for the API's own version, with a macOS 14 fallback.
- Today that applies to one call: `glassEffect(_:in:)` in `FloatingSurface`. On macOS 14 and 15 the surface is an
  opaque capsule, the same as with Reduce Transparency.
- The runner's Xcode 16.4 (Swift 6.1) compiles only the fallback. The glass branch is first compiled by Xcode 26 or
  later, on the Mac.
- When the target is raised, the gated branches become the only branch, and the macOS 27 items in design-system.md §2
  (bordered text fields, `.tabs` pickers, `reorderable()`, concentric radii) can be adopted.

## Names in the code

The code follows the specs, with a few names changed so they don't clash with InvoicingCore or SwiftUI:

| Spec | Code | Why |
| --- | --- | --- |
| `Layout` | `LayoutMetrics` | `Layout` is a SwiftUI protocol. |
| window and sheet sizes as tuples | `CGSize` values | Simpler to pass to `frame` and `defaultSize`. |
| `DocumentStatus` | `DocumentStateInputs` | `InvoicingCore.DocumentStatus` is the draft/issued lifecycle. |
| `DocumentKind` (`advance`) | `DocumentStateInputs.Kind` (`advanceRequest`) | Raw values match `InvoicingCore.DocumentKind`, so `Kind(rawValue:)` maps one to the other. |
| `Settlement` | `DocumentStateInputs.Settlement` | Kept next to the inputs it belongs to. |
| `MatchStatus` | `BankMatchState` | Says what is being matched. |

## Using it

```swift
Text(verbatim: document.number ?? "—").textRole(.documentNumber)   // drafts have no number yet

StatusBadge(DocumentStateInputs(kind: .invoice, settlement: .partlyPaid, isOverdue: true),
            detail: "+12 dní · zbývá 1 000,00 €")

MoneyText(amount: total, currency: "EUR", locale: uiLocale, czk: totalInCZK, role: .total)

NavigationSplitView {
    Sidebar()
        .navigationSplitViewColumnWidth(min: LayoutMetrics.sidebar.min,
                                        ideal: LayoutMetrics.sidebar.ideal,
                                        max: LayoutMetrics.sidebar.max)
} content: { … } detail: { … }

// View ▸ Bigger / Smaller: set once at the scene root; text roles, amounts and badges follow it.
ContentView().environment(\.textScale, textScale)
```

`Brand.accent` is the "Inkoust" accent as a fill colour, for custom drawing. App-wide, the accent comes from an
`AccentColor` asset with the same values and the `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` build setting, which
the build adds with the project settings (not `.tint` on the root view). Links and accent-coloured text use
`NSColor.linkColor`, never the brand colour.

Every status label is a `LocalizedStringResource` in the `DesignSystem` table, with English defaults in sentence case and
Czech translations in `DesignSystem.xcstrings`. Three Czech labels wait for the accountant: "Uzavřeno – neuhrazeno",
"K opravě dobropisem" and "Zúčtováno v konečné faktuře" (it follows the type name "Konečná faktura"). `StatusBadge`
resolves its word in the view's locale, so the visible word, the tooltip and VoiceOver always agree.
