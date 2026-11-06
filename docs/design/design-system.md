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
| P3 | **Keyboard first, never keyboard only** | Every daily action is two keystrokes or fewer from anywhere: ⌘N, ⌘D, ⌘R, ⌘F, ⌘Return, plus ↩, ⌫ and ⎋ in a focused list, where letters type-select. Every command also appears in the menu bar, because the HIG asks for the menu bar to list all commands and every toolbar item [S14][S8]. ⌘K stays free for a later command palette, which would repeat the menus, never replace them. The one authoritative keyboard map is screens-flows §3.1. | swift and quick |
| P4 | **Calm surface, loud only when money needs Sasa** | Chrome stays neutral. There is one accent colour and one prominent action per context [S8][S35]. Red appears only for Overdue. The Overview is a queue of what needs attention, not a gallery of charts. | comfortable, calm |
| P5 | **Native first, custom last** | Use standard `NavigationSplitView`, `Table`, `toolbar`, `Form`, sheets and menus; v0.1 has no inspector column. They pick up Liquid Glass and the macOS 27 refinements automatically [S1][S44]. Add no custom backgrounds to bars or the sidebar [S1]. There is **no** custom glass element in any version (§6). | modern, 2027 ready |
| P6 | **Every number shows where it came from** | Each CZK figure carries its rate, the rate's date and its source ("Typed" or "ČNB file"), and is labelled when the rate is a weekend or holiday fallback. Each bank match carries a reason label, an idea taken from Xero's labels and hover reasoning [S89]. Issued documents show a lock glyph once, in the issued view's lock line. | trustworthy |
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
| **macOS 27.x** (Sasa's Mac: 27.2) | **macOS 27.0** | Nothing; this document assumes it. There are no `#available` branches. The app uses `TextFieldStyle.bordered`, the `.tabs` picker on the client page, `reorderable()` for line items and `concentricCornerRadii`, and it avoids every API deprecated in 27.3. The macOS 27 design refinements come for free: the uniform toolbar under scrolled content, edge-to-edge sidebars, sidebar icons coloured with the accent, and the tighter window radius [S44]. 27.0 is enough because nothing in 27.1 or 27.2 is needed. |
| **Fallback A: macOS Tahoe 26.x.** Not needed for Sasa's Mac, which runs 27.2. It stays as the list of macOS 27.0 `#available` branches. The macOS 14.0 build target needs more: every API above 14.0 is gated. That includes the macOS 26 APIs in Facts above, plus `presentationSizing(_:)` (15.0 [S63]), `textInputSuggestions(_:)` (15.0 [S58]), `visibilityPriority(_:)` (26.1 [S74]) and `onDropSessionUpdated(_:)` (26.0 [S101]). The §7 symbols marked 15.0, 15.2 or 26.0 also need a macOS 14 fallback symbol. | **macOS 26.1** (not 26.0, so that `visibilityPriority(_:)`, macOS 26.1 [S74], needs no gate) | Same layout and tokens. Every API below is macOS 27.0 in the docs and needs an `if #available(macOS 27, *)` branch (or a `@available` wrapper view):<br>- `TextFieldStyle.bordered` / `textInputBorderShape(_:)` [S73]: fall back to the default style, without the deprecated `.roundedBorder`<br>- `reorderable()` + `reorderContainer(for:isEnabled:move:)` [S46][S99]: line items reorder through menu commands only, with no drag<br>- `PickerStyle.tabs` [S75]: the client page uses a `TabView`<br>- `GeometryProxy.concentricCornerRadii` [S53]: compute the radius with `Radius.concentric(outer:inset:)`<br>- `NSMenuItem.preferredImageVisibility` [S45]: menus keep the 26 icon behaviour<br>If Fallback A has to target 26.0 after all, `visibilityPriority(_:)` also needs an `if #available(macOS 26.1, *)` gate.<br>The app looks "Tahoe", not "Golden Gate". To build on that Mac with Xcode 27.2 it must run 26.6 or later [S41]. |
| **Fallback B: macOS 14 or 15** | Does not apply: Sasa's Mac runs 27.2. | No Liquid Glass APIs are available [S52]. `ToolbarSpacer` groups become plain items, and the v0.2 drop zone uses the drop API that is deprecated in 27.3. Xcode 27.2 can't run on that Mac [S41], so builds happen on another Apple-silicon Mac. |

**Baseline statement (used in screens-flows §0.1 and Q1):** the design targets macOS 27.0, because Sasa's Mac runs macOS 27.2. The app builds for macOS 14.0 until CI builds with Xcode 26 or later.

**Build decision (agreed with the build thread):** the app keeps targeting **macOS 14.0**, with `#if compiler(>=6.2)` and `if #available` gates. CI runs on the `macos-15` runner and has built with Xcode 26.3 (the macOS 26 SDK) since the build's PR 20 ([README.md](README.md), Platform policy; `.github/workflows/ci.yml`). The target is still macOS 14.0 on main; when to raise it is the build's call. 27.0 stays the design recommendation for that raise. The macOS 27.0 APIs in the first row need the macOS 27 SDK, which ships with Xcode 27 [S41]. So a raise made on Xcode 26 can reach at most Fallback A (macOS 26.1). Sasa's Mac is not in Fallback B, but on macOS 14 and 15 the gated fallbacks are the ones the Fallback B row lists.

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
| Form and sheet section headers | (system) | `Section` header; title case, not all caps [S1] | system | — | system |
| Document number in the issued view header ("FV 2026-0042") | `.documentNumber` | `.title3.weight(.semibold).monospacedDigit()` | 15 / 20 Semibold | tabular | primary, selectable |
| Table cells, form values, labels | `.body` / `.label` | `.body` | 13 / 16 | — | primary |
| Amounts in table cells | `.amount` | `.body.monospacedDigit()` | 13 / 16 | tabular, trailing | primary |
| Invoice number, VS and IBAN cells | `.amount` | `.body.monospacedDigit()` | 13 / 16 | tabular | primary |
| Emphasised amount (open balance in a row) | `.amountStrong` | `.body.weight(.semibold).monospacedDigit()` | 13 / 16 Semibold | tabular | primary |
| Second line in a row (IČO, client city, "due in 5 days"); the client defaults line, the closing reason line, Stock's "Counted 3 weeks ago" | `.rowSecondary` | `.subheadline` | 11 / 14 | — | secondary |
| CZK equivalent under an EUR or USD amount | `.amountSecondary` | `.subheadline.monospacedDigit()` | 11 / 14 | tabular | secondary |
| Totals rows (base, VAT per rate); Stock quantity cells (On Hand, history) and the Numbering "Next number" line | `.amount` | `.body.monospacedDigit()` | 13 / 16 | tabular | primary |
| Grand total ("Amount due"; the PDF prints "K úhradě") | `.total` | `.title3.weight(.semibold).monospacedDigit()` | 15 / 20 Semibold | tabular | primary |
| Overview KPI figure; Stock's on-hand figure in the item header | `.kpi` | `.largeTitle.bold().monospacedDigit()` | 26 / 32 Bold | tabular | primary |
| Status badge text | `.badge` | `.callout.weight(.medium)` | 12 / 15 Medium | — | primary |
| In-app legal notices (the printed clauses, quoted exactly: "daň odvede zákazník", the not-a-tax-document note on an advance; strings from the §9 legal-strings table); the issued view's lock line | `.legalNote` | `.callout` | 12 / 15 | — | primary, never secondary |
| Captions: rate source, timestamps, hints | `.caption` | `.caption` | 10 / 13 | — | secondary |

### Notes

- **Floor.** 10 pt is the on-screen minimum [S3]. Legal notices are never set below Callout (12 pt) in the app.
- **Text enlargement.** The HIG asks that people can enlarge text by at least 200 % [S5], and macOS has no Dynamic Type, so the app does it itself (RECOMMENDATION). Add View ▸ Bigger (⇧⌘=, which the keyboard table lists as "Increase the size of the selection") and View ▸ Smaller (⌘−) [S13], plus Actual Size (⌘0; see screens-flows §3.1). They scale **every content surface** from 100 % to 200 % in steps, from one app-wide scale value: the Table, the editor, the issued view, the Overview, `TotalsPanel` and sheet content. The amounts Sasa most needs to read live in the issued view, the totals and the Overview, so none of them stays at 100 %. System chrome (toolbar, sidebar, menus) keeps the system sizes. The mechanism is `Font.system(size:weight:design:)` (macOS 13.0 [S55]), fed with the HIG sizes above times the scale. The one app-wide scale value is the SwiftUI environment value `textScale` (1 to 2, `DesignTokens.swift`): the app sets `.environment(\.textScale, …)` once at the scene root, and `textRole(_:)`, `MoneyText` and `StatusBadge` read it, so callers never pass a scale by hand. Whether system-size text keeps the text-style tracking is UNVERIFIED; compare it on device. When the scale isn't 1, table row height follows the scaled line height plus padding (§5.3), so text never clips. Test 200 % in the minimum window (§5.3).
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
- **AccentColor (fill)**: the table above. Used for the prominent action, selection and, from v0.2, the drop-zone highlight.
- **Links and any accent-coloured text**: system `linkColor` (§4.1), never the AccentColor.
- **Check on device first.** If the system turns out not to draw white text on the raw accent, re-measure with Accessibility Inspector before changing anything else.

**Why ink indigo**
- It is clearly separate from the status hues: red and orange, plus neutral grey. The app UI has no green. That keeps "one colour, one meaning" [S4].
- It avoids the default blue that most apps use.
- It reads as calm and trustworthy for a money app.

**Where it appears.** The system applies the app accent to buttons, selection highlights and sidebar icons, but only when the person's General ▸ Accent colour setting is *multicolor*; otherwise the person's choice wins [S4]. On macOS 27, sidebar icons use the accent colour again [S44]. In v0.1 the app adds accent in two places: the one prominent action per context, and the app icon (from v0.2 also the drop-zone highlight). Links use `linkColor`.

**How to define it**
- Preferred: an `AccentColor` colour set in the asset catalog with Any, Dark and High Contrast variants, so the system supplies the variants. Asset-catalog high-contrast slots are UNVERIFIED; check them in Xcode 27.2.
- In code: `App/FA/DesignSystem/` keeps a reviewable twin built with `NSColor(name:dynamicProvider:)` (macOS 10.15) and `NSAppearance.bestMatch(from:)` (macOS 10.14), using the `.aqua`, `.darkAqua`, `.accessibilityHighContrastAqua` and `.accessibilityHighContrastDarkAqua` names [S64].
- The HIG asks for light and dark variants plus an increased-contrast option for every custom colour [S4].

**Note on the increased-contrast variants.** How the system colours the label on a `.glassProminent` or `.borderedProminent` button when Increase Contrast is on is UNVERIFIED. The variants above assume a white label; the earlier light-on-dark value `#A39CFF` (white text 2.40 : 1) is dropped for that reason. Measure all four on device.

### 4.3 Status styles

**Rule: status is always symbol + word, and colour only reinforces it.** The HIG says not to rely on colour alone and to consider what colours mean in different cultures [S4][S5]. The status word is drawn in the label colour, not the hue, for the contrast reasons in §4.4.

**Three tones** (RECOMMENDATION): neutral (`.secondary`), caution (`.orange`) and danger (`.red`, Overdue only). The tone colours are SwiftUI system colours: `Color.red` and `.orange` (macOS 10.15), plus `.secondary`. **The app UI has no green**: the Getting started ticks, the result line's done symbol, "Bank account removed" and the sheet confirmations use `.secondary`. **Red appears in three places, all for Overdue**: the badge, the Unpaid sidebar row's fixed red tint (screens-flows §1.2), and the Overview queue's Overdue row. The "Data can't be opened" banner uses the caution tone (screens-flows §2a). The HIG says system colours "already define variants" for light, dark and increased-contrast contexts, and the system colour table lists the increased-contrast values [S4]. Still check on device that the SwiftUI `Color` statics resolve to those values under Increase Contrast.

**Document state: two axes.** The model owns the state; the UI only displays it. It is computed from the document **kind**, the lifecycle (Draft → Issued) and the payments, on two independent axes (RECOMMENDATION):
- **Settlement**: `draft`, `open` (issued, nothing paid), `partlyPaid`, `paid`, `overpaid`, `settledByAdvances` (final invoice whose amount due is 0), `closedUnpaid` (advance closed without payment, screens-flows §2d).
- **`isOverdue`**: past the due date and not settled. It never replaces the settlement; it adds to it.
- Document facts that are not states: `markedForCreditNote` (screens-flows §2d) and, for advances, whether every received payment has its tax document, whether the advance needs one at all (not for EU goods, the build's ADR 0012; other treatments Q5, ACCT), and which final invoice deducted it or settled it as "Paid in advance".

**Precedence.** When `isOverdue` is true and the settlement is `open` or `partlyPaid`, the badge is Overdue: **word, tone and symbol** (danger), unless it is an advance whose received payment still lacks its tax document (see Label order). Its detail keeps the days overdue and the open balance, so a partly paid overdue invoice never hides what is left. **One detail format in both spec files:** "+12 days · 1 000,00 € left". The days are counted from the due date; the remainder is the open balance in the document currency.

**Label order.** A badge shows one label, chosen in this order: Draft; Marked for credit note (it outranks every settlement word, because the whole document is to be corrected); Closed unpaid; Settled in final invoice; Paid for a DDPP; an advance's missing tax document (Partly paid – / Paid – tax document missing), which outranks Overdue because the § 28 deadline is the supplier's; Overdue (open or partly paid only); then the settlement label from the table below. That gives **13 labels** in all.

**Labels derived from kind + settlement** (status badges use sentence case in English, §9). The **UI label** is the English word; it is the `defaultValue` in `App/FA/DesignSystem/StatusStyles.swift`. The **Catalog cs (bonus)** column is the `cs` entry that `DesignSystem.xcstrings` keeps. Czech UI is not in scope (§9), so nothing depends on that column.

| Kind | Settlement / fact | Tone | Symbol (macOS since [S85]) | UI label | Catalog cs (bonus) | Detail |
|---|---|---|---|---|---|---|
| any | draft | neutral (`.secondary`) | `pencil.circle` (10.15) | Draft | Koncept | — |
| Invoice, Final | open, not overdue | neutral (`.secondary`) | `clock` (10.15) | Issued | Vystaveno | "due in 5 days" |
| Advance | open, not overdue | neutral (`.secondary`) | `clock` (10.15) | Awaiting payment | Čeká na platbu | "due in 5 days" |
| Invoice, Final; Advance with every payment's tax document, or needing none | partlyPaid | caution (`.orange`) | `circle.lefthalf.filled` (12.0) | Partly paid | Částečně uhrazeno | "1 000,00 € left" |
| Invoice, Final | paid | neutral (`.secondary`) | `checkmark.circle.fill` (10.15) | Paid | Uhrazeno | payment date |
| Final | settledByAdvances | neutral (`.secondary`) | `checkmark.circle.fill` (10.15) | Paid | Uhrazeno | "by advances" |
| DDPP | (always paid by definition) | neutral (`.secondary`) | `checkmark.circle.fill` (10.15) | Paid | Uhrazeno | the advance number |
| Advance | paid, needs no tax document (EU goods, the build's ADR 0012; other treatments Q5, ACCT) | neutral (`.secondary`) | `checkmark.circle.fill` (10.15) | Paid | Uhrazeno | payment date |
| Advance | partlyPaid, a received payment has no tax document yet | caution (`.orange`) | `checkmark.circle.trianglebadge.exclamationmark` (12.0) | Partly paid – tax document missing | Částečně uhrazeno – chybí daňový doklad | "paid 3 days ago · 700,00 € left" |
| Advance | paid or overpaid, a received payment has no tax document yet | caution (`.orange`) | `checkmark.circle.trianglebadge.exclamationmark` (12.0) | Paid – tax document missing | Uhrazeno – chybí daňový doklad | "paid 3 days ago" |
| Advance | paid, tax document issued, not yet deducted | neutral (`.secondary`) | `checkmark.circle.fill` (10.15) | Tax document issued | Daňový doklad vystaven | the DDPP number |
| Advance | deducted, or settled as "Paid in advance", by an issued final invoice | neutral (`.secondary`) | `checkmark.seal` (10.15) | Settled in final invoice | Zúčtováno v konečné faktuře (wording ACCT, follows "Konečná faktura") | the final invoice number |
| Advance | closedUnpaid | neutral (`.secondary`) | `xmark.circle` (10.15) | Closed unpaid | Uzavřeno – neuhrazeno | the reason (ACCT wording) |
| any issued | overpaid | caution (`.orange`) | `plus.circle.fill` (10.15) | Overpaid | Přeplaceno | surplus |
| any issued | `isOverdue` | danger (`.red`) | `exclamationmark.circle.fill` (10.15) | Overdue | Po splatnosti | "+12 days · 1 000,00 € left" |
| Invoice, Final | `markedForCreditNote` (fact) | neutral (`.secondary`) | `flag` (10.15) | Marked for credit note | K opravě dobropisem (ACCT) | the reason; wording ACCT |

On main the DDPP reads "Issued (paid)" and the settled final invoice "Paid (by advances)" (`StatusStyles.swift`); both become Paid, with the detail above, so the labels go from 15 to 13.

**Stock (when Stock ships, screens-flows §2n).** One more badge, not a document state: **Low**, caution (`.orange`), `arrow.down.circle` (10.15 [S85]), only on the On Hand cell of an item at or below its reorder level. The Stock sidebar badge is a plain, untinted count. A quantity below zero ("−5 ks") is `.secondary` text, never red, and "Counted 3 weeks ago" is plain `.rowSecondary` text, never a tone.

Kinds: Invoice = Faktura – daňový doklad; Advance = Zálohová faktura; DDPP = Daňový doklad k přijaté platbě; Final = Konečná faktura (ACCT; §9 glossary).

- **Where the states come from.** The core states follow iDoklad's five, which include *Přeplaceno* (Overpaid), plus Draft [S88]. The brief requires partial payments and overpayments. The advance states come from the advance chain in screens-flows §2d.
- **Overdue and the two "closing" facts.** A `closedUnpaid` advance and a document `markedForCreditNote` are never overdue: they leave the Unpaid and Overdue figures and the attention queue (screens-flows §2a aggregation rules).
- **Orange means "the amount doesn't match, or a step is missing; decide something".** That is why Partly paid, Overpaid, both "tax document missing" states and a Suggested match share it. They are told apart by symbol and word. The Repair mode banner (v0.1.x, §8.18) also uses the caution tone, because every change it allows needs care.
- **Lock glyph.** The issued view's lock line carries `lock.fill` (10.15), once per issued document; the tables, the issued view header, the totals and the frozen fields show no lock (§8.18). This is a fact about the document, not a status, so it is never coloured. While Repair mode is on (v0.1.x), the glyph is `lock.open.fill` (10.15 [S85]) instead, also uncoloured (§8.18).
- Symbol names come from data up to macOS 26 [S85]; check them in the SF Symbols 27 app.

**Bank match state (v0.2; used only in the gallery for now)**

| State | Tone | Symbol (macOS since [S85]) | UI label | Catalog cs (bonus) | Extra text |
|---|---|---|---|---|---|
| **Already recorded** | neutral (`.secondary`) | `checkmark.circle` (10.15) | Already recorded | Už zaznamenáno | the payment recorded by hand that the line confirms |
| **Matched** | neutral (`.secondary`) | `checkmark.circle.fill` (10.15) | Matched | Spárováno | reason: "VS + amount", "Known IBAN", "Manual" |
| **Suggested** | caution (`.orange`) | `checkmark.circle.badge.questionmark` (13.0) | Suggested | Návrh | reason and difference |
| **Unmatched** | neutral (`.secondary`) | `circle.dashed` (11.0) | Unmatched | Nespárováno | — |
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

1. **Never set status words or amounts in a system hue in Light Mode.** The default orange, blue and red all fall below 4.5 : 1 on white. Hue is reserved for the symbol and a 14 % tinted capsule; the word stays `.primary`.
2. **Orange symbols fall below 3 : 1 on white.** That is acceptable only because the word carries the meaning. Never show a symbol-only badge without a tooltip and a VoiceOver label (§8.1).
3. **Yellow is not used for anything** in the app UI.
4. **Under Increase Contrast** every system hue reaches about 4.5 : 1 or more. The badge also adds a 1 pt border (§8.1).
5. **Selected rows.** When a selected, focused row is filled with the accent, the badge drops its tint and goes monochrome. Apple's docs say foreground content "should be adjusted" on increased-prominence backgrounds, such as selected rows in a `List` or `Table` (`backgroundProminence`, macOS 14.0) [S54].
6. **Custom colours.** Aim for 7 : 1 in small text [S6]. Check both appearances and Increase Contrast [S5][S6].

---

## 5. Spacing and layout

### 5.1 Window structure

```
┌ Sidebar ──────────┬ Content: Table ──────────┬ Detail: draft editor / issued view ─────┐
│ Overview          │ Number  Client  Total  … │ chain line (in an advance chain)        │
│ Documents         │ ───────────────────────  │ header grid: Client · Issue date ·      │
│   Drafts          │ selection drives detail  │   (Period) · DUZP · Due · Currency ·    │
│   Unpaid          │                          │   VAT treatment · Bank account          │
│   Open advances   │                          │ LineItemsEditor                         │
│ Clients           │                          │ totals bar (TotalsPanel, compact)       │
│ Payments          │                          │ (or the PDF preview: View ▸ Preview)    │
│ Stock (later)     │                          │                                         │
└───────────────────┴──────────────────────────┴─────────────────────────────────────────┘
```

- **Columns.** One three-column `NavigationSplitView` for every section, with **no inspector** in any section (screens-flows §1.2). The HIG recommends showing more content "in fewer nested levels" [S29] and keeping the sidebar to at most two levels [S9]. **On macOS the content column is always displayed** [S61], so no section can drop it. Every section therefore fills the content column, and the detail column shows the selected item (screens-flows §1.2 lists what each section puts where). Overview, for example, puts its tiles and queue in the content column and the selected queue item's document in the detail; with nothing selected, the detail shows a title-only `ContentUnavailableView` placeholder ("Select a document"), with no symbol. Real empty states keep their symbol and their one action.
- **The sidebar** is the one in screens-flows §1.2: Overview ⌘1, Documents ⌘2 (one selectable row, with Drafts, Unpaid and Open advances indented under it), Clients ⌘3, Payments ⌘4, and Stock ⌘5 once it ships; ⌘6 is unassigned. This document does not repeat it.
- **Drafts are edited in place** in the detail column (RECOMMENDATION, given Sasa's few documents a month and the HIG advice to "avoid opening new windows as default behavior unless it benefits your user experience" [S32]). v0.1 has one main window and no document window (screens-flows §1.1).
- **Header fields live in one place:** the editor's header grid, where Tab reaches them (screens-flows §2c). Type and document language change through the Document menu, the VS is assigned at Issue, and the QR follows the currency, so none of them is a header row. An issued document shows its frozen values (DUZP, rate with date and source, VAT in CZK, account and VS, the language · treatment line) as selectable figures in the issued view (screens-flows §2b).
- **Totals placement.** Totals appear in the editor's totals bar and in the issued view's figures, not only at the bottom. The HIG says "Avoid placing controls or critical information at the bottom of a window" [S7].
- **No sidebar footer.** The sidebar bottom holds nothing: no backup button, no licence text [S9].

### 5.2 Spacing scale (4-pt base)

| Token | pt | Use |
|---|---|---|
| `Spacing.xxs` | 2 | Half-step: vertical badge padding; tight two-line stacks (amount over its CZK line, caption under a value) |
| `Spacing.xs` | 4 | Icon-to-label gap, including the badge's symbol-to-word and word-to-detail gaps; compact-badge horizontal padding |
| `Spacing.s` | 8 | Gap between related controls; horizontal badge padding; grid cell spacing |
| `Spacing.m` | 12 | **Padding around bezeled elements** (≈12 pt in the HIG [S5]); row groups in the issued view's figures |
| `Spacing.l` | 16 | Card padding; space between form groups |
| `Spacing.xl` | 20 | Content-pane margins (editor, Overview) — RECOMMENDATION |
| `Spacing.xxl` | 24 | **Padding around elements without a bezel** (≈24 pt in the HIG [S5]); Overview tile gaps |
| `Spacing.section` | 32 | Between major sections (editor header ↔ line items ↔ notes) |
| `Spacing.page` | 40 | Empty-state block padding; the v0.2 drop zone's inner padding |

### 5.3 Sizes (RECOMMENDATION; tune them on Sasa's display)

| Element | Value | API (macOS) |
|---|---|---|
| Sidebar column | min 180, ideal 210, max 280 | `navigationSplitViewColumnWidth(min:ideal:max:)` 13.0 [S61] |
| Content (Table) column | min 360, ideal 560, max 900. Narrow widths hide the optional columns first (screens-flows §2b). | same |
| Detail column | min 520 (the draft editor's minimum). An A4 page is 595 pt wide at 100 %, so the preview fits it to the width. | same |
| Window | default 1360 × 860, **minimum 1080 × 640**. The column minimums add up to 180 + 360 + 520 = 1060 pt, so at the window minimum all three columns and their dividers still fit. | `defaultSize(width:height:)` 13.0 |
| Narrow windows | No breakpoint of its own: with no inspector, the window minimum already fits all three columns. The HIG suggests auto-collapsing the sidebar when the window shrinks [S9], and asks for minimum sizes that keep every divider visible [S10]. | — |
| Table row height | **The system default at 100 % text; don't override it.** On 26+, lists and tables have "a larger row height and padding" [S1]. The documents table uses single-line rows; the clients list uses two-line rows (name, plus IČO and city). When View ▸ Bigger is above 100 %, the row height follows the scaled line height plus padding (§3 Notes). `defaultMinListRowHeight` exists for `List` (macOS 10.15) [S71]; whether `Table` honours it is UNVERIFIED, so test the scaled rows early. | — |
| Controls | The macOS default control size is 28 × 28 pt and the minimum is 20 × 20 pt [S5]. On a touch-capable Mac, keep control sizes and enlarge only the tap targets [S30]. | `controlSize(_:)` only where a dense area needs it (RECOMMENDATION; not from [S1]) |
| Sheets | **One approach: `.form` for form sheets, `.fitted` plus an explicit frame where a size matters.** Record Payment, Issue confirmation, New Client, the Stock sheets and Export for Accountant use `presentationSizing(.form)` ("appropriate for forms") and size to their content, with no fixed widths. The Exchange Rates sheet uses `.fitted` with `frame(minWidth: 560, idealWidth: 640, minHeight: 400, idealHeight: 480)`, so it stays user-resizable; `.fitted` sheets are resizable by default on macOS and a fixed frame makes them non-resizable [S63]. On macOS 14 the frame alone applies. The ČNB import review is deferred (screens-flows §2g); it would use the same frame. | `presentationSizing(_:)` 15.0 [S63] |
| QR code on the PDF | about 30 mm side, error correction M | QR Platba standard: 29.6–32.8 mm for typical content [S94] |

### 5.4 Corner radii and concentricity

1. **Never set radii on system containers**: windows, sheets, popovers, menus, toolbar glass or the sidebar. Window and sheet corner radii changed with macOS 26 [S1], and macOS 27 gave every window "the same tighter corner radius" [S44]. A hard-coded number would be wrong on at least one of those releases.
2. **Shapes nested in a rounded container are concentric.** Use `ConcentricRectangle` or `containerShape(_:)` (both macOS 26.0) [S53]. On 27, `GeometryProxy.concentricCornerRadii` (macOS 27.0) gives the radii [S53]. If you have to compute it: inner radius = max(outer radius − inset, 4).
3. **Standalone content shapes use tokens**: `Radius.s` 4 (small inline shapes), `Radius.m` 8 (small tiles; the v0.2 drop zone), `Radius.l` 12 (Overview tiles, empty-state cards). Badges and the problems chip are `Capsule`.
4. **Style.** Use `RoundedRectangle(cornerRadius:style:)` with the default `.continuous` style (macOS 10.15).

---

## 6. Materials and Liquid Glass

### Where glass appears: system chrome only, automatically

Standard components pick up Liquid Glass when built with the latest SDK [S1]:
- toolbar and title bar, including the uniform toolbar on 27 when content scrolls under it [S44]
- the sidebar
- sheets, popovers, menus and alerts
- the search field, which sits trailing in the toolbar [S27]
- standard buttons inside bars

On 27 the system also tunes glass diffusion and highlights and offers a Settings slider from "ultra clear" to "fully tinted". Apps get these rendering improvements without recompiling [S44]. New in macOS 27, glass can also "subtly bounce" when clicked, and Apple's advice is that "a little goes a long way" [S47].

### Custom glass: none (RECOMMENDATION)

- **The app has no custom glass in any version.** Undoable actions confirm with the **inline result line** (§8.17): plain opaque text plus a borderless "Undo" button at the top of the content pane. Edit ▸ Undo (⌘Z) stays the primary undo. The v0.2 bulk results (bulk accept, import) use the same line; there is no Undo toast and no `FloatingSurface`.
- **v0.2 adds no glass.** The "Accept Exact Matches (N)" control is a toolbar item, not a floating bar. That keeps controls out of the window's bottom edge [S7].

### Never glass

- the Table and all its rows
- the line-item editor, `TotalsPanel` and any `MoneyText`
- the PDF preview and the QR code
- status badges, KPI tiles, the v0.2 drop zone, the activity log and the inline result line
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

One prominent control per context, text only (no symbol), on the trailing side [S8]:
- draft editor: **Issue…**
- unpaid issued document: **Record Payment…** (**Record Refund…** on an overpaid one)
- first-run Overview: **Open Settings…**
- an empty state: its one action (New Invoice, New Client). Import ČNB Rates… stays `.bordered`, because importing is the secondary path.
- Settings ▸ Numbering: **Save** (the one pane with a Save button, screens-flows §2i)
- Stock item detail (when Stock ships): **Count…**, with Receive… beside it as `.bordered`
- v0.2 queue: **Accept Exact Matches**

The Repair mode bar's End Repair Mode stays `.bordered`. Custom lists highlight with the system selection style (`SelectionShapeStyle`), as the Overview queue already does; that applies to the client suggestion list too, which on main uses the accent at 15 %. How that style resolves, and whether the row text then turns white, is UNVERIFIED; check it on device.

### Accessibility behaviour

| Setting | System chrome | Custom parts of this app (RECOMMENDATION) |
|---|---|---|
| Reduce Transparency | adapts automatically [S1][S5] | none: the app has no custom glass |
| Increase Contrast | adapts automatically | Status badges and the Repair mode banner (v0.1.x) add a 1 pt tone border; the accent switches to its high-contrast variant; tiles and the v0.2 drop zone get a `separatorColor` border. |
| Show Borders (macOS 27) | supported [S44] | When `accessibilityShowBorders` is on (back-deployed, macOS 11.0 listing [S67]), borderless custom buttons (the inline result line's "Undo" and close, inline "Change…") draw `.bordered`. |
| Liquid Glass slider (27) | — | Test at both ends: ultra clear and fully tinted [S44]. |
| Reduce Motion | — | Fades instead of slides; no animated blur [S5]. |
| Inactive window | — | none: the app has no custom glass |

---

## 7. Iconography

All symbols are SF Symbols, monochrome by default. Use hierarchical rendering only for status glyphs (`symbolRenderingMode(.hierarchical)`, macOS 12.0). Use filled variants for status and outline variants for toolbars and lists [S21]. Toolbar symbols have no border and no outlined circle [S8].

**Heads-up on naming.** SF Symbols 6 (macOS 15) renamed the `doc.*` family. For example, `doc.text` became `text.document` and `doc.on.doc` became `document.on.document`; the HIG Icons page already uses `document.on.document` for Copy [S20][S85]. With a 26/27 baseline, always use the new names. "HIG" in the table below means the HIG Icons page names that symbol for that action [S20]. "Data" means the name exists in [S85] (data up to macOS 26), so **check it in the SF Symbols 27 app**.

| Concept | Symbol | macOS since | Source |
|---|---|---|---|
| **Sidebar** (rows and labels: screens-flows §1.2 and §5) | | | |
| Overview | `square.grid.2x2` | 10.15 | data |
| Documents | `text.document` | 15.0 | data |
| Filters under Documents: Drafts / Unpaid / Open advances | `pencil.circle` / `clock`, which becomes `exclamationmark.circle` with a fixed red tint (`listItemTint`, macOS 11.0 [S66]) while something is overdue / `document.badge.clock` (15.0) | 10.15 unless noted | data |
| Clients | `person.2` | 10.15 | data |
| Payments | `banknote` | 11.0 | data |
| v0.2 child row: one per bank account | `building.columns` | 11.0 | data |
| Stock (when it ships) | `shippingbox` | 11.0 | data |
| **Actions** | | | |
| New Invoice, New Stock Item (toolbar) | `plus` | — | HIG (Add) |
| New Client (toolbar) | `person.badge.plus` | 10.15 | data |
| Duplicate as draft | `plus.square.on.square` | — | HIG (Duplicate) |
| Edit client (toolbar) | `pencil` | 10.15 | data |
| Print | `printer` | — | HIG |
| Save PDF / Export | `square.and.arrow.up` | — | HIG (Share/Export) |
| Show PDF in Finder | `folder` | 10.15 | data. The HIG Icons page maps `folder` to "Move to / Folder", not to Reveal in Finder [S20]; RECOMMENDATION. |
| Delete draft | `trash` | — | HIG |
| Undo / Redo | `arrow.uturn.backward` / `arrow.uturn.forward` | — | HIG |
| Search | `magnifyingglass` | — | HIG |
| Filter | `line.3.horizontal.decrease` | — | HIG |
| Import file (ČNB) | `tray.and.arrow.down` | 10.15 | data |
| v0.2: drop target glyph / drop not allowed | `arrow.down.document` (15.0) / `circle.slash` (12.0) | as noted | data; the HIG drag-and-drop page names `circle.slash` [S23] |
| More | `ellipsis` | — | HIG |
| **Objects and metadata** | | | |
| Locked / issued (the issued view's lock line, and the Payments table's locked payments) | `lock.fill` | 10.15 | data |
| Issued, unlocked in Repair mode (v0.1.x, §8.18) | `lock.open.fill` | 10.15 | data |
| Repair mode bar and repair events (v0.1.x, §8.18) | `wrench.and.screwdriver.fill` | 11.0 | data |
| Fallback rate (weekend/holiday) | `calendar.badge.exclamationmark` | 11.0 | data |
| Date | `calendar` | — | HIG |
| Closed advance / marked for credit note | `xmark.circle` / `flag` | 10.15 | data (§4.3) |
| Problem (inline messages, result line, Issue sheet, readiness chip) | `exclamationmark.triangle.fill` | 10.15 | data; the HIG alerts page says to use it sparingly |
| Information (inline messages, result line) / done (result line) | `info.circle` / `checkmark.circle` | 10.15 | data |
| Stock-linked line in the editor (when Stock ships) | `shippingbox` (one concept, one symbol with the sidebar row) | 11.0 | data |
| Stock running low (when Stock ships) | `arrow.down.circle` | 10.15 | data (§4.3) |
| **Status glyphs** | see §4.3 | | data |

- **No symbol where it carries no state or action** (RECOMMENDATION). Activity events are a sentence plus a timestamp, with no kind symbol; only Repair mode changes keep `wrench.and.screwdriver.fill`. Overview tiles have no label symbols. The "Select a document" and "Select a client" placeholders are title only. The rate line has no leading symbol; `calendar.badge.exclamationmark` stays on a fallback rate. The prominent Record Payment… and Record Refund… are text only, like Issue…. The issued view's payment rows show no lock; the payment caption says why a payment can't change (screens-flows §2f).
- **Document types** are text everywhere (§8.1; screens-flows §5 short names), so they have no symbols. The type symbols on main (`text.document`, `document.badge.clock`, `receipt`, `checkmark.seal.text.page`) go with the type chip and the New ▸ submenu; `text.document` stays for the Documents sidebar row and `document.badge.clock` for Open advances.
- **VAT treatments** are plain text in the goods short forms ("EU goods, exempt", "EU services, reverse charge", "Czech VAT", "Outside EU, services", "Other exemption"), never a chip and never with a symbol. No symbol was clear enough, and the HIG prefers text in lists and tables [S12].
- **Menus on macOS 27.** SwiftUI hides menu item symbol images in most contexts by default. Show icons only for object or concept items with `.labelStyle(.titleAndIcon)`, and treat a group uniformly: icons for all items or none [S45][S25]. RECOMMENDATION: the menus get no icons. File ▸ New holds New Invoice, New Advance Invoice and New Client… as text items, with no New ▸ submenu (screens-flows §1.4).

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
- no glass
- the document type is text everywhere: the screens-flows §5 short names in tables (Invoice · Advance · Tax doc (payment) · Final, long title as tooltip), the long English name with the Czech title in the issued view header and the Issue sheet, and the editor subtitle ("Invoice · Draft · Saved") in a draft. There is no type chip; Document ▸ Change Type ▸ changes a draft's type.
- all UI strings in English, through the String Catalog (§9); legal and tax strings come only from the §9 legal-strings table
- all numbers formatted through `FormatStyle`

The sketches are illustrative. The basic views they use (`Text`, `Button`, `TextField(_:text:)`, `ForEach`, `HStack`/`VStack`, `Section`, `Divider`) are macOS 10.15+. Lines marked `// verify` call an API or behaviour I could not confirm.

### 8.1 StatusBadge

- **Purpose:** show one document or match state (§4.3), or Stock's Low (§4.3), as symbol + word + optional detail.
- **Anatomy:**
  - `Capsule` filled with the tone colour at 14 % opacity
  - an SF Symbol in the tone colour, hierarchical rendering
  - the word in `.primary`, `TextRole.badge`
  - optional detail ("+12 days · 1 000,00 € left") in `.secondary`. The detail follows the label shown (§4.3). In the issued view's header a closing event (Closed unpaid, Marked for credit note) shows no detail; its reason is one selectable `.rowSecondary` line under the header. The Documents table keeps the reason as the badge detail.
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
  - an inline problem line below (`InlineMessage`, problem kind: `exclamationmark.triangle.fill` in orange, words in `.primary`)
- **Parsing:**
  - `TextField(_:value:format:prompt:)` (macOS 12.0). "If the format style can't parse the input, the bound value remains unchanged" [S57].
  - Whether the value commits on every keystroke or on submit or focus loss is UNVERIFIED; test it.
  - RECOMMENDATION: a tolerant parser in the core module that accepts "1 234,50", "1234,5" and "1234.50", plus regular and non-breaking spaces. The field shows the canonical form after commit.
  - **Separator rule** (RECOMMENDATION, one unit-tested function):
    - Spaces (regular, U+00A0 no-break, U+202F narrow no-break) are always grouping.
    - When both "," and "." occur, the last one is the decimal mark and the other is grouping.
    - When only one of them occurs, once, it is the decimal mark, unless it is the UI locale's grouping separator and exactly three digits follow it. So in an English locale that groups with commas, "1,234" is 1234 and "36,5" is 36.5.
    - A mark that occurs more than once is grouping only when every group after it has exactly three digits. Anything else, such as "1.5." or two decimal marks, is invalid and shows the error state.
    - **Rate fields** (every field that takes an exchange rate: the inline rate form and Change…, §8.9) always read a single "," or "." as the decimal mark. A ČNB rate for EUR or USD is quoted with three decimals and is far below 1 000, so "24,315" is always 24.315.
- **Locale:** typing follows the **UI locale**, Sasa's habit (the §8.2 rule). The PDF locale applies only to the preview and PDF.
- **Format:** the field binds with a plain **number** format, `Decimal.FormatStyle(locale:)` (macOS 12.0 [S107]) with two fraction digits via `precision(_:)` (macOS 12.0 [S107]). It does **not** use `Decimal.FormatStyle.Currency`: a currency style puts the symbol or code into the field text, so the currency would show twice next to the suffix label, and parsing could require the symbol. `Currency` is for read-only display (`MoneyText`).
- **States:**
  - empty (placeholder: zero in the UI locale, such as "0.00" or "0,00")
  - valid
  - invalid: the orange problem line next to the field, with no red outline, saying how to fix it: "Enter an amount, such as 1 234,50" (the example in the UI locale) when the text is not a number, and "Enter an amount greater than zero." for 0 or less in Record Payment and Record Refund [S19][S28]
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
  - each suggestion shows the name, then "IČO · country · default currency · document language · VAT treatment" in `.secondary`, with the treatment in its short form ("EUR · 14 days · EU goods, exempt")
  - problem lines (`InlineMessage`, problem kind) instead of chips, under the field and in the suggestion row: "VAT ID missing" (under either EU treatment, "EU goods, exempt (§ 64)" or "EU services, reverse charge"), "Address missing". The Issue sheet's ⛔ rows still block.
  - the highlighted suggestion uses the system selection style (`SelectionShapeStyle`), not an accent tint (§6 Prominence)
  - a final suggestion "New Client "…"…", which opens the New Client sheet (screens-flows §2e)
- **Matching:** name, IČO and VAT ID; insensitive to diacritics and case (RECOMMENDATION; the exact folding API is UNVERIFIED). Sort with `.localizedStandard`, the default comparator of `TableColumn.init(_:value:comparator:)` (macOS 13.5) [S81].
- **States:**
  - empty: recent clients first
  - typing: filtered
  - no match: "create" option
  - chosen: the name with the defaults line underneath. Picking a client applies all of its defaults at once, including its default treatment: "EU business, goods" gives "EU goods, exempt (§ 64)", "EU business, services" gives "EU services, reverse charge" (screens-flows §2c)
  - locked (Issued): plain text
- **Keyboard:**
  - Focus lands here first in a new draft (`defaultFocus`, macOS 13.0).
  - ↓ and ↑ move the highlight through the list; Return takes the highlighted client (the top one until the highlight moves); Tab accepts and moves to the first line's Description.
  - Esc reverts the field to the chosen client, or empties it when none is chosen.
- **VoiceOver** (RECOMMENDATION): the highlighted row carries the selected trait, and moving the highlight announces the client's name and defaults line, so the list is usable without sight.
- **Undo:** picking a client is one undoable change, like any edit [S16]. A separate "Undo Apply Client Defaults" is deferred with the defaults banner (screens-flows §2c).

### 8.5 LineItemsEditor

- **Purpose:** fast, spreadsheet-like entry of invoice lines.
- **Anatomy:**
  - a `Grid` (macOS 13.0) [S78] with a header row
  - columns: Description · Qty · Unit · Unit price · [Discount %] · [VAT rate] · Line total, then the row's problem marker. Five columns show by default.
  - **Line total** is computed, read-only and trailing (`gridColumnAlignment(.trailing)`)
  - **No currency suffix in the grid cells** (RECOMMENDATION). The document's currency is set once in the header and shows in the totals bar, so the Unit price and Line total cells are plain numbers with tabular digits and two decimals ("85,00" in a Czech-format locale). The MoneyField suffix (§8.3) is for standalone amount fields.
  - **VAT rate follows the document's VAT treatment** (document-level rule, RECOMMENDATION; the same rule as screens-flows §2c):
    - *Czech VAT (rate per line)*: the VAT rate column shows, a text field with suggestions "21", "12" and "0" (keyboard-only, no pop-up to Tab past). Neither reverse charge nor an exemption is offered per line: all are document-level treatments (ADR 0009).
    - *EU goods, exempt (§ 64)* (the build's ADR 0011; the usual treatment for a new EU business client, §8.12): the VAT rate column and the VAT amounts are hidden. The printed treatment text and clause are ACCT (§9 table).
    - *EU services, reverse charge* (printed "daň odvede zákazník", §9 table): the VAT rate column and the VAT amounts are hidden.
    - *Outside EU, services* and *Other exemption*: the same; their printed texts are ACCT.
    - The header and the totals bar state the treatment once; no line carries an "RC" or other marker.
    - Mixed documents (some lines under one treatment, some under another) only if the accountant confirms them.
    - All rate and treatment labels are ACCT strings (§9 legal-strings table).
  - **Discount %** is hidden until a line has a discount. It is added with the line's context menu Add Discount or Document ▸ Add Discount, and it disappears when no line has one.
  - **Unit** is a text field. On macOS 15 and later (behind the version check) it offers ks, hod, den, MD and km as `textInputSuggestions` [S58]; on macOS 14 it is plain text. There is no chevron menu. The unit is document text and prints as typed.
  - **Stock link** (when Stock ships, screens-flows §2n): a linked line shows `shippingbox` (§7) at the trailing edge of its Description cell, with the tooltip and VoiceOver label "Takes from stock: Bolt M8 (120 ks on hand)"; on an advance, which takes nothing, "Bolt M8 (120 ks on hand) leaves stock with the final invoice". There is no stock column.
- **Suggestions:** the description cell suggests earlier items with their last unit, price, VAT rate and discount, via `textInputSuggestions` [S58]. Accepting one fills the row. When Stock ships, stock items whose name matches come first, each with its on-hand figure as secondary text ("120 ks in stock"), on Invoice, Advance invoice and Final invoice drafts, never on a DDPP; the list ends with "Add “‹typed text›” to Stock…" (screens-flows §2n).
- **States:**
  - draft: editable
  - issued: read-only text, selectable
  - row invalid: the orange `exclamationmark.triangle.fill` beside the cell, with a tooltip, an accessibility label and a fix-it `accessibilityHint`, and no red outline; the Issue sheet lists it by line and column
  - empty: one blank row with placeholder text
  - **fully empty trailing lines** (e.g. after ↩ on the last row): exist on screen only. All of them are dropped on save and at issue, never counted as invalid and never printed.
- **Keyboard** (RECOMMENDATION; the authoritative map is screens-flows §3.1):
  - **Tab / ⇧Tab** move to the next or previous cell. Tab on the last cell of the last row appends a row. Whether the system Tab order follows `Grid` row order is UNVERIFIED; drive it with `@FocusState` and `focused(_:equals:)` (macOS 12.0) [S65] if not.
  - **Return** moves down one row in the same column. On the last row it appends a new row and focuses its description (`onSubmit`).
  - **Delete Line and Move Line Up / Down have no shortcut in v0.1.** They live in Document ▸ and in the row's context menu (Insert Line Below · Move Up · Move Down · Add Discount · Don't Take from Stock | Delete Line). A grid of text fields has no "row focused" state for ⌫, and a menu key equivalent such as ⌘⌫ fires even while a cell's text field is being edited (in Finder ⌘⌫ means "Move the selected item to the Trash" [S106]; what it does inside a text field is UNVERIFIED). Deleting a line can be undone and shows no alert [S15].
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
        .contextMenu { lineMenu(line.id) }                 // Insert Line Below · Move Up · Move Down · Add Discount · Don't Take from Stock | Delete Line
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
- **Placement:** the compact totals bar pinned at the top of the draft editor (`safeAreaInset`, edge `.top`, as built), and the issued view's figures [S7].
- **Which blocks appear depends on the document kind** (RECOMMENDATION, matching screens-flows §2d):

  | Block | Invoice | Advance | DDPP | Final |
  |---|---|---|---|---|
  | Per-rate block, Rate · Base · VAT | ✓ | ACCT (whether the advance shows a VAT breakdown) | ✓ | ✓ |
  | VAT in CZK + rate line (EUR and USD documents) | ✓ | **never** (no DUZP, no rate) | ✓, rate for the payment date (ACCT) | ✓ |
  | Advances deducted, as negative amounts, with the VAT already taxed in CZK; or Paid in advance (EU goods, no VAT columns) | — | — | — | ✓ |
  | Amount due (printed "K úhradě") | on the PDF ✓; in the bar only when something is deducted | on the PDF ✓; in the bar only when something is deducted | — (nothing payable) | ✓ |
  | Legal note | "daň odvede zákazník" when the document treatment is EU services, reverse charge; the § 64 clause under EU goods, exempt (ACCT) | the not-a-tax-document clause (`DocumentClause.notATaxDocument`, §9 table, ACCT) | — | as Invoice |

- **The editor's totals bar** (screens-flows §2c) shows one figure per fact:
  - Czech VAT: "Base 4 000,00 € · VAT 840,00 € · Total 4 840,00 €", plus "VAT in CZK 20 424,60 Kč" on EUR and USD documents.
  - No-VAT treatments: one figure with the treatment, "Total 3 142,50 € · Exempt (§ 64)" (EU goods), "Total 3 142,50 € · Reverse charge" (EU services), "Total … · Outside EU, services" or "Total … · Other exemption".
  - Amount due only when something is deducted. A final invoice adds the deduction and "Amount due", and under Czech VAT keeps the VAT after advances. An EU-goods final invoice reads "Total 10 000,00 € · Exempt (§ 64)" / "Paid in advance −4 000,00 €" / "Amount due 6 000,00 €"; the § 64 value is never reduced.
  - On EUR and USD tax documents, the rate line (§8.9) under the figures.
- **Anatomy** (the PDF and the issued view's figures keep every printed total, VAT per rate included):
  - **Per-rate block** (`Grid`, trailing columns): Rate · Base · VAT, with a CZK column on EUR and USD tax documents; Czech VAT only.
  - **Totals:** Base; VAT; **VAT in CZK** (when Czech VAT is charged on an EUR or USD tax document; the rate line from §8.9 sits right under it); Total.
  - **Final invoice only:** one deduction line per advance, labelled with the advance and DDPP numbers ("Advances deducted"), or, for EU goods, "Paid in advance" with one row per payment (advance number · day paid · amount paid) and no VAT columns. The printed wording ("Odečet zálohy …", "Uhrazené zálohy / Advances paid") is ACCT.
  - **Amount due**, in `TextRole.total`.
  - **Legal notes** (`TextRole.legalNote`), from the §9 legal-strings table, never typed inline:
    - "daň odvede zákazník", exactly the brief's lowercase string, when the **document's** VAT treatment is EU services, reverse charge. Whether it may be capitalised at the start of a printed line is ACCT.
    - the § 64 clause and § 29 odst. 2 písm. a) reference under EU goods, exempt (§9 table, ACCT)
    - the not-a-tax-document clause from the §9 table on an advance invoice: "Toto není daňový doklad. Daňový doklad bude vystaven po přijetí platby." (InvoicingCore `DocumentClause.notATaxDocument`), or only "Toto není daňový doklad." on a goods-only EU advance, which gets no payment tax document (the build's ADR 0012; ACCT)
- **States:**
  - draft: live recalculation
  - issued: values frozen; the issued view's lock line says so, and the panel draws no lock of its own (§8.18). In Repair mode (v0.1.x) the values are editable (§8.18).
  - missing rate (tax documents only): the CZK cells show "—" and the **inline rate form** (§8.9) takes the rate line's place, the same form as in the Issue sheet (§8.16). Typing the rate here is the v0.1 primary path.
  - mismatch: a VAT rounding note
- **Keyboard:** read-only. The values are selectable. Tab skips the panel.
- **Never glass, never colour-coded** (P1).
- **Sums across documents** (Overview tiles, the multi-selection summary, the CSV) never add up TotalsPanel values naively. They follow the **aggregation rules** in screens-flows §2a: VAT only from tax documents, advances never as revenue, Unpaid split from unpaid advances, and a final invoice's revenue net only of the advances it deducts through issued DDPPs (a "Paid in advance" deduction doesn't reduce it).

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

### 8.7 Document type (no component)

There is no `DocumentTypeChip`. The type is text everywhere (the §8 rule above): the short name in tables, the long English name with the Czech title in the issued view header and the Issue sheet, and the editor subtitle in a draft. Document ▸ Change Type ▸ (checkmarked items) changes a draft's type between Invoice, Advance invoice and Final invoice; a tax document for a received payment keeps its type (ADR 0009). If Czech names are ever added (a bonus, not in scope), never use a bare "Záloha", which also means backup.

### 8.8 The printed QR (no in-app component)

v0.1 has no in-app QR image and no QR choice: no pop-up in the editor, no Document ▸ QR ▸, no client QR field. The QR exists only on the issued PDF (the issued view's PDF pages and print).
- **Type by currency** (as built, `PaymentInstructions.standard`): CZK gets **QR Platba**, EUR gets **EPC QR (SEPA)**, USD gets none. The Issue sheet's Payment row names the type with the account and the predicted VS.
- **Why the payment details print beside it:** the EPC guideline assumes the data is "also shown at the same time in plain text" [S95]. In the app the payment details are selectable text (IBAN and VS).
- **Sizing:** error correction M and about 30 mm at print size [S94][S95], black on white.
- **Caption:** one name everywhere, printed under the code: **"QR Platba"** and **"EPC QR (SEPA)"**. The wording is not required by either standard (HEURISTIC).
- **Draft:** no scannable QR, in the preview **and in print**. A placeholder box of the same size takes its place, because a draft has no number and no VS yet, so a payment made from its QR could never be matched. It is document text: "QR po vystavení / QR after issue", or "QR po vystavení" alone on a Czech document (screens-flows §2c, §5).
- **Nothing to pay** (a DDPP, or a final invoice with an amount due of 0 or less): no QR and no payment block.
- **Payload limits:** EPC allows at most 331 bytes, and unstructured remittance at most 140 characters [S95].
- **Code unavailable** on an issued document (the core refuses the payload, or the code can't be generated from it): the PDF prints "QR kód není k dispozici" (with " / QR code unavailable" on a bilingual document) in the code's place, never a silent gap, and the payment details beside it still let the customer pay (ADR 0010).
- **No account for the currency:** the Issue sheet's ⛔ row "The document has no bank details." with Fill in…, which opens Settings ▸ Bank Accounts, blocks Issue; no QR surface shows it.
- **VoiceOver:** the PDF page that carries the code gets the description as its accessibility value, "QR code for a payment of 1 234,50 euros to account CZ65 …, variable symbol 120260042" (the series-prefixed VS, screens-flows §2i); a draft's page reads "QR after issue". The renderer (`Sources/InvoicingPDF/DocumentPDF.swift`), which draws the code, hands the description and the page index to the PDF page view. On main every page reads only "Page 1 of 2".

### 8.9 ExchangeRateRow

- **Purpose:** show where every CZK figure comes from (P6), and take the rate Sasa types.
- **v0.1: typing the rate is the primary path.** Sasa's answer in the proposal doc, 5 Nov 2026: "for start everything that nmeeds to be online i willů do manualy, s ill type current cnb rate for each invoice". So Sasa types the ČNB rate on the document, in the draft editor. It is the rate for the rate day (the DUZP; for § 64 goods the § 22 odst. 1 day, `Document.exchangeRateDay`, the build's ADR 0011); for a weekend or holiday, the last published rate. Importing a ČNB file is secondary: File ▸ Import ČNB Rates…, the Exchange Rates sheet and the form's own button (screens-flows §2g).
- **Anatomy:**
  - one line, "1 EUR = 24,315 CZK · for 30. 10. 2026 · Typed" (or "· ČNB file"), with tabular digits and no leading symbol; illustrative values, formatted by the UI locale. In a draft, Change… follows it.
  - the date is always the **rate's own publication date**, never the rate day or the payment date it is used for. The date comes from `Date.FormatStyle`, never a fixed format string.
  - a source tag: "Typed" or "ČNB file". A typed rate is saved to the same Exchange rates list as imported ones, with source "Typed" (InvoicingCore `ExchangeRateSource.manual`, saved by InvoicingData `RateStore.save`).
- **States:**
  - **missing** (the usual start in v0.1): the inline rate form, "EUR rate for 30. 10. 2026 missing" (the document's currency, so "USD rate for …" on a USD document; the day is the rate day's publication day), one rate field, **Save Rate** (↩, source "Typed"; as built), then the secondary "Import ČNB Rates…" (`.bordered`, a file dialog). The rate field has initial focus in the Issue sheet; in the editor, Document ▸ Enter Rate… moves focus to it. There is no date picker and no drop target; a bad value shows the orange fix-it line ("Enter the rate as a number, such as 24,315"), with no red outline. An optional **Open ČNB Rates Page** link may follow (RECOMMENDATION, still open as Q7; screens-flows §2g has its source and the UNVERIFIED sandbox note).
  - typed: source "Typed"
  - imported: source "ČNB file"
  - **fallback:** `calendar.badge.exclamationmark` plus "last published rate (weekend/holiday)", for example "ČNB 30. 10., last published" on a DUZP of Saturday 31. 10. 2026.
  - **after the rate day:** blocked, "The rate date cannot be after ‹day›, the day this document needs the rate for." (`exchangeRateAfterTaxPoint`, text from the build's PR 21).
  - **stale:** the rate's date is more than 7 days before the rate day (InvoicingCore `DocumentValidator.exchangeRateStaleAfterDays = 7`). This is a warning, not a blocker. The row shows the validator's text, "The exchange rate is from {detail}, more than a week before the day the document needs the rate for; check that the rate table is complete." ({detail} is the rate's date; PR 21), and the Issue sheet lists it as a ⚠ Check row (§8.16).
  - issued: a frozen row in the issued view's figures; the lock line covers it, and it draws no lock of its own. In Repair mode (v0.1.x) "Change…" works again (§8.18).
- **Which rate applies to a rate day** (that day's rate, or the previous publication day's, depending on publication time) is a legal rule: ACCT. The resolver is one unit-tested function (screens-flows §2g).
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
- **SwiftUI:** `ContentUnavailableView(label:description:actions:)`, macOS 14.0 [S76], with one `.borderedProminent` button (macOS 12.0) and the shortcut shown in the description, where the command has one. Detail-column placeholders ("Select a document", "Select a client", "Select an item") are title only, with no symbol and no description.
- **Examples:**
  - Documents: "No documents yet" + "Press ⌘N to create your first invoice." + New Invoice
  - Search: `ContentUnavailableView.search`
  - Clients: "No clients yet" + the built description + New Client (no shortcut in the description, because File ▸ New Client… has none)
  - Exchange Rates sheet: "No rates yet" + "Rates you type on a document appear here." It has no button of its own, because the sheet's button row carries Import ČNB Rates… (`.bordered`, the secondary path, §8.9).
  - Unpaid filter: "Nothing overdue" with `checkmark.circle` and "Every issued invoice is paid." This is the only positive empty state, and it is calm, not celebratory [S36].
  - Stock (when it ships): "No stock items yet" + "Add the things you keep on the shelf to see what's running low." + New Stock Item…
- **No blocking setup wizard at first launch.** The Overview shows the non-blocking "Getting started" checklist specified in screens-flows §2j. It has no import step: Sasa's current tool is a "poverty self made unsuccesful local app" (Sasa's answer in the proposal doc, 5 Nov 2026), so there is nothing to import. Missing company details are also listed as ⛔ in the Issue sheet [S31]. The HIG also says to avoid alerts at app launch [S15].

```swift
ContentUnavailableView {
    Label { Text("No documents yet") } icon: { Image(systemName: "text.document") }
} description: { Text("Press ⌘N to create your first invoice.") }
  actions: { Button("New Invoice") { newInvoice() }.buttonStyle(.borderedProminent) }
```

### 8.11 Toolbar sets per screen

Every toolbar is **fixed**: a plain `.toolbar {}` with no `toolbar(id:)`, so it can't be customised. Each screen has at most four items plus search, and at most one prominent item, text only, on the trailing side [S8]. Search sits trailing in the toolbar [S27]. Every item is also in the menu bar [S8]. **This is the one toolbar table**; screens-flows refers to it. Tooltips are sentence case, 60–75 characters at most, and don't repeat the label.

| Screen | Title and subtitle (system, leading) | Items (leading to trailing) |
|---|---|---|
| Overview | "Overview" | New Invoice (`plus`, "Create a new invoice"). No search. |
| Documents list | "Documents"; subtitle such as "Unpaid · 3" or "Unpaid · 7 · 3 overdue" (`navigationSubtitle`, macOS 13.0) | New Invoice (`plus`, "Create a new invoice") · search ("Search documents") |
| Draft editor | the client name, or "New Invoice" before a client is chosen; subtitle "Invoice · Draft · Saved" (screens-flows §2c) | Preview toggle (View ▸ Show/Hide Preview, "Show or hide the PDF preview") · **Issue…** (prominent) |
| Issued, accepts a payment | the number | Duplicate (`plus.square.on.square`, "Copy this document into a new draft") · **Record Payment…** (prominent) |
| Issued, overpaid | the number | Duplicate · **Record Refund…** (prominent, "Record money returned to the client") |
| Issued, settled (paid; a closed advance; an advance deducted or settled by a final invoice; marked for a credit note) | the number | Duplicate |
| Tax document for a received payment | the number | no items; its commands are in the File and Document menus |
| Clients list | "Clients" | New Client (`person.badge.plus`, "Add a client") · search ("Search clients") |
| Client page | the client name | New Invoice (`plus`, "Create an invoice for Acme GmbH") · Duplicate (`plus.square.on.square`, "Duplicate FV 2026-0038 as a new draft"; disabled when the client has no invoice) · Edit… (`pencil`, "Edit this client's details") |
| Payments | "Payments" | search ("Search payments"); a selected payment's document brings its issued-view items into the detail toolbar |
| Stock list (when it ships) | "Stock" | New Stock Item (`plus`, "Add a stock item") · search ("Search stock") |
| Stock item (when it ships) | the item name | Receive… (text, "Add goods that arrived") · **Count…** (prominent, "Set the number on hand after counting the shelf") |
| Bank statement triage (v0.2) | statement name | Import Statement… · Filter · search · **Accept Exact Matches (N)** (prominent; the only place for bulk accept) |

- **Not in any toolbar:** a New ▾ pull-down, Print, Save PDF (the issued view's PDF row has them, screens-flows §2b), an inspector toggle, Customize Toolbar…, and bulk items for a multi-selection. Bulk actions live in the menus and the context menu, never in a bottom status bar [S32].
- **Issued advances.** The chain line's one `.bordered` next-step button (Create Tax Document or Create Final Invoice, screens-flows §2d) is the place for the next step, so the toolbar has no Create Final Invoice. Main shows it in the toolbar (`MainSplitView.swift`); it stays there until the chain line ships. An unpaid advance's next step is the prominent Record Payment….
- **Sheets have no toolbar.**

**Implementation**
- **Placement.** Don't use `.primaryAction` for these items: on macOS "the location for the primary action is the leading edge of the toolbar" [S103], while the HIG puts the one prominent action on the trailing side [S8]. Use the default `.automatic` placement, which on macOS places items "in the current toolbar section in order of leading to trailing" [S103], and declare the prominent item last. That it then sits trailing next to search is UNVERIFIED; check the result on device. `.principal` is the centre of the toolbar on macOS [S103], which suits nothing here.
- **New Invoice:** a plain `Button` with `plus`. A pull-down returns only with three real items [S35].
- **Grouping:** `ToolbarSpacer(.fixed)` (macOS 26.0) [S74] goes only between Receive… and Count… on the Stock item, under `#if compiler(>=6.2)` and `if #available(macOS 26, *)`.
- **Narrow windows:** `visibilityPriority(_:)` (macOS 26.1) keeps New Invoice and the prominent item visible longer. `ToolbarItemVisibilityPriority` has `.automatic`, `.low` and `.high`, plus `init(lowerThan:)` and `init(higherThan:)`; lower-priority items move into the overflow menu first [S74].
- **Prominent style:** which SwiftUI style renders the HIG's toolbar `.prominent`, `.glassProminent` (macOS 26.0) or `.borderedProminent`, is UNVERIFIED.
- **Overflow:** don't add an overflow menu by hand [S8].
- **Show/Hide Toolbar** (⌥⌘T) stays. First check on macOS 27.2 what `ToolbarCommands()` (as built) lists with fixed toolbars. If Customize Toolbar… is absent, `ToolbarCommands()` stays. Only if it shows does `CommandGroup(replacing: .toolbar)` replace it: one item whose label shows the state ("Hide Toolbar" / "Show Toolbar"), toggling `@SceneStorage("toolbarHidden")`, applied with `toolbar(_:for: .automatic)` on macOS 14 and `toolbarVisibility(_:for:)` under `if #available(macOS 15, *)`, since `toolbar(_:for:)` is deprecated at macOS 27.3. It never uses `.windowToolbar`, which also hides the title and the traffic lights. Either way, check that ⌘F still presents search while the toolbar is hidden (screens-flows §1.4).

```swift
.toolbar {
    ToolbarItem {                                          // .automatic (default); not .primaryAction (= leading on macOS)
        Button { duplicate() } label: { Label { Text("Duplicate") } icon: { Image(systemName: "plus.square.on.square") } }
            .help(Text("Copy this document into a new draft"))
    }
    ToolbarItem {                                          // declared last, so it is trailing
        Button("Record Payment…") { showRecordPayment = true }
            .buttonStyle(.borderedProminent)               // verify which style matches HIG .prominent
            .keyboardShortcut("r", modifiers: .command)
    }
    .visibilityPriority(.high)                             // macOS 26.1
}
// verify on device: the prominent item ends up trailing
```

### 8.11a Keyboard map (cross-cutting)

**The one authoritative keyboard map is screens-flows §3.1** (with the single-key table in §3.2). This document keeps no second table, so the two can't disagree. The decisions it records, in short: ⌘N New Invoice · ⇧⌘N New Advance Invoice · ⌘D Duplicate ‹number› as Draft · ⌘R Record Payment… · ⌘↩ Issue… · ⌘F search · ⌘1–⌘4 sidebar (⌘5 Stock once it ships) · ⇧⌘= / ⌘− / ⌘0 text size. In a focused list the single keys are ↩, ⌫ and ⎋ only; letters type-select. New Client…, Add Note, Delete Line and Move Line have no shortcut. Never bound: ⌘K (reserved for a later command palette), ⌥⌘I (reserved for its HIG inspector meaning), ⌘Y (no Quick Look).

- **Modifiers.** No Control-modifier shortcuts [S13]. Prefer letters with ⌘ or ⇧⌘, and let shortcuts localise to the layout, which is the `.automatic` default of `keyboardShortcut(_:modifiers:localization:)`, macOS 12.0 [S80].
- **Later: the palette.** If the command palette ships (screens-flows §2k), it lists every command with its shortcut on the right, as Raycast does [S91], and `Return` runs the top result. It repeats the menus; it never replaces them.

### 8.12 Issued view figures

There is no inspector (§5.1). What it held now lives here:
- **Issued document: the figures grid** (screens-flows §2b), selectable `LabeledContent` rows, each only where it applies: Total · Advances deducted −X or Paid in advance −X · Paid (above 0) · Open balance (never on a DDPP) · Issued · DUZP (tax documents) · Due (payable kinds) · VS · Account (IBAN) · Rate (EUR and USD tax documents, §8.9) · VAT in CZK (only when Czech VAT is charged on an EUR or USD document). Below the grid, one line gives the document language and the treatment's short form ("Czech + English · EU goods, exempt"). The payment details are text; the QR is only on the PDF (§8.8).
- **The lock line** carries the only lock glyph and the issue time: `lock.fill` (uncoloured, `TextRole.legalNote`) and "Issued 5. 11. 2026 at 19:02 · locked. Corrections via credit note (Phase 2)." In Repair mode (v0.1.x) it shows `lock.open.fill` and reads "Repair mode: changes are logged", and the figures become the same editable controls as in a draft (§8.18).
- **The chain line** (an advance chain, screens-flows §2d): one text line under the header, `TextRole.body` links, no per-step symbols or tints, ending in one `.bordered` next-step button while a step is missing. VoiceOver reads each link with its state, for example "Advance ZF 2026-0003, paid". There is no ChainStrip component.
- **Payments**, the **Activity** disclosure (collapsed, §8.15) and the **PDF row** (Save PDF…, Show PDF in Finder, Print) follow, in that order.
- **A draft** keeps its derived values where Sasa edits: the totals bar (§8.6) and its rate line (§8.9).
- **The client page** shows the contact details (email and phone), the client note and one defaults line under the header ("EUR · Czech + English · EU services, reverse charge · 30 days", one interpolated key, `TextRole.rowSecondary`), and the balances once, as the figure tiles (screens-flows §2e).
- **A multi-selection** shows one summary in the detail column (screens-flows §2b): the title "3 selected", the caption "Totals per currency", and "Revenue (tax documents)", "Open balance" and, when an open advance is selected, "Unpaid advances". It follows the screens-flows §2a aggregation rules.
- **Defaults for a new client** follow screens-flows §2e: the client type follows the VAT ID and the country (an EU VAT ID gives "EU business, goods", whose editor treatment is "EU goods, exempt (§ 64)", the build's ADR 0011), the payment term is 14 days, and the currency and document language follow the country. No footer text is printed until Sasa sets one in Settings ▸ Company.
- **Keyboard:** Control-Tab moves to the next group of controls [S13]. Full Keyboard Access reaches every control.

### 8.13 FileDropZone (v0.2: bank statement)

- **Purpose:** drag in a file, check it, then commit. It ships with the v0.2 bank statement import, where dropping a file is the main path.
- **v0.1 has no drop anywhere:** not on the window, the Exchange Rates sheet, the Issue sheet or the totals bar's rate form. A ČNB file is imported through File ▸ Import ČNB Rates…, the Exchange Rates sheet's button and the inline rate form's button, each opening the file dialog. That import is already built (InvoicingData `RateStore.importDaily` and `RateStore.importYearly`); imported rates show source "ČNB file", typed ones "Typed", in the same list. There is no "Drop a ČNB rates file here" tip.
- **Anatomy:**
  - a `RoundedRectangle(cornerRadius: Radius.m)` with a 1 pt dashed `separatorColor` stroke
  - the `arrow.down.document` symbol
  - the text "Drop a bank statement here", with the accepted formats
  - a secondary line: "or click to choose a file"
  - Clicking opens `fileImporter` (macOS 11.0). It provides security-scoped URLs, which must be started and stopped [S82].
- **States:**
  - idle
  - **targeted, valid:** accent stroke and 8 % accent fill
  - **targeted, invalid:** `circle.slash` + "This file can't be imported"
  - The HIG says to highlight only when the drop is acceptable [S23].
  - The targeted state does not come from `dropDestination(for:isEnabled:action:)`, which has no `isTargeted` parameter; it comes from `onDropSessionUpdated(_:)` (macOS 26.0), which reports the `DropSession` and its phase while the drag is over the view [S101][S62].
  - importing: determinate progress [S34]
  - **review:** an inline summary with Import / Cancel
  - imported: a result line with Undo (§8.17)
  - error: the reason and a fix
- **Keyboard:** focusable. Return or Space opens the file dialog. The v0.2 window-wide drop for a statement works too.

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
  - exact: pre-ticked and included in the toolbar's bulk "Accept Exact Matches (N)" (also in the menu bar, and in the palette if it ships)
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
- **SwiftUI:** `onKeyPress(_:action:)` (macOS 14.0) on the focused list [S65]; the action returns `KeyPress.Result`, which has `.handled` and `.ignored` [S102]. If `List`/`Table` are backed by `NSTableView` on macOS (UNVERIFIED), its type-select is on by default (`allowsTypeSelect` defaults to true [S110]) and may eat letter keys before `onKeyPress` sees them. Prototype this on macOS 26/27 first. These v0.2 letter keys (N, S) are the only single-letter actions in the design, and each also has a menu item (screens-flows §3.2).

```swift
List(selection: $selected) { ForEach(queue) { MatchRow(item: $0) } }
    .onKeyPress(.return) { accept(selected); return .handled }   // KeyPress.Result: .handled / .ignored
    .onKeyPress("n") { showNotInvoiceMenu(); return .handled }
```

### 8.15 ActivityLogItem

- **Purpose:** the light-CRM timeline on the client page's Activity tab and in the issued view's collapsed Activity disclosure ("Activity" everywhere).
- **Anatomy:**
  - no kind symbol, except `wrench.and.screwdriver.fill` on repair changes (v0.1.x, §8.18)
  - the text, one built sentence ("Issued as FV 2026-0042", "Received: 1 000,00 €", "PDF saved to …", "Closed as unpaid: …"), in Body and selectable; a repair event names the field, old → new and the reason, and in the client tab starts with the document number
  - in the client tab, the linked document number as a link
  - a timestamp in Caption, secondary, formatted with `Date.formatted(date:time:)` (macOS 12.0); the full timestamp is in the tooltip
  - newest first
- **States:**
  - user note: editable and deletable, both undoable, no alert [S15]
  - system event: immutable, secondary style
  - highlighted: the row returns after Undo, scrolled into view [S16]
- **Keyboard:**
  - Return edits a note.
  - Delete removes it (undoable, `onDeleteCommand`).
  - File ▸ Add Note to “‹Client›”… (which switches to Activity and focuses the composer) or the composer "Add a note…" at the top of the timeline adds one; ↩ saves. Add Note has **no** shortcut: the HIG warns against adding a modifier to an existing shortcut for an unrelated command [S13].

```swift
HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
    if entry.isRepair { Image(systemName: "wrench.and.screwdriver.fill").foregroundStyle(.secondary).accessibilityHidden(true) }
    VStack(alignment: .leading, spacing: Spacing.xxs) {
        Text(verbatim: entry.text).textSelection(.enabled)
        Text(verbatim: entry.date.formatted(date: .abbreviated, time: .shortened)).textRole(.caption)
    }
}
.accessibilityElement(children: .combine)
```

### 8.16 IssueSheet: the one deliberate commit

This component is not in the task list, but P2 depends on it.

- **Trigger:** ⌘Return, the prominent toolbar button, or a click on the editor's readiness chip. It is a `.form` sheet sized to its content (§5.3) [S63]. The readiness chip shows only while something blocks Issue ("1 problem" / "N problems", §8.6); with nothing blocking, the prominent Issue… is the one go control.
- **Contents, which become immutable** (the full layout is in screens-flows §2c):
  - the heading with the **number that will be assigned** (`TextRole.documentNumber`): "Issue invoice FV 2026-0042?" and "Once issued, the document can't be edited or deleted." There is no series picker.
  - **seven summary rows:** Type (the type name, long English with the Czech title; an advance adds "· Not a tax document"), Client (name, VAT ID and the treatment's short form), Language, Dates (no DUZP on an advance), Total (one VAT row per rate under Czech VAT; under a no-VAT treatment the VAT row carries the printed clause; a final invoice adds Advances deducted or Paid in advance, then Amount due), Rate (EUR and USD tax documents, §8.9) and Payment (QR type · account · predicted VS; a DDPP shows that there is no payment request)
  - **two conditional rows:** PDF, only when no PDF folder is chosen; "Takes from stock: Bolt M8 −25 (95 left) · …", only when lines are linked (each item once with its summed quantity; the bracket is the on hand after Issue; the variant "(40 left, counted after the DUZP)"; never a blocker)
  - no Legal row and no Info section: every clause sits in the Type, Dates, Total or Rate row
  - **two severities**, ⛔ before ⚠: "Fix before issuing" rows keep Issue disabled until they're fixed [S28]; "Check before issuing" rows each have a "Checked" tick. A ⛔ row whose fix lies outside the draft has Fill in…, and the default button then reads Go to Problem.
  - **Missing rate, fixed in place:** the Rate row is the inline rate form (§8.9). Saving re-validates the sheet without closing it.
- **Focus:** the rate field when the rate is missing; otherwise, when a ⚠ Check row needs the "Checked" checkbox, the first checkbox gets initial focus with `defaultFocus` (macOS 13.0 [S65]), so Space ticks it without Tab.
- **Buttons:** **Cancel** on the leading side, and **Issue** on the trailing side as the default (Return). Not the destructive style, because the person deliberately chose to issue [S15]. Esc cancels.
- **No undo afterwards.** That is the point of gapless numbering (P2). The one exception is the audited Repair mode (v0.1.x, §8.18), which logs every change.

### 8.17 Undo confirmation: inline result line

- **Purpose:** confirm an action that took effect immediately (delete a draft, delete a note, issue, import; in v0.2 also unmatch and bulk accept), with a one-click Undo when the action registered one. It is the only confirmation surface, in v0.1 and v0.2.
- **Edit ▸ Undo (⌘Z) is the primary undo.** It never expires: ⌘Z works at any time, as many times as needed, with named actions [S16]. The visual confirmation is secondary.
- **Anatomy** (no glass): a plain line at the top of the content pane (`safeAreaInset`, top), just under the toolbar, on an opaque `.background(.background)` with a bottom `Divider`:
  - a symbol by message kind, shared with `InlineMessage`: problem `exclamationmark.triangle.fill` in `.orange`, info `info.circle` in `.secondary`, done `checkmark.circle` in `.secondary` (result line only); the words stay `.primary`
  - selectable text, up to two lines
  - a borderless "Undo" when the action registered one
  - a borderless close (`xmark`, label and tooltip "Close")
  - nothing else: no other buttons. After Issue it reads "Issued FV 2026-0042 · PDF saved to ~/…/2026/FV 2026-0042 Acme GmbH.pdf" (one interpolated key), with close only; Record Payment… and Show PDF in Finder are in the issued view below it and in the menus. After Repair mode: "Repair mode ended · 3 changes logged".
  - The Stock Count, Receive and Take Out sheets show their result in place (the figure and its history line), with no result line.
- **v0.2:** the bulk results (bulk accept, import) use the same line. There is no Undo toast and no `FloatingSurface`.
- **Shared rules:**
  - The button says "Undo", the same word as the Edit ▸ Undo item.
  - **Placement:** top of the content pane, never at the bottom edge [S7].
  - **Not time-boxed.** The line stays until the next user action in that pane or until it is closed explicitly (its own close button or Esc). It never hides on a timer: the HIG asks to "minimize use of time-boxed interface elements" and to "prefer dismissing views with an explicit action" [S5]. This is unlike Superhuman's 10-second undo [S97].
  - After Undo, scroll to and highlight the restored item [S16].
  - Reduce Motion: fade only [S5].
  - Show Borders (macOS 27): Undo, close and the inline Change… draw `.bordered` when `accessibilityShowBorders` is on (§6).
  - VoiceOver: post an announcement with `AccessibilityNotification.Announcement(_:).post()` (macOS 14.0). `Announcement` has three `init(_:)` overloads, for `String`, `AttributedString` and `NSAttributedString` [S68].
- **Keyboard:** the button doesn't bind ⌘Z again; the Edit menu owns it.

```swift
.safeAreaInset(edge: .top) {                                     // safeAreaInset(edge:alignment:spacing:content:), VerticalEdge, macOS 12.0 [S111]
    if let result {
        HStack(spacing: Spacing.s) {
            Image(systemName: result.kind.symbol).foregroundStyle(result.kind.tint).accessibilityHidden(true)
            Text(result.message)
            if result.canUndo { Button("Undo") { undoManager?.undo() }.buttonStyle(.borderless) }
            Spacer()
            Button { self.result = nil } label: { Image(systemName: "xmark") }   // explicit close; Esc too
                .buttonStyle(.borderless).accessibilityLabel(Text("Close"))
        }
        .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.s)
        .background(.background)                                   // opaque
        .transition(.opacity)                                    // verify Transition-protocol .opacity
    }
}
```

### 8.18 RepairModeBanner (v0.1.x)

- **Purpose:** show, at all times, that Repair mode is on. Repair mode is the one audited exception to P2.
- **The decision it follows** (the decisions table in Sasa's proposal doc, last row, 5 Nov 2026): "A Repair mode behind Touch ID or the password will unlock every record, issued documents included; each repair change is written to the audit log, which never leaves the Mac. There is no trace-free mode". It is planned for v0.1.x. The normal fix for a wrong issued document stays a corrective document (Phase 2). This design has no trace-free path.
- **Starting Repair mode:**
  - From a menu command, with no keyboard shortcut and no single key (RECOMMENDATION). File ▸ Repair Mode… opens the entry sheet (`presentationSizing(.form)` on macOS 15 [S63], a width range on macOS 14) with a required reason, then authentication. Every change also logs a reason (screens-flows §1.4, §2m).
  - The app calls `LAContext.evaluatePolicy(_:localizedReason:reply:)` (macOS 10.10 [S113]) with `LAPolicy.deviceOwnerAuthentication` (macOS 10.11 [S112]). On macOS that policy authenticates "with Touch ID, Apple Watch, or the user's password". Touch ID goes first when it is available and enrolled; "when these options aren't available, the system prompts the user for … user's password". The dialog's fallback button also asks for the password [S112]. So the password is always a way in.
  - The same policy also tries a nearby paired Apple Watch [S112]. The decision names only Touch ID and the password, so confirm with Sasa that a watch unlock is acceptable.
  - The reason text in the system dialog says what will happen and leaves out the app name, as Apple asks [S113]. Example (RECOMMENDATION): "unlock every record for repair" (screens-flows §2m).
  - Cancel or a failed check changes nothing and shows no extra alert.
- **Placement:** one full-width bar at the top of the main window, under the toolbar and above all three columns. v0.1 has no other window that shows documents. Never at the bottom: the HIG says "Avoid placing controls or critical information at the bottom of a window" [S7].
- **Anatomy:**
  - leading `wrench.and.screwdriver.fill` (macOS 11.0, data [S85]) in the caution tone (`.orange`), hierarchical rendering
  - the text **"Repair mode is on. Every change to a locked record is logged."** in `.primary`, Body semibold (`.body.weight(.semibold)`, [S55])
  - trailing, one standard `.bordered` button (macOS 10.15 [S114]): **"End Repair Mode"**. It is not prominent, so the window keeps one prominent action (P4).
  - background: the caution tone at 14 % opacity over opaque `windowBackgroundColor`, like a StatusBadge fill (§8.1); a 1 pt tone border at the bottom under Increase Contrast
- **Tone:** caution (orange), never red, which is only for Overdue (P4). Symbol plus words, never colour alone [S4][S5]. The words stay `.primary`, because the system orange is below 4.5 : 1 on white (§4.4).
- **Never glass.** The bar is opaque, like the inline result line (§6, §8.17).
- **Not dismissable while the mode is on:**
  - no close button; Esc does nothing to it; no timer hides it; it never scrolls away
  - "End Repair Mode" ends it (the menu offers the same command). So do 10 minutes without a change (RECOMMENDATION, screens-flows §2m) and quitting (next bullet).
  - quitting the app also ends it, so every launch starts locked (RECOMMENDATION)
  - After a timeout the bar stays and reads "Repair mode ended after 10 minutes without changes" until Sasa closes it (screens-flows §2m). Only then does it get a close button.
- **Issued documents while unlocked:**
  - The lock line's `lock.fill` is replaced by `lock.open.fill` (macOS 10.15, data [S85]), and the line reads "Repair mode: changes are logged". It stays uncoloured, like the lock (§4.3). Tooltip and VoiceOver label: "Unlocked for repair" (RECOMMENDATION).
  - The banner is always visible at the same time, so the open lock never stands alone.
  - Read-only values (`LabeledContent` in the issued view's figures) become the same editable controls as in a draft (§8.3, §8.9, §8.12).
  - Status badges keep their state; Repair mode is not a document state.
  - When Repair mode ends, `lock.fill` returns and the fields are read-only again. The result line reads "Repair mode ended · N changes logged", with close only (§8.17).
  - A repaired issued document gets a new PDF. The previous PDF bytes stay with the audit event (screens-flows §2m, RECOMMENDATION). Whether the client needs the new PDF, or a corrective document instead, is ACCT.
- **Every change is logged.** Each repair change is written to the audit log (InvoicingData `auditEvent`; the schema blocks updates and deletes of its rows). The log never leaves the Mac (decision). Backups include the log. The default backup folder is local, a Backups folder next to the data file inside the app's container; how a cloud-synced backup folder fits the decision is open for the lead and Sasa (screens-flows §2m). RECOMMENDATION: the issued view's Activity disclosure and the client's Activity tab also list each repair change as an immutable system event with `wrench.and.screwdriver.fill`: one sentence with the field, old → new and the reason (§8.15).
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
| Partly paid / Paid / Overpaid | — (Paid also names a DDPP and a final invoice settled by advances, §4.3) |
| Awaiting payment / Partly paid – tax document missing / Paid – tax document missing / Tax document issued / Settled in final invoice (cs wording ACCT) / Closed unpaid | — |
| Marked for credit note (cs wording ACCT) | — |
| Variable symbol (VS) | Variabilní symbol (VS) |
| Date of taxable supply | DUZP (ACCT) |
| EU services, reverse charge | the clause "daň odvede zákazník" (Brief); the per-line treatment text is in the table below (ACCT) |
| EU goods, exempt (§ 64) | the treatment text and the § 64 clause are in the table below (ACCT) |
| Czech VAT · Outside EU, services · Other exemption | the per-line texts are in the table below (ACCT) |
| Client type: EU business, goods · EU business, services · Czech VAT payer · Czech business, not a VAT payer · EU consumer · Business outside the EU, services · Consumer outside the EU | — (the client page, the suggestion line and the Issue sheet show the treatment's short form, not the client type) |
| Paid in advance | Uhrazené zálohy (ACCT) |
| Matched / Suggested / Unmatched / Not an invoice / Already recorded | — |
| Activity | — |
| Open balance | — (the one term for what is left to pay; never "Outstanding" or "Open") |
| Stock item · On hand · Low (running low) · Count (the stock-take) · Receive · Take out | — (UI only; nothing about stock prints, screens-flows §2n) |
| Document language: Czech / Czech + English | — |

### Legal and tax strings: one reviewed table (P7)

Every string printed on a document, or shown in the app with legal or tax meaning, comes from this table and from nowhere else; code references a constant, never a literal. **Brief** = the exact wording from the project brief (approved). **Design** = a printed marker or caption with no legal or tax meaning, worded by the design specs; it needs no accountant check. **ACCT** = "confirm with accountant" until the accountant approves the wording; ACCT strings may be used in drafts and previews, and the app ships v0.1 only once the column says approved. In the English UI a legal or tax string shows its English gloss from this table, or quotes the printed Czech exactly (P7).

| String | Used for | Status |
|---|---|---|
| Faktura – daňový doklad (with an en dash) | title of a regular invoice | Brief |
| Zálohová faktura | title of an advance request | Brief |
| Toto není daňový doklad. Daňový doklad bude vystaven po přijetí platby. / This is not a tax document. A tax document will be issued upon receipt of the payment. | note printed on an advance request for services or under Czech VAT (InvoicingCore `DocumentClause.notATaxDocument`) | ACCT |
| Toto není daňový doklad. / This is not a tax document. | note printed on an advance request whose lines are all § 64 goods, which takes no payment tax document (`DocumentClause.notATaxDocumentForGoods`, ADR 0012) | ACCT |
| Není daňovým dokladem | the brief's short form, not the printed clause; the in-app banner on an advance shows the English "Not a tax document" (screens-flows §5) | Brief |
| Daňový doklad k přijaté platbě | title of a tax document for a received advance | Brief |
| daň odvede zákazník (lowercase, with diacritics) | reverse-charge clause (`DocumentClause.reverseChargeNotice`; the PDF prints "Daň odvede zákazník.", with the English gloss on a bilingual document); capitalising it at the start of a printed line is ACCT | Brief |
| Dodání zboží do jiného členského státu, osvobozeno od daně podle § 64 odst. 1 zákona č. 235/2004 Sb., o dani z přidané hodnoty. / Intra-Community supply of goods, exempt from VAT under Section 64(1) of the Czech VAT Act and Article 138 of Council Directive 2006/112/EC. | the exemption reference § 29 odst. 2 písm. a) asks for, on a § 64 goods document (`DocumentClause.intraCommunitySupply`, ADR 0011) | ACCT |
| IČO · DIČ · spisová značka · VS | identifiers | Brief |
| Konečná faktura | Czech type name of the final invoice; the UI name is "Final invoice" (its PDF title in InvoicingCore `DocumentKind.title` is "Faktura – daňový doklad (vyúčtování záloh)", screens-flows §2d) | ACCT |
| Odečet záloh · Odečteny zálohy zdaněné daňovými doklady č. … (§ 37a zákona o DPH). | caption of the deductions on a final invoice (InvoicingCore `DocumentLabel.advanceDeductions`) and the clause under them (`DocumentClause.advancesDeducted`); each deduction line is the next row | ACCT |
| Odečet zálohy – daňový doklad č. …, platba ze dne …, sazba DPH … % | one deduction line per tax document and VAT rate on a final invoice (InvoicingPDF `PDFStrings.deductionLine`); the rate part is left out when there is none | ACCT |
| Uhrazené zálohy / Advances paid · Záloha ZF 2026-0003 uhrazena 12. 11. 2026 / Advance ZF 2026-0003 paid on 12. 11. 2026 | heading (`DocumentLabel.advancesPaid`) and one row per payment for advances paid on § 64 goods on a final invoice, with no tax document (ADR 0012); the day prints the Czech way in the gloss too | ACCT |
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
| DPH 21 % · dodání zboží do jiného členského státu · přenesení daňové povinnosti · mimo předmět daně v tuzemsku · osvobozeno (English: VAT 21 % · intra-Community supply of goods · reverse charge · outside the scope of Czech VAT · exempt) | per-line treatment texts as built (`Document+Payment.swift`), for Czech VAT, EU goods, EU services, outside the EU and other exemptions | ACCT |
| Plnění není předmětem daně v tuzemsku – místo plnění je mimo tuzemsko (§ 9 odst. 1 zákona o DPH). · Osvobozeno od daně podle ‹reference› zákona č. 235/2004 Sb., o dani z přidané hodnoty. | notes for outside-EU services (`DocumentClause.outsideScope`) and other exemptions (`DocumentClause.exempt`), with their English glosses | ACCT |
| Kurzový rozdíl | CZK difference on a payment | ACCT |
| Obchodní firma | label for the legal name | ACCT |
| Dobropis / opravný daňový doklad | credit note (Phase 2) | ACCT |
| Daňový doklad k platbě přijaté dne … na základě zálohové faktury č. …. / Tax document for the payment received on … against advance invoice No. …. | opening sentence of a DDPP (`DocumentClause.paymentReceived`) | ACCT |
| Uzavřeno – neuhrazeno · K opravě dobropisem | closing actions (screens-flows §2d); the UI shows them in English (§4.3) | ACCT |
| Zúčtováno v konečné faktuře | status of an advance deducted by an issued final invoice (follows "Konečná faktura"); the UI label is "Settled in final invoice" | ACCT |

The advance note: the brief's short form "Není daňovým dokladem" and the clause InvoicingCore prints (`DocumentClause.notATaxDocument`) differ. The PDF prints the core clause; reconciling the two with the accountant is a follow-up outside the design system (ACCT). If the PDF must print exactly the short form, the change belongs in InvoicingCore `DocumentClause.swift`.

The deduction clause and the DDPP sentence above are the texts InvoicingCore prints (`DocumentClause.advancesDeducted`, `DocumentClause.paymentReceived`); the accountant approves them like every ACCT row.

- **In the UI** the printed Czech title follows the English name, as in "Advance invoice (Zálohová faktura)", wherever the distinction matters: the issued view header and the Issue sheet's Type row.
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
| Relative dates ("Counted 3 weeks ago", screens-flows §2n) | a relative date format style; which API, and its availability, is UNVERIFIED (check the Foundation docs before building Stock) | UI locale |
| CSV for the accountant | One fixed format, no presets (screens-flows §2h): the delimiter, decimal mark, date format and encoding are agreed with the accountant (ACCT) and then built with a fixed `Locale`, never the UI locale. | fixed |

- Never concatenate strings. Use full-sentence keys with interpolation in a String Catalog.
- Counts need plural variants: English "1 day / 5 days", and the cs bonus entries "1 den / 2–4 dny / 5 dní". That String Catalogs support plurals is UNVERIFIED in this research; check it in Xcode 27.2.
- **No separate English PDF locale.** Both document languages print Czech number and date formats (above), so there is no `en_*` locale to choose.

### UI language

**English only.** Sasa's answer in the proposal doc, 5 Nov 2026: "en". Sasa's Mac also runs with English as the system language (§2). Sasa's comment: "czech is not needed anywhere. its jsut a very little bonus that i might not use. dont bother if not super easy to implement, maybe version 10.9 or omething ahah".

- The UI is written and tested in English.
- `DesignSystem.xcstrings` keeps its cs entries as a free bonus; the build thread keeps them. Czech UI is not in scope, and nothing in v0.1 depends on those entries.
- There is no in-app language switch. The HIG warns against repeating system settings in the app [S18]. Whether the system's per-app language setting (System Settings ▸ General ▸ Language & Region ▸ Applications [S51]) would pick up the bonus cs entries is UNVERIFIED (screens-flows §2i). That mixed UI is out of scope.
- Czech stays on documents (above); the UI shows it only where it quotes printed text (P7). The **document** language is per document (Document ▸ Document Language ▸, default from the client), and never a global setting [S18].

---

## 10. Accessibility checklist

**VoiceOver**
- [ ] Every `MoneyText` reads "amount + full currency name", plus the CZK line on EUR and USD documents (§8.2). Digits are never read one by one.
- [ ] Every StatusBadge reads its word and detail ("Overdue, +12 days · 1 000,00 € left"). Compact badges carry an explicit label (`accessibilityLabel`, macOS 13.0 / `Text` overload 11.0) [S68], and the same text as tooltip.
- [ ] Table rows read as one sentence: "Invoice FV 2026-0042, Acme GmbH, 1 234,50 euros, overdue 12 days" (`accessibilityElement(children: .combine)`) [S68].
- [ ] Every icon-only toolbar button has a label [S1].
- [ ] The QR code has a descriptive label on the PDF page that carries it (§8.8); a draft's page reads "QR after issue".
- [ ] Every missing-rate prompt states its currency and date in text ("EUR rate for 30. 10. 2026 missing"), and Enter Rate… has a text label (screens-flows §2c, §2g).
- [ ] Each link of the advance chain line is a labelled `Button` with its state ("Advance ZF 2026-0003, paid"); Document ▸ Show Related Documents ▸ is its menu path (screens-flows §2d).
- [ ] Overview tiles are one element each ("Unpaid, 18 400,00 euros and 35 000 Czech korunas, 7 documents"); the Unpaid advances link is a second element (screens-flows §2a).
- [ ] Stock (when it ships): the Low badge is symbol + word; the sidebar Stock badge has the accessibility value "3 running low"; the editor's `shippingbox` marker has a VoiceOver label ("Takes from stock: Bolt M8 (120 ks on hand)", or on an advance "Bolt M8 (120 ks on hand) leaves stock with the final invoice") (screens-flows §2n).
- [ ] The Repair mode banner (v0.1.x) reads "Repair mode is on. Every change to a locked record is logged.", its "End Repair Mode" button is its own element, and starting or ending Repair mode is announced. The open lock reads "Unlocked for repair" (§8.18).
- [ ] If a chart is ever added (v0.1 has none), it carries `accessibilityChartDescriptor` and titles the main message [S33].
- [ ] Voice Control: "Issue" works on the prominent button; add `accessibilityInputLabels` (macOS 11.0) where a control needs another spoken name.

**Keyboard and Full Keyboard Access**
- [ ] Every action is reachable from the menu bar [S14], including the Window menu with Minimize and Zoom [S14].
- [ ] **FKA on:** turn on Full Keyboard Access in System Settings ▸ Accessibility ▸ Keyboard (the HIG says to turn it on "in the Accessibility area" of Settings [S13]; the HIG keyboard table also lists Control-F1 to toggle it [S13], but the Apple Support shortcuts page of 14 Sep 2026 does not [S106], so don't rely on Control-F1). Tab through the editor, the issued view, sheets and, in v0.2, the matching queue.
- [ ] **FKA off pass:** with Full Keyboard Access off, check that every editor control has a path that doesn't depend on Tab reaching it: Document ▸ Change Type ▸, Currency ▸, Document Language ▸, VAT Treatment ▸ and Bank Account ▸ (checkmarked items), Document ▸ Show Related Documents ▸ and View ▸ Client Tab ▸; in Stock, the Stock menu's Count…, Receive… and Take Out…; per-line VAT is a text field; the Issue sheet checkbox has initial focus. Whether a default setup skips non-text controls when tabbing is UNVERIFIED; test it on Sasa's Mac. The HIG keyboard table lists Control-F7 to "temporarily override the current keyboard access mode" [S13].
- [ ] Single-key shortcuts work only when a list has focus, never in text fields [S92]. Prototype `onKeyPress` on a SwiftUI `Table` on macOS 26/27 before relying on it, because type-select may consume letter keys (§8.14). In v0.1 the single keys are ↩, ⌫ and ⎋ only, and each has a menu item.
- [ ] No hover-only affordances. The context menu and menu bar offer every hover action [S30].
- [ ] Test the shortcut map on the **Czech QWERTZ** layout, especially ⌘1…⌘5, ⌘+ (⇧⌘=), ⌘−, ⌘0 and ⌘?, and record the result. On that layout "+" sits unshifted on the 1 key, so ⌘+ and ⌘1 may collide or behave unexpectedly (UNVERIFIED; no Apple page found on Czech key equivalents).

**Contrast and colour**
- [ ] Status words and amounts are never drawn in a hue (§4.4).
- [ ] Text is ≥ 4.5 : 1 up to 17 pt and ≥ 3 : 1 when bold or larger [S5]. Custom colours aim for 7 : 1 [S6]. Measure with Accessibility Inspector [S5].
- [ ] Check both appearances × Increase Contrast × Reduce Transparency, separately and together [S6].
- [ ] Differentiate Without Colour (`accessibilityDifferentiateWithoutColor`, macOS 10.15 [S67]) needs nothing extra, because the symbol and word are always present.

**Motion and transparency**
- [ ] Reduce Motion (`accessibilityReduceMotion`): fades replace slides; no blur animation; no glass bounce on custom elements [S5].
- [ ] Reduce Transparency (`accessibilityReduceTransparency`): nothing custom to adapt; the app has no custom glass (§6).
- [ ] No time-boxed UI: nothing auto-dismisses on a timer (§8.17) [S5].
- [ ] Show Borders (`accessibilityShowBorders`) on macOS 27: borderless custom buttons get borders [S67].
- [ ] Liquid Glass slider at ultra clear and at fully tinted [S44]. Inactive windows (`appearsActive`) [S83].

**Text**
- [ ] Nothing below 10 pt on screen [S3]. View ▸ Bigger reaches 200 % on every content surface (tables, editor, issued view, Overview, totals, sheets) [S5], with no clipped table rows; test 200 % in the 1080 × 640 minimum window.
- [ ] Sidebar row size follows the system sidebar size setting (small, medium, large) [S9]. Don't fix it.

**Data safety as accessibility**
- [ ] Every destructive action except Issue can be undone. Issue always goes through the sheet and can't be triggered by one key [S15]. Repair mode (v0.1.x) needs Touch ID or the password, has no shortcut, and logs every change (§8.18).

---

## Sources

The research threads opened these on or before 2026-11-05. After the lean pass (6 Nov 2026) no section cites S11, S17, S26, S59, S60, S69, S70, S77, S84, S86, S87, S93, S96, S98, S100, S104, S105 or S109; their entries stay so that the numbers stay stable. HIG and developer pages were read as Apple's DocC JSON; the URLs below are the human-readable versions. **[WebFetch]** means the page was read through a summarising fetch, so the wording may differ slightly.

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
