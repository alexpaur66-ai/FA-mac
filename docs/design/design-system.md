# FA-mac design system

Native macOS invoicing app with a light CRM, built for Sasa's Czech s.r.o. (a VAT payer). Version 0.1 of the design system, written 2026-11-05.

## How to read this

- **[S#]** points to the numbered source list at the end. Every claim about Apple design, APIs or OS versions comes from a page that I or the research threads opened.
- **RECOMMENDATION** marks my own design decision. It is not an Apple rule.
- **UNVERIFIED** means I did not confirm it on any page. Check it in Xcode 27.2 or on Sasa's Mac before relying on it.
- API availability ("macOS 26.0") is `introducedAt` from Apple's documentation JSON, read on 2026-11-05.
- The documentation currently reflects the 27.3 **beta** SDK. Anything marked "deprecated 27.3" therefore comes from that beta.
- SF Symbol names were checked against the SF Symbols name and availability data that the third-party SFSafeSymbols project mirrors [S85]. That data runs up to the 2025 release (macOS 26). It cannot show symbols added or renamed in SF Symbols 27, so confirm every name in the SF Symbols 27 app (the current download [S48]) before use.
- Code companion: `App/FA/DesignSystem/`. It is written for the current build target, macOS 14.0 (see the §2 build decision), and gates the macOS 26 glass API. [README.md](README.md) lists where its names differ from this document.
- **Examples.** The app UI is English (P7, §9). Numbers and dates in examples, such as "1 000,00 €" or "30. 10. 2026", only illustrate. On screen they follow the system locale; on documents they follow the document's locale.

---

## 1. Design principles

Sasa's brief for the design: *"useful, nice and comfortable and swift and quick while looking good and modern Apple 2027 ready"*. The seven principles below turn that into rules. When two of them conflict, the earlier one wins.

| # | Principle | What it means in practice | Serves |
|---|---|---|---|
| P1 | **Money is content, never decoration** | Amounts sit on opaque surfaces and use tabular digits (`monospacedDigit`). The currency is always shown. On EUR and USD documents the CZK equivalents are shown wherever the VAT law needs them. Glass never covers amounts, tables or the invoice preview: the HIG says "Don't use Liquid Glass in the content layer" [S2]. | trustworthy |
| P2 | **Commit is deliberate; everything else is undoable** | **Issuing** is the only irreversible action: it assigns the number and locks the document. It gets one confirmation sheet that shows exactly what will be locked. Everything else (draft edits, deleting a draft, unmatching, notes) happens immediately and can be undone by name, with no alert. This follows the HIG: no alerts for common undoable actions, an alert for an uncommon one that can't be undone [S15], and named, multi-level undo [S16]. **The one exception is Repair mode** (v0.1.x, §8.18). Behind Touch ID or the password it unlocks every record, issued documents included. Every repair change is written to the audit log, which never leaves the Mac. There is no trace-free mode. The normal fix for a wrong issued document stays a corrective document (Phase 2). | trustworthy, fast |
| P3 | **Keyboard first, never keyboard only** | Every daily action is two keystrokes or fewer from anywhere: ⌘N, ⌘D, ⌘R, ⌘K, ⌘Return, plus single keys in a focused list. Every command also appears in the menu bar, because the HIG asks for the menu bar to list all commands and every toolbar item [S14][S8]. The palette repeats the menus; it never replaces them. The one authoritative keyboard map is screens-flows §3.1. | swift and quick |
| P4 | **Calm surface, loud only when money needs Sasa** | Chrome stays neutral. There is one accent colour and one prominent action per context [S8][S35]. Red appears only for Overdue. The Overview is a queue of what needs attention, not a gallery of charts. | comfortable, calm |
| P5 | **Native first, custom last** | Use standard `NavigationSplitView`, `Table`, `inspector`, `toolbar`, `Form`, sheets and menus. They pick up Liquid Glass and the macOS 27 refinements automatically [S1][S44]. Add no custom backgrounds to bars or the sidebar [S1]. v0.1 has **no** custom glass element; the one planned custom glass element (the Undo toast) arrives with the v0.2 bulk actions (§6). | modern, 2027 ready |
| P6 | **Every number shows where it came from** | Each CZK figure carries its rate, the rate's date and its source ("Typed" or "ČNB file"), and is labelled when the rate is a weekend or holiday fallback. Each bank match carries a reason label, an idea taken from Xero's labels and hover reasoning [S89]. Issued documents show a lock glyph. | trustworthy |
| P7 | **English UI, exact Czech on documents** | The app UI is English only (Sasa's answer in the proposal doc, 5 Nov 2026: "en"). Czech legal terms stay exact on documents, which print in Czech, or in Czech and then English (§9). Where the UI quotes a printed legal string, it shows it exactly as printed, from the §9 legal-strings table. All numbers, dates and currencies go through `FormatStyle` with an explicit locale; none are built by hand. The UI uses the system locale; documents and their preview use the document's locale, which is Czech formatting in both document languages (§9). | trustworthy, comfortable |

The HIG design principles page backs the spirit of these: Agency ("Help people recover from mistakes"), Responsibility ("Only collect what your product needs", which fits offline-only), and "Simplicity isn't minimalism" [S36].

---

## 2. Platform baseline

### Facts

- **Current release.** macOS 27 Golden Gate shipped on 14 Sep 2026, and **27.2 is the current release** (26 Oct 2026). The 27.3 betas are out. macOS Tahoe still gets updates, most recently 26.7.2 [S40][S45].
- **Sasa's hardware is supported.** Sasa's Mac is an M1 Pro with 32 GB (Sasa's message in the project chat, 5 Nov 2026). The M1 Pro ships only in the MacBook Pro (14-inch, 2021) and (16-inch, 2021) [S39]. Both models are on the macOS 27 compatibility list [S37] and the macOS Tahoe 26 list [S38].
- **Liquid Glass needs macOS 26.** Every Liquid Glass API is macOS 26.0 or later: `glassEffect(_:in:)`, `GlassEffectContainer`, the `.glass` and `.glassProminent` button styles, `ToolbarSpacer`, `scrollEdgeEffectStyle`, `ConcentricRectangle` and `containerShape(_:)` [S52][S53][S74]. So does the non-deprecated drop API `dropDestination(for:isEnabled:action:)` [S62].
- **macOS 27 additions.** `TextFieldStyle.bordered` and `textInputBorderShape(_:)` are macOS 27.0 [S73]. They replace `.roundedBorder`, which is deprecated in 27.3. Also macOS 27.0: `PickerStyle.tabs` [S75], `GeometryProxy.concentricCornerRadii` [S53], `reorderable()`, and `NSMenuItem.preferredImageVisibility` [S45][S46].
- **The new design can't be switched off.** When you build for macOS 27 or later, the system ignores `UIDesignRequiresCompatibility` [S43]. Apps rebuilt with Xcode 27 always use Liquid Glass [S44].
- **Toolchain.** Xcode 27.2 ships Swift 6.4 and the 27.2 SDKs, and it **requires macOS Tahoe 26.6 or later** [S41]. Xcode 27 installs only on Apple silicon Macs, and its macOS 27 SDK can still back-deploy to macOS 12 [S42].
- **Sasa's Mac runs macOS 27.2, with English as the system language.** Sasa's answer in the proposal doc, 5 Nov 2026: "27.2, english", and "m1 pro 32gb ram 200gb bandwith 256gb disk - using mainly 8tb cloud / macOS 27.2 (the newest one, im just updating it right now)". So open question Q1 (which macOS) is answered. 27.2 is the current release [S40], and it is later than the 26.6 that Xcode 27.2 needs [S41].

### RECOMMENDATION

| Situation on Sasa's Mac | Deployment target | What changes in the design |
|---|---|---|
| **macOS 27.x** (Sasa's Mac: 27.2) | **macOS 27.0** | Nothing; this document assumes it. There are no `#available` branches. The app uses `TextFieldStyle.bordered`, the `.tabs` picker in inspectors, `reorderable()` for line items and `concentricCornerRadii`, and it avoids every API deprecated in 27.3. The macOS 27 design refinements come for free: the uniform toolbar under scrolled content, edge-to-edge sidebars, sidebar icons coloured with the accent, and the tighter window radius [S44]. 27.0 is enough because nothing in 27.1 or 27.2 is needed. |
| **Fallback A: macOS Tahoe 26.x.** Not needed for Sasa's Mac, which runs 27.2. It stays as the list of macOS 27.0 `#available` branches. The macOS 14.0 build target needs more: every API above 14.0 is gated. That includes the macOS 26 APIs in Facts above, plus `presentationSizing(_:)` (15.0 [S63]), `textInputSuggestions(_:)` (15.0 [S58]), `visibilityPriority(_:)` (26.1 [S74]) and `onDropSessionUpdated(_:)` (26.0 [S101]). The §7 symbols marked 15.0, 15.2 or 26.0 also need a macOS 14 fallback symbol. | **macOS 26.1** (not 26.0, so that `visibilityPriority(_:)`, macOS 26.1 [S74], needs no gate) | Same layout and tokens. Every API below is macOS 27.0 in the docs and needs an `if #available(macOS 27, *)` branch (or a `@available` wrapper view):<br>- `TextFieldStyle.bordered` / `textInputBorderShape(_:)` [S73]: fall back to the default style, without the deprecated `.roundedBorder`<br>- `reorderable()` + `reorderContainer(for:isEnabled:move:)` [S46][S99]: line items reorder through menu commands only, with no drag<br>- `PickerStyle.tabs` [S75]: the inspector tabs use `.segmented`<br>- `GeometryProxy.concentricCornerRadii` [S53]: compute the radius with `Radius.concentric(outer:inset:)`<br>- `presentationPlacement(_:)` / `PresentationPlacement` [S100]: the command palette uses the default sheet placement<br>- `NSMenuItem.preferredImageVisibility` [S45]: menus keep the 26 icon behaviour<br>If Fallback A has to target 26.0 after all, `visibilityPriority(_:)` also needs an `if #available(macOS 26.1, *)` gate.<br>The app looks "Tahoe", not "Golden Gate". To build on that Mac with Xcode 27.2 it must run 26.6 or later [S41]. |
| **Fallback B: macOS 14 or 15** | Does not apply: Sasa's Mac runs 27.2. | No Liquid Glass APIs are available [S52], so the one custom glass element becomes an opaque surface (§6). `ToolbarSpacer` groups become plain items, and the drop zone uses the drop API that is deprecated in 27.3. Xcode 27.2 can't run on that Mac [S41], so builds happen on another Apple-silicon Mac. |

**Baseline statement (used in screens-flows §0.1 and Q1):** the design targets macOS 27.0, because Sasa's Mac runs macOS 27.2. The app builds for macOS 14.0 until CI builds with Xcode 26 or later.

**Build decision (agreed with the build thread):** the app keeps targeting **macOS 14.0**, with `#if compiler(>=6.2)` and `if #available` gates. The reason is CI: it runs on the `macos-15` runner with Xcode 16.4, which has the macOS 15 SDK ([README.md](README.md), Platform policy; `.github/workflows/ci.yml`). The minimum rises once CI builds with Xcode 26 or later. 27.0 stays the design recommendation for that later raise. The macOS 27.0 APIs in the first row need the macOS 27 SDK, which ships with Xcode 27 [S41]. So a raise made on Xcode 26 can reach at most Fallback A (macOS 26.1). Sasa's Mac is not in Fallback B, but on macOS 14 and 15 the gated fallbacks are the ones the Fallback B row lists.

---

## 3. Typography

### Rules

- Use only the built-in text styles: **SF Pro**, with tracking applied by the system. macOS has **no Dynamic Type**. The default size is **13 pt** and the minimum is **10 pt** [S3][S5].
- Avoid the Ultralight, Thin and Light weights [S3].
- Change emphasis with symbolic traits (`bold()`, `weight(_:)`), never with custom sizes [S3].

**HIG macOS text styles** (copied from [S3]; points at 144 ppi @2x):

| Style | Weight | Size / line height | Emphasized |
|---|---|---|---|
| Large Title | Regular | 26 / 32 | Bold |
| Title 1 | Regular | 22 / 26 | Bold |
| Title 2 | Regular | 17 / 22 | Bold |
| Title 3 | Regular | 15 / 20 | Semibold |
| Headline | Bold | 13 / 16 | Heavy |
| Body | Regular | 13 / 16 | Semibold |
| Callout | Regular | 12 / 15 | Semibold |
| Subheadline | Regular | 11 / 14 | Semibold |
| Footnote | Regular | 10 / 13 | Semibold |
| Caption 1 | Regular | 10 / 13 | Medium |
| Caption 2 | Medium | 10 / 13 | Semibold |

### Role map (RECOMMENDATION)

Every font is a SwiftUI `Font` static or method, verified [S55]: `.largeTitle`, `.title2`, `.title3`, `.headline`, `.body`, `.callout`, `.subheadline`, `.caption`, `Font.weight(_:)`, `Font.bold()` and `Font.monospacedDigit()`.

| Use | Token (`TextRole`) | SwiftUI | macOS pt | Digits | Colour |
|---|---|---|---|---|---|
| Window title, subtitle | (system) | `navigationTitle` / `navigationSubtitle`; don't style | system | — | system |
| Screen header in content (client name, "Overview") | `.screenTitle` | `.title2.bold()` | 17 / 22 Bold | — | primary |
| Section headers in content (Overview groups) | `.sectionTitle` | `.headline` | 13 / 16 Bold | — | primary |
| Form and inspector section headers | (system) | `Section` header; title case, not all caps [S1] | system | — | system |
| Document number in editor header ("FV-2026-0042") | `.documentNumber` | `.title3.weight(.semibold).monospacedDigit()` | 15 / 20 Semibold | tabular | primary, selectable |
| Table cells, form values, labels | `.body` / `.label` | `.body` | 13 / 16 | — | primary |
| Amounts in table cells | `.amount` | `.body.monospacedDigit()` | 13 / 16 | tabular, trailing | primary |
| Invoice number, VS and IBAN cells | `.amount` | `.body.monospacedDigit()` | 13 / 16 | tabular | primary |
| Emphasised amount (open balance in a row) | `.amountStrong` | `.body.weight(.semibold).monospacedDigit()` | 13 / 16 Semibold | tabular | primary |
| Second line in a row (IČO, client city, "due in 5 days") | `.rowSecondary` | `.subheadline` | 11 / 14 | — | secondary |
| CZK equivalent under an EUR or USD amount | `.amountSecondary` | `.subheadline.monospacedDigit()` | 11 / 14 | tabular | secondary |
| Totals rows (base, VAT per rate) | `.amount` | `.body.monospacedDigit()` | 13 / 16 | tabular | primary |
| Grand total ("Amount due"; the PDF prints "K úhradě") | `.total` | `.title3.weight(.semibold).monospacedDigit()` | 15 / 20 Semibold | tabular | primary |
| Overview KPI figure | `.kpi` | `.largeTitle.bold().monospacedDigit()` | 26 / 32 Bold | tabular | primary |
| Status badge text | `.badge` | `.callout.weight(.medium)` | 12 / 15 Medium | — | primary |
| In-app legal notices (the printed clauses, quoted exactly: "daň odvede zákazník", the not-a-tax-document note on an advance; strings from the §9 legal-strings table) | `.legalNote` | `.callout` | 12 / 15 | — | primary, never secondary |
| Captions: rate source, timestamps, hints | `.caption` | `.caption` | 10 / 13 | — | secondary |

### Notes

- **Floor.** 10 pt is the on-screen minimum [S3]. Legal notices are never set below Callout (12 pt) in the app.
- **Text enlargement.** The HIG asks that people can enlarge text by at least 200 % [S5], and macOS has no Dynamic Type, so the app does it itself (RECOMMENDATION). Add View ▸ Bigger (⇧⌘=, which the keyboard table lists as "Increase the size of the selection") and View ▸ Smaller (⌘−) [S13], plus Actual Size (⌘0; see screens-flows §3.1). They scale **every content surface** from 100 % to 200 % in steps, from one app-wide scale value: the Table, the editor, the inspector, the Overview, `TotalsPanel` and sheet content. The amounts Sasa most needs to read live in the inspector, the totals and the Overview, so none of them stays at 100 %. System chrome (toolbar, sidebar, menus) keeps the system sizes. The mechanism is `Font.system(size:weight:design:)` (macOS 13.0 [S55]), fed with the HIG sizes above times the scale. The one app-wide scale value is the SwiftUI environment value `textScale` (1 to 2, `DesignTokens.swift`): the app sets `.environment(\.textScale, …)` once at the scene root, and `textRole(_:)`, `MoneyText` and `StatusBadge` read it, so callers never pass a scale by hand. Whether system-size text keeps the text-style tracking is UNVERIFIED; compare it on device. When the scale isn't 1, table row height follows the scaled line height plus padding (§5.3), so text never clips. Test 200 % in the minimum window (§5.3).
- **PDF typography is out of scope.** The PDF is drawn with Core Graphics and has its own A4 sizes. HIG tracking values matter only for custom PDF text [S3].

---

## 4. Colour

### 4.1 Semantic system colours

Never hard-code system colours, because their "values may fluctuate from release to release" [S4]. The AppKit names below are bridged with `Color(nsColor:)` (macOS 12.0).

| Use | Colour |
|---|---|
| Window, sidebar, toolbar | system default; set nothing [S1] |
| Primary text | `labelColor` / `.primary` |
| Secondary text | `secondaryLabelColor` / `.secondary` |
| Unavailable text | `tertiaryLabelColor` |
| Watermarks in on-screen chrome only (e.g. an empty-state glyph) | `quaternaryLabelColor` |
| "KONCEPT / DRAFT" watermark **drawn into the PDF** (preview and print) | a **fixed** colour defined in the PDF spec, e.g. mid-grey sRGB 50 % at a fixed alpha (RECOMMENDATION). Never a dynamic colour: the page is always white paper, a dynamic label colour turns light in Dark Mode, and a Core Graphics PDF has no appearance. |
| Behind the PDF page (preview surround) | `underPageBackgroundColor` ("Behind a document's content") |
| Editable field background | `textBackgroundColor` |
| Large content background (table) | `controlBackgroundColor` |
| Alternating table rows | `alternatingRowBackgrounds(_:)` (macOS 14.0) [S79] |
| Separators | `separatorColor` / `.separator` |
| Table grid lines (if any) | `gridColor` |
| Links ("Open in Finder") | `linkColor` |
| Search hit highlight | `findHighlightColor` |
| Selection | system: `selectedContentBackgroundColor`, and `unemphasized…` when the window is not key |

The colours come from the macOS dynamic system colour table in the HIG [S4]. Per that table and the Labels page, **label** is for primary information, **secondary** for subheadings and supplemental text, **tertiary** for unavailable items and **quaternary** for watermarks [S4].

The PDF page is **always shown as white paper**, in Light and in Dark Mode, because it is content, not chrome (RECOMMENDATION). In Dark Mode consider a slight dim, following the HIG advice to "soften the color of white backgrounds" [S6]. Don't offer an app-specific Light/Dark switch [S6].

### 4.2 App accent: "Inkoust" (ink indigo). RECOMMENDATION

| Variant | sRGB | Contrast (WCAG, computed) |
|---|---|---|
| Light | `#4B3FD6` (75, 63, 214) | 7.04 : 1 against white; white text on it 7.04 : 1 |
| Dark | `#6A5FF5` (106, 95, 245) | white text on it **4.60 : 1**; 3.63 : 1 against `#1E1E1E`* (passes 3 : 1 as a UI element, not as text) |
| Increased contrast, light | `#372BB0` (55, 43, 176) | 9.84 : 1 against white; white text on it 9.84 : 1 |
| Increased contrast, dark | `#5F54E8` (95, 84, 232) | white text on it **5.36 : 1**; 3.11 : 1 against `#1E1E1E`* |

\* `#1E1E1E` is only a stand-in for a dark window surface in this calculation. It is not an Apple value. Measure the real surfaces with Accessibility Inspector, which uses the same WCAG ratios as the HIG table [S5]. All ratios computed with the WCAG formula on 2026-11-05.

**Why the dark variants are darker than a "readable on dark" indigo.** The HIG Color page says the system "applies the app accent color to the background in prominent buttons" [S4], so the accent is a **fill under a white label** (the prominent Issue button, and selected rows when the person's accent setting is multicolor). The HIG minimum for text up to 17 pt is 4.5 : 1; 3 : 1 applies only to bold text or 18 pt and up [S5]. The previous dark value `#8076FF` gave white text only 3.53 : 1, and whether the system button label is bold enough for the 3 : 1 rule is UNVERIFIED. No single indigo gives both ≥ 4.5 : 1 under white text and ≥ 4.5 : 1 as text on a dark surface, so the tokens split (RECOMMENDATION):
- **AccentColor (fill)**: the table above. Used for the prominent action, selection and the drop-zone highlight.
- **Links and any accent-coloured text**: system `linkColor` (§4.1), never the AccentColor.
- **Check on device first.** If the system turns out not to draw white text on the raw accent, re-measure with Accessibility Inspector before changing anything else.

**Why ink indigo**
- It is clearly separate from the status hues: red, orange and green, plus neutral grey. That keeps "one colour, one meaning" [S4].
- It avoids the default blue that most apps use.
- It reads as calm and trustworthy for a money app.

**Where it appears.** The system applies the app accent to buttons, selection highlights and sidebar icons, but only when the person's General ▸ Accent colour setting is *multicolor*; otherwise the person's choice wins [S4]. On macOS 27, sidebar icons use the accent colour again [S44]. The app adds accent in only three places: the one prominent action (Issue), the drop-zone highlight, and the app icon. Links use `linkColor`.

**How to define it**
- Preferred: an `AccentColor` colour set in the asset catalog with Any, Dark and High Contrast variants, so the system supplies the variants. Asset-catalog high-contrast slots are UNVERIFIED; check them in Xcode 27.2.
- In code: `App/FA/DesignSystem/` keeps a reviewable twin built with `NSColor(name:dynamicProvider:)` (macOS 10.15) and `NSAppearance.bestMatch(from:)` (macOS 10.14), using the `.aqua`, `.darkAqua`, `.accessibilityHighContrastAqua` and `.accessibilityHighContrastDarkAqua` names [S64].
- The HIG asks for light and dark variants plus an increased-contrast option for every custom colour [S4].

**Note on the increased-contrast variants.** How the system colours the label on a `.glassProminent` or `.borderedProminent` button when Increase Contrast is on is UNVERIFIED. The variants above assume a white label; the earlier light-on-dark value `#A39CFF` (white text 2.40 : 1) is dropped for that reason. Measure all four on device.

### 4.3 Status styles

**Rule: status is always symbol + word, and colour only reinforces it.** The HIG says not to rely on colour alone and to consider what colours mean in different cultures [S4][S5]. The status word is drawn in the label colour, not the hue, for the contrast reasons in §4.4.

The tone colours are SwiftUI system colours: `Color.red`, `.orange` and `.green` (macOS 10.15), plus `.primary` and `.secondary`. The HIG says system colours "already define variants" for light, dark and increased-contrast contexts, and the system colour table lists the increased-contrast values [S4]. Still check on device that the SwiftUI `Color` statics resolve to those values under Increase Contrast.

**Document state: two axes.** The model owns the state; the UI only displays it. It is computed from the document **kind**, the lifecycle (Draft → Issued) and the payments, on two independent axes (RECOMMENDATION):
- **Settlement**: `draft`, `open` (issued, nothing paid), `partlyPaid`, `paid`, `overpaid`, `settledByAdvances` (final invoice whose amount due is 0), `closedUnpaid` (advance closed without payment, screens-flows §2d).
- **`isOverdue`**: past the due date and not settled. It never replaces the settlement; it adds to it.
- Document facts that are not states: `markedForCreditNote` (screens-flows §2d) and, for advances, whether every received payment has its tax document, whether the client's advances need one at all (Q5, ACCT), and which final invoice deducted it.

**Precedence.** When `isOverdue` is true and the settlement is `open` or `partlyPaid`, the badge is Overdue: **word, tone and symbol** (danger), unless it is an advance whose received payment still lacks its tax document (see Label order). Its detail keeps the days overdue and the open balance, so a partly paid overdue invoice never hides what is left. **One detail format in both spec files:** "+12 days · 1 000,00 € left". The days are counted from the due date; the remainder is the open balance in the document currency.

**Label order.** A badge shows one label, chosen in this order: Draft; Marked for credit note (it outranks every settlement word, because the whole document is to be corrected); Closed unpaid; Settled in final invoice; Issued (paid) for a DDPP; an advance's missing tax document (Partly paid – / Paid – tax document missing), which outranks Overdue because the § 28 deadline is the supplier's; Overdue (open or partly paid only); then the settlement label from the table below.

**Labels derived from kind + settlement** (status badges use sentence case in English, §9). The **UI label** is the English word; it is the `defaultValue` in `App/FA/DesignSystem/StatusStyles.swift`. The **Catalog cs (bonus)** column is the `cs` entry that `DesignSystem.xcstrings` keeps. Czech UI is not in scope (§9), so nothing depends on that column.

| Kind | Settlement / fact | Tone | Symbol (macOS since [S85]) | UI label | Catalog cs (bonus) | Detail |
|---|---|---|---|---|---|---|
| any | draft | neutral (`.secondary`) | `pencil.circle` (10.15) | Draft | Koncept | — |
| Invoice, Final | open, not overdue | pending (`.primary`) | `clock` (10.15) | Issued | Vystaveno | "due in 5 days" |
| Advance | open, not overdue | pending (`.primary`) | `clock` (10.15) | Awaiting payment | Čeká na platbu | "due in 5 days" |
| Invoice, Final; Advance with every payment's tax document | partlyPaid | caution (`.orange`) | `circle.lefthalf.filled` (12.0) | Partly paid | Částečně uhrazeno | "1 000,00 € left" |
| Invoice, Final | paid | success (`.green`) | `checkmark.circle.fill` (10.15) | Paid | Uhrazeno | payment date |
| Advance | partlyPaid, a received payment has no tax document yet | caution (`.orange`) | `checkmark.circle.trianglebadge.exclamationmark` (12.0) | Partly paid – tax document missing | Částečně uhrazeno – chybí daňový doklad | "paid 3 days ago · 700,00 € left" |
| Advance | paid or overpaid, a received payment has no tax document yet | caution (`.orange`) | `checkmark.circle.trianglebadge.exclamationmark` (12.0) | Paid – tax document missing | Uhrazeno – chybí daňový doklad | "paid 3 days ago" |
| Advance | paid, tax document issued, not yet deducted | success (`.green`) | `checkmark.circle.fill` (10.15) | Tax document issued | Daňový doklad vystaven | the DDPP number |
| Advance | paid, the client's advances need no tax document (Q5, ACCT) | success (`.green`) | `checkmark.circle.fill` (10.15) | Paid | Uhrazeno | payment date |
| Advance | deducted by an issued final invoice | neutral (`.secondary`) | `checkmark.seal` (10.15) | Settled in final invoice | Zúčtováno v konečné faktuře (wording ACCT, follows "Konečná faktura") | the final invoice number |
| Advance | closedUnpaid | neutral (`.secondary`) | `xmark.circle` (10.15) | Closed unpaid | Uzavřeno – neuhrazeno | the reason (ACCT wording) |
| DDPP | (always paid by definition) | success (`.green`) | `checkmark.circle.fill` (10.15) | Issued (paid) | Vystaveno (uhrazeno) | the advance number |
| Final | settledByAdvances | success (`.green`) | `checkmark.circle.fill` (10.15) | Paid (by advances) | Uhrazeno (zálohami) | — |
| any issued | overpaid | caution (`.orange`) | `plus.circle.fill` (10.15) | Overpaid | Přeplaceno | surplus |
| any issued | `isOverdue` | danger (`.red`) | `exclamationmark.circle.fill` (10.15) | Overdue | Po splatnosti | "+12 days · 1 000,00 € left" |
| Invoice, Final | `markedForCreditNote` (fact) | neutral (`.secondary`) | `flag` (10.15) | Marked for credit note | K opravě dobropisem (ACCT) | the reason; wording ACCT |

Kinds: Invoice = Faktura – daňový doklad; Advance = Zálohová faktura; DDPP = Daňový doklad k přijaté platbě; Final = Konečná faktura (ACCT; §9 glossary).

- **Where the states come from.** The core states follow iDoklad's five, which include *Přeplaceno* (Overpaid), plus Draft [S88]. The brief requires partial payments and overpayments. The advance states come from the advance chain in screens-flows §2d.
- **Overdue and the two "closing" facts.** A `closedUnpaid` advance and a document `markedForCreditNote` are never overdue: they leave the Unpaid and Overdue figures and the attention queue (screens-flows §2a aggregation rules).
- **Orange means "the amount doesn't match, or a step is missing; decide something".** That is why Partly paid, Overpaid, both "tax document missing" states and a Suggested match share it. They are told apart by symbol and word. The Repair mode banner (v0.1.x, §8.18) also uses the caution tone, because every change it allows needs care.
- **Lock glyph.** Every issued document also shows `lock.fill` (10.15) beside its number. This is a fact about the document, not a status, so it is never coloured. While Repair mode is on (v0.1.x), the glyph is `lock.open.fill` (10.15 [S85]) instead, also uncoloured (§8.18).
- Symbol names come from data up to macOS 26 [S85]; check them in the SF Symbols 27 app.

**Bank match state (v0.2)**

| State | Tone | Symbol (macOS since [S85]) | UI label | Catalog cs (bonus) | Extra text |
|---|---|---|---|---|---|
| **Already recorded** | success (`.green`) | `checkmark.circle` (10.15) | Already recorded | Už zaznamenáno | the payment recorded by hand that the line confirms |
| **Matched** | success (`.green`) | `checkmark.circle.fill` (10.15) | Matched | Spárováno | reason: "VS + amount", "Known IBAN", "Manual" |
| **Suggested** | caution (`.orange`) | `checkmark.circle.badge.questionmark` (13.0) | Suggested | Návrh | reason and difference |
| **Unmatched** | pending (`.primary`) | `circle.dashed` (11.0) | Unmatched | Nespárováno | — |
| **Ignored** ("not an invoice") | neutral (`.secondary`) | `minus.circle` (10.15) | Not an invoice | Není faktura | category: Fees, Software, Rent, Tax, Owner |

Already recorded uses the outline `checkmark.circle`, so it is told apart from Matched (`checkmark.circle.fill`) by symbol as well as by word.

The reason labels follow Xero's practice of labelling every reconciled line ("Rule, Match, Memory…") [S89].

### 4.4 Contrast notes

Computed with the WCAG formula from the HIG's default system colour values [S4], against pure white (light) or black (dark):

| System colour | Light vs white | Dark vs black | Increased-contrast light vs white | Increased-contrast dark vs black |
|---|---|---|---|---|
| Red | 3.57 | 6.12 | 4.56 | 7.15 |
| Orange | **2.31** | 9.41 | 4.55 | 10.41 |
| Yellow | **1.51** | 14.87 | 4.59 | 15.85 |
| Green | **2.22** | 10.39 | 4.54 | 11.42 |
| Blue | 3.52 | 6.49 | 4.57 | 9.76 |

**Consequences** (RECOMMENDATION, based on the HIG minimum of 4.5 : 1 for text up to 17 pt and 3 : 1 for bold or 18 pt+ [S5]):

1. **Never set status words or amounts in a system hue in Light Mode.** The default orange, green, blue and red all fall below 4.5 : 1 on white. Hue is reserved for the symbol and a 14 % tinted capsule; the word stays `.primary`.
2. **Orange and green symbols fall below 3 : 1 on white.** That is acceptable only because the word carries the meaning. Never show a symbol-only badge without a tooltip and a VoiceOver label (§8.1).
3. **Yellow is not used for anything** in the app UI.
4. **Under Increase Contrast** every system hue reaches about 4.5 : 1 or more. The badge also adds a 1 pt border (§8.1).
5. **Selected rows.** When a selected, focused row is filled with the accent, the badge drops its tint and goes monochrome. Apple's docs say foreground content "should be adjusted" on increased-prominence backgrounds, such as selected rows in a `List` or `Table` (`backgroundProminence`, macOS 14.0) [S54].
6. **Custom colours.** Aim for 7 : 1 in small text [S6]. Check both appearances and Increase Contrast [S5][S6].

---

## 5. Spacing and layout

### 5.1 Window structure

```
┌ Sidebar ──────────┬ Content: Table ──────────┬ Detail: draft editor / issued view ─┬ Inspector ──────┐
│ Overview          │ Number  Client  Total  … │ totals bar (TotalsPanel, compact)   │ Details|Payments│
│ Documents ▾       │ ───────────────────────  │ header grid: Client · Type ·        │ |Activity       │
│   All · Drafts    │ selection drives detail  │   dates · Currency · Document       │ (derived info:  │
│   Unpaid          │                          │   language · VAT treatment ·        │  rate, VAT recap│
│   Overdue         │                          │   Account · QR · VS                 │  CZK, QR, chain,│
│   This month      │                          │ LineItemsEditor                     │  history)       │
│   Open advances   │                          │ (or the PDF preview: View ▸ Preview)│                 │
│ Clients           │                          │                                     │                 │
│ Payments & Bank ▾ │                          │                                     │                 │
│ Exchange rates    │                          │                                     │                 │
│ Exports & Backup  │                          │                                     │                 │
└───────────────────┴──────────────────────────┴─────────────────────────────────────┴─────────────────┘
```

- **Columns.** One three-column `NavigationSplitView` for every section, plus a trailing `.inspector`. The HIG recommends showing more content "in fewer nested levels" [S29], putting the inspector "on the trailing side of a split view" [S32], and keeping the sidebar to at most two levels [S9]. **On macOS the content column is always displayed** [S61], so no section can drop it. Every section therefore fills the content column, and the detail column shows the selected item (screens-flows §1.2 lists what each section puts where). Overview, for example, puts its tiles and queue in the content column and the selected queue item's document in the detail; with nothing selected, the detail shows a calm `ContentUnavailableView` placeholder.
- **The sidebar** is the one in screens-flows §1.2 (six rows, ⌘1–⌘6). This document does not repeat it.
- **Drafts are edited in place** in the detail column (RECOMMENDATION, given Sasa's few documents a month and the HIG advice to "avoid opening new windows as default behavior unless it benefits your user experience" while offering the option [S32]). Document ▸ Open in New Window and the context menu open the same editor in its own window, which shows editor and live preview side by side.
- **Header fields live in one place:** the editor's header grid, where Tab reaches them. The inspector holds only derived information (rate and source, VAT recap with CZK, payment and QR preview, the document chain, PDF file, activity).
- **Totals placement.** Totals appear in the editor's totals bar and in the inspector, not only at the bottom. The HIG says "Avoid placing controls or critical information at the bottom of a window" [S7].
- **No sidebar footer.** The sidebar bottom holds nothing: no backup button, no licence text [S9].

### 5.2 Spacing scale (4-pt base)

| Token | pt | Use |
|---|---|---|
| `Spacing.xxs` | 2 | Half-step: vertical badge padding; tight two-line stacks (amount over its CZK line, caption under a value) |
| `Spacing.xs` | 4 | Icon-to-label gap, including the badge's symbol-to-word and word-to-detail gaps; compact-badge horizontal padding |
| `Spacing.s` | 8 | Gap between related controls; horizontal badge padding; grid cell spacing |
| `Spacing.m` | 12 | **Padding around bezeled elements** (≈12 pt in the HIG [S5]); inspector row groups |
| `Spacing.l` | 16 | Inspector insets; card padding; space between form groups |
| `Spacing.xl` | 20 | Content-pane margins (editor, Overview) — RECOMMENDATION |
| `Spacing.xxl` | 24 | **Padding around elements without a bezel** (≈24 pt in the HIG [S5]); Overview tile gaps |
| `Spacing.section` | 32 | Between major sections (editor header ↔ line items ↔ notes) |
| `Spacing.page` | 40 | Empty-state block padding; drop-zone inner padding |

### 5.3 Sizes (RECOMMENDATION; tune them on Sasa's display)

| Element | Value | API (macOS) |
|---|---|---|
| Sidebar column | min 180, ideal 210, max 280 | `navigationSplitViewColumnWidth(min:ideal:max:)` 13.0 [S61] |
| Content (Table) column | min 360, ideal 560, max 900. Narrow widths hide the optional columns first (screens-flows §2b). | same |
| Detail column | min 520 (the draft editor's minimum). An A4 page is 595 pt wide at 100 %, so the preview fits it to the width. | same |
| Inspector | min 260, ideal 300, max 400 | `inspectorColumnWidth(min:ideal:max:)` 14.0 [S60] |
| Window | default 1360 × 860, **minimum 1080 × 640**. The column minimums add up to 180 + 360 + 520 = 1060 pt, so at the window minimum all three columns and their dividers still fit. | `defaultSize(width:height:)` 13.0 |
| Narrow windows | **Breakpoint = sum of column minimums + inspector minimum = 1060 + 260 = 1320 pt.** Below it the app closes the inspector (it stays one ⌥⌘I away); the default 1360 pt still shows it. The HIG suggests auto-collapsing the sidebar when the window shrinks [S9], and asks for minimum sizes that keep every divider visible [S10]. Whether SwiftUI closes the inspector by itself at narrow widths is UNVERIFIED, so the app drives it from the window width (RECOMMENDATION). | — |
| Table row height | **The system default at 100 % text; don't override it.** On 26+, lists and tables have "a larger row height and padding" [S1]. The documents table uses single-line rows; the clients list uses two-line rows (name, plus IČO and city). When View ▸ Bigger is above 100 %, the row height follows the scaled line height plus padding (§3 Notes). `defaultMinListRowHeight` exists for `List` (macOS 10.15) [S71]; whether `Table` honours it is UNVERIFIED, so test the scaled rows early. | — |
| Controls | The macOS default control size is 28 × 28 pt and the minimum is 20 × 20 pt [S5]. On a touch-capable Mac, keep control sizes and enlarge only the tap targets [S30]. | `controlSize(_:)` for dense inspectors (RECOMMENDATION; not from [S1]) |
| Sheets | **One approach: `.form` for form sheets, `.fitted` plus an explicit frame where a size matters.** Record Payment, Issue confirmation and New Client use `presentationSizing(.form)` ("appropriate for forms") and size to their content, with no fixed widths. The ČNB import review uses `.fitted` with `frame(minWidth: 560, idealWidth: 640, minHeight: 400, idealHeight: 480)`, so it stays user-resizable; `.fitted` sheets are resizable by default on macOS and a fixed frame makes them non-resizable [S63]. The command palette uses `.fitted` with a fixed 560 pt width. | `presentationSizing(_:)` 15.0 [S63] |
| QR code on the PDF | about 30 mm side, error correction M | QR Platba standard: 29.6–32.8 mm for typical content [S94] |

### 5.4 Corner radii and concentricity

1. **Never set radii on system containers**: windows, sheets, popovers, menus, toolbar glass, the sidebar or the inspector. Window and sheet corner radii changed with macOS 26 [S1], and macOS 27 gave every window "the same tighter corner radius" [S44]. A hard-coded number would be wrong on at least one of those releases.
2. **Shapes nested in a rounded container are concentric.** Use `ConcentricRectangle` or `containerShape(_:)` (both macOS 26.0) [S53]. On 27, `GeometryProxy.concentricCornerRadii` (macOS 27.0) gives the radii [S53]. If you have to compute it: inner radius = max(outer radius − inset, 4).
3. **Standalone content shapes use tokens**: `Radius.s` 4 (inline chips, the QR frame), `Radius.m` 8 (drop zone, small tiles), `Radius.l` 12 (Overview tiles, empty-state cards). Badges are `Capsule`.
4. **Style.** Use `RoundedRectangle(cornerRadius:style:)` with the default `.continuous` style (macOS 10.15).

---

## 6. Materials and Liquid Glass

### Where glass appears: system chrome only, automatically

Standard components pick up Liquid Glass when built with the latest SDK [S1]:
- toolbar and title bar, including the uniform toolbar on 27 when content scrolls under it [S44]
- sidebar and inspector
- sheets, popovers, menus and alerts
- the search field, which sits trailing in the toolbar [S27]
- standard buttons inside bars

On 27 the system also tunes glass diffusion and highlights and offers a Settings slider from "ultra clear" to "fully tinted". Apps get these rendering improvements without recompiling [S44]. New in macOS 27, glass can also "subtly bounce" when clicked, and Apple's advice is that "a little goes a long way" [S47].

### Custom glass: none in v0.1, one element in v0.2 (RECOMMENDATION)

- **v0.1 has no custom glass.** Undoable actions confirm with an **inline result line** (§8.17): plain opaque text plus a borderless "Undo" button at the top of the content pane. Edit ▸ Undo (⌘Z) stays the primary undo.
- **v0.2: the Undo toast (§8.17).** It arrives with the bulk actions (bulk accept, import), where a floating confirmation earns its cost. It is a transient control floating above content, which is the role the HIG gives Liquid Glass: "a functional layer for controls and navigation that floats above content" [S2]. It uses `glassEffect(.regular, in: Capsule())` (macOS 26.0) [S52].
- **Grouping.** Group any future custom glass in a `GlassEffectContainer` for performance [S1][S52].
- **v0.2 adds no other glass.** The "Accept Exact Matches (N)" control is a toolbar item, not a floating bar. That keeps controls out of the window's bottom edge [S7].

### Never glass

- the Table and all its rows
- the line-item editor, `TotalsPanel` and any `MoneyText`
- the PDF preview and the QR code
- status badges, KPI tiles, the VAT table, drop zones, the activity log and the v0.1 inline result line
- the Repair mode banner (v0.1.x, §8.18)

The HIG says: "Don't use Liquid Glass in the content layer" [S2]. Also never use:
- custom backgrounds behind the `NavigationSplitView` sidebar or the toolbar [S1]
- `.clear` glass. The HIG reserves it for components "that appear over visually rich backgrounds" such as photos and videos, and says that if the underlying content is bright, *consider* a dark dimming layer of about 35 % [S2]. The app has no such content.
- `backgroundExtensionEffect()`, because there is no hero imagery

### Scroll edge effect

- Keep the **automatic** style. The HIG says to prefer it, and that the automatic style itself "provides a more opaque visual separation" for top toolbars with many controls, text outside Liquid Glass controls, and pinned table headers [S24]. So there is no need to choose hard for those cases. On macOS 27 the automatic style resolves to hard when free-floating text, such as the window title, sits over it [S47].
- If the Table header looks muddy under the toolbar, set `scrollEdgeEffectStyle(.hard, for: .top)` (macOS 26.0) [S72].
- Use one effect per pane, with equal heights across panes [S24].

### Prominence

Only one prominent control per context, on the trailing side [S8]:
- Draft editor: **Issue…**
- Unpaid issued document: **Record Payment…**
- v0.2 queue: **Accept Exact Matches**

### Accessibility behaviour

| Setting | System chrome | Custom parts of this app (RECOMMENDATION) |
|---|---|---|
| Reduce Transparency | adapts automatically [S1][S5] | v0.2: the Undo toast switches to an opaque `windowBackgroundColor` capsule with a `separatorColor` border (`FloatingSurface` in `App/FA/DesignSystem/FloatingSurface.swift`). Whether system glass already goes opaque for a custom `glassEffect` is UNVERIFIED; keep the fallback until it's checked. v0.1 has no custom glass. |
| Increase Contrast | adapts automatically | Status badges and the Repair mode banner (v0.1.x) add a 1 pt tone border; the accent switches to its high-contrast variant; tiles and the drop zone get a `separatorColor` border. |
| Show Borders (macOS 27) | supported [S44] | When `accessibilityShowBorders` is on (back-deployed, macOS 11.0 listing [S67]), borderless custom buttons (the inline result line's "Undo", inline "Change…", the v0.2 toast) get a border. |
| Liquid Glass slider (27) | — | Test at both ends: ultra clear and fully tinted [S44]. |
| Reduce Motion | — | Fades instead of slides; no animated blur [S5]. |
| Inactive window | — | Custom glass dims through `appearsActive` [S83][S84]. |

---

## 7. Iconography

All symbols are SF Symbols, monochrome by default. Use hierarchical rendering only for status glyphs (`symbolRenderingMode(.hierarchical)`, macOS 12.0). Use filled variants for status and outline variants for toolbars and lists [S21]. Toolbar symbols have no border and no outlined circle [S8].

**Heads-up on naming.** SF Symbols 6 (macOS 15) renamed the `doc.*` family. For example, `doc.text` became `text.document` and `doc.on.doc` became `document.on.document`; the HIG Icons page already uses `document.on.document` for Copy [S20][S85]. With a 26/27 baseline, always use the new names. "HIG" in the table below means the HIG Icons page names that symbol for that action [S20]. "Data" means the name exists in [S85] (data up to macOS 26), so **check it in the SF Symbols 27 app**.

| Concept | Symbol | macOS since | Source |
|---|---|---|---|
| **Sidebar** (rows and labels: screens-flows §1.2 and §5) | | | |
| Overview | `square.grid.2x2` | 10.15 | data |
| Documents | `text.document` | 15.0 | data |
| Clients | `person.2` | 10.15 | data |
| Payments & Bank | `banknote` | 11.0 | data |
| v0.2 child row: one per bank account | `building.columns` | 11.0 | data |
| Exchange rates | `arrow.left.arrow.right` | 11.0 | data |
| Exports & Backup | `externaldrive` | 11.0 | data |
| Filters under Documents: All / Drafts / Unpaid / Overdue / This month / Open advances | `tray.full` (10.15) / `pencil.circle` / `clock` / `exclamationmark.circle` (fixed red tint via `listItemTint`, macOS 11.0 [S66]) / `calendar` (HIG Date) / `document.badge.clock` (15.0, the advance type symbol) | 10.15 unless noted | data |
| **Document types** (printed Czech title in brackets) | | | |
| Invoice – tax document (Faktura – daňový doklad) | `text.document` | 15.0 | data |
| Advance invoice (Zálohová faktura) | `document.badge.clock` | 15.0 | data |
| Tax document for received payment, DDPP (Daňový doklad k přijaté platbě) | `receipt` | **15.2** | data |
| Final invoice, deducts advances (Faktura – daňový doklad (vyúčtování záloh); type name Konečná faktura, ACCT) | `checkmark.seal.text.page` | 15.0 | data |
| Credit note (Phase 2; Czech term ACCT) | to be chosen; must not reuse `arrow.uturn.backward` (Undo) | — | — |
| **Actions** | | | |
| New (pull-down) | `plus` | — | HIG (Add) |
| Issue | `lock.document` | 15.0 | data |
| Record payment | `banknote` | 11.0 | data |
| Duplicate as draft | `plus.square.on.square` | — | HIG (Duplicate) |
| Print | `printer` | — | HIG |
| Save PDF / Export | `square.and.arrow.up` | — | HIG (Share/Export) |
| Show PDF in Finder | `folder` | 10.15 | data. The HIG Icons page maps `folder` to "Move to / Folder", not to Reveal in Finder [S20]; RECOMMENDATION. |
| Delete draft | `trash` | — | HIG |
| Undo / Redo | `arrow.uturn.backward` / `arrow.uturn.forward` | — | HIG |
| Search | `magnifyingglass` | — | HIG |
| Filter | `line.3.horizontal.decrease` | — | HIG |
| Show inspector | `sidebar.right` | 10.15 | data |
| Import file (CNB, statement) | `tray.and.arrow.down` | 10.15 | data |
| Drop target glyph | `arrow.down.document` | 15.0 | data |
| Drop not allowed | `circle.slash` | 12.0 | data; the HIG drag-and-drop page names it [S23] |
| More | `ellipsis` | — | HIG |
| Keyboard shortcuts help | `keyboard` | 10.15 | data |
| **Objects and metadata** | | | |
| Locked / issued | `lock.fill` | 10.15 | data |
| Issued, unlocked in Repair mode (v0.1.x, §8.18) | `lock.open.fill` | 10.15 | data |
| Repair mode banner (v0.1.x, §8.18) | `wrench.and.screwdriver.fill` | 11.0 | data |
| Payment QR | `qrcode` | 10.15 | data |
| Exchange rate | `arrow.left.arrow.right` | 11.0 | data |
| Fallback rate (weekend/holiday) | `calendar.badge.exclamationmark` | 11.0 | data |
| Date | `calendar` | — | HIG |
| Contact person | `person.crop.circle` | — | HIG (Account) |
| Activity note | `text.pad.header` | **26.0** (replaces `note.text`, deprecated in 26) | data |
| Activity (log) | `clock.arrow.trianglehead.counterclockwise.rotate.90` | 15.0 | data |
| Closed advance / marked for credit note | `xmark.circle` / `flag` | 10.15 | data (§4.3) |
| Blocking issue (in the Issue sheet) | `exclamationmark.triangle` | 10.15 | data; the HIG alerts page says to use it sparingly |
| VAT rate | `percent` | 10.15 | data |
| **Status glyphs** | see §4.3 | | data |

- **VAT treatments** (21 %, reverse charge, outside EU) are **text chips without symbols**. No symbol was clear enough, and the HIG prefers text in lists and tables [S12].
- **Menus on macOS 27.** SwiftUI hides menu item symbol images in most contexts by default. Show icons only for object or concept items with `.labelStyle(.titleAndIcon)`, and treat a group uniformly: icons for all items or none [S45][S25]. RECOMMENDATION: action menus (Document, Edit) get no icons; the New ▸ submenu shows the four document-type symbols, because those items are objects.

### App icon concept: "List a pečeť" (sheet and seal). RECOMMENDATION

The concept is original and copies no brand.

- **Format.** One **Icon Composer 2** file [S49][S50]:
  - 1024 × 1024 square, unmasked layers; the system applies the rounded-rectangle mask [S22]
  - at most four groups [S50]
  - vector (SVG or PDF) layers [S22]
- **Background.** A gradient made in Icon Composer [S22], from the accent `#4B3FD6` to a deeper violet.
- **Group 1: the sheet.** A portrait sheet in near-white, centred and slightly inset. Two or three short, thick horizontal bars on it stand for line items. They must be thick, because the system does not apply glass to thin lines when it segments a bitmap [S22].
- **Group 2: the seal.** A solid warm-amber disc overlapping the lower-right corner of the sheet, with a bold filled tick cut out of it. It means "issued and settled". Refraction goes on this layer only [S49].
- **Rules.**
  - No text, no "Kč" or "€", and no QR code: QR modules are thin detail, and the HIG says to avoid text [S22].
  - No baked-in shadows or highlights, because the system draws them [S22].
  - Annotate every appearance the HIG lists for macOS: Default, Dark, Clear light, Clear dark, Tinted light and Tinted dark [S22]. Keep the sheet and seal identical across them; the HIG asks for consistent core features across appearances [S22].
  - Preview both design generations, 26 and 27 [S42][S44].
- **Before finalising,** compare the icon side by side with the icons of competing invoicing apps and Apple's own apps, so it doesn't accidentally look like any of them.

---

## 8. Components

Every component follows the same rules:
- built only from standard controls
- no glass (the v0.2 Undo toast is the one exception)
- all UI strings in English, through the String Catalog (§9); legal and tax strings come only from the §9 legal-strings table
- all numbers formatted through `FormatStyle`

The sketches are illustrative. The basic views they use (`Text`, `Button`, `TextField(_:text:)`, `ForEach`, `HStack`/`VStack`, `Section`, `Divider`) are macOS 10.15+. Lines marked `// verify` call an API or behaviour I could not confirm.

### 8.1 StatusBadge

- **Purpose:** show one document or match state (§4.3) as symbol + word + optional detail.
- **Anatomy:**
  - `Capsule` filled with the tone colour at 14 % opacity
  - an SF Symbol in the tone colour, hierarchical rendering
  - the word in `.primary`, `TextRole.badge`
  - optional detail ("+12 days · 1 000,00 € left") in `.secondary`
- **States:**
  - *regular*
  - *in a selected, focused row* (`backgroundProminence == .increased`, macOS 14.0 [S54]): no tint fill, monochrome symbol. The prominence is read in a custom `ShapeStyle`, as Apple recommends, because a table cell's top-level view may not see the row's value
  - *Increase Contrast*: 1 pt tone border
  - *compact*: symbol only, for narrow columns. Without the flag, the badge falls back by itself when its column is too narrow: full, then word only, then symbol only (`ViewThatFits`, macOS 13.0). The tooltip and the VoiceOver label always carry the **same** text, word plus detail, in the view's locale: `help(Text(verbatim: spoken))` (the `Text` overload of `help(_:)`, macOS 11.0 [S108]), so mouse users don't lose the detail that VoiceOver users hear.
- **Keyboard:** not focusable. Its text joins the row's accessibility label.
- **SwiftUI:** see `StatusBadge` in `App/FA/DesignSystem/`. Usage:

```swift
TableColumn("Status") { row in StatusBadge(row.stateInputs, detail: row.statusDetail) }
// row.stateInputs: DocumentStateInputs from the data layer (not Document.status, which is draft/issued)
// row.statusDetail: "+12 days · 1 000,00 € left"
```

### 8.2 MoneyText

- **Purpose:** show an amount with its currency, tabular digits, trailing alignment, and an optional CZK equivalent on a second line.
- **Anatomy:**
  - primary line: `Decimal` formatted by `Decimal.FormatStyle.Currency(code:locale:)` (macOS 12.0) [S56]
  - secondary line: the CZK equivalent (`TextRole.amountSecondary`), shown only when the currency is not CZK
- **States:**
  - normal; strong (open balance)
  - total (`TextRole.total`)
  - negative (advance deductions): the formatter's own minus sign, never brackets
  - unavailable (CZK line missing because there is no rate): the row shows ExchangeRateRow's warning instead of a fake number
- **Locale (one rule in both spec files):** the **UI locale**, which is the system locale, everywhere in the app, including editor input and the editor's totals bar. The **PDF locale** in the PDF and its preview. The PDF locale is Czech formatting (`cs_CZ`) for both document languages, "Czech" and "Czech + English" (§9; RECOMMENDATION, confirm with Sasa and the accountant). The `locale` parameter is always passed explicitly, because `init(code:locale:)` otherwise defaults to `.autoupdatingCurrent` [S56].
- **Keyboard:** the text is selectable (`textSelection(.enabled)`, macOS 12.0) so Sasa can copy amounts.
- **VoiceOver:** reads the amount with the currency's full name, using `presentation(.fullName)` (macOS 12.0 [S56]), in the UI locale. For example, "1 234,50 euros, 30 862,50 Czech korunas". The exact spoken output is UNVERIFIED.
- **SwiftUI:** see `MoneyText` in `App/FA/DesignSystem/`.

### 8.3 MoneyField

- **Purpose:** enter a `Decimal` amount in the document currency.
- **Anatomy:**
  - a trailing-aligned `TextField` with tabular digits
  - a currency code suffix label ("EUR", "CZK" or "USD", the three v0.1 currencies) outside the text, so Sasa types digits only
  - an inline error line below, in `.callout`
- **Parsing:**
  - `TextField(_:value:format:prompt:)` (macOS 12.0). "If the format style can't parse the input, the bound value remains unchanged" [S57].
  - Whether the value commits on every keystroke or on submit or focus loss is UNVERIFIED; test it.
  - RECOMMENDATION: a tolerant parser in the core module that accepts "1 234,50", "1234,5" and "1234.50", plus regular and non-breaking spaces. The field shows the canonical form after commit.
  - **Separator rule** (RECOMMENDATION, one unit-tested function):
    - Spaces (regular, U+00A0 no-break, U+202F narrow no-break) are always grouping.
    - When both "," and "." occur, the last one is the decimal mark and the other is grouping.
    - When only one of them occurs, once, it is the decimal mark, unless it is the UI locale's grouping separator and exactly three digits follow it. So in an English locale that groups with commas, "1,234" is 1234 and "36,5" is 36.5.
    - A mark that occurs more than once is grouping only when every group after it has exactly three digits. Anything else, such as "1.5." or two decimal marks, is invalid and shows the error state.
    - **Rate fields** (every field that takes an exchange rate: the inline rate form and Change…, §8.9, and the rate sheet behind Add Rate… and Enter Rate…, screens-flows §2g) always read a single "," or "." as the decimal mark. A ČNB rate for EUR or USD is quoted with three decimals and is far below 1 000, so "24,315" is always 24.315.
- **Locale:** typing follows the **UI locale**, Sasa's habit (the §8.2 rule). The PDF locale applies only to the preview and PDF.
- **Format:** the field binds with a plain **number** format, `Decimal.FormatStyle(locale:)` (macOS 12.0 [S107]) with two fraction digits via `precision(_:)` (macOS 12.0 [S107]). It does **not** use `Decimal.FormatStyle.Currency`: a currency style puts the symbol or code into the field text, so the currency would show twice next to the suffix label, and parsing could require the symbol. `Currency` is for read-only display (`MoneyText`).
- **States:**
  - empty (placeholder: zero in the UI locale, such as "0.00" or "0,00")
  - valid
  - invalid: an error next to the field that says how to fix it: "Enter an amount, such as 1 234,50" (the example in the UI locale) [S19][S28]
  - read-only: Issued documents show `LabeledContent` + `MoneyText`, never a disabled field. In Repair mode (v0.1.x, §8.18) they show the normal field.
  - focused
- **Keyboard:**
  - Tab and ⇧Tab move between fields.
  - Return commits (`onSubmit`, macOS 12.0 [S65]).
  - Esc reverts the field. `onExitCommand(perform:)` (macOS 10.15) fires on Esc "while the view has focus"; whether it still fires while a SwiftUI `TextField` is being edited (the field editor may consume Esc) is UNVERIFIED. Prototype it; if it doesn't fire, revert on focus loss or with `onKeyPress(.escape)` (macOS 14.0 [S65]).
  - No ↑/↓ stepping.

```swift
HStack(spacing: Spacing.xs) {
    TextField("Amount", value: $amount,
              format: Decimal.FormatStyle(locale: uiLocale).precision(.fractionLength(2)),  // fractionLength(_:) 12.0 [S107]
              prompt: Text(verbatim: zeroPlaceholder))      // zero in uiLocale
        .multilineTextAlignment(.trailing)
        .monospacedDigit()
        .textFieldStyle(.bordered)            // macOS 27.0; Fallback A: #available branch, §2
    Text(verbatim: currencySuffix).foregroundStyle(.secondary)   // "EUR" / "CZK" / "USD"
}
```

### 8.4 ClientPicker

- **Purpose:** choose the client first; selecting one prefills the draft.
- **Anatomy:**
  - a text field with the app's own suggestion list drawn under it, on every macOS version (v0.1; ADR 0009 amendments). `textInputSuggestions(_:)` and `textInputCompletion(_:)` (macOS 15.0 [S58]) are not used for the client: they have no room for the final New Client row
  - each suggestion shows the name, then "IČO · country · default currency · document language · VAT treatment" in `.secondary`
  - caution chips on suggestions with gaps that would block Issue later: "VAT ID missing", "Address missing"
  - a final suggestion "New Client "…"…", which opens the New Client sheet (screens-flows §2e)
- **Matching:** name, IČO and VAT ID; insensitive to diacritics and case (RECOMMENDATION; the exact folding API is UNVERIFIED). Sort with `.localizedStandard`, the default comparator of `TableColumn.init(_:value:comparator:)` (macOS 13.5) [S81].
- **States:**
  - empty: recent clients first
  - typing: filtered
  - no match: "create" option
  - chosen: the name with the defaults line underneath
  - locked (Issued): plain text
- **Keyboard:**
  - Focus lands here first in a new draft (`defaultFocus`, macOS 13.0).
  - ↓ and ↑ move the highlight through the list; Return takes the highlighted client (the top one until the highlight moves); Tab accepts and moves to the first line's Description.
  - Esc reverts the field to the chosen client, or empties it when none is chosen.
- **VoiceOver** (RECOMMENDATION): the highlighted row carries the selected trait, and moving the highlight announces the client's name and defaults line, so the list is usable without sight.
- **Undo:** "Undo Apply Client Defaults" restores the fields that the client's defaults overwrote [S16].

### 8.5 LineItemsEditor

- **Purpose:** fast, spreadsheet-like entry of invoice lines.
- **Anatomy:**
  - a `Grid` (macOS 13.0) [S78] with a header row
  - columns: # · Description · Qty · Unit · Unit price · Discount · VAT rate · Total
  - **Total** is computed, read-only and trailing (`gridColumnAlignment(.trailing)`)
  - **No currency suffix in the grid cells** (RECOMMENDATION). The document's currency is set once in the header and shows in the totals bar, so the Unit price and Total cells are plain numbers with tabular digits and two decimals ("85,00" in a Czech-format locale). The MoneyField suffix (§8.3) is for standalone amount fields.
  - **VAT rate follows the document's VAT treatment** (document-level rule, RECOMMENDATION; the same rule as screens-flows §2c):
    - *Czech 21 %* (the screens-flows §5 label; printed "Tuzemsko 21 %", §9 table): a text field with suggestions "21", "12" and "0" (keyboard-only, no pop-up to Tab past). Neither reverse charge nor exempt is offered per line: both are document-level treatments (ADR 0009).
    - *EU reverse charge* (printed "EU – přenesená daňová povinnost", §9 table; the default for a new client, §8.12): every line is locked to "RC" (tooltip "EU reverse charge"; RECOMMENDATION, screens-flows §2c); VAT amounts are hidden.
    - *Outside EU* and *Exempt*: ACCT.
    - Mixed documents (some lines reverse charge, some not) only if the accountant confirms them; then TotalsPanel gains a reverse-charge base row.
    - All rate and treatment labels are ACCT strings (§9 legal-strings table).
  - Unit offers suggestions (ks, hod, den, MD, km) plus free text. The unit is document text and prints as typed.
- **Suggestions:** the description cell suggests earlier items with their last unit, price, VAT rate and discount, via `textInputSuggestions` [S58]. Accepting one fills the row.
- **States:**
  - draft: editable
  - issued: read-only text, selectable
  - row invalid: a trailing `exclamationmark.triangle` with a tooltip explaining the fix, and the Issue sheet lists it
  - empty: one blank row with placeholder text
  - **fully empty trailing lines** (e.g. after ↩ on the last row): exist on screen only. All of them are dropped on save and at issue, never counted as invalid and never printed.
- **Keyboard** (RECOMMENDATION; the authoritative map is screens-flows §3.1):
  - **Tab / ⇧Tab** move to the next or previous cell. Tab on the last cell of the last row appends a row. Whether the system Tab order follows `Grid` row order is UNVERIFIED; drive it with `@FocusState` and `focused(_:equals:)` (macOS 12.0) [S65] if not.
  - **Return** moves down one row in the same column. On the last row it appends a new row and focuses its description (`onSubmit`).
  - **Delete Line and Move Line Up / Down have no shortcut in v0.1.** They live in Document ▸ and in the row's context menu. A grid of text fields has no "row focused" state for ⌫, and a menu key equivalent such as ⌘⌫ fires even while a cell's text field is being edited (in Finder ⌘⌫ means "Move the selected item to the Trash" [S106]; what it does inside a text field is UNVERIFIED). Deleting a line can be undone and shows no alert [S15].
  - Reorder by drag with `reorderable()` on the `ForEach`, inside a container that declares `reorderContainer(for:isEnabled:move:)` (both macOS 27.0) [S46][S99]. Fallback A: menu commands only.
  - **No hover-only delete buttons.** The HIG asks for touch-Mac equivalents for hover-only actions [S30]. Use the context menu and the menu bar instead.

```swift
Grid(alignment: .leading, horizontalSpacing: Spacing.s, verticalSpacing: Spacing.xs) {
    GridRow { /* header labels, .textRole(.label), secondary */ }
    ForEach($draft.lines) { $line in                       // verify: binding ForEach
        GridRow {
            TextField("Description", text: $line.text)
                .focused($focus, equals: .text(line.id))
                .textInputSuggestions { /* item history (Suggestions above); macOS 15.0, gate with if #available */ }
            TextField("Unit price", value: $line.unitPrice,
                      format: Decimal.FormatStyle(locale: uiLocale).precision(.fractionLength(2)))  // number style, §8.3
                .multilineTextAlignment(.trailing).monospacedDigit()
                .focused($focus, equals: .price(line.id))
            Text(line.total, format: Decimal.FormatStyle(locale: uiLocale).precision(.fractionLength(2)))  // plain number, no currency suffix (above)
                .monospacedDigit()
                .gridColumnAlignment(.trailing)
        }
        .contextMenu { lineMenu(line.id) }                 // Delete Line, Move Up, Move Down
    }
    .reorderable()                                         // DynamicViewContent, macOS 27.0
}
.reorderContainer(for: LineItem.self) { difference in      // macOS 27.0; verify that Grid acts as the container
    draft.apply(difference)
}
.onSubmit { moveDownOrAppend() }
```

### 8.6 TotalsPanel

- **Purpose:** show every legally relevant total, always visible.
- **Placement:** the top of the inspector, plus the compact totals bar at the top of the editor [S7].
- **Which blocks appear depends on the document kind** (RECOMMENDATION, matching screens-flows §2d):

  | Block | Invoice | Advance | DDPP | Final |
  |---|---|---|---|---|
  | Per-rate block, Rate · Base · VAT | ✓ | ACCT (whether the advance shows a VAT breakdown) | ✓ | ✓ |
  | VAT in CZK + rate line (EUR and USD documents) | ✓ | **never** (no DUZP, no rate) | ✓, rate for the payment date (ACCT) | ✓ |
  | Advances deducted, as negative amounts, with the VAT already taxed in CZK | — | — | — | ✓ |
  | Amount due (printed "K úhradě") | ✓ | ✓ | — (nothing payable) | ✓ |
  | Legal note | "daň odvede zákazník" when the document treatment is EU reverse charge | the not-a-tax-document clause (`DocumentClause.notATaxDocument`, §9 table, ACCT) | — | as Invoice |

- **Anatomy:**
  - **Per-rate block** (`Grid`, trailing columns): Rate · Base · VAT, with a CZK column on EUR and USD tax documents.
  - **Totals:** Base; VAT; **VAT in CZK** (EUR and USD tax documents; the rate line from 8.9 sits right under it); Total.
  - **Final invoice only:** one deduction line per advance, labelled with the advance and DDPP numbers ("Advances deducted"); the printed wording ("Odečet zálohy …") is ACCT.
  - **Amount due**, in `TextRole.total`.
  - **Legal notes** (`TextRole.legalNote`, with a symbol), from the §9 legal-strings table, never typed inline:
    - "daň odvede zákazník", exactly the brief's lowercase string, when the **document's** VAT treatment is EU reverse charge. Whether it may be capitalised at the start of a printed line is ACCT.
    - the not-a-tax-document clause from the §9 table (InvoicingCore `DocumentClause.notATaxDocument`: "Toto není daňový doklad. Daňový doklad bude vystaven po přijetí platby.", ACCT), on an advance invoice
- **States:**
  - draft: live recalculation
  - issued: the lock glyph, values frozen (in Repair mode, v0.1.x: the open lock, values editable, §8.18)
  - missing rate (tax documents only): the CZK cells show "—" and an **inline rate form** "EUR rate for 30. 10. 2026 missing" with a rate field, the needed publication date prefilled, and ↩ to save (the same form as in the Issue sheet, §8.16). Typing the rate here is the v0.1 primary path (§8.9).
  - mismatch: a VAT rounding note
- **Keyboard:** read-only. The values are selectable. Tab skips the panel.
- **Never glass, never colour-coded** (P1).
- **Sums across documents** (Overview tiles, the VAT table, selection totals, the CSV) never add up TotalsPanel values naively. They follow the **aggregation rules** in screens-flows §2a: VAT only from tax documents, advances never as revenue, Unpaid split from unpaid advances.

```swift
Grid(horizontalSpacing: Spacing.m, verticalSpacing: Spacing.xs) {
    ForEach(totals.rates) { r in
        GridRow {
            Text(verbatim: r.rateLabel)
            MoneyText(amount: r.base, currency: cur, locale: loc).gridColumnAlignment(.trailing)
            MoneyText(amount: r.vat, currency: cur, locale: loc, czk: r.vatCZK)
        }
    }
    Divider().gridCellColumns(3)
    GridRow { Text("Amount due").textRole(.sectionTitle).gridCellColumns(2)
              MoneyText(amount: totals.due, currency: cur, locale: loc, role: .total) }
}
```

### 8.7 DocumentTypeChip

- **Purpose:** show the document type in the editor header, the table and the Issue sheet.
- **Anatomy:**
  - the type symbol (§7)
  - a short name, from the screens-flows §5 label table: Invoice · Advance · Tax doc (payment) · Final. If Czech names are ever added (a bonus, not in scope), never use a bare "Záloha", which also means backup.
  - an outline capsule in `separatorColor`
  - **No tint**: a type is not a status (P4).
- **States:**
  - draft: a `Menu` that switches between Invoice, Advance and Final (screens-flows §1.4). Switching is undoable and keeps the lines. A tax document for a received payment is never offered, and on its own draft the chip is static, as when issued (ADR 0009).
  - issued: static, because the type is immutable after issue
  - in the table: symbol only, with a tooltip
- **Keyboard:** in a draft the menu is focusable, and Space opens it. Whether Tab reaches it with Full Keyboard Access off is UNVERIFIED, so Document ▸ Change Type ▸ (with a checkmark on the current type) and the palette offer the same choice without Tab.

```swift
Menu {
    ForEach(DocumentKind.allCases.filter { $0 != .paymentTaxDocument }) { k in Button { kind = k } label: { Label { Text(k.title) } icon: { Image(systemName: k.symbol) } } }
} label: { Label { Text(kind.shortTitle) } icon: { Image(systemName: kind.symbol) } }
.menuIndicator(isDraft && kind != .paymentTaxDocument ? .visible : .hidden)   // menuIndicator macOS 12.0
.disabled(!isDraft || kind == .paymentTaxDocument)
```

### 8.8 QRPreview

- **Purpose:** preview the payment QR exactly as it will print, with the same data in plain text beside it.
- **Why the plain text:** the EPC guideline assumes the data is "also shown at the same time in plain text" [S95].
- **Anatomy:**
  - a square QR image, black on white in both appearances, because it is content
  - a caption with the standard's name: "QR Platba" or "EPC QR (SEPA)"
  - the data block: IBAN, BIC, amount, currency, VS or reference, due date, all selectable
  - a type pop-up, defaulting from the client: QR Platba / EPC QR (SEPA) / None. Build note (v0.1): the client model has no QR-type field and the editor no type pop-up yet; the QR type follows the currency (`PaymentInstructions.standard`) until they exist (screens-flows §2c)
- **Defaults and sizing:**
  - Czech client paying in CZK gets QR Platba; EU client paying in EUR gets EPC (RECOMMENDATION).
  - USD (the third v0.1 currency): which QR standard, if any, fits a USD payment is UNVERIFIED. Until it is checked, a USD document defaults to None (RECOMMENDATION).
  - Error correction M and about 30 mm at print size [S94][S95].
  - The caption wording is not required by either standard (HEURISTIC). Use one name everywhere, in the UI and printed under the code: **"QR Platba"** and **"EPC QR (SEPA)"**.
- **States:**
  - valid (issued documents only)
  - **draft:** no scannable QR, in the app **and in print or Quick Look**. A placeholder box of the same size takes its place, because a draft has no number and no VS yet, so a payment made from its QR could never be matched. In the app's QRPreview (inspector) the placeholder reads "QR after issue" (UI label, screens-flows §5). On the draft PDF (the PDF preview, print and Quick Look) it is document text: "QR po vystavení / QR after issue", or "QR po vystavení" alone on a Czech document (screens-flows §2c, §5).
  - not payable (balance 0, or a DDPP): "No QR – nothing to pay"
  - missing data (no IBAN, BIC or VS): a reason plus "Add Account…", which opens Settings ▸ Bank accounts
  - payload too long: EPC allows at most 331 bytes, and unstructured remittance at most 140 characters [S95]
  - code unavailable on an issued document (the core refuses the payload, or the code can't be generated from it): the PDF prints "QR kód není k dispozici" (with " / QR code unavailable" on a bilingual document) in the code's place, never a silent gap, and the payment details beside it still let the customer pay (ADR 0010)
- **Keyboard:** the type pop-up is focusable. ⌘C on the data block copies the IBAN.
- **VoiceOver:** "QR code for a payment of 1 234,50 euros to account CZ65 …, variable symbol 120260042" (the series-prefixed VS, screens-flows §2i).
- **SwiftUI:** a Core Image QR rendered into an `Image`. The bridging initialiser and `interpolation(.none)` are not in the research, so they're marked `// verify`.

### 8.9 ExchangeRateRow

- **Purpose:** show where every CZK figure comes from (P6), and take the rate Sasa types.
- **v0.1: typing the rate is the primary path.** Sasa's answer in the proposal doc, 5 Nov 2026: "for start everything that nmeeds to be online i willů do manualy, s ill type current cnb rate for each invoice". So Sasa types the ČNB rate on the document, in the draft editor. It is the rate for the DUZP; for a weekend or holiday, the last published rate. Importing a ČNB file is a secondary action in the Exchange rates section (§8.13).
- **Anatomy:**
  - `arrow.left.arrow.right`
  - "1 EUR = 24,315 Kč" (or "1 USD = …") with tabular digits; illustrative values, formatted by the UI locale
  - "ČNB · 30. 10. 2026": always the **rate's own publication date**, never the DUZP or the payment date it is used for. The date comes from `Date.FormatStyle`, never a fixed format string.
  - a source tag: "Typed" or "ČNB file". A typed rate is saved to the same Exchange rates list as imported ones, with source "Typed" (InvoicingCore `ExchangeRateSource.manual`, saved by InvoicingData `RateStore.save`).
- **States:**
  - **missing** (the usual start in v0.1): an inline rate form "EUR rate for 30. 10. 2026 missing" (the document's currency, so "USD rate for …" on a USD document). The rate field takes focus, the needed publication date is prefilled, and ↩ saves. An optional **Open ČNB Rates Page** link may follow (RECOMMENDATION, still open as Q7; screens-flows §2g has its source and the UNVERIFIED sandbox note). A secondary "Import ČNB Rates…" button follows it, and the row also accepts a dropped ČNB file.
  - typed: source "Typed"
  - imported: source "ČNB file"
  - **fallback:** `calendar.badge.exclamationmark` plus "last published rate (weekend/holiday)", for example "ČNB 30. 10., last published" on a DUZP of Saturday 31. 10. 2026.
  - **stale:** the rate's date is more than 7 days before the DUZP (InvoicingCore `DocumentValidator.exchangeRateStaleAfterDays = 7`). This is a warning, not a blocker. The row shows the validator's text, "The exchange rate is from {detail}, more than a week before the date of supply; check that the rate table is complete." ({detail} is the rate's date), and the Issue sheet lists it as a ⚠ Check row (§8.16).
  - issued: frozen, with a lock. In Repair mode (v0.1.x) it shows the open lock and "Change…" works again (§8.18).
- **Which rate applies to a DUZP** (that day's rate, or the previous publication day's, depending on publication time) is a legal rule: ACCT. The resolver is one unit-tested function (screens-flows §2g).
- **Keyboard:** in a draft, "Change…" opens a popover with the rate and date fields; Return saves, Esc cancels.

```swift
LabeledContent {
    VStack(alignment: .trailing, spacing: Spacing.xxs) {
        Text(verbatim: rate.pairText).textRole(.amount)
        HStack(spacing: Spacing.xs) {
            if rate.isFallback { Image(systemName: "calendar.badge.exclamationmark").accessibilityHidden(true)
                                 Text("last published rate") }
            Text(verbatim: rate.sourceAndDate)                   // "ČNB · " + date.formatted(date: .numeric, time: .omitted)
        }.textRole(.caption)
    }
} label: { Text("Rate") }
```

### 8.10 EmptyState

- **Purpose:** say what is missing and offer the one next step [S19].
- **SwiftUI:** `ContentUnavailableView(label:description:actions:)`, macOS 14.0 [S76], with one `.borderedProminent` button (macOS 12.0) and the shortcut shown in the description.
- **Examples:**
  - Documents: "No documents yet" + "New Invoice (⌘N)"
  - Search: `ContentUnavailableView.search`
  - Exchange rates: "No rates yet" + "Rates you type on a document appear here." The one action is "Import ČNB Rates…" as a plain `.bordered` button (macOS 10.15 [S114]), not the prominent style, because importing is the secondary path (§8.9). The FileDropZone sits under it.
  - Overdue: "Nothing overdue" with `checkmark.circle`. This is the only positive empty state, and it is calm, not celebratory [S36].
- **No blocking setup wizard at first launch.** The Overview shows the non-blocking "Getting started" checklist specified in screens-flows §2j. It has no import step: Sasa's current tool is a "poverty self made unsuccesful local app" (Sasa's answer in the proposal doc, 5 Nov 2026), so there is nothing to import. Missing company details are also listed as ⛔ in the Issue sheet [S31]. The HIG also says to avoid alerts at app launch [S15].

```swift
ContentUnavailableView {
    Label { Text("No documents yet") } icon: { Image(systemName: "text.document") }
} description: { Text("Press ⌘N to create your first invoice.") }
  actions: { Button("New Invoice") { newInvoice() }.buttonStyle(.borderedProminent) }
```

### 8.11 Toolbar sets per screen

Each screen has at most three groups and at most one prominent item, on the trailing side [S8]. Search sits trailing in the toolbar [S27]. Every item is also in the menu bar [S8]. **This is the one toolbar table**; screens-flows refers to it.

| Screen | Leading (system) | Centre (customisable) | Trailing |
|---|---|---|---|
| Overview | sidebar toggle, "Overview" | New ▾ | search |
| Documents list | toggle, "Documents", subtitle such as "12 unpaid" (`navigationSubtitle`, macOS 13.0) | New ▾ · Duplicate · Record Payment · Print | search · inspector |
| Draft editor (main-window detail or its own window) | toggle; title: the client name, or "New Invoice" before a client is chosen; subtitle "Draft · Saved" (screens-flows §2c) | Preview toggle · Duplicate | inspector · **Issue…** (prominent) |
| Issued, unpaid | toggle, number | Print · Save PDF · Duplicate | inspector · **Record Payment…** (prominent) |
| Issued, paid | toggle, number | Print · Save PDF · Duplicate | inspector |
| Clients | toggle, "Clients" | New Client · New Document for Client | search · inspector |
| Payments & Bank | toggle, "Payments & Bank" | Record Payment · Filter | search |
| Exchange rates | toggle, "Exchange rates" | Add Rate… · Import ČNB Rates… (secondary; typing on the document is the v0.1 primary path, §8.9) | search |
| Bank statement triage (v0.2) | toggle, statement name | Import Statement… · Filter | search · **Accept Exact Matches (N)** (prominent; the only place for bulk accept) |

Bulk actions on a multi-selection (Save PDFs to Folder…, Export CSV…, Print) live in this toolbar, the menus, the context menu and the inspector's multi-selection view, never in the bottom status bar [S32].

**Implementation**
- **Placement.** Don't use `.primaryAction` for these items: on macOS "the location for the primary action is the leading edge of the toolbar" [S103], while the HIG puts the one prominent action on the trailing side [S8]. Use the default `.automatic` placement, which on macOS places items "in the current toolbar section in order of leading to trailing" [S103]. That the resulting items sit at the trailing edge, next to search and the inspector toggle, is UNVERIFIED; check the result on device and adjust the order. `.principal` is the centre of the toolbar on macOS [S103], which suits nothing here.
- **New ▾:** `Menu(_:content:primaryAction:)` (macOS 13.0). A click makes a new invoice; the menu holds the advance invoice, the DDPP and the final invoice. A pull-down needs at least three items [S35].
- **Grouping:** `ToolbarSpacer(.fixed)` (macOS 26.0) separates groups [S74].
- **Narrow windows:** `visibilityPriority(_:)` (macOS 26.1) keeps New and the prominent item visible longer. `ToolbarItemVisibilityPriority` has `.automatic`, `.low` and `.high`, plus `init(lowerThan:)` and `init(higherThan:)`; lower-priority items move into the overflow menu first [S74].
- **Prominent style:** which SwiftUI style renders the HIG's toolbar `.prominent`, `.glassProminent` (macOS 26.0) or `.borderedProminent`, is UNVERIFIED.
- **Overflow:** don't add an overflow menu by hand [S8].

```swift
.toolbar {
    ToolbarItem {                                          // .automatic (default); not .primaryAction (= leading on macOS)
        Menu("New", content: { newMenuItems }, primaryAction: { newInvoice() })
    }
    .visibilityPriority(.high)                             // macOS 26.1
    ToolbarSpacer(.fixed)
    ToolbarItem { Button { duplicate() } label: { Label { Text("Duplicate") } icon: { Image(systemName: "plus.square.on.square") } } }
    ToolbarSpacer(.fixed)
    ToolbarItem {
        Button("Issue…") { showIssueSheet = true }
            .buttonStyle(.glassProminent)                  // verify which style matches HIG .prominent
            .keyboardShortcut(.return, modifiers: .command)
    }
    .visibilityPriority(.high)
}
// verify on device: the prominent item ends up trailing, after search and the inspector toggle
```

### 8.11a Keyboard map (cross-cutting)

**The one authoritative keyboard map is screens-flows §3.1** (with the single-key table in §3.2). This document keeps no second table, so the two can't disagree. The decisions it records, in short: ⌘N New Invoice · ⇧⌘N New Advance Invoice · ⌥⌘N New Client · ⌘D Duplicate as Draft · ⌘R Record Payment (R in lists) · ⌘↩ Issue… · ⌘K palette · ⌘Y and Space Quick Look · ⌘1–⌘6 sidebar · ⇧⌘= / ⌘− / ⌘0 text size. Add Note, Delete Line and Move Line have no shortcut.

- **Modifiers.** No Control-modifier shortcuts [S13]. Prefer letters with ⌘ or ⇧⌘, and let shortcuts localise to the layout, which is the `.automatic` default of `keyboardShortcut(_:modifiers:localization:)`, macOS 12.0 [S80].
- **Palette.** The palette lists every command with its shortcut on the right, as Raycast does [S91]. `Return` runs the top result.

### 8.12 Inspector panels

- **Container:**
  - `.inspector(isPresented:content:)` (macOS 14.0) [S60] at the `LayoutMetrics.inspector` widths (§5.3); the framework restores its presentation state [S60]
  - toggle: ⌥⌘I and the toolbar's `sidebar.right`
  - tabs: a `.tabs` picker (macOS 27.0) [S75] with **Details · Payments · Activity**; six at most [S10]
  - content: `Form` + `.formStyle(.grouped)` [S1], section headers in title case [S1]
- **Draft document: derived information only.** Every editable header field (Client, Type, Document language, Currency, VAT treatment, dates, Bank account, QR, VS) lives in the editor's header grid (§5.1), where Tab reaches it; the inspector never repeats it. The Details tab shows:
  - TotalsPanel (§8.6)
  - Rate: ExchangeRateRow with its source (tax documents only)
  - VAT recap per rate with CZK
  - payment details and QR preview (QRPreview, draft placeholder)
  - the document chain (screens-flows §2d)
- **Issued document:**
  - the frozen header fields as `LabeledContent` (read-only, selectable) and the lock glyph. In Repair mode (v0.1.x) they become editable fields and the glyph is the open lock (§8.18).
  - "Issued 5. 11. 2026 at 10:42", plus "PDF: Show in Finder"
- **Payments tab:** the list of payments (date, `MoneyText`, CZK difference, source, note) and the "Record Payment…" button.
- **Activity tab:** ActivityLogItems.
- **Client inspector:** defaults (currency, document language, VAT treatment, due days, QR type, fixed VS); contacts; known payer IBANs (v0.2); open balance.
- **Defaults for a new client:**
  - VAT treatment: **EU reverse charge**, because Sasa's clients are "99% EU-EU" (Sasa's answer in the proposal doc, 5 Nov 2026). The client's country and VAT ID then adjust it, as InvoicingCore `CustomerVATStatus.inferred` does. An EU client without a VAT ID gets Czech 21 % with a warning. A client outside the EU gets Outside EU only with a VAT ID, and Czech 21 % without one (screens-flows §2e, ACCT). Czech VAT payers and customers outside the EU stay possible: the treatment is set per client.
  - Payment term: **14 days** (InvoicingCore `Customer`, `paymentTermDays` default 14). Sasa answered "dunno", so this is the build default.
  - Currency: **EUR, CZK or USD**, the v0.1 currencies (Sasa: "for start its enough, you can add dollar").
  - Document language: follows the client's address. A Czech address gives Czech; any other gives Czech + English (InvoicingCore `Customer`).
  - No footer text is printed until Sasa sets one in Settings (Footer text).
- **Naming:** the menu item is "Show Inspector". The HIG Panels page notes that many apps title an inspector panel "Inspector" and name the menu item "Show Inspector" [S11]; that advice is for floating panels, and here the inspector is a split-view column, which the same page also allows [S11].
- **Keyboard:** Control-Tab moves to the next group of controls [S13]. Full Keyboard Access reaches every control.

```swift
enum InspectorTab: Hashable { case details, payments, activity }   // not "Tab": that would shadow SwiftUI.Tab (macOS 15.0) [S109]

.inspector(isPresented: $showInspector) {
    VStack(spacing: 0) {
        Picker("Panel", selection: $inspectorTab) {
            Text("Details").tag(InspectorTab.details)
            Text("Payments").tag(InspectorTab.payments)
            Text("Activity").tag(InspectorTab.activity)
        }
        .pickerStyle(.tabs).labelsHidden()               // macOS 27.0; Fallback A: .segmented
        Form { /* sections for inspectorTab */ }.formStyle(.grouped)
    }
    .inspectorColumnWidth(min: LayoutMetrics.inspector.min, ideal: LayoutMetrics.inspector.ideal, max: LayoutMetrics.inspector.max)
}
```

### 8.13 FileDropZone (ČNB rates file, a secondary action in v0.1; bank statement in v0.2)

- **Purpose:** drag in a file, check it, then commit.
- **v0.1 role: secondary.** Typing the rate on the document is the primary path (§8.9). The ČNB file import stays as a secondary action in the Exchange rates section. It is already built: InvoicingData `RateStore.importDaily` and `RateStore.importYearly`, and the app shell's RatesView (build thread) has the file importer and a coverage view. Imported rates show source "ČNB file"; typed rates show "Typed", in the same list.
- **Anatomy:**
  - a `RoundedRectangle(cornerRadius: Radius.m)` with a 1 pt dashed `separatorColor` stroke
  - the `arrow.down.document` symbol
  - the text "Drop a ČNB rates file (.txt) here", for the daily or the yearly file
  - a secondary line: "or click to choose a file"
  - Clicking opens `fileImporter` (macOS 11.0). It provides security-scoped URLs, which must be started and stopped [S82].
- **States:**
  - idle
  - **targeted, valid:** accent stroke and 8 % accent fill
  - **targeted, invalid:** `circle.slash` + "This file can't be imported"
  - The HIG says to highlight only when the drop is acceptable [S23].
  - The targeted state does not come from `dropDestination(for:isEnabled:action:)`, which has no `isTargeted` parameter; it comes from `onDropSessionUpdated(_:)` (macOS 26.0), which reports the `DropSession` and its phase while the drag is over the view [S101][S62].
  - importing: determinate progress [S34]
  - **review:** an inline summary such as "254 days · EUR, USD · 2 new days" with Import / Cancel
  - imported: a result line with Undo (§8.17)
  - error: the reason and a fix
- **Also a drop target:** the Issue sheet's and TotalsPanel's missing-rate forms accept the ČNB file directly, and re-validate without closing the sheet (screens-flows §2c). There the drop is secondary too: the forms lead with the rate field.
- **Keyboard:** focusable. Return or Space opens the file dialog. The window-wide drop works too.

```swift
RoundedRectangle(cornerRadius: Radius.m)
    .stroke(.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))   // stroke(_:style:) macOS 14.0
    .overlay { dropLabel }
    .dropDestination(for: URL.self) { urls, session in                    // macOS 26.0; verify URL as Transferable
        review(urls)
    }
    .onDropSessionUpdated { session in                                    // macOS 26.0: targeted state from session.phase
        updateTargeted(session)
    }
```

### 8.14 MatchRow (v0.2 matching queue)

- **Purpose:** show one bank line beside its best candidate document, with one-key decisions.
- **Anatomy, three zones:**
  - **Left, the bank line, untouched:** date, `MoneyText`, counterparty name, IBAN, VS, message.
  - **Middle:** StatusBadge (Already recorded / Matched / Suggested / Unmatched / Ignored) plus the reason ("VS + amount") and any difference ("−0,40 Kč, rounding").
  - **Right, the candidate:** number, client, open amount, due date. If there is none: "No suggestion".
  - The layout follows Xero's side-by-side row with one accept per line [S89]. Xero users asked for bulk accept (248 votes); the idea page has shown "in development" since 17 Nov 2025 (status checked 2026-11-05) [S90].
- **States:**
  - exact: pre-ticked and included in the toolbar's bulk "Accept Exact Matches (N)" (also Bank ▸ Accept Exact Matches and the palette)
  - **already recorded:** the bank line matches a payment Sasa recorded by hand (same document or VS, same amount, date within a tolerance, same account). Accepting links the line to that payment instead of creating a second one; it is included in the bulk accept (screens-flows §2f).
  - likely: needs Return
  - none
  - matched
  - ignored: with a category
  - partial or overpaid: the document status updates
- **Keyboard** (list focused, never in text fields [S92]):
  - **Return** accepts.
  - **↓ / ↑** move to the next or previous line.
  - **⌘F** finds another document.
  - **N** means "Not an invoice", which opens a category menu.
  - **S** skips.
  - **⌘Z** undoes the last decision.
- **Data rule:** unmatching never deletes the bank record.
- **SwiftUI:** `onKeyPress(_:action:)` (macOS 14.0) on the focused list [S65]; the action returns `KeyPress.Result`, which has `.handled` and `.ignored` [S102]. If `List`/`Table` are backed by `NSTableView` on macOS (UNVERIFIED), its type-select is on by default (`allowsTypeSelect` defaults to true [S110]) and may eat letter keys before `onKeyPress` sees them. Prototype this on macOS 26/27 first; every single-letter action also has a menu item and a palette command (screens-flows §3.2).

```swift
List(selection: $selected) { ForEach(queue) { MatchRow(item: $0) } }
    .onKeyPress(.return) { accept(selected); return .handled }   // KeyPress.Result: .handled / .ignored
    .onKeyPress("n") { showNotInvoiceMenu(); return .handled }
```

### 8.15 ActivityLogItem

- **Purpose:** the light-CRM timeline on the client page and the document Activity tab ("Activity" everywhere).
- **Anatomy:**
  - a kind symbol: note `text.pad.header`, issued `lock.fill`, payment `banknote`, PDF saved `square.and.arrow.up`, import `tray.and.arrow.down`, repair change `wrench.and.screwdriver.fill` (v0.1.x, §8.18)
  - the text, in Body and selectable
  - a linked document chip (DocumentTypeChip + number)
  - a timestamp in Caption, secondary, formatted with `Date.formatted(date:time:)` (macOS 12.0); the full timestamp is in the tooltip
  - newest first
- **States:**
  - user note: editable and deletable, both undoable, no alert [S15]
  - system event: immutable, secondary style
  - highlighted: the row returns after Undo, scrolled into view [S16]
- **Keyboard:**
  - Return edits a note.
  - Delete removes it (undoable, `onDeleteCommand`).
  - Client ▸ Add Note…, the composer at the top of the timeline, or the palette adds one. Add Note has **no** shortcut: ⌥⌘N is New Client (screens-flows §3.1), and the HIG warns against adding a modifier to an existing shortcut for an unrelated command [S13].

```swift
HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
    Image(systemName: entry.kind.symbol).foregroundStyle(.secondary).accessibilityHidden(true)
    VStack(alignment: .leading, spacing: Spacing.xxs) {
        Text(verbatim: entry.text).textSelection(.enabled)
        Text(verbatim: entry.date.formatted(date: .abbreviated, time: .shortened)).textRole(.caption)
    }
}
.accessibilityElement(children: .combine)
```

### 8.16 IssueSheet: the one deliberate commit

This component is not in the task list, but P2 depends on it.

- **Trigger:** ⌘Return, the prominent toolbar button, or a click on the editor's readiness chip. It is a `.form` sheet sized to its content (§5.3) [S63]. Readiness is shown in exactly two places: this sheet and one chip in the editor's totals bar ("✓ Ready to issue" / "2 problems").
- **Contents, which become immutable** (the full layout and the three severities are in screens-flows §2c):
  - the **number that will be assigned** (`TextRole.documentNumber`)
  - DocumentTypeChip
  - client
  - TotalsPanel (compact), **by document kind** (§8.6):
    - *Invoice*: VAT in CZK and ExchangeRateRow (EUR or USD), QR type
    - *Advance*: no DUZP, no rate, no "VAT in CZK"; the not-a-tax-document clause (§9 table, ACCT); QR type
    - *DDPP*: the rate for its DUZP (the payment date; ACCT), VAT in CZK, no QR
    - *Final*: the block of advances deducted, then Amount due; QR only if something is still payable
  - legal notes
  - a list of **blocking issues** (`exclamationmark.triangle`) that keeps "Issue" disabled until they're fixed [S28]
  - **Missing rate, fixed in place:** when the only blocker is a missing ČNB rate, the row is an inline form, "EUR rate for 30. 10. 2026 missing", with a rate field, the needed publication date prefilled, and ↩ to save. Typing is the v0.1 primary path (§8.9); the typed rate gets source "Typed". The sheet is also a drop target for the ČNB file, as a secondary path. Either way it re-validates without closing.
- **Focus:** when a ⚠ Check row needs the "Checked" checkbox, the checkbox gets initial focus with `defaultFocus` (macOS 13.0 [S65]), so Space ticks it without Tab.
- **Buttons:** **Cancel** on the leading side, and **Issue** on the trailing side as the default (Return). Not the destructive style, because the person deliberately chose to issue [S15]. Esc cancels.
- **No undo afterwards.** That is the point of gapless numbering (P2). The one exception is the audited Repair mode (v0.1.x, §8.18), which logs every change.

### 8.17 Undo confirmation: inline result line (v0.1) and Undo toast (v0.2)

- **Purpose:** confirm an undoable action that took effect immediately (delete a draft, unmatch, delete a note, import; in v0.2 also bulk accept), with a one-click Undo.
- **Edit ▸ Undo (⌘Z) is the primary undo.** It never expires: ⌘Z works at any time, as many times as needed, with named actions [S16]. The visual confirmation is secondary.
- **v0.1: inline result line** (no glass). A plain, opaque line at the top of the content pane, just under the toolbar: `checkmark.circle` + the message ("Draft deleted") + a borderless "Undo" button. It is part of the content, not a floating layer.
- **v0.2: Undo toast.** The same content in a capsule (`FloatingSurface` in `App/FA/DesignSystem/FloatingSurface.swift`, the one custom glass element, §6), for bulk actions where a floating confirmation earns its cost.
- **Shared rules:**
  - The button says "Undo", the same word as the Edit ▸ Undo item.
  - **Placement:** top of the content pane, never at the bottom edge [S7].
  - **Not time-boxed.** The line or toast stays until the next user action in that pane or until it is closed explicitly (its own close button or Esc). It never hides on a timer: the HIG asks to "minimize use of time-boxed interface elements" and to "prefer dismissing views with an explicit action" [S5]. This is unlike Superhuman's 10-second undo [S97].
  - After Undo, scroll to and highlight the restored item [S16].
  - Reduce Motion: fade only [S5].
  - VoiceOver: post an announcement with `AccessibilityNotification.Announcement(_:).post()` (macOS 14.0). `Announcement` has three `init(_:)` overloads, for `String`, `AttributedString` and `NSAttributedString` [S68].
- **Keyboard:** the button doesn't bind ⌘Z again; the Edit menu owns it.

```swift
.safeAreaInset(edge: .top) {                                     // safeAreaInset(edge:alignment:spacing:content:), VerticalEdge, macOS 12.0 [S111]
    if let result {
        HStack(spacing: Spacing.s) {
            Image(systemName: "checkmark.circle").accessibilityHidden(true)
            Text(result.message)
            Button("Undo") { undoManager?.undo() }.buttonStyle(.borderless)
            Spacer()
            Button { self.result = nil } label: { Image(systemName: "xmark") }   // explicit close; Esc too
                .buttonStyle(.borderless).accessibilityLabel(Text("Close"))
        }
        .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.s)
        .background(.background)                                   // opaque in v0.1; v0.2 toast: .modifier(FloatingSurface())
        .transition(.opacity)                                    // verify Transition-protocol .opacity
    }
}
```

### 8.18 RepairModeBanner (v0.1.x)

- **Purpose:** show, at all times, that Repair mode is on. Repair mode is the one audited exception to P2.
- **The decision it follows** (the decisions table in Sasa's proposal doc, last row, 5 Nov 2026): "A Repair mode behind Touch ID or the password will unlock every record, issued documents included; each repair change is written to the audit log, which never leaves the Mac. There is no trace-free mode". It is planned for v0.1.x. The normal fix for a wrong issued document stays a corrective document (Phase 2). This design has no trace-free path.
- **Starting Repair mode:**
  - From a menu command, with no keyboard shortcut and no single key (RECOMMENDATION). File ▸ Repair Mode… (and the palette) opens the entry sheet with a required reason, then authentication. Every change also logs a reason (screens-flows §1.4, §2m).
  - The app calls `LAContext.evaluatePolicy(_:localizedReason:reply:)` (macOS 10.10 [S113]) with `LAPolicy.deviceOwnerAuthentication` (macOS 10.11 [S112]). On macOS that policy authenticates "with Touch ID, Apple Watch, or the user's password". Touch ID goes first when it is available and enrolled; "when these options aren't available, the system prompts the user for … user's password". The dialog's fallback button also asks for the password [S112]. So the password is always a way in.
  - The same policy also tries a nearby paired Apple Watch [S112]. The decision names only Touch ID and the password, so confirm with Sasa that a watch unlock is acceptable.
  - The reason text in the system dialog says what will happen and leaves out the app name, as Apple asks [S113]. Example (RECOMMENDATION): "unlock every record for repair" (screens-flows §2m).
  - Cancel or a failed check changes nothing and shows no extra alert.
- **Placement:** one full-width bar at the top of the main window, under the toolbar and above all three columns. It also appears in every document window opened from it (RECOMMENDATION). Never at the bottom: the HIG says "Avoid placing controls or critical information at the bottom of a window" [S7].
- **Anatomy:**
  - leading `wrench.and.screwdriver.fill` (macOS 11.0, data [S85]) in the caution tone (`.orange`), hierarchical rendering
  - the text **"Repair mode is on. Every change to a locked record is logged."** in `.primary`, Body semibold (`.body.weight(.semibold)`, [S55])
  - trailing, one standard `.bordered` button (macOS 10.15 [S114]): **"End Repair Mode"**. It is not prominent, so the window keeps one prominent action (P4).
  - background: the caution tone at 14 % opacity over opaque `windowBackgroundColor`, like a StatusBadge fill (§8.1); a 1 pt tone border at the bottom under Increase Contrast
- **Tone:** caution (orange), never red, which is only for Overdue (P4). Symbol plus words, never colour alone [S4][S5]. The words stay `.primary`, because the system orange is below 4.5 : 1 on white (§4.4).
- **Never glass.** The bar is opaque, like the v0.1 inline result line (§6, §8.17).
- **Not dismissable while the mode is on:**
  - no close button; Esc does nothing to it; no timer hides it; it never scrolls away
  - "End Repair Mode" ends it (the menu offers the same command). So do 10 minutes without a change (RECOMMENDATION, screens-flows §2m) and quitting (next bullet).
  - quitting the app also ends it, so every launch starts locked (RECOMMENDATION)
  - After a timeout the bar stays and reads "Repair mode ended after 10 minutes without changes" until Sasa closes it (screens-flows §2m). Only then does it get a close button.
- **Issued documents while unlocked:**
  - The `lock.fill` beside the number is replaced by `lock.open.fill` (macOS 10.15, data [S85]). It stays uncoloured, like the lock (§4.3). Tooltip and VoiceOver label: "Unlocked for repair" (RECOMMENDATION).
  - The banner is always visible at the same time, so the open lock never stands alone.
  - Read-only values (`LabeledContent`) become the same editable controls as in a draft (§8.3, §8.9, §8.12).
  - Status badges keep their state; Repair mode is not a document state.
  - When Repair mode ends, `lock.fill` returns and the fields are read-only again.
  - A repaired issued document gets a new PDF. The previous PDF bytes stay with the audit event (screens-flows §2m, RECOMMENDATION). Whether the client needs the new PDF, or a corrective document instead, is ACCT.
- **Every change is logged.** Each repair change is written to the audit log (InvoicingData `auditEvent`; the schema blocks updates and deletes of its rows). The log never leaves the Mac (decision). Backups include the log. How backups, and a cloud-synced backup folder, fit that decision is open for the lead and Sasa (screens-flows §2m). RECOMMENDATION: the document's Activity tab also lists each repair change as an immutable system event with `wrench.and.screwdriver.fill` (§8.15).
- **VoiceOver:**
  - The bar is one container, `accessibilityElement(children: .contain)` (macOS 10.15 [S68][S114]), labelled "Repair mode is on. Every change to a locked record is logged." The "End Repair Mode" button stays its own element.
  - Starting and ending post an announcement with `AccessibilityNotification.Announcement(_:).post()` (macOS 14.0 [S68]): "Repair mode on. Every change is logged." and "Repair mode ended. Records are locked." (RECOMMENDATION).
- **Keyboard:** Tab reaches "End Repair Mode" with Full Keyboard Access; the menu command works without it.

```swift
NavigationSplitView { sidebar } content: { list } detail: { detail }
    .safeAreaInset(edge: .top, spacing: 0) {                       // macOS 12.0 [S111]; verify the bar spans all columns
        if repairMode.isOn {
            HStack(spacing: Spacing.s) {
                Image(systemName: "wrench.and.screwdriver.fill")       // macOS 11.0 [S85]
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(StatusTone.caution.tint)
                    .accessibilityHidden(true)
                Text("Repair mode is on. Every change to a locked record is logged.")
                    .font(.body.weight(.semibold))
                Spacer()
                Button("End Repair Mode") { repairMode.end() }
                    .buttonStyle(.bordered)                            // macOS 10.15 [S114]
            }
            .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.s)
            .background(StatusTone.caution.tint.opacity(0.14))
            .background(Color(nsColor: .windowBackgroundColor))      // opaque; never glass
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Repair mode is on. Every change to a locked record is logged."))
        }
    }
```

Whether a `safeAreaInset` on the `NavigationSplitView` draws one bar under the toolbar across all columns is UNVERIFIED. Prototype it first. If it doesn't, put the same bar in the top inset of each column.

---

## 9. Writing and localisation

**Voice:** calm, exact and brief. These are a finance tool's virtues: trust and stability [S19]. Use verbs on buttons, no "we", no blame, no "Oops" [S19]. Put error text next to the problem and say how to fix it [S19][S28].

### Capitalisation

- **English:** title-style capitalisation for menus, buttons, column headings and toolbar labels [S25][S12]. Sentence case for tooltips, at 60–75 characters at most [S31].
- **Status badges and state words use sentence case in English** ("Partly paid", "Not an invoice", "Paid – tax document missing"), because they are values, not commands (RECOMMENDATION). The String Catalog defaults in `App/FA/DesignSystem/` follow this.
- **Czech** (printed document text, and the catalog's cs bonus entries): capitalise only the first word, because Czech has no title case (RECOMMENDATION). Example: "Zálohová faktura".
- **Ellipsis:** add "…" when a command needs more input [S25].

### Alert and sheet buttons

Use specific verbs ("Issue", "Delete"), never "OK", and always "Cancel" for cancel [S15].

### Glossary (one term, one meaning, used identically in the UI, PDF and CSV)

English comes first, because the UI is English. The Czech column is filled only where the term is printed on documents. For UI-only words, the String Catalog keeps cs entries as a bonus (§4.3); they are not in scope.

| English (UI) | Czech (printed on documents) |
|---|---|
| Invoice – tax document | Faktura – daňový doklad |
| Advance invoice | Zálohová faktura |
| Tax document for received payment (DDPP) | Daňový doklad k přijaté platbě |
| Final invoice | Faktura – daňový doklad (vyúčtování záloh), the printed title (InvoicingCore `DocumentKind.title`); the Czech type name "Konečná faktura" is ACCT |
| Issue / Issued | — |
| Draft | KONCEPT (the watermark "KONCEPT / DRAFT" on every draft PDF, §4.1) |
| Overdue | — |
| Partly paid / Paid / Overpaid | — |
| Awaiting payment / Partly paid – tax document missing / Paid – tax document missing / Tax document issued / Settled in final invoice (cs wording ACCT) / Closed unpaid | — |
| Issued (paid) / Paid (by advances) | — |
| Marked for credit note (cs wording ACCT) | — |
| Variable symbol (VS) | Variabilní symbol (VS) |
| Date of taxable supply | DUZP (ACCT) |
| Reverse charge | the clause "daň odvede zákazník" (Brief); the treatment label "EU – přenesená daňová povinnost" is in the table below (ACCT) |
| Matched / Suggested / Unmatched / Not an invoice / Already recorded | — |
| Activity | — |
| Document language: Czech / Czech + English | — |

### Legal and tax strings: one reviewed table (P7)

Every string printed on a document, or shown in the app with legal or tax meaning, comes from this table and from nowhere else; code references a constant, never a literal. **Brief** = the exact wording from the project brief (approved). **Design** = a printed marker or caption with no legal or tax meaning, worded by the design specs; it needs no accountant check. **ACCT** = "confirm with accountant" until the accountant approves the wording; ACCT strings may be used in drafts and previews, and the app ships v0.1 only once the column says approved. In the English UI a legal or tax string shows its English gloss from this table, or quotes the printed Czech exactly (P7).

| String | Used for | Status |
|---|---|---|
| Faktura – daňový doklad (with an en dash) | title of a regular invoice | Brief |
| Zálohová faktura | title of an advance request | Brief |
| Toto není daňový doklad. Daňový doklad bude vystaven po přijetí platby. / This is not a tax document. A tax document will be issued upon receipt of the payment. | note printed on an advance request (InvoicingCore `DocumentClause.notATaxDocument`) | ACCT |
| Není daňovým dokladem | the brief's short form, not the printed clause; the in-app banner on an advance shows the English "Not a tax document" (screens-flows §5) | Brief |
| Daňový doklad k přijaté platbě | title of a tax document for a received advance | Brief |
| daň odvede zákazník (lowercase, with diacritics) | reverse-charge clause; capitalising it at the start of a printed line is ACCT | Brief |
| IČO · DIČ · spisová značka · VS | identifiers | Brief |
| Konečná faktura | Czech type name of the final invoice; the UI name is "Final invoice" (its PDF title in InvoicingCore `DocumentKind.title` is "Faktura – daňový doklad (vyúčtování záloh)", screens-flows §2d) | ACCT |
| Odečet záloh · Odečteny zálohy zdaněné daňovými doklady č. … (§ 37a zákona o DPH). | caption of the deductions on a final invoice (InvoicingCore `DocumentLabel.advanceDeductions`) and the clause under them (`DocumentClause.advancesDeducted`); each deduction line is the next row | ACCT |
| Odečet zálohy – daňový doklad č. …, platba ze dne …, sazba DPH … % | one deduction line per tax document and VAT rate on a final invoice (InvoicingPDF `PDFStrings.deductionLine`); the rate part is left out when there is none | ACCT |
| Plnění · Základ daně a daň dokladu | VAT summary sub-rows on a final invoice: the supply, then the tax base and VAT of this document after the deducted advances (`PDFStrings`) | ACCT |
| v Kč, kurz … | the VAT summary in CZK with its rate (`PDFStrings.inCZKAtRate`) | ACCT |
| Celkem bez DPH | total before VAT (`PDFStrings.totalExcludingVAT`) | ACCT |
| Cena za MJ s DPH | unit-price caption on a document priced with VAT, a tax document for a received payment, so quantity × price is not read as the tax base (`PDFStrings.unitPriceIncludingVAT`) | ACCT |
| KONCEPT / DRAFT | watermark across every page of a draft PDF; always both languages, a Czech-only draft included (screens-flows §2c) | Design |
| Číslo bude přiděleno při vystavení / number assigned at issue · QR po vystavení / QR after issue | in place of the number and of the QR on a draft PDF (screens-flows §2c; §8.8) | Design |
| QR kód není k dispozici / QR code unavailable | in the QR's place on an issued document whose payment data can't be encoded (§8.8, ADR 0010) | Design |
| QR Platba · EPC QR (SEPA) | caption under the printed QR code (§8.8) | Design |
| pokračování / continued · Banka / Bank | page-continuation marker; bank-name label | Design |
| English gloss of every Brief and ACCT string in this table | bilingual PDF | ACCT |
| DUZP · Datum uskutečnění zdanitelného plnění | date-of-supply label | ACCT |
| Tuzemsko 21 % · EU – přenesená daňová povinnost (PDP) · Mimo EU · Osvobozeno | VAT treatments and per-line rate labels | ACCT |
| Kurzový rozdíl | CZK difference on a payment | ACCT |
| Obchodní firma | label for the legal name | ACCT |
| Dobropis / opravný daňový doklad | credit note (Phase 2) | ACCT |
| K záloze … , platba ze dne … | reference line on a DDPP (core prints `DocumentClause.paymentReceived`) | ACCT |
| Uzavřeno – neuhrazeno · K opravě dobropisem | closing actions (screens-flows §2d); the UI shows them in English (§4.3) | ACCT |
| Zúčtováno v konečné faktuře | status of an advance deducted by an issued final invoice (follows "Konečná faktura"); the UI label is "Settled in final invoice" | ACCT |
| Texts for outside-EU and exempt supplies | PDF notes | ACCT |

The advance note: the brief's short form "Není daňovým dokladem" and the clause InvoicingCore prints (`DocumentClause.notATaxDocument`) differ. The PDF prints the core clause; reconciling the two with the accountant is a follow-up outside the design system (ACCT). If the PDF must print exactly the short form, the change belongs in InvoicingCore `DocumentClause.swift`.

The same applies to the deduction clause and the DDPP reference. InvoicingCore prints `DocumentClause.advancesDeducted` ("Odečteny zálohy zdaněné daňovými doklady č. … (§ 37a zákona o DPH).") and `DocumentClause.paymentReceived` ("Daňový doklad k platbě přijaté dne … na základě zálohové faktury č. …."). Reconcile them with the accountant (ACCT).

- **In the UI** the printed Czech title follows the English name, as in "Advance invoice (Zálohová faktura)", wherever the distinction matters: the type picker and the Issue sheet.
- **Document language** (per document, default from the client): **"Czech"** or **"Czech + English"**. These are InvoicingCore `DocumentLanguage.czech` ("cs", Czech only, for Czech customers) and `.english` ("en", bilingual: Czech first, then English, for foreign customers). On a bilingual document every legal string is in Czech, with the English gloss underneath. The UI label is "Document language". The client default uses the same two values. Czech remains on documents. The UI shows Czech only where it quotes printed text (P7).
- **PDF number and date format:** Czech formatting (`cs_CZ`, e.g. "1 234,50 €", "5. 11. 2026") in both document languages (RECOMMENDATION; confirm with Sasa and the accountant). The English gloss changes words, never number formats.
- The required wording comes from the legal or VAT research and the accountant, not from this document.

### Formatting (no hand-built formats anywhere)

| Data | API (macOS) | Locale |
|---|---|---|
| Money (display) | `Decimal.FormatStyle.Currency(code:locale:)` (12.0) [S56] | UI locale (the system locale) in the app; the PDF locale (`cs_CZ`) in the preview and PDF |
| Money and quantities (input) | `Decimal.FormatStyle(locale:)` (12.0) with `precision(_:)` (12.0) [S107]; never `Currency` in an editable field (§8.3) | UI locale |
| Quantities, rates (display) | `Decimal.FormatStyle(locale:)` (12.0) [S107] | same as money |
| VAT percent | `Decimal.FormatStyle.Percent` (12.0). Czech puts a space before % ("21 %"); confirm the formatter's output | same |
| Dates | `Date.FormatStyle` / `formatted(date:time:)` (12.0) | same |
| CSV for the accountant | Two presets (screens-flows §2h): "For the accountant (Excel CZ)" and "Machine (ISO)". The machine preset uses a fixed `Locale(identifier: "en_US_POSIX")` formatter, ISO dates and "." decimals. Whether the accountant's Excel reads those as numbers is UNVERIFIED and depends on their tool, so the delimiter, decimal mark and encoding of the Excel preset are agreed with the accountant (ACCT). Never the UI locale. | fixed per preset |

- Never concatenate strings. Use full-sentence keys with interpolation in a String Catalog.
- Counts need plural variants: English "1 day / 5 days", and the cs bonus entries "1 den / 2–4 dny / 5 dní". That String Catalogs support plurals is UNVERIFIED in this research; check it in Xcode 27.2.
- **No separate English PDF locale.** Both document languages print Czech number and date formats (above), so there is no `en_*` locale to choose.

### UI language

**English only.** Sasa's answer in the proposal doc, 5 Nov 2026: "en". Sasa's Mac also runs with English as the system language (§2). Sasa's comment: "czech is not needed anywhere. its jsut a very little bonus that i might not use. dont bother if not super easy to implement, maybe version 10.9 or omething ahah".

- The UI is written and tested in English.
- `DesignSystem.xcstrings` keeps its cs entries as a free bonus; the build thread keeps them. Czech UI is not in scope, and nothing in v0.1 depends on those entries.
- There is no in-app language switch. The HIG warns against repeating system settings in the app [S18]. Whether the system's per-app language setting (System Settings ▸ General ▸ Language & Region ▸ Applications [S51]) would pick up the bonus cs entries is UNVERIFIED (screens-flows §2i). That mixed UI is out of scope.
- Czech stays on documents (above); the UI shows it only where it quotes printed text (P7). The **document** language is per document, in the editor's header grid, and never a global setting [S18].

---

## 10. Accessibility checklist

**VoiceOver**
- [ ] Every `MoneyText` reads "amount + full currency name", plus the CZK line on EUR and USD documents (§8.2). Digits are never read one by one.
- [ ] Every StatusBadge reads its word and detail ("Overdue, +12 days · 1 000,00 € left"). Compact badges carry an explicit label (`accessibilityLabel`, macOS 13.0 / `Text` overload 11.0) [S68], and the same text as tooltip.
- [ ] Table rows read as one sentence: "Invoice FV 2026-0042, Acme GmbH, 1 234,50 euros, overdue 12 days" (`accessibilityElement(children: .combine)`) [S68].
- [ ] Every icon-only toolbar button has a label [S1].
- [ ] The QR code has a descriptive label (§8.8).
- [ ] Glyph grids and strips have text: each ČNB coverage-grid day cell has a label such as "4. 11. 2026, rate published, 24,315", with the "Needed rates" text list beneath the grid; the advance chain strip uses SF Symbols and StatusStyle, and each step is a labelled `Link` or `Button` ("Advance ZF 2026-0003, paid") (screens-flows §2d, §2g).
- [ ] The Repair mode banner (v0.1.x) reads "Repair mode is on. Every change to a locked record is logged.", its "End Repair Mode" button is its own element, and starting or ending Repair mode is announced. The open lock reads "Unlocked for repair" (§8.18).
- [ ] If a chart is ever added (v0.1 uses a VAT table instead), it carries `accessibilityChartDescriptor` and titles the main message [S33].
- [ ] Voice Control: "Issue" works on the prominent button; add `accessibilityInputLabels` (macOS 11.0) where a control needs another spoken name.

**Keyboard and Full Keyboard Access**
- [ ] Every action is reachable from the menu bar [S14], including the Window menu with Minimize and Zoom [S14].
- [ ] **FKA on:** turn on Full Keyboard Access in System Settings ▸ Accessibility ▸ Keyboard (the HIG says to turn it on "in the Accessibility area" of Settings [S13]; the HIG keyboard table also lists Control-F1 to toggle it [S13], but the Apple Support shortcuts page of 14 Sep 2026 does not [S106], so don't rely on Control-F1). Tab through the editor, the inspector, sheets and the matching queue.
- [ ] **FKA off pass:** with Full Keyboard Access off, check that every editor control has a path that doesn't depend on Tab reaching it: Document ▸ Currency ▸, Document Language ▸, VAT Treatment ▸, QR ▸ and Change Type ▸ (checkmarked items, also in the palette); per-line VAT is a text field; the Issue sheet checkbox has initial focus. Whether a default setup skips non-text controls when tabbing is UNVERIFIED; test it on Sasa's Mac. The HIG keyboard table lists Control-F7 to "temporarily override the current keyboard access mode" [S13].
- [ ] Single-key shortcuts work only when a list has focus, never in text fields [S92]. Prototype `onKeyPress` on a SwiftUI `Table` on macOS 26/27 before relying on it, because type-select may consume letter keys (§8.14); every single key has a ⌘ chord, a menu item or a palette command.
- [ ] No hover-only affordances. The context menu and menu bar offer every hover action [S30].
- [ ] Test the shortcut map on the **Czech QWERTZ** layout, especially ⌘1…⌘6, ⌘+ (⇧⌘=), ⌘−, ⌘0 and ⌘?, and record the result. On that layout "+" sits unshifted on the 1 key, so ⌘+ and ⌘1 may collide or behave unexpectedly (UNVERIFIED; no Apple page found on Czech key equivalents).

**Contrast and colour**
- [ ] Status words and amounts are never drawn in a hue (§4.4).
- [ ] Text is ≥ 4.5 : 1 up to 17 pt and ≥ 3 : 1 when bold or larger [S5]. Custom colours aim for 7 : 1 [S6]. Measure with Accessibility Inspector [S5].
- [ ] Check both appearances × Increase Contrast × Reduce Transparency, separately and together [S6].
- [ ] Differentiate Without Colour (`accessibilityDifferentiateWithoutColor`, macOS 10.15 [S67]) needs nothing extra, because the symbol and word are always present.

**Motion and transparency**
- [ ] Reduce Motion (`accessibilityReduceMotion`): fades replace slides; no blur animation; no glass bounce on custom elements [S5].
- [ ] Reduce Transparency (`accessibilityReduceTransparency`): v0.2's Undo toast becomes opaque (§6). v0.1 has no custom glass.
- [ ] No time-boxed UI: nothing auto-dismisses on a timer (§8.17) [S5].
- [ ] Show Borders (`accessibilityShowBorders`) on macOS 27: borderless custom buttons get borders [S67].
- [ ] Liquid Glass slider at ultra clear and at fully tinted [S44]. Inactive windows (`appearsActive`) [S83].

**Text**
- [ ] Nothing below 10 pt on screen [S3]. View ▸ Bigger reaches 200 % on every content surface (Table, editor, inspector, Overview, totals, sheets) [S5], with no clipped table rows; test 200 % in the 1080 × 640 minimum window.
- [ ] Sidebar row size follows the system sidebar size setting (small, medium, large) [S9]. Don't fix it.

**Data safety as accessibility**
- [ ] Every destructive action except Issue can be undone. Issue always goes through the sheet and can't be triggered by one key [S15]. Repair mode (v0.1.x) needs Touch ID or the password, has no shortcut, and logs every change (§8.18).

---

## Sources

The research threads opened these on or before 2026-11-05. HIG and developer pages were read as Apple's DocC JSON; the URLs below are the human-readable versions. **[WebFetch]** means the page was read through a summarising fetch, so the wording may differ slightly.

**HIG** (base `https://developer.apple.com/design/human-interface-guidelines/`)
- [S1] Adopting Liquid Glass — https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- [S2] Materials — …/materials
- [S3] Typography — …/typography
- [S4] Color — …/color
- [S5] Accessibility — …/accessibility
- [S6] Dark Mode — …/dark-mode
- [S7] Layout — …/layout
- [S8] Toolbars — …/toolbars
- [S9] Sidebars — …/sidebars
- [S10] Split views; Tab views — …/split-views, …/tab-views
- [S11] Panels — …/panels
- [S12] Lists and tables — …/lists-and-tables
- [S13] Keyboards — …/keyboards
- [S14] The menu bar — …/the-menu-bar
- [S15] Alerts — …/alerts
- [S16] Undo and redo — …/undo-and-redo
- [S17] Sheets — …/sheets
- [S18] Settings — …/settings
- [S19] Writing — …/writing
- [S20] Icons — …/icons
- [S21] SF Symbols — …/sf-symbols
- [S22] App icons — …/app-icons
- [S23] Drag and drop — …/drag-and-drop
- [S24] Scroll views — …/scroll-views
- [S25] Menus — …/menus
- [S26] Context menus — …/context-menus
- [S27] Search fields — …/search-fields
- [S28] Text fields; Entering data — …/text-fields, …/entering-data
- [S29] Designing for macOS — …/designing-for-macos
- [S30] Gestures; Pointing devices (touch-display Mac guidance, 28 Oct 2026) — …/gestures, …/pointing-devices
- [S31] Offering help; Onboarding — …/offering-help, …/onboarding
- [S32] Windows — …/windows
- [S33] Charts — …/charts
- [S34] Loading; Progress indicators; Feedback — …/loading, …/progress-indicators, …/feedback
- [S35] Buttons; Pull-down buttons — …/buttons, …/pull-down-buttons
- [S36] Design principles — …/design-principles

**Platform state**
- [S37] macOS 27 Golden Gate is compatible with these computers — https://support.apple.com/en-us/127255 [WebFetch]
- [S38] macOS Tahoe 26 compatible computers — https://support.apple.com/en-us/122867 [WebFetch]
- [S39] MacBook Pro (14-inch, 2021) technical specifications — https://support.apple.com/en-us/111902 [WebFetch]
- [S40] Apple security releases (release dates) — https://support.apple.com/en-us/100100 [WebFetch]
- [S41] Xcode 27.2 release notes — https://developer.apple.com/documentation/xcode-release-notes/xcode-27_2-release-notes
- [S42] Xcode 27 release notes — https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes
- [S43] UIDesignRequiresCompatibility — https://developer.apple.com/documentation/bundleresources/information-property-list/uidesignrequirescompatibility
- [S44] WWDC26 Platforms State of the Union — https://developer.apple.com/videos/play/wwdc2026/102/
- [S45] macOS 27 release notes — https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes
- [S46] SwiftUI updates (June and September 2026) — https://developer.apple.com/documentation/updates/swiftui
- [S47] WWDC26 "Modernize your AppKit app" — https://developer.apple.com/videos/play/wwdc2026/289/
- [S48] Apple Design Resources (SF Symbols 27 download) — https://developer.apple.com/design/resources/
- [S49] Icon Composer — https://developer.apple.com/icon-composer/
- [S50] Creating your app icon using Icon Composer — https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer
- [S51] Change the language your Mac uses (per-app language) — https://support.apple.com/guide/mac-help/change-the-system-language-mh26684/mac

**API reference** (base `https://developer.apple.com/documentation/`)
- [S52] swiftui/view/glasseffect(_:in:) · swiftui/glasseffectcontainer · swiftui/primitivebuttonstyle/glassprominent
- [S53] swiftui/concentricrectangle · swiftui/view/containershape(_:) · swiftui/geometryproxy/concentriccornerradii · swiftui/edge/corner/style/concentric
- [S54] swiftui/backgroundprominence · swiftui/environmentvalues/backgroundprominence
- [S55] swiftui/font/textstyle · swiftui/font/title2 · …/title3 · …/caption2 · swiftui/font/weight(_:) · swiftui/font/bold() · swiftui/font/monospaceddigit() · swiftui/font/system(size:weight:design:) · swiftui/view/monospaceddigit()
- [S56] foundation/decimal/formatstyle/currency/init(code:locale:) · foundation/decimal/formatted(_:) · foundation/decimal/formatstyle/currency/presentation(_:) · foundation/currencyformatstyleconfiguration/presentation/fullname
- [S57] swiftui/textfield/init(_:value:format:prompt:)-3fh51
- [S58] swiftui/view/textinputsuggestions(_:) · swiftui/view/textinputcompletion(_:)
- [S59] swiftui/table · swiftui/tablecolumncustomization · swiftui/view/contextmenu(forselectiontype:menu:primaryaction:)
- [S60] swiftui/view/inspector(ispresented:content:) · swiftui/view/inspectorcolumnwidth(min:ideal:max:)
- [S61] swiftui/view/navigationsplitviewcolumnwidth(min:ideal:max:) · swiftui/navigationsplitviewvisibility
- [S62] swiftui/view/dropdestination(for:isenabled:action:) · swiftui/dropsession
- [S63] swiftui/view/presentationsizing(_:) · swiftui/presentationsizing/form · swiftui/presentationsizing/fitted
- [S64] appkit/nscolor/init(name:dynamicprovider:) · appkit/nsappearance/bestmatch(from:) · appkit/nsappearance/name-swift.struct/accessibilityhighcontrastaqua · appkit/nscolor/init(srgbred:green:blue:alpha:)-3vuej
- [S65] swiftui/view/onkeypress(_:action:) · swiftui/view/onsubmit(of:_:) · swiftui/view/focused(_:equals:) · swiftui/keyequivalent
- [S66] swiftui/view/listitemtint(_:)
- [S67] swiftui/environmentvalues/accessibilityshowborders · …/accessibilityreducetransparency · …/accessibilityreducemotion · …/colorschemecontrast · …/accessibilitydifferentiatewithoutcolor
- [S68] swiftui/view/accessibilitylabel(_:) · swiftui/view/accessibilityelement(children:) · swiftui/view/accessibilityinputlabels(_:) · accessibility/accessibilitynotification/announcement (lists `init(_:)` for String, AttributedString and NSAttributedString)
- [S69] swiftui/text/init(_:)-1s6o1 (LocalizedStringResource) · foundation/localizedstringresource
- [S70] swiftui/labelstyle/titleandicon
- [S71] swiftui/environmentvalues/defaultminlistrowheight
- [S72] swiftui/view/scrolledgeeffectstyle(_:for:) · swiftui/view/safeareabar(edge:alignment:spacing:content:)
- [S73] swiftui/textfieldstyle/bordered · swiftui/view/textinputbordershape(_:) · swiftui/textfieldstyle/roundedborder
- [S74] swiftui/toolbarspacer/init(_:placement:) · swiftui/toolbarcontent/visibilitypriority(_:)
- [S75] swiftui/pickerstyle/tabs
- [S76] swiftui/contentunavailableview/init(label:description:actions:)
- [S77] swiftui/view/quicklookpreview(_:) · pdfkit/pdfview · swiftui/nsviewrepresentable
- [S78] swiftui/grid · swiftui/view/gridcolumnalignment(_:) · swiftui/view/gridcellcolumns(_:)
- [S79] swiftui/view/alternatingrowbackgrounds(_:)
- [S80] swiftui/view/keyboardshortcut(_:modifiers:localization:) · swiftui/view/keyboardshortcut(_:modifiers:)
- [S81] swiftui/tablecolumn/init(_:value:comparator:)
- [S82] swiftui/view/fileimporter(ispresented:allowedcontenttypes:allowsmultipleselection:oncompletion:)
- [S83] swiftui/environmentvalues/appearsactive
- [S84] WWDC26 "What's new in SwiftUI" — https://developer.apple.com/videos/play/wwdc2026/269/

**Added in the review pass (opened 2026-11-05; base `https://developer.apple.com/documentation/` unless a full URL is given)**
- [S99] swiftui/view/reordercontainer(for:isenabled:move:) · swiftui/view/reordercontainer(for:in:isenabled:move:) · swiftui/dynamicviewcontent/reorderable() (all macOS 27.0; `reorderable()` works "within a reorderable container", "a list, stack, grid, or custom layout")
- [S100] swiftui/view/presentationplacement(_:) · swiftui/presentationplacement (macOS 27.0; `.automatic`, `.center`, `.leading`, `.trailing`; "Only sheet presentations respect this placement")
- [S101] swiftui/view/ondropsessionupdated(_:) (macOS 26.0) · swiftui/dropsession (macOS 26.0)
- [S102] swiftui/keypress/result (macOS 14.0; `.handled`, `.ignored`)
- [S103] swiftui/toolbaritemplacement · …/primaryaction ("In macOS … the location for the primary action is the leading edge of the toolbar") · …/automatic · …/principal
- [S104] Accessing files from the macOS App Sandbox — security/accessing-files-from-the-macos-app-sandbox (security-scoped bookmarks with the User Selected File capability; no separate bookmark entitlement is named)
- [S105] bundleresources/entitlements/com.apple.security.network.client · …/com.apple.security.network.server
- [S106] Apple Support, Mac keyboard shortcuts (published 14 Sep 2026) — https://support.apple.com/en-us/102650 [WebFetch]: Command-Delete = "Move the selected item to the Trash"; Shift-Command-Q, Command-Grave accent, Shift-Command-5, Shift-Command-6 (macOS 27 Siri); no Control-F1 row
- [S107] foundation/decimal/formatstyle · foundation/decimal/formatstyle/init(locale:) · foundation/decimal/formatstyle/precision(_:) (all macOS 12.0) · foundation/decimal/formatstyle/configuration (typealias of NumberFormatStyleConfiguration) · foundation/numberformatstyleconfiguration/precision/fractionlength(_:)-3wkd9 (`static func fractionLength(_ length: Int)`, macOS 12.0) — https://developer.apple.com/documentation/foundation/numberformatstyleconfiguration/precision
- [S108] swiftui/view/help(_:) (macOS 13.0 for the LocalizedStringResource overload; the Text overload, help(_:)-9lm7l, is macOS 11.0; overloads for LocalizedStringResource, LocalizedStringKey, StringProtocol and Text)
- [S109] swiftui/tab (macOS 15.0)
- [S110] appkit/nstableview/allowstypeselect ("The default value of this property is true")
- [S111] swiftui/view/safeareainset(edge:alignment:spacing:content:)-4s51l (`edge: VerticalEdge`, macOS 12.0) — https://developer.apple.com/documentation/swiftui/view/safeareainset(edge:alignment:spacing:content:)-4s51l

**Third-party and standards**
- [S85] SF Symbols name and availability data, mirrored by the SFSafeSymbols project (third-party; data up to the 2025 / macOS 26 release):
  - https://raw.githubusercontent.com/SFSafeSymbols/SFSafeSymbols/stable/SymbolsGenerator/Sources/SymbolsGenerator/Resources/name_availability.plist
  - rename annotations: https://raw.githubusercontent.com/SFSafeSymbols/SFSafeSymbols/stable/Sources/SFSafeSymbols/Symbols/SFSymbol+1.0.swift (and +1.1 … +7.0)
- [S86] Fakturoid — QR kód na faktuře — https://www.fakturoid.cz/podpora/faktury/qr-kod-na-fakture
- [S87] Fakturoid — Variabilní symbol — https://www.fakturoid.cz/podpora/faktury/variabilni-symbol
- [S88] iDoklad — Faktury vydané (statuses incl. Přeplaceno) — https://www.idoklad.cz/podpora/faktury-vydane
- [S89] Xero — reconcile bank transactions (reason labels, confidence) — https://xero.com/us/accounting-software/reconcile-bank-transactions
- [S90] Xero Product Ideas — "Bulk OK" — https://productideas.xero.com/forums/967136-banking-chart-of-accounts/suggestions/44988634-reconciliation-bulk-ok-for-reconciling-bank-tr
- [S91] Raycast — Action Panel — https://manual.raycast.com/action-panel
- [S92] iÚčto — keyboard shortcuts (Aug 2026) — https://www.iucto.cz/app/uploads/2026/08/iucto-klavesove-zkratky.pdf
- [S93] Fakturoid — keyboard shortcuts; navigation palette — https://www.fakturoid.cz/podpora/nastaveni/klavesove-zkratky · https://www.fakturoid.cz/blog/2026/06/29/navigacni-paleta
- [S94] CBA — QR Platba standard v1.2 — https://qr-platba.cz/wp-content/uploads/1645-standard-qr-v1-2-cerven-2021.pdf
- [S95] EPC069-12 v3.0 — EPC QR guidelines — https://europeanpaymentscouncil.eu/sites/default/files/kb/file/2022-09/EPC069-12%20v3.0%20Quick%20Response%20Code%20-%20Guidelines%20to%20Enable%20the%20Data%20Capture%20for%20the%20Initiation%20of%20an%20SCT_0.pdf
- [S96] Fakturoid — párování plateb; nespárované platby — https://www.fakturoid.cz/podpora/automatizace/parovani-plateb-s-bankou · https://www.fakturoid.cz/podpora/automatizace/nesparovane-platby
- [S97] Superhuman — Undo — https://help.superhuman.com/hc/en-us/articles/47278253460499-Undo
- [S98] Things — keyboard shortcuts — https://culturedcode.com/things/support/articles/2785159/

**Added for Sasa's answers: Repair mode (opened 2026-11-05; read as Apple's DocC JSON)**
- [S112] LAPolicy.deviceOwnerAuthentication (macOS 10.11) — https://developer.apple.com/documentation/localauthentication/lapolicy/deviceownerauthentication: "in macOS with Touch ID, Apple Watch, or the user's password"; "If biometry is available, enrolled, and not disabled, the system uses that first"; "In macOS, the system simultaneously looks for a nearby, paired Apple Watch running watchOS 6 or later, and tries to use that in parallel"; "When these options aren't available, the system prompts the user for the device passcode or user's password"; the fallback button "reverts to asking for the device passcode or user's password"
- [S113] LAContext.evaluatePolicy(_:localizedReason:reply:) (macOS 10.10) — https://developer.apple.com/documentation/localauthentication/lacontext/evaluatepolicy(_:localizedreason:reply:): the reason should "provide a clear reason for the authentication request, and describe the resulting action"; "Don't include the app name"
- [S114] swiftui/primitivebuttonstyle/bordered (macOS 10.15) · swiftui/accessibilitychildbehavior/contain (macOS 10.15) — https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/bordered · https://developer.apple.com/documentation/swiftui/accessibilitychildbehavior/contain
