# Design review log

## 2026-11-05 — Editor pass: review findings F1–F68

Files: design-system.md (ds), screens-flows.md (sf), DesignSystem.swift (swift; later split into App/FA/DesignSystem/, with the renames in README.md). The pre-review originals are kept in the design thread.
I re-checked every finding against the source before changing anything. Sources added: ds [S99]–[S111], sf [S139]–[S148], [S151].

**Totals:** 68 findings. 64 applied in full, 4 applied in part (one sub-claim rejected in each), 0 rejected outright.
Duplicates merged into one edit: F5 + F36 (shortcut map), F4 + F54 (dark accent), F15 + F53 (baseline), F24 + F41 (clause wording and treatment).

| # | Finding | Result |
|---|---|---|
| F1 | `.primaryAction` is the leading edge on macOS | **Applied.** The sketch now uses `ToolbarItem { … }` (`.automatic`) with ToolbarSpacer, and ds §8.11 says not to use `.primaryAction` [S103]. The claim that `.automatic` sits on the trailing side is not in the docs I opened, so it is marked UNVERIFIED: check on a device. |
| F2 | The Overview row says "no content column" in a three-column NSV | **Applied.** Overview sits in the content column and the detail column holds the selected tile or queue item. One three-column NSV everywhere (ds §5.1, sf §1.2/§2a) [S142]. |
| F3 | An 8 s toast contradicts "nothing is time-boxed" | **Applied.** v0.1 uses an inline result line that stays until the next action or an explicit close. The toast moves to v0.2 and is not timed. The HIG "Minimize use of time-boxed interface elements" is cited. sf §0.1 speed principle 7. |
| F4 | White text on the #8076FF prominent fill is 3.53:1 | **Applied** (merged with F54). Dark is now #6A5FF5 (white text 4.60:1; 3.63:1 vs #1E1E1E as a non-text fill). Increased-contrast dark is #5F54E8 (5.36:1). ds §4.2 explains that AccentColor is a fill, and links use linkColor. Same values in App/FA/DesignSystem/DesignTokens.swift. |
| F5 | The two shortcut maps disagree (⇧⌘N, ⌥⌘N, R/⌘R, P) | **Applied** (merged with F36). sf §3.1 is now the one authoritative map. ds §8.11a points to it. The values are ⇧⌘N = New Advance Invoice, ⌥⌘N = New Client…, Add Note has no key, Record Payment = ⌘R (R in focused lists), and the P binding is dropped. |
| F6 | ⌘⌫ = Move to Trash, and a menu key fires inside text fields | **Applied.** Delete Line and Move Line have no shortcut in v0.1; they live in the Document menu and the row's context menu. ⌘⌫ is unbound. Source: Apple Support 102650 [S106]. |
| F7 | Single-letter keys may be eaten by type-select | **Applied.** `allowsTypeSelect` defaults to true [S110]. Whether SwiftUI Table is NSTableView-backed is marked UNVERIFIED. sf §3.2 rule 5 says to prototype first, with menu and palette fallbacks. A checklist line was added. |
| F8 | Column minimums are wider than the window minimum | **Applied.** Content min is 360 and detail min is 520. The window minimum is 1080×640, and the inspector breakpoint is the sum of the minimums plus the inspector, 1320. The Swift Layout computes it. |
| F9 | The `.Currency` format puts the symbol inside the field | **Applied.** MoneyField uses `Decimal.FormatStyle(locale:).precision(.fractionLength(2))` with a currency-code suffix label [S107]. I verified `fractionLength(_:)` (Int, macOS 12.0). |
| F10 | The `#available` gate list is incomplete | **Applied.** Fallback A is now macOS 26.1. The full list of 27.0 gates is in ds §2, and a note says 26.0 would also need a visibilityPriority gate. |
| F11 | Tax terms appear without an ACCT flag | **Applied.** The VAT treatment and rate labels, "Odečet zálohy" and the other terms are marked ACCT in ds §8.5 and §9. They are also in the new "Legal and tax strings" table. |
| F12 | Reverse-charge content and the ČNB rate date are stated as fact | **Applied.** sf §0 rules 4 and 6 say "ACCT: to verify". The resolver rule is ACCT and unit-tested. |
| F13 | Wi-Fi transfer needs network entitlements | **Applied.** Both network entitlements stay off [S139]. Phase 3 is AirDrop or file transfer only, and Wi-Fi is out of scope. Whether AirDrop through the share sheet needs no entitlement is UNVERIFIED. |
| F14 | The files disagree on the editor input locale | **Applied.** In-app input and display follow the UI locale. The preview and PDF use the PDF locale (cs_CZ for both document languages). Stated the same way in both files. |
| F15 | sf makes 26 the default baseline; ds says 27 | **Applied** (merged with F53). One baseline sentence is used word for word in ds §2, sf §0.1 and Q1. |
| F16 | Seven misattributed citations | **Applied in part.** Fixed: automatic edge effect, controlSize (RECOMMENDATION), monospacedDigit (RECOMMENDATION, not from the typography HIG), the Inspector naming (panels page, reworded), `folder` = "Move to / Folder" (data + RECOMMENDATION), and the colon rule (Combo boxes [S32] and Boxes [S151]). **Rejected:** "no Oops [S19]". The Writing HIG does mention "oops!" as a phrase to avoid, so the citation stays. |
| F17 | The 35 % dim is conditional | **Applied.** It is reworded as "if the content underneath is bright, consider about 35 %". |
| F18 | The Control-F1 toggle for Full Keyboard Access | **Applied in part.** The checklist now points to System Settings ▸ Accessibility ▸ Keyboard first. **Rejected:** removing Control-F1. The HIG keyboards table lists Control-F1, even though Apple Support 102650 has no row for it. Both facts are now stated. |
| F19 | The never-bind list is missing system shortcuts | **Applied.** Added ⇧⌘Q / ⌥⇧⌘Q, ⌘` / ⇧⌘`, ⇧⌘3/4/5 and ⇧⌘6 (macOS 27 Siri). The screenshot keys now cite Apple Support [S8]/[S106]. |
| F20 | ⌥⌘T is marked ✅ without a source | **Applied in part.** The ⌥⌘T standard comes from the HIG keyboards table (Option-Command-T), so the shortcut has a source. Only "ToolbarCommands generates it" is now UNVERIFIED (check the generated menu). |
| F21 | `reorderable()` needs a container | **Applied.** The sketch has `.reorderable()` on the ForEach and `.reorderContainer(for: LineItem.self) { … }` on the enclosing view (27.0) [S99]. Whether Grid works as a reorder container is UNVERIFIED. |
| F22 | The UNVERIFIED notes can be settled from the docs | **Applied.** Visibility priorities, onDropSessionUpdated/DropSession, KeyPress.Result, the Announcement inits, Increase Contrast and the bookmark entitlement are now facts with citations [S101][S102][S104]. |
| F23 | The primary action of `contextMenu(forSelectionType:)` is double-click only | **Applied.** ↩ is implemented with `onKeyPress(.return)` on the focused Table, and double-click uses the primaryAction [S69]. |
| F24 | The clause is capitalised as "Daň odvede zákazník" | **Applied.** It is now the lowercase "daň odvede zákazník" everywhere, from the one legal-strings table in ds §9. |
| F25 | `Brand.accent` is a computed var, with a Swift 6 isolation risk | **Applied.** It is now `static let accent` on the plain enum `Brand` (App/FA/DesignSystem/DesignTokens.swift). `Brand` has no actor isolation and the target sets no default actor isolation, so `accent`, its provider closure and `srgb(_:)` are nonisolated without annotations. If the target ever sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, mark them `nonisolated` explicitly. The isolation risk itself stays PLAUSIBLE: not compiled here (no Swift toolchain). |
| F26 | Fixed sheet widths conflict with `.form` | **Applied.** Sheets use `.form` with no fixed widths. The import review is `.fitted` with a min/ideal frame (560/640 × 400/480), and the palette is `.fitted` at 560 [S63]. |
| F27 | The Xero bulk-OK status may be out of date | **Applied.** Re-checked: "In development" since 17 Nov 2025, 248 votes, not shipped. So "one OK per line" stays and the status sentence is updated in sf §4. |
| F28 | onExitCommand may not fire while editing | **Applied.** Marked UNVERIFIED, with an `onKeyPress(.escape)` fallback and a checklist prototype. |
| F29 | `enum Tab` shadows SwiftUI.Tab | **Applied.** Renamed to `InspectorTab` [S109]. |
| F30 | "Mono" is not an HIG appearance | **Applied.** The appearances are now Default, Dark, Clear light/dark and Tinted light/dark. |
| F31 | ⌘+ and ⌘1 on Czech QWERTZ | **Applied.** It is a test item in the checklist, still UNVERIFIED. |
| F32 | Sums across document kinds are undefined | **Applied.** sf §2a has a new Aggregation rules table, referenced from ds §8.6 and sf §2h. Tax documents only for VAT, advances on their own line, and grouping by DUZP (ACCT). |
| F33 | Payments behind a DDPP or a deduction can be deleted | **Applied.** Those payments are locked, and sf §0 rule 1 and §2f describe the edge cases. |
| F34 | Where drafts are edited | **Applied.** Drafts are edited in place in the detail column, and Open in New Window is optional. Both files agree. Header fields live only in the editor's header grid, and the inspector shows derived information. |
| F35 | A missing rate blocks the top task | **Applied.** Editor and Issue sheet get an inline rate form and a drop target, the queue item is "Kurzy ke konci měsíce chybí", the 12 K script has a missing-rate variant, and Q7 asks Sasa about it. |
| F36 | Shortcut conflicts (duplicate of F5) | **Applied** with F5. |
| F37 | The Swift status model is missing states | **Applied.** It now has two axes: `Settlement` (draft, open, partlyPaid, paid, overpaid, settledByAdvances, closedUnpaid) plus `isOverdue`, and the facts `taxDocumentIssued`, `deductedInFinal` and `markedForCreditNote`. The 14 labels each have a tone and a symbol, with precedence rules. The ds §4.3 table matches. |
| F38 | Advance closing states are missing | **Applied.** Added "Close Advance as Unpaid…" and "Mark for Credit Note…", with their states, labels and the closing event in the CSV. |
| F39 | Manual payments get duplicated on import | **Applied.** The "Už zaznamenáno / Already recorded" lane is matched first and included in bulk accept. The v0.1 model gets `source` and `bankLineID`, and MatchStatus gets `.alreadyRecorded`. |
| F40 | Bilingual PDF vs per-client language | **Applied.** The document language is "Čeština" or "Čeština + English", defaulting from the client. It lives in the header grid, and Q4 asks Sasa. |
| F41 | Per-line reverse charge allows mixed documents | **Applied.** Reverse charge is a document-level treatment. Lines take their VAT from it, and the clause follows the treatment. |
| F42 | The issue-date check trips on old drafts | **Applied.** The issue date is set "at issue". A "Set to today" action and a date-order check were added, and severities were revised. |
| F43 | Period text is rewritten silently | **Applied.** It only shifts at the start or end of a line, is highlighted, and shows a ⚠ Check (before → after) that must be ticked. |
| F44 | The DUZP rule is relative to the issue date | **Applied.** It now uses the last day of the billed period (Období). Q3 matches. |
| F45 | Export spec gaps | **Applied.** The period is by DUZP (ACCT), advances are flagged non-tax, and the CSV has fixed columns (Base21 … BaseRC in the document currency and CZK, RelatedDocs, DeductedAdvance, DeductedVAT_CZK, RateIsFallback, Closing event). Two presets, PDFs default ACCT, and the export history has Export Again. |
| F46 | An overpayment is a dead end | **Applied.** Added "Apply Credit To…", "Record Refund…" and the payment tolerance setting. |
| F47 | Cross-currency payments need two amounts | **Applied.** The payment form has "Připsáno na účet" and "Uhrazuje z dokladu", with the implied rate and kurzový rozdíl (ACCT). |
| F48 | EU clients without a VAT ID | **Applied.** They default to Tuzemsko with a warning. The New Client sheet spec has live derived defaults and required fields. |
| F49 | Keyboard paths need Tab | **Applied.** `defaultFocus` goes on the Issue checkbox [S145], and the chips and Document-menu paths are documented. |
| F50 | Payment date defaults to today | **Applied.** It defaults to the last payment date entered in the session, otherwise today. |
| F51 | ⌘D in the palette collides with File ▸ Duplicate | **Applied.** The palette handles ⌘N/⌘D itself for the highlighted row (key window first [S147]). The menu commands are disabled while the palette is open as a second guard, and there is an acceptance test. Precedence in a sheet is UNVERIFIED until prototyped. |
| F52 | WindowGroup and File ▸ New semantics | **Applied.** The main WindowGroup has an id and `CommandGroup(replacing: .newItem)`, plus Window ▸ Main Window. Document windows are optional. The id initialiser is marked UNVERIFIED (listed as deprecated at macOS 15). |
| F53 | Baseline inconsistency (duplicate of F15) | **Applied** with F15. |
| F54 | Accent contrast in Dark Mode (duplicate of F4) | **Applied** with F4. |
| F55 | Bare "Záloha" in "Exporty a záloha" | **Applied.** The sidebar now reads "Exporty a zálohování", the type short name is "Zálohová", and backup is "Záloha dat". |
| F56 | The PDF-statement path and bulk-accept placement | **Applied.** The match-manually fallback (PDFView beside the open documents, R, VS search) and Q8 (RB CSV/camt.053) were added. Bulk accept has one placement (toolbar), one label "Accept Exact Matches (N)" and a menu command. |
| F57 | IssueSheet and TotalsPanel ignore the document kind | **Applied.** There is a block table per kind (advance: no DUZP, no rate, "Není daňovým dokladem"; DDPP; final), in ds §8.6/§8.16 and sf §2c. |
| F58 | Draft QR can be printed | **Applied.** Drafts show a "QR po vystavení" placeholder in the preview and in print. |
| F59 | The rate is shown with the DUZP date | **Applied.** The rate shows its own date plus the fallback label ("ČNB 30. 10., poslední vyhlášený"). |
| F60 | Dynamic colour for the PDF watermark | **Applied.** The PDF uses a fixed colour (RECOMMENDATION). quaternaryLabelColor is for on-screen chrome only. |
| F61 | Text scaling only covers Table and editor, and rows clip | **Applied.** Scaling covers every content surface and adds ⌘0. Rows scale with the line height (`TextRole.lineHeight`, `scaledRowHeight`). |
| F62 | Bulk actions sit in the status bar | **Applied.** The status bar is information only. Bulk actions are in the toolbar, menus, context menu and inspector. |
| F63 | `.help(style.label)` won't compile | **Applied in part.** **Rejected:** the compile claim. `help(_:)` has a LocalizedStringResource overload [S108]. **Applied:** the detail was lost, so it now uses `.help(Text(verbatim: spoken))`. |
| F64 | Weekday holidays block the coverage grid | **Applied.** The resolver uses a Czech holiday table (sf §2g, ACCT, unit-tested). |
| F65 | An empty trailing line blocks Issue | **Applied.** An empty trailing line is dropped on Issue and save. |
| F66 | The coverage grid and chain strip are glyphs only | **Applied.** They use SF Symbols with words and accessibility labels, and a checklist line was added. |
| F67 | The VAT chart is over-engineered | **Applied.** It is replaced by a VAT table. A chart is in the checklist only if added later. |
| F68 | Small inconsistencies | **Applied.** Status badges are sentence case (ds §9 and Swift). VS 120260042 everywhere. The iPhone banner is orange with a symbol. The log is "Aktivita" everywhere. There is one toolbar table, ds §8.10 points to the sf §2j checklist, and the toast is v0.2 in both files. |

