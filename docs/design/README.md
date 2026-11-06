# Design

The UI design for FA: how the app looks, how it is laid out, and how it stays fast to use from the keyboard.

| File | What it holds |
| --- | --- |
| [design-system.md](design-system.md) | Principles, platform baseline, typography, colour and status styles, spacing and layout, materials (no custom glass), icons, components, writing and localisation, accessibility checklist, sources. |
| [screens-flows.md](screens-flows.md) | Information architecture, menus, every screen and flow (Overview, Documents, draft editor and Issue, Clients, payments, Stock, exchange rates, bank import, Settings, iPhone companion, Repair mode), the keyboard map, speed budgets, open questions. |
| [review-log.md](review-log.md) | The review findings on both specs and what was changed for each. |
| `App/FA/DesignSystem/` | The code: tokens, status styles, `StatusBadge`, `MoneyText`, a debug gallery, and the `DesignSystem` string table (English; the Czech entries are a free bonus). |

The interactive mockups (a design canvas with sample data) are linked from the project thread.

**The UI is English only.** Saša answered "en" for the interface language (proposal doc, 5 Nov 2026). Czech appears only in document text (what prints on the PDF); Czech UI is out of scope.

## Markers in the specs

- **RECOMMENDATION** is a design decision, not an Apple rule.
- **UNVERIFIED** was not confirmed on any page. Check it in Xcode or on the Mac before relying on it.
- **ACCT** is wording or a rule for the accountant to confirm.
- **[S#]** points to the numbered source list at the end of each spec.

## Platform policy (agreed with the build)

Saša's Mac runs **macOS 27.2** with English as the system language (Saša's answer in the proposal doc, 5 Nov 2026),
so the question about the macOS version is answered. The decision, agreed with the build:

- The deployment target stays **macOS 14.0** for now.
- CI builds on the `macos-15` runner with **Xcode 26.3** (the macOS 26 SDK, Swift 6.2) since the build's PR 20
  (`DEVELOPER_DIR` in `.github/workflows/ci.yml`). Any API newer than macOS 14 sits behind
  `#if compiler(>=6.2)` and an `if #available(macOS NN, *)` check for the API's own version, with a macOS 14
  fallback. A macOS 27 API needs the macOS 27 SDK, which ships with Xcode 27, so CI can't compile one yet.
- Today the gated calls are `safeAreaBar` under the editor's totals bar (`DraftEditorView.swift`) and
  `glassEffect(_:in:)` in `FloatingSurface`. The lean design (6 Nov 2026) has no custom glass and no
  `FloatingSurface` (design-system.md §6), so the build removes that one.
- When to raise the minimum is the build's call. For that raise the specs recommend **macOS 27.0**
  (design-system.md §2, screens-flows.md §0.1); a raise made on Xcode 26 can reach at most Fallback A (macOS 26.1).
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
            detail: "+12 days · 1 000,00 € left")

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
Czech translations in `DesignSystem.xcstrings`. The app ships an English UI; the Czech entries stay as a free bonus. If
the Czech UI is ever turned on, three Czech labels wait for the accountant: "Uzavřeno – neuhrazeno",
"K opravě dobropisem" and "Zúčtováno v konečné faktuře" (it follows the type name "Konečná faktura"). `StatusBadge`
resolves its word in the view's locale, so the visible word, the tooltip and VoiceOver always agree.