Late fixes in this pass: `fractionLength(_:)` verified and added to [S107]. `safeAreaInset(edge:…)` with VerticalEdge verified as macOS 12.0 [S111], so its "verify" note is gone. The last "dashboard" in sf §4 now says "Overview".

## 2026-11-05 — Code review of the design-system pull request

Four independent reviewers (toolchain, behaviour, localisation and accessibility, docs) read `App/FA/DesignSystem/` and
these docs; a separate skeptic tried to refute each finding. 41 findings: 29 confirmed (about 20 after merging
duplicates), 12 refuted.

| Finding | Result |
| --- | --- |
| An advance with money received but no tax document showed the warning only when paid exactly | **Fixed.** New state "Částečně uhrazeno – chybí daňový doklad / Partly paid – tax document missing"; an overpaid advance without its DDPP shows "Uhrazeno – chybí daňový doklad". Both win over Overdue. ds §4.3, sf §2a, §2d, §5. |
| View ▸ Bigger could not reach `MoneyText` or `StatusBadge` | **Fixed.** One `textScale` environment value, read by `textRole(_:scale:)` and the badge. |
| `backgroundProminence` read at a table cell's top level may miss the row | **Fixed.** Resolved in a private `ShapeStyle`, as Apple's docs recommend. |
| `fixedSize()` let a long badge overflow a narrow column | **Fixed.** `ViewThatFits` falls back to word only, then symbol only. |
| The badge word and its tooltip/VoiceOver text could resolve in different locales | **Fixed.** One string in the view's locale for all three. |
| The label order was not written down | **Fixed.** ds §4.3 "Label order". |
| Overdue text said the settlement word stays | **Fixed.** Overdue takes the word, tone and symbol; the detail keeps days and balance. ds §4.3, sf §2b, §2d. |
| "Zúčtováno ve FV …" left in the specs | **Fixed.** "Zúčtováno v konečné faktuře" everywhere, marked ACCT. |
| Already recorded missing from the bank match table and §8.14 | **Fixed.** |
| Spacing table swapped `xxs` and `xs` against the code | **Fixed** in the docs; the code was right. |
| `help(_:)` Text overload given as macOS 13.0 | **Fixed:** macOS 11.0. |
| Czech VoiceOver example "korun českých" | **Fixed:** "české koruny" (CLDR plural for decimals). |
| README examples did not compile (`Text` of an optional; column width on the split view) | **Fixed.** |
| §2 decision gate contradicted the interim macOS 14.0 target | **Fixed.** |
| §8.1 sketch passed `Document.status` to the badge | **Fixed.** |
| File menu table broken by a paragraph | **Fixed.** |
| F5 above said ⇧⌘N is a type chooser; F25 claimed `nonisolated` annotations | **Fixed** in this log. |
| Stale names ("Layout widths", "the Swift file"), a research path in [S147] | **Fixed.** |

Refuted, among others: rounding in `MoneyText` (the core rounds every displayed amount to two decimals, half away
from zero, before it reaches the view), marking the ACCT strings `needs_review` (the catalog's "translated" only means
a translation exists; the ship gate is the legal-strings table in ds §9), and a README gating rule that would break a
macOS 27 API (it covered only the macOS 26 glass call; the wording now names the API's own version anyway).

## 2026-11-05 — Build thread review (PR 7)

Six focused reviewers and one adversarial reviewer read `App/FA/DesignSystem/` and these docs against the merged
InvoicingCore; a verifier checked each finding. 17 confirmed, 10 refuted. Those not already fixed above:

- A final invoice with a negative amount due is no longer blocked at Issue: sf §2d now gives the `advancesExceedSupply` warning (ADR 0004, `DocumentValidator`); the QR and payment request are suppressed as for a zero amount due (RECOMMENDATION).
- The advance note: ds §9 lists the clause InvoicingCore prints (`DocumentClause.notATaxDocument`, ACCT) next to the brief's short form "Není daňovým dokladem", which stays an in-app label only; ds §3 table, §8.6 TotalsPanel and §8.16 IssueSheet, and sf §0 rule 3, §2d step 1, the opening ground rules and the §5 label table follow it.
- The final-invoice PDF title in sf §2d and the ds §9 table now quotes InvoicingCore `DocumentKind.title` ("Faktura – daňový doklad (vyúčtování záloh)", ACCT).
- `DesignSystemGallery.swift`: the 24,310 CZK/EUR sample is marked an illustrative rate, not a published ČNB rate.
- sf §2f: the Raiffeisenbank format and price statements and Q8 are marked UNVERIFIED (not confirmed on any page in the source list).
- sf §2g: the ČNB publication-day assumption in the coverage grid and the resolver is marked UNVERIFIED / ACCT.
- sf §2f: the Xero sentence now says only what [S120] shows (one idea, 248 votes, "In development").
