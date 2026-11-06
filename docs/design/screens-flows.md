# FA-mac: Screens & Flows spec

Date: 2026-11-05 · Role: Mac UX (speed first) · Status: draft for Sasa's review, updated with Sasa's answers in the proposal doc and by the lean pass (both 5 Nov 2026) · Covers v0.1, v0.1.x (Repair mode), Stock (§2n; the build's roadmap sets its version), v0.2 and Phase 3 (iPhone)

## How to read this

- **This whole document is a design proposal (RECOMMENDATION).** Statements about Apple platforms, APIs, the HIG or other products carry a source tag **[S#]**. The numbered list of sources is at the end.
- **UNVERIFIED** marks anything that no opened page confirms. Test it before building on it.
- **ACCT** marks anything that needs to be confirmed with the accountant. This covers all legal or tax wording and treatment beyond what the project brief states.
- **The lean rule.** Sasa's rule for the lean pass (5 Nov 2026): "Let's keep it precise and clean. No need to rush. Hopefully the gui won't be bilions of setting and icons and menus but nice intuitive easy to use and fast." The pass cut, merged or deferred whatever did not serve that rule. The design thread records it in [review-log.md](review-log.md).
  - **"Later (‹version›): …"** marks something deferred. It keeps only the constraints a later build needs, and nothing in v0.1 depends on it.
- **Build status.** Notes on what is built describe `main` at 18679ea unless they name a later PR. The EU goods work merged after that commit and is on `main` at 3ce8589: PR 21 (the § 64 treatment and the rate day, `Document.exchangeRateDay`, ADR 0011) and PR 22 (advances paid on EU goods, ADR 0012). PR 20 moved CI to Xcode 26.3. The shell's build-status notes were not re-checked against PRs 20–22 except where they name them.
- **The UI is English only.** Sasa answered "en" for the interface language and commented: "czech is not needed anywhere. its jsut a very little bonus that i might not use. dont bother if not super easy to implement, maybe version 10.9 or omething ahah" (Sasa's answer in the proposal doc, 5 Nov 2026).
  - Every UI label in this spec is English: sidebar, menus, toolbars, buttons, column headers, badges, empty states, hints and sheets. Czech UI is out of scope.
  - Czech appears only in **document text**: what prints on the PDF (titles, legal and tax strings), the column names of the accountant's CSV (ACCT, §2h), what Sasa types into a document (line descriptions, units, the Note and the Order reference) and the company footer (Settings ▸ Company, §2i).
  - The only language control sets document text, never the UI: "Document language: Czech / Czech + English" on each document (a new client's default follows its country, §2e), mapped to InvoicingCore `DocumentLanguage.czech` ("cs", Czech only, for Czech customers) and `.english` ("en", bilingual, Czech first then English, for foreign customers).
  - The Czech entries in `DesignSystem.xcstrings` stay as a free bonus from the build thread. Nothing in this spec depends on them.
- The only legal wording used verbatim in this spec is the wording from the brief: "Faktura – daňový doklad", "Zálohová faktura", "Daňový doklad k přijaté platbě", "Není daňovým dokladem" (the brief's short form; the English UI shows "Not a tax document" instead, and the PDF prints the InvoicingCore clause from design-system §9, ACCT) and "daň odvede zákazník". Everything else printed on a PDF is ACCT, except the **Design** strings (the draft markers, the QR captions and the QR-unavailable notice, the continuation marker and the bank label), which carry no legal or tax meaning. **All printed and legal strings, with their status (Brief, Design or ACCT), are kept in one reviewed table: design-system §9 "Legal and tax strings".** Czech terms in this spec such as "DUZP / Datum uskutečnění zdanitelného plnění", "Obchodní firma", "Kurzový rozdíl", "Konečná faktura", "Odečet zálohy" and "Uhrazené zálohy" are **ACCT: confirm with accountant** wherever they appear. In the app they appear only in document text, if at all.
- **Cross-references.** design-system.md owns the tokens, colours, status styles, components and the toolbar table (§8.11). This spec owns the screens, flows, menus and the **one authoritative keyboard map (§3.1)**.
- Notation:
  - ⌘ = Command, ⇧ = Shift, ⌥ = Option, ⌃ = Control, ↩ = Return, ⌫ = Delete, ⎋ = Esc.
  - A chord such as ⌘N counts as **1 keystroke**. Each typed character counts as 1.
- Example data:
  - Client "Acme GmbH", the services example: EUR, document language "Czech + English", client type "EU business, services" (picked by hand; its documents get "EU services, reverse charge"), 30 days (set by hand; a new client starts at 14 days, §2e). Its monthly invoices carry a Period, so their DUZP is the period's last day (§2c).
  - Most of what Sasa sells is goods (Sasa in the project chat, 5 Nov 2026: "90% goods"). A new German client with a VAT ID gets "EU business, goods" by the country rule, so its documents get "EU goods, exempt (§ 64)" (§2e). An EU client without a VAT ID gets the same: "EU business, goods; Issue waits for the VAT ID". Sasa sells to businesses only for now ("i dont do b2C CURRENTLY", 6 Nov 2026), so a missing VAT ID means it isn't typed in yet (ACCT).
  - Stock item "Bolt M8", unit "ks" (§2n).
  - Numbers are shown as "FV 2026-0042", the default invoice pattern FV {YYYY}-{NNNN} (§2i). Sasa's own format and last numbers are an open question (Q2).
  - Amounts and dates in UI examples are written in Czech formats. The UI formats them with the UI locale; the PDF uses Czech formats (RECOMMENDATION; confirm with Sasa and the accountant, design-system §9).

## 0. Ground rules the UI enforces (domain rules, from the brief and the EU goods decisions)

1. **Issued documents are immutable.**
   - There is no edit and no hard delete.
   - Corrections come only through a credit note, which arrives in Phase 2.
   - The one exception is **Repair mode** (v0.1.x, §2m): behind Touch ID or the password, every record unlocks, and every change is written to the audit log. There is no trace-free mode.
   - Payments, notes, file exports and two dated **closing events** may be *added* around an issued document. They never change it. The closing events are v0.1 actions so that nothing nags forever (§2d): "Close Advance as Unpaid…" for advances, and "Mark for Credit Note…" for tax documents. Once one is recorded, the same menu row reads "Reopen Advance" or "Remove Credit Note Mark" and removes it at once, undoably. Wording and accounting effect: ACCT.
   - **A payment that an issued document rests on is locked too** (§2f): it can't be deleted, unmatched, or have its amount or date changed. That covers a payment that has a tax document and a payment that an EU-goods final invoice settled as paid in advance (built in PR 22).
   - Stock never touches a document (§2n). A line's stock link lives outside it, and the document, its hash and its PDF never mention stock.
2. **The number is assigned at issue.**
   - It comes from one of three fixed series and is continuous, with no gaps: invoices and final invoices (FV), advance invoices (ZF), and tax documents for received payments (DD) (§2i).
   - Drafts have no number. Deleting a draft never uses up a number.
3. **"Zálohová faktura" is not a tax document.**
   - It prints the not-a-tax-document clause from design-system §9 (InvoicingCore `DocumentClause.notATaxDocument`: "Toto není daňový doklad. Daňový doklad bude vystaven po přijetí platby.", ACCT). An advance for EU goods prints only "Toto není daňový doklad. / This is not a tax document.", because its payment gets no tax document (built in PR 22; ACCT). The advance's legal line in the app reads "Not a tax document" (English UI); the brief's Czech short form "Není daňovým dokladem" isn't shown in the app.
   - It has no DUZP field. ACCT: confirm that no date of supply should print.
4. **The VAT treatment is document-level** (RECOMMENDATION; design-system §8.5 uses the same rule). The editor offers "EU goods, exempt (§ 64)", "EU services, reverse charge" | "Czech VAT (rate per line)", "Outside EU, services", "Other exemption" (the goods decisions; ADR 0011). Under every treatment other than Czech VAT, the document shows no VAT rate and no VAT amount (goods decisions).
   - **EU services, reverse charge** prints the clause "daň odvede zákazník" (the brief's exact string). The English wording of the clause is ACCT. **ACCT: to verify** that a reverse-charge document shows no VAT rate and no VAT amount, and cite the legal source once the accountant confirms it.
   - **EU goods, exempt (§ 64)** needs the client's VAT ID: § 64 odst. 1 písm. a) ZDPH exempts the supply only if "tato osoba sdělila plátci své daňové identifikační číslo pro účely daně z přidané hodnoty". The printed treatment label and clause are ACCT (design-system §9).
   - Under either EU treatment, a client without a VAT ID blocks Issue (§2c).
5. **EUR documents that charge Czech VAT** also show the VAT amount in CZK. USD documents follow the same rule (ACCT).
6. **Exchange rate.**
   - The rate is for the document's **rate day**: the DUZP; for § 64 goods the § 22 odst. 1 day (the day the tax document is issued, if that is before the 15th of the month after the supply; otherwise that 15th). This follows § 4 odst. 8 ZDPH: "kurz platný pro osobu provádějící přepočet ke dni vzniku povinnosti přiznat daň, nebo přiznat uskutečnění plnění". The build stores the day as `Document.exchangeRateDay` (PR 21): the § 22 odst. 1 day when every line is § 64 goods, otherwise the tax point (the document's DUZP). Mixed documents (not every line § 64 goods) and tax documents for received payments (DDPPs) keep the tax point (ACCT).
   - **ACCT: to verify** which ČNB rate counts for the rate day: that day's rate, or the last rate published before it, or (depending on publication time) the previous publication day's rate. The design below assumes "the rate day's rate, or the last one published before it".
   - The rate, the date it was published for, and its source are stored on the document. The UI always shows the rate's own date, never the DUZP or the rate day in its place (P6).
   - A fallback (a weekend or holiday) is labelled.
   - In v0.1 Sasa types the rate on each EUR or USD document (§2c). Importing a ČNB file through File ▸ Import ČNB Rates… is the secondary path. The stored rates are listed in the Exchange Rates sheet, opened from the File menu (§2g).
7. **The app never sends anything and makes no network calls.**
   - The App Sandbox runs without network entitlements: `com.apple.security.network.client` and `com.apple.security.network.server` stay off [S139].
   - Exports and PDFs only go to folders Sasa chooses.
   - Phase 3 keeps this rule by limiting iPhone transfer to AirDrop and file-based exchange (§2l). Local Wi-Fi sync would need the client and/or server network entitlement [S139] and is out of scope unless Sasa decides to relax this rule.

## 0.1 Platform stance

- **Sasa's Mac:** an M1 Pro with 32 GB, on **macOS 27.2** with **English** as the system language. Sasa's answer in the proposal doc, 5 Nov 2026: "27.2, english" and "m1 pro 32gb ram 200gb bandwith 256gb disk - using mainly 8tb cloud / macOS 27.2 (the newest one, im just updating it right now)". This answers Q1.
  - An M1 Pro Mac (the 14- or 16-inch MacBook Pro from 2021) is on the compatibility lists for both 26 and 27 [S5][S6][S7].
- **Design for Liquid Glass from day one.** Xcode 27.2 ships the macOS 27.2 SDK [S4]. Apps built with Xcode 27 always use Liquid Glass, because `UIDesignRequiresCompatibility` is ignored when building for macOS 27 [S2][S3].
- **Deployment target (decision, build thread):** the app keeps targeting **macOS 14.0**.
  - CI is the `macos-15` runner, building with Xcode 26.3 (macOS 26 SDK) since the build's PR 20. Every macOS 26 API still sits behind `#if compiler(>=6.2)`, and every macOS 27 API sits behind the compiler check for the Swift version of the macOS 27 SDK. Each one also gets an `if #available` check and a macOS 14 fallback ([README.md](README.md), Platform policy).
  - The target is still macOS 14.0 on main; when to raise it is the build's call. For that raise the design recommends **macOS 27.0**: Sasa's Mac already runs 27.2, and nothing in 27.1 or 27.2 is needed (design-system §2). The macOS 27.0 APIs need the macOS 27 SDK, which ships with Xcode 27 (design-system §2), so a raise made on Xcode 26 can reach at most Fallback A (macOS 26.1).
  - APIs that need 27 are marked **(27)** in this spec; each is on the design-system §2 list; the macOS 15 and 26 APIs are gated too (design-system §2, Fallback A row). Until the raise, each (27) API is gated and uses the fallback that design-system §2 names.
- **Standard components only in v0.1:** `NavigationSplitView`, `Table`, toolbars, sheets.
  - They pick up glass automatically [S1].
  - **No custom glass, in any version** (design-system §6). The tables, the invoice editor and the PDF preview are content. The HIG says "Don't use Liquid Glass in the content layer" [S14]. The result line, the one confirmation surface, is opaque (design-system §8.17).
- **Speed principles** used on every screen:
  1. **Prefill from the client.** Every new document inherits the client's defaults.
  2. **Undo instead of confirm.** Only the actions that can't be undone ask first: **Issue** (the review-and-issue sheet, §2c) and Restore from Backup… (an alert, §2h). That follows the HIG alert rule for uncommon destructive actions that can't be undone [S25][S42]. Entering Repair mode (v0.1.x, §2m) is not a confirm: it asks for a reason and for Touch ID or the password. The built Delete Payment dialog stays until its combined Undo ships (§2f).
  3. **Every command is in the menu bar**, so the app can be run keyboard-only [S10]. Shortcuts are shown there. Later (v0.2+): a command palette (§2k; ⌘K stays reserved) mirrors the menus and never replaces them [S18].
  4. **Single keys only inside a focused list**, never while a text field has focus. This is the pattern used by iÚčto, Fakturoid, Linear and Raycast [S116][S102][S129][S131]. In v0.1 the keys are ↩, ⌫ and ⎋, and letters only type-select (Clients, Stock); there are no letter actions (§3.2). `onKeyPress` only fires when its view has focus [S67].
  5. **Critical information goes at the top**, never only at the bottom of a window [S11][S26].
  6. **Launch instantly and restore the previous state**: the sidebar row (a section or a Documents filter), each filter's sort order, and the selections in Overview, Documents, Clients, Payments and Stock (once it ships) [S27]; §1.1 Restore has the details. There is no splash screen. On main the sidebar row and the Payments selection are restored; the rest is still to build.
  7. **Nothing is time-boxed.** No banner, result line or confirmation hides on a timer; each stays until the next action or an explicit close [S16]. Repair mode's timeout ends the mode but never hides its notice (§2m).

---

## 1. Information architecture

### 1.1 Windows (scenes)

v0.1 has two scenes: the main window and Settings.

| Window | Scene | Purpose | Notes |
|---|---|---|---|
| Main window | `WindowGroup(id: "main")`; **one main window** (RECOMMENDATION, as built) | Sidebar navigation across all sections; **drafts are edited in place** in its detail column (§2c) | Don't use `Window` for the main scene: "If your app uses a single window as its primary scene, the app quits when the window closes" [S75]. A `WindowGroup` doesn't enforce one instance, so the File menu replaces the system New group (`CommandGroup(replacing: .newItem)` [S143]; by default `.newItem` "includes … New" [S143]), which removes File ▸ New Window. ⌘W closes the main window. Window ▸ Main Window (`CommandGroup(after: .windowArrangement)`) brings it to the front, or reopens it through `openWindow(id: "main")` after ⌘W (as built). Whether a click on the Dock icon also reopens it is UNVERIFIED on macOS 27.2; check on device. Initialiser: `init(id:content:)` is deprecated at macOS 15.0 ("Use the initializer which takes an escaping content builder instead.") [S156], and `init(id:makeContent:)` is available from macOS 11.0 [S157]. RECOMMENDATION: name `makeContent:` in the call, so the trailing closure can't resolve to the deprecated one. |
| Statement triage (v0.2) | `WindowGroup(for: Statement.ID)` | Match bank lines | SwiftUI lists WindowGroup titles under File ▸ New, and File ▸ New Window passes a `nil` value [S144]. The replaced New group (above) keeps both out, so an empty triage window can't open. |
| Settings | `Settings` scene (macOS only) | App-level configuration (§1.3, §2i) | It enables the app's Settings item and ⌘, [S76]. |

Later (no version set): a document window, `WindowGroup(for: Document.ID)`, opened only through an Open in New Window item in the Document menu or the context menu, never by default ("avoid opening new windows as default behavior unless it benefits your user experience" [S26]). It stays out of File ▸ New in the same way, and `openWindow` brings an existing window for that value to the front [S75]. v0.1 has no document window and no Open in New Window; a draft's preview is View ▸ Show/Hide Preview inside the editor (§2c).

Later (v0.2 or after): the command palette, a sheet on the main window (§2k). ⌘K stays unbound and reserved for it (§3.1).

**Restore.** The main window keeps the sidebar row (`@SceneStorage("sidebar")`) and the Payments selection (`@SceneStorage("payments.selection")`), both as built. It also keeps the Documents selection (stored as joined IDs) and the Overview and Clients selections (each a single ID) (R007, to build), and the Stock selection (a single ID) once Stock ships (RECOMMENDATION). IDs that no longer exist are dropped once the documents load. A stored sidebar value whose row is gone restores to the nearest row (§1.2): "documents.all" as Documents (the same tag), "documents.overdue" as Unpaid, "documents.thisMonth" as Documents, and "rates" or "exports" as Overview.

The main window's title is the section name, the document number or a name (a client; for a draft its client, or "New Invoice" before one is chosen), never the app name. Keep it under 15 characters where the name allows ("Documents", "FV 2026-0042", "Acme GmbH", "New Invoice") [S19]. The subtitle carries the filter or state through `navigationSubtitle` [S100], for example "Unpaid · 3" (§2b).

### 1.2 Main window sidebar

There are at most 2 levels [S20]. Icons follow the accent colour on 27 [S3]. The Unpaid row's overdue state gets a fixed red tint because it carries meaning [S20]. Counts are badges [S80]. Nothing critical goes at the bottom of the sidebar [S20].

This is **the** sidebar; design-system §5.1 and §7 refer to it.

| # | Section | Children | Shortcut | Content column | Detail column |
|---|---|---|---|---|---|
| 1 | Overview | — | ⌘1 | Tiles and the attention queue (§2a) | The selected queue row's document; otherwise a calm placeholder (title only), "Select a document" |
| 2 | Documents (selectable: all documents) | Drafts (badge) · Unpaid (overdue badge, see Badges) · Open advances | ⌘2 | One `Table` with filters (§2b) | Issued view, or the draft editor in place |
| 3 | Clients | — | ⌘3 | Clients table (§2e) | The client page (§2e); otherwise "Select a client" (title only) |
| 4 | Payments | — (v0.2: one row per bank account · Unmatched (badge)) | ⌘4 | Payments list (§2f) | The payment's document |
| 5 | Stock (when Stock ships) | — | ⌘5 | Items table (§2n) | The selected item |

**Documents row.** One selectable row, "Documents", shows all documents (tag `SidebarItem.filter(.all)`). Drafts, Unpaid and Open advances are indented under it. It is expanded by default, and its expanded state is kept in `@SceneStorage`. There is no "Documents" header and no separate All row. Fallback: if a selectable parent row with children doesn't work in a macOS 14 sidebar `List` (UNVERIFIED; try a tagged `DisclosureGroup`), Documents becomes a plain row (⌘2) and the three filter rows follow it at the same level, with no header.

**Badges.**
- Drafts shows its count when it is above 0. The count goes in as an Int (`.badge(count)`; "Set the value to zero to hide the badge" [S80]) or as `count.formatted()`, never as `Text(verbatim: String(count))` (R073).
- While at least one document is overdue, Unpaid shows the overdue count. Its symbol changes from `clock` to `exclamationmark.circle` with `.listItemTint(.fixed(.red))`, and its accessibility value and tooltip read "N overdue" (one plural key). The Documents subtitle on Unpaid then reads "Unpaid · 7 · 3 overdue" (one interpolated key), so the badge and the row count explain each other. With nothing overdue, Unpaid shows `clock`, with no badge and no tint.
- Stock, once it ships, counts its Low items: no badge at 0, no tint (the Low tone is only on the On hand cell, §2n), and the accessibility value "3 running low".
- Documents, Open advances, Clients and Payments have no badge. No row warns about missing rates: a missing rate shows only where a document needs it (§2c). The v0.2 Payments ▸ Unmatched badge stays.

**Keys and focus.** ⌘1…⌘4 choose the sections, and ⌘5 is Stock once it ships. Until then ⌘5 is unassigned, and so is ⌘6 (§3.1). The View menu repeats the rows (§1.4). Choosing a section with ⌘1…⌘5, a View section item or a click on a sidebar row moves keyboard focus into that section's list (`@FocusState` or `defaultFocus`), so letters typed next reach its type-select: "acm" after ⌘3 (§4 task 1), "bol" after ⌘5 (§2n). ↑↓ in a focused sidebar only changes the selection. This is UNVERIFIED until checked on macOS 27.2; if focus stays in the sidebar, each of those budgets gains one ⇥.

Exchange rates, the export for the accountant and the backup are File menu commands (§1.4, §2g, §2h), not sidebar rows.

**One three-column `NavigationSplitView` for every section.** The docs say "macOS always displays the content column" [S142], so a section can't drop it; each section fills the content column as listed above (RECOMMENDATION). No section has an inspector column. The sidebar's SF Symbols are in design-system §7 (checked against SF Symbols data up to macOS 26; confirm them in the SF Symbols 27 app). Stock's symbol (for example `shippingbox`) is chosen and checked for the macOS 14 target when Stock ships.

The sidebar is visible by default ("Avoid hiding the sidebar by default" [S20]) and collapses automatically when the window gets narrow.

### 1.3 Settings window panes

The Settings window uses a noncustomizable toolbar of panes. It always shows the active pane, its title is the pane name, and it reopens on the pane Sasa viewed last [S29] (as built). The HIG says "Minimize the number of settings you offer" [S29], so there are four panes, in this order:

| Pane | Contents |
|---|---|
| General | PDF folder and backup folder (path controls [S49]; the backup folder ships with the backup step), with the last-backup line under the backup folder. No app-language setting: the UI is English only. |
| Company | Legal name, registered office, Company ID (IČO), VAT ID (DIČ), file number (register court + one field), phone, email, footer text (one footer for both document languages; empty by default) |
| Bank Accounts | Accounts: account number (IBAN or Czech), BIC, bank name, currency (EUR, CZK, USD or any) |
| Numbering | Three fixed series: pattern, last issued number, next number with VS; collision check |

A field applies as soon as it is committed, except in Numbering, which has one Save because a used number series can't be changed back. Documents & PDF, VAT defaults and Backup are not panes. A new client's due days (14), the payment tolerance, the QR type by currency, the PDF path, the VAT rates and treatments, and the backup schedule are fixed rules (§2i); a new client's VAT status follows the country rule (§2e).

Details are in §2i.
### 1.4 Menu bar: every command

Menu order: App, File, Edit, View, Document, Stock (when Stock ships), Bank (v0.2), Window, Help [S18]. The app-specific menus are `CommandMenu`s, which sit between View and Window in the order they are declared [S64]. There is no Format menu, because the app has no formatted text editing [S18].

Menu rules:
- Unavailable items are disabled, never hidden [S18].
- An ellipsis means that more input follows [S46].
- A show/hide item's title reads the current state, for example "Hide Toolbar" while the toolbar shows [S18].
- On 27, action items show no icons [S4].
- What File's client and document items, the Document menu and the Stock menu act on comes from `focusedSceneValue`, so the menu bar follows the main window's selection [S66] (as built for File and Document).
- Shortcuts appear here and not in context menus [S47].

**App menu: "FA"** (working name; at most 16 characters [S18])

| Item | Shortcut |
|---|---|
| About FA | — |
| Settings… | ⌘, |
| Services ▸ | — |
| Hide FA / Hide Others / Show All | ⌘H / ⌥⌘H / — |
| Quit FA | ⌘Q |

**File**

| Item | Shortcut | Enabled when |
|---|---|---|
| New Invoice | ⌘N | Always. In client context it reads "New Invoice for Acme GmbH" and prefills that client. |
| New Advance Invoice | ⇧⌘N | Always. Same rule: "New Advance Invoice for Acme GmbH". |
| New Client… | — | Always. Opens the New Client sheet (§2e). |
| New Stock Item… (when Stock ships) | — | Always. Opens the New Stock Item sheet (§2n). |
| — | | |
| Duplicate ‹number› as Draft | ⌘D | A document is selected, other than a tax document for a received payment (as built). The title names an issued document, e.g. "Duplicate FV 2026-0041 as Draft". In client context it names and copies that client's last invoice. For a draft it reads "Duplicate as Draft"; with nothing to copy it reads the same, disabled. |
| Edit Client “Acme GmbH”… | — | A client in context. Opens the Edit sheet (§2e). Without one it reads "Edit Client…", disabled. |
| Add Note to “Acme GmbH”… (with the Activity tab) | — | A client in context. Shows that client's Activity tab and focuses "Add a note…" (§2e). Without one it reads "Add Note…", disabled. |
| — | | |
| Exchange Rates | — | Always. Opens the read-only Exchange Rates sheet (§2g); no ellipsis, because it asks for no input. |
| Import ČNB Rates… | — | Always. Opens the file importer from any section, without switching section or opening the sheet, and reports in the result line. Takes the ČNB daily or yearly file. This is the secondary rate path: in v0.1 Sasa types the rate on the document (§2c, §2g). Drag and drop comes with the v0.2 bank import. |
| Import Bank Statement… (v0.2) | — | Always |
| Export for Accountant… | — | Opens the export sheet (§2h). Disabled until the export step is built, as on main. |
| — | | |
| Back Up Now | — | Always. Runs at once and reports "Backup made at 9:02" in the result line (§2h). |
| Restore from Backup… | — | Always. Asks for the file, shows a preview, then the replace alert (§2h). |
| Show Data Folder | — | The data lives in a file (as built). Shows it in Finder (`activateFileViewerSelecting` [S92]). |
| — | | |
| Repair Mode… (v0.1.x) | — | Always. Asks for a reason, then Touch ID or the password; every change is audited. While the mode is on, the item reads **End Repair Mode** (§2m). |
| — | | |
| Save PDF… | — | An issued document is selected. Drafts can only produce a watermarked preview. |
| Show PDF in Finder | — | An issued document has a saved PDF (uses `activateFileViewerSelecting` [S92]) |
| Print… | ⌘P | A document is selected (prints its PDF through the system print panel [S44]). A draft prints with the fixed-colour "KONCEPT / DRAFT" watermark and the "QR po vystavení / QR after issue" placeholder ("QR po vystavení" alone on a Czech document; document text, §2c) instead of a scannable QR (design-system §8.8). |
| Close | ⌘W | System. Its place is the one macOS 27.2 generates (device check). |

**Client context** is the Clients section with a client selected. Edit Client and Add Note also take the selected document's client when Clients isn't shown (as `menuClientID` resolves it today). Tax documents for received payments and final invoices are created from the advance chain in the Document menu (§2d), not from File.

The New items are the whole File ▸ New group: the menu is built with `CommandGroup(replacing: .newItem)` [S143] (as built), so the system's New Window item and the WindowGroup titles that SwiftUI lists under File ▸ New [S144] never appear. Whether the system item would otherwise also claim ⌘N is UNVERIFIED; the replacement makes it moot.

Close is the system item: the `saveItem` group, which by default holds Close, Save, Save As/Duplicate and Revert to Saved [S162]. The HIG's File order puts Close before Print… [S18]. Where 27.2 places Close and Print… relative to the app's groups is UNVERIFIED, so the table records the order 27.2 generates once it is checked on device; the same check confirms that none of the Save items appears. Print… replaces the system print group (`CommandGroup(replacing: .printItem)`, as built), which by default holds Page Setup and Print [S163], so Page Setup never appears.

Deliberately left out:
- **Open (⌘O), Save (⌘S), Save As/Duplicate (⇧⌘S) and Page Setup (⇧⌘P).** Drafts autosave, so no Save is needed [S43]. The PDF is a fixed A4 page. These shortcuts stay **unbound** and are never reused for anything else (§3.1).

**Edit**

| Item | Shortcut | Notes |
|---|---|---|
| Undo ‹action› / Redo ‹action› | ⌘Z / ⇧⌘Z | The title names the target, e.g. "Undo Record Payment" [S42]. Issue never appears here. |
| Cut / Copy / Paste / Paste and Match Style | ⌘X / ⌘C / ⌘V / ⌥⇧⌘V | Copy on a document row puts the PDF file and a plain-text summary on the pasteboard (multiple representations [S36]; `copyable` [S99]). Whether Mail accepts the pasted file is **UNVERIFIED**. |
| Delete | ⌫ | Enabled only when the focused selection can be deleted (see Delete below). Every deletion can be undone. |
| Select All | ⌘A | — |
| Find ▸ Find… (system), or Search… and Jump to Search Field | ⌘F / ⌥⌘F | One ⌘F and one ⌥⌘F, never bound twice (see Find below) |
| Spelling and Grammar ▸ · Substitutions ▸ · Transformations ▸ · Speech ▸ · Start Dictation · Emoji & Symbols | system | They act on the text field that has focus [S18]. The four submenus share the system `textEditing` group with Find ▸ [S159]; the system adds Start Dictation and Emoji & Symbols itself [S18]. |

**Delete.** ⌫ deletes a draft, a manual payment that no issued document rests on (§2f), a client note (with the Activity tab) or a stock item with no movements (when Stock ships, §2n). `onDeleteCommand` fires on ⌫ or ⌦ while the view has focus [S68]. For any other selection the view installs no `onDeleteCommand` action, so Edit ▸ Delete is disabled; the action parameter is optional [S68], and that a nil action disables the item is UNVERIFIED (check on device). An issued document is never deletable, and a stock item with movements is archived (Stock menu). Line items are deleted through Document ▸ Delete Line or the row's context menu, not ⌫ (§2c).

**Find.** Check on macOS 14 and 27.2 whether the system Find ▸ Find… ⌘F presents the current section's toolbar search.
- If it does, it stays, and the app adds only Jump to Search Field ⌥⌘F.
- If it doesn't, Search… ⌘F and Jump to Search Field ⌥⌘F take the place of the Find ▸ items. Find ▸ is in the same system group as the text submenus [S159], so whether it can be replaced on its own is UNVERIFIED.

The app's items set the section's `isPresented` binding on `.searchable(text:isPresented:placement:prompt:)` with `.toolbar` placement (macOS 14.0 [S158]) in Documents, Clients, Payments and, once it ships, Stock. On Overview, which has no search field, ⌘F and ⌥⌘F switch to Documents and present its search. While the toolbar is hidden, they show it first if hiding it removed the field. In the field, ↩ moves focus to the first result (§2b). Check on device that presenting the search focuses the field on macOS 14 and 27.2; if it doesn't on 14, ⌘F there switches to Documents and the field takes one click.

**View**

The system rows come first, in the order macOS 27.2 generates them (device check). Until that check, the table follows the HIG's order: Show/Hide Toolbar, Customize Toolbar, Show/Hide Sidebar, Enter/Exit Full Screen [S18]. The app's rows follow through `CommandGroup(after: .sidebar)` (as built).

| Item | Shortcut | Notes |
|---|---|---|
| Show/Hide Toolbar | ⌥⌘T | System, from `ToolbarCommands` (as built; see Toolbar below). ⌥⌘T is the HIG standard for "Show or hide a toolbar" [S17]; the `ToolbarCommands` docs page doesn't state the key it generates, so check the generated menu (UNVERIFIED). |
| Show/Hide Sidebar | system default from `SidebarCommands` | As built. The default shortcut is **UNVERIFIED**: the doc page doesn't state it [S57]. |
| Enter/Exit Full Screen | ⌃⌘F | System. It shares the `sidebar` group with Show/Hide Sidebar [S161], so the app's rows come after it. |
| — | | |
| Overview, Documents, Clients, Payments · Stock (when Stock ships) | ⌘1 … ⌘4 · ⌘5 | Section navigation, not window navigation [S18]. Choosing one moves keyboard focus into the section's list (§1.2). |
| — | | |
| Filter ▸ All Documents / Drafts / Unpaid / Open Advances | — | Always enabled: picking one switches to Documents and selects that sidebar row. The current filter has a checkmark while Documents is shown, and no item has one elsewhere. |
| Sort By ▸ ‹columns› · Ascending / Descending | — | The current table's sortable columns in header order, with a checkmark on the current column, then a divider and Ascending / Descending with a checkmark on the current direction. Choosing a column keeps the direction. Disabled where there is no table (Overview). |
| — | | |
| Show/Hide Preview | — | A draft in the editor: swaps the detail column between editor and PDF preview (as built). |
| Client Tab ▸ Documents / Activity / Items | — | A client page is shown (Clients with a client selected). Checkmarked, so the tabs have a path that doesn't depend on Tab. Items is listed once Stock ships, and is disabled while no stock item exists (§2e). |
| — | | |
| Bigger Text / Smaller Text / Actual Size | ⌘+ (⇧⌘=) / ⌘− / ⌘0 | Scales **every content surface** (tables, editor, issued view, Overview, totals, sheets) from 100 to 200 % [S16] (design-system §3). ⌘0 is **UNVERIFIED** as a convention; it isn't in Apple's tables. |

**Toolbar.** The toolbars are fixed (design-system §8.11), so Customize Toolbar… never shows. The system toolbar group holds Show/Hide Toolbar and Customize Toolbar by default [S160]. If Customize Toolbar… shows on 27.2, `CommandGroup(replacing: .toolbar)` takes the place of `ToolbarCommands`, with one item whose title reads the state (design-system §8.11); then check that View has exactly one Show/Hide Toolbar item and that the traffic lights stay.

Later (v0.2 or after): Command Palette… ⌘K joins View when the palette ships (§2k). ⌘K stays unbound and reserved until then (§3.1).

**Document** (app-specific; applies to the selected document or the draft in the detail column)

| Item | Shortcut | Enabled when |
|---|---|---|
| Issue… | ⌘↩ | A draft is focused (in the detail column, or a draft selected in the list) |
| Record Payment… | ⌘R | An issued document with an open balance that is not closed and not a tax document for a received payment (as built), and not an advance that an issued final invoice has deducted or settled as "Paid in advance" (R065): money that arrives later is recorded on the final invoice. On an overpaid document the same row reads **Record Refund…**, and ⌘R opens it. |
| Create Tax Document for Payment | — | An issued advance, other than an EU-goods (§ 64) advance, with one or more received payments that have no tax document. It acts on the oldest such payment. An EU-goods advance takes no payment tax document (ADR 0012, built in PR 22; ACCT). |
| Create Final Invoice | — | An issued advance that has at least one payment, is not closed, and has not been deducted or settled as "Paid in advance" by a final invoice. On a paid EU-goods advance it is the next step, and the final invoice carries the advance's payments as "Paid in advance" (ADR 0012, built in PR 22; §2d). On any other advance, while a payment still waits for its tax document, it refuses with the built message (§2d); the chain line offers it only once every payment's tax document is issued. |
| — | | |
| Add Line Item | ⌘L | Editor. Inserts a line below the one that holds the cursor, otherwise at the end. |
| Add Discount | — | Editor, with the cursor in a line. Shows the Discount % column and focuses that line's cell (§2c). |
| Delete Line | — | Editor, with the cursor in a line. **No shortcut** (⌘⌫ stays unbound, §3.1); also in the row's context menu. Undoable. |
| Move Line Up / Move Line Down | — | Editor, with the cursor in a line. No shortcut on purpose, to keep custom shortcuts few [S17]. Dragging also works on 27. |
| Don't Take from Stock (when Stock ships) | — | Editor, with the cursor in a line linked to a stock item. Undoable; picking the stock suggestion again links the line again (§2n). |
| — | | |
| Change Type ▸ Invoice / Advance Invoice / Final Invoice | — | Draft (checkmark on the current type). Not on a tax document for a received payment: that type is created only from its payment and can't be changed (§2d, ADR 0009). |
| Currency ▸ EUR / CZK / USD | — | Draft (checkmarked). Not on a tax document for a received payment, which takes its payment's currency (as built). |
| Document Language ▸ Czech / Czech + English | — | Draft (checkmarked) |
| VAT Treatment ▸ EU Goods, Exempt (§ 64) · EU Services, Reverse Charge, a divider, then Czech VAT · Outside EU, Services · Other Exemption | — | Draft (checkmarked; the editor's VAT treatment pop-up, §2c). Other Exemption takes an ellipsis only if choosing it asks for the exemption reference. |
| Bank Account ▸ ‹the accounts that fit› | — | A draft for which two or more bank accounts fit the currency (checkmarked; §2c) |
| Enter Rate… | — | A draft of a tax document in EUR or USD (as built). Moves focus to the draft's inline rate form for its rate day (§2c), or opens Change… when a rate is already set. The v0.1 rate path. |
| — | | |
| Close Advance as Unpaid… | — | An issued advance with no payment and no deduction, as built (§2d). On a closed advance the row reads **Reopen Advance**, which acts at once and can be undone ("Undo Reopen Advance"). |
| Mark for Credit Note… | — | An issued tax document (§2d). On a marked document the row reads **Remove Credit Note Mark**, which acts at once and can be undone ("Undo Remove Credit Note Mark"). |
| — | | |
| Show Client | — | A document with a client is selected. Selects that client in Clients (as built). |
| Show Related Documents ▸ | — | A document in an advance chain. One item per other document of the chain, in the chain line's order, named by type and number: "Advance ZF 2026-0003", "Tax Document DD 2026-0007", "Final Invoice FV 2026-0050"; a draft step reads "Final Invoice (Draft)". Choosing one shows that document; a draft opens in the editor. This is the menu path for the chain line's links (§2d). Disabled outside a chain. |
| — | | |
| Delete Draft | — | A draft is selected. Undoable, like Edit ▸ Delete. |

The Change Type, Currency, Document Language, VAT Treatment and Bank Account submenus give every header choice a path that doesn't depend on Tab (§2c).

**Stock** (when Stock ships; app-specific, after Document; §2n)

| Item | Shortcut | Enabled when |
|---|---|---|
| Count “Bolt M8”… | — | A stock item is selected in Stock. ↩ on the selected row does the same (§3.2). |
| Receive “Bolt M8”… | — | A stock item is selected |
| Take Out “Bolt M8”… | — | A stock item is selected |
| — | | |
| Archive “Bolt M8” | — | The selected item has movements. Undoable. An item with no movements is deleted instead, with Edit ▸ Delete ⌫ (undoable). |

With no item selected, the items read Count…, Receive…, Take Out… and Archive Item, disabled, never with an empty name. None has a shortcut. New Stock Item… is in File, and Don't Take from Stock is in Document. The undo titles are Undo Count, Undo Receive, Undo Take Out and Undo Archive. The item detail's toolbar Count… and Receive… run the same commands.

**Bank (v0.2)**

| Item | Shortcut | Notes |
|---|---|---|
| Accept Suggestion | ↩ in the triage list | — |
| Accept Exact Matches (N) | — | The same command as the prominent toolbar item (its only placement in the window), and a palette command if the palette ships with v0.2. No shortcut: ⇧⌘A is Deselect All. |
| Find Document for Line… | ⌘F in the triage window | — |
| Not an Invoice ▸ categories | N in the triage list | The menu (and the palette, if it ships with v0.2) is the fallback if type-select eats N (§3.2) |
| Skip | S in the triage list | Same fallback |
| Unmatch | — | Undoable. Blocked when an issued document rests on the payment (§2f). |
| Show Monthly Cash View | — | — |

**Window**: Minimize ⌘M · Zoom · the window-tiling items macOS 27.2 adds, if any (device check) · Bring All to Front · **Main Window** · the window list [S18] (document windows are later, §1.1). Main Window is `CommandGroup(after: .windowArrangement)`, the group that holds Bring All to Front [S164] (as built): it brings the main window to the front, or reopens it after ⌘W.

**Help**:
- The system search field. The HIG ties it to the Help Book format [S18], so whether it shows in an app without a help book, and that it also searches the menus, is UNVERIFIED: check on 27.2.
- FA Help ⌘?, the system item of the `help` group [S165]. Until help content exists, `CommandGroup(replacing: .help)` replaces it with Getting Started only if both of these hold on 27.2 after the replacement: the Help menu still has its search field, and ⌘? still opens the Help menu. Otherwise the system item stays.
- Getting Started (`CommandGroup(after: .help)`, as built): shows the setup card on the Overview again (§2j).

---

## 2. Screen specs

### (a) Overview

**Purpose.** Open the app and see what needs doing, and how the month looks, in under a second.

**Layout.**
- Sidebar | Overview in the **content** column | the detail column. The detail column shows the selected document row's issued view or draft editor. With nothing selected, or a row that is not a document selected, it shows `ContentUnavailableView` "Select a document", title only (§1.2). macOS always displays the content column [S142], so this is the buildable form of "one screen of attention". No inspector. The selected row is restored with the window (§1.1 Restore).
- The content scrolls. The toolbar follows design-system §8.11: a leading title "Overview" and one plain **New Invoice** button (symbol `plus`, tooltip "Create a new invoice"). A click is File ▸ New Invoice (⌘N); New Advance Invoice stays at ⇧⌘N and in File. The toolbar has no search field.
- Edit ▸ Find ▸ Search… (⌘F) on Overview switches to Documents, which shows all documents, and presents its search field (the §1.4 Find mechanism). If presenting doesn't focus the field on macOS 14, the field takes one click there (§1.4). Budget #4's search path stays 8 K: ⌘F · 0042 · ↩ · ⌘R · ↩ (§4).

**Content, top to bottom.** Three blocks: the two tiles for today, the queue, then the month.

1. **Unpaid and Overdue tiles.**

   | Tile | Value | Secondary lines | Click |
   |---|---|---|---|
   | Unpaid | Open balances of invoices and final invoices, one per currency and never summed: "18 400,00 €" and "35 000 Kč" | "7 documents". A second line shows only while an advance has an open balance: "Unpaid advances: 2 · 3 000,00 € · 1 overdue". It is one full-sentence key with one-forms, and "· N overdue" appears only above 0. This line is its own link to Documents ▸ Open advances. | Documents ▸ Unpaid |
   | Overdue | Overdue open balances of invoices and final invoices, per currency. With nothing overdue the value is "—" and there is no line. | "3 documents · oldest 23 days", with the forms "1 document" and "oldest 1 day" | Documents ▸ Unpaid, sorted by Due, oldest first, even if Sasa chose another sort for Unpaid earlier, so overdue rows always come first |

   - Later (v0.2): a caption under these tiles, "Payments recorded up to 31. 10. 2026", from each account's last imported statement period. It tells Sasa that "Overdue" may include clients who already paid after that date. Whether v0.1 needs it depends on whether Sasa records payments in one go from a monthly statement (§6).
2. **"Needs attention" queue.**
   - It is a keyboard-navigable `List` with selection. ↑↓ selects, and ↩ runs the selected row's action; no other single key acts on the queue. ⌘R and the Document menu work on a selected document row. A restored selection (§1.1 Restore) stays selected, so ↓ then moves to the row after it; the §4 budgets that start with ⌘1 · ↓ assume nothing is selected yet, and from a restored selection the wanted row may need ↑ or ↓ more.
   - Document rows carry no buttons. Selecting one shows the document in the detail column, with its one prominent action.
   - The groups appear in this order:
     1. Overdue documents, the most days overdue first: "FV 2026-0031 · Beta s.r.o." / "23 days overdue" / the open balance. The symbol is `exclamationmark.circle.fill` in red, the one red place on Overview; the words carry the meaning, never the colour alone [S13]. ↩ opens **Record Payment…**. Not listed: an advance that an issued final invoice deducted or settled as "Paid in advance", an advance closed as unpaid, and a document marked for credit note.
     2. Advances whose received money has no tax document yet: "Payment received, tax document missing", with the amount that has no tax document. ↩ runs **Create Tax Document for Payment** (the oldest payment without one). Only advances whose treatment needs a payment tax document are listed. An EU-goods (§ 64) advance never appears: under the goods decisions (a) it gets no payment tax document, and its next step is Create Final Invoice in the Record Payment success step (§2d; ADR 0012, built in PR 22).
     3. Later (v0.2): unmatched bank lines. ↩ runs **Triage**.
     4. "October 2026 · 1 document changed after export", the same words as the export sheet's status line (§2h), with a trailing **Export Again…** button that opens the export sheet on that month. ↩ does the same. The row appears when a document is issued, or changed in Repair mode (§2m), in a month that was already exported. It stays until that month is exported again.
     5. Backup, with a trailing **Back Up Now**. ↩ does the same. A fixed rule picks the wording, and the first match wins: "Backup failed: ‹reason›" from a failed backup until the next one succeeds, shown at once; "No backup yet" while no backup has ever succeeded; "Last backup 9 days ago" while the last successful backup is more than 7 days old. A backup runs on each day's first launch, on quit and before each export (§2h), so the last two appear only when backups have not run.
   - With every group empty, the queue shows "All caught up" (`checkmark.circle`, `.secondary`).
   - This follows Fakturoid's unpaired payments [S107] and iDoklad's notifications widget [S115].
3. **The month: the month bar and the Issued and VAT tiles.**
   - **Month bar:** "◀ November 2026 ▶". The default is the current month, and one click goes to the previous one. The ◀ ▶ buttons are labelled "Previous month" and "Next month" (as built).

   | Tile | Value | Secondary line | Click |
   |---|---|---|---|
   | Issued in November | The month's revenue from tax documents, per currency, by issue date (aggregation rules). The value is "—" when no tax document was issued that month. | "9 documents", counting every type issued that month; no line when nothing was issued | Not a button: no list is filtered to a month |
   | VAT for November by DUZP (CZK) | "42 180 Kč": the Czech VAT in CZK on the tax documents whose DUZP falls in the month. A final invoice counts net of the advance VAT its payment tax documents already taxed. Czech VAT only, as built. | One line, shown only above 0: "EU services, reverse charge: base 80 000 Kč". ACCT: the DUZP grouping and how reverse-charge services are reported. | Not a button |

   - § 64 goods never appear in the VAT tile: it counts Czech VAT only, so § 64 documents need no month rule here. Like any other document, they count in Unpaid, Overdue, the Issued revenue and the queue. The export dates them by their § 22 odst. 1 day (ACCT, §2h).
   - The brief asks for a "VAT summary per month in CZK". That is this VAT tile, stepped through the months with the month bar, and the accountant's CSV (§2h), which holds every month.

**Tiles (all four).**
- Each tile has a label and a value, then its secondary lines.
- Each tile is one VoiceOver element, for example "Unpaid, 18 400,00 euros and 35 000 Czech korunas, 7 documents". The Unpaid advances link is a second element.
- The Unpaid advances line is a separate button, never nested inside the Unpaid tile's own button. Check on device that both keep their click areas (UNVERIFIED).
- Amounts use `.monospacedDigit()` (RECOMMENDATION, design-system §3; not from the typography HIG).
- Every figure follows the **aggregation rules** below.

**Aggregation rules** (RECOMMENDATION; every rule marked ACCT is confirmed with the accountant). The same rules feed the tiles, the client page's "Invoiced this year" (§2e), the multi-selection summary (§2b) and the CSV (§2h); design-system §8.6 points here.

| Figure | Counts | Never counts |
|---|---|---|
| VAT (tile, CSV VAT columns) | Czech VAT on tax documents only: Faktura, DDPP, and the final invoice **net of** the advance VAT its DDPPs already taxed. Grouped by DUZP month (ACCT). | Zálohová faktura (not a tax document); the same advance VAT a second time in the final invoice; § 64 goods, which carry no Czech VAT (the export uses their § 22 odst. 1 day, ACCT) |
| Revenue in "Issued in ‹month›" | Tax documents, by issue date. A Faktura and a DDPP count their total. A final invoice counts its total minus only the advances it deducts through issued DDPPs, which counted already. A § 64 "Paid in advance" deduction, whose advance has no tax document, does not reduce it: the final invoice counts its full value (goods decisions (b)). As built since PR 22 (OverviewView.swift:549, ADR 0012). | Advances; drafts |
| Unpaid, Overdue | Open balances of Faktura and Konečná, per currency. DDPPs are paid by definition. | Advances (they get their own "Unpaid advances" line); a document marked for credit note; an overpaid document (client credit, see Edge cases) |
| Unpaid advances line | Advances with an open balance that no issued final invoice has deducted or settled as "Paid in advance", and that aren't closed (`closedUnpaid`). "· N overdue" counts the overdue ones among them. | — |
| CSV rows | Every issued document, with a "Daňový doklad ano/ne" column | Advance rows never fill the VAT columns |

**Primary and secondary actions.**
- ↩ runs the selected queue row's action.
- ⌘N creates a new invoice; the toolbar's New Invoice does the same.
- ⌘F switches to Documents, which shows all documents, with its search focused.
- Unpaid and Overdue open Documents ▸ Unpaid. The Unpaid advances line opens Documents ▸ Open advances.
- ◀ ▶ step the month block through the months.

**States.** The content shows one state at a time, in this order of precedence. Main still draws the Getting started card above the error banner; this order is to build.
1. *Error* (the database can't be opened): only an inline banner, "Data can't be opened", with the error text, **Try Again**, **Show Data Folder** and **Restore from Backup…**, and an orange (caution-tone) icon, because red appears only for Overdue (design-system P4). It replaces all other Overview content, the Getting started card included, so a database failure always leads to Restore from Backup…, never to Settings. Never an alert at launch [S25]. "Try Again" is the built "Try again" in title case, as design-system §9 asks for buttons. Restore from Backup… stays disabled until the backup step ships (as built).
2. *Setup incomplete, no document yet (first run):* the Getting started card alone (§2j). There is no month bar, no tile, no queue and no "No documents yet". ⌘N and the toolbar's New Invoice still create a draft (§2j).
3. *Setup incomplete, with documents* (for example after the last bank account was removed): the card above the normal content, so overdue documents never disappear from Overview.
4. *Empty* (setup complete, no document): `ContentUnavailableView` "No documents yet", the description "Press ⌘N to create your first invoice." and a prominent **New Invoice** [S79].
5. Otherwise the three blocks above.

- *Loading:* the data is local, so this should be instant. Until the first states arrive, state 5 shows placeholder tiles with `.redacted(reason: .placeholder)` [S38] (as built).
- Help ▸ Getting Started adds the card, all ✓, with a close button (×) and without Open Settings…, above state 4 or 5. It never covers state 1.

**Edge cases.**
- Mixed currencies: shown per currency, never summed. Overview shows no CZK equivalent of foreign-currency sums; the VAT tile is in CZK from each document's own rate (§0 rule 6).
- Overpaid documents are left out of Unpaid. The surplus is refunded with Record Refund… or kept as client credit (§2f).
- Dates are local calendar dates with no time zone maths.
### (b) Documents (Table + detail)

**Purpose.** Find, check and act on any document with the keyboard.

**Layout.** The three-column `NavigationSplitView` [S58]: sidebar | `Table` (content column) | detail (the issued view, the draft editor in place, or the multi-selection summary). There is no inspector.
- Column minimum widths keep the dividers visible [S21]: sidebar 180, content 360, detail 520, window minimum 1080 pt (design-system §5.3).
- The selection, the column layout and each filter's sort come back with the window (§1.1 Restore).

**Toolbar:** the "Documents list" row of the toolbar table in design-system §8.11 (the one toolbar table). The toolbar is fixed; it can't be customized.
- *Leading:* sidebar toggle, title "Documents", and the subtitle: the filter name and its count, "Unpaid · 3" (one interpolated key, the count formatted). While something is overdue, Unpaid's subtitle reads "Unpaid · 7 · 3 overdue".
- **New Invoice:** a plain button (symbol `plus`, tooltip "Create a new invoice"), the same as File ▸ New Invoice (⌘N). It gets `visibilityPriority(.high)` (macOS 26.1, gated) so it survives in narrow windows [S83]. New Advance Invoice is ⇧⌘N in the File menu.
- *Trailing:* the search field, prompt "Search documents".
- No prominent button here. The prominent primary action lives in the editor (Issue…) and in the issued view (Record Payment…): one per context, trailing [S19]. Don't place it with `.primaryAction`, which is the leading edge on macOS [S141].
- Record Payment…, Duplicate and the PDF commands are not in this toolbar. They are in the menus, the row's context menu and the selected document's own toolbar.

**Table columns.**
- Columns can be resized, reordered and hidden. Each column needs a `customizationID` [S60].
- The column state persists with `@SceneStorage` [S60] (as built).
- The table doesn't sort itself, so the model re-sorts when the sort order changes [S59].

| Column | Default | Align | Content |
|---|---|---|---|
| Status | visible | leading | StatusBadge (design-system §4.3): symbol + word, e.g. Draft, Issued, Awaiting payment, Partly paid, Paid, Overpaid, and Overdue with the detail "+12 days · 1 000,00 € left". Overdue replaces the word, tone and symbol; the detail keeps the days and the open balance. Exception: an advance with a received payment that still lacks its tax document shows that instead (design-system §4.3, Label order). Never colour alone [S13]. |
| Number | visible | leading | "FV 2026-0042"; drafts show "—". No lock glyph: the lock shows only on the issued view's lock line. |
| Type | visible | leading | Short type names from §5, text only (no symbol): Invoice / Advance / Tax doc (payment) / Final. The long title is the tooltip. |
| Client | visible | leading | Name, middle-truncated [S23] |
| Issued | visible | trailing | Date. For drafts, the planned issue date in grey. |
| Due | visible | trailing | Date |
| Total | visible | trailing | "4 840,00 €" (monospaced digits) |
| Open | visible | trailing | Open balance in the document currency |
| DUZP | hidden | trailing | Date of taxable supply (the header uses the short form); "—" when the document has none |
| VS | hidden | trailing | Variable symbol |

- There is no Currency column: Total and Open print the currency with each amount.
- Later (no version set): the VAT in CZK and Paid on columns. The accountant's export (§2h) answers both until then. Paid on also needs the last payment date on `DocumentState`.

**Filters** (the sidebar rows, §1.2, and View ▸ Filter ▸, §1.4). Each filter opens with its default sort. After that it remembers its own sort with the window (`@SceneStorage`). iDoklad likewise remembers the last filter [S114].
- **Documents** (all documents): Issued, newest first. Drafts sort by their planned date, so they show up near the top.
- **Drafts:** last edit, newest first.
- **Unpaid:** invoices and final invoices with an open balance, the same set as the Overview's Unpaid and Overdue tiles (§2a aggregation rules). Due, oldest first, so overdue rows come first, each with its Overdue status word. The Unpaid row's overdue badge counts the overdue rows of this set (§1.2). The Overview's Overdue tile opens Unpaid sorted by Due, oldest first, whatever sort Unpaid had before (§2a).
- **Open advances:** issued advances that no final invoice has deducted and that aren't closed, as built. That includes a paid EU-goods advance waiting for its final invoice (PR 22). Issued, oldest first. An overdue advance stays here, where its status badge shows Overdue; it never counts in Unpaid (the app shell, PR #11).

**Detail column.**
- **One issued document:** the issued view (below).
- **One draft:** its editor, right here (§2c). ↩ in the table moves focus into it. Drafts never use the issued view.
- **Several rows:** the multi-selection summary (below).
- **Nothing selected:** "Select a document", a title-only `ContentUnavailableView` with no symbol.

**Issued view** (issued documents only; Overview and Payments show the same view in their detail column, §1.2). From top to bottom, so the critical numbers sit at the top [S11]:
1. **Header:** the number; the English long title with the Czech document title, e.g. "Invoice – tax document (Faktura – daňový doklad)" (`kind.pickerTitle`); the client link (tooltip "Show this client in Clients"); the StatusBadge.
   - A closed document's badge reads "Closed unpaid" or "Marked for credit note", with no detail. Its reason shows once, as one selectable secondary line under the header. There is no closing banner.
2. **Chain line** (§2d), on a document in an advance chain: one text line of links. While a step is missing, it ends in one `.bordered` next-step button in that step's place: Create Tax Document (for the oldest payment without one) or Create Final Invoice. An unpaid or a closed advance has none. It is the only place in this view that links the chain. Document ▸ Show Related Documents ▸ lists the same documents.
3. **PDF not saved:** if Issue couldn't write the PDF file, the problem message with Choose Folder… and Save PDF… (§2c).
4. **Figures** (design-system §8.12): read-only, selectable `LabeledContent` rows [S98], each only where it applies, in this order:
   - Total.
   - Advances deducted −X (a final invoice that deducts advance tax documents), or Paid in advance −X (a final invoice for EU goods; ADR 0012, built in PR 22).
   - Paid, only when above 0.
   - Open balance (invoices, advances and final invoices; never a DDPP).
   - Issued.
   - DUZP (tax documents; not on advances).
   - Due (not on a DDPP).
   - VS.
   - Account: the IBAN of the document's bank account.
   - Rate (EUR and USD tax documents): "1 EUR = 24,315 CZK · for 30. 10. 2026 · Typed", or "· ČNB file" for an imported rate. The date is the rate's own date (§0 rule 6); a fallback is labelled as the last published rate. The rate is for the document's rate day (the DUZP; for § 64 goods the § 22 odst. 1 day), `Document.exchangeRateDay` (ADR 0011, built in PR 21). Mixed documents and DDPPs keep the tax point (ACCT).
   - VAT in CZK, only when Czech VAT is charged on an EUR or USD document (§0 rule 5).

   Under the rows, one line gives the document language and the VAT treatment in short form, e.g. "Czech + English · EU goods, exempt". The short forms are "EU goods, exempt", "EU services, reverse charge", "Czech VAT", "Outside EU, services" and "Other exemption".
5. **Lock line:** `lock.fill`, the only lock in the view, and "Issued 5. 11. 2026 at 19:02 · locked. Corrections via credit note (Phase 2)." The time is the stored issue time. The credit note's Czech title is ACCT (Phase 2).
6. **Payments:** the document's payment rows (§2f).
7. **Activity:** a collapsed `DisclosureGroup`. Each row is its sentence and timestamp, newest first, text only: "Issued as FV 2026-0042", "Received: 1 000,00 €", "PDF saved to …", "Closed as unpaid: …". The only symbol is `wrench.and.screwdriver.fill`, on audited Repair-mode changes (v0.1.x). Full Keyboard Access reaches the disclosure, and VoiceOver can expand it.
8. **PDF row:** the path line (the saved path, or "Kept in the app, not saved as a file yet.") and Save PDF… · Show PDF in Finder · Print… (⌘P), as built. This row is the view's home of the PDF commands. File has the same three, and the row's context menu has Save PDF….
9. **PDF pages:** the page images of the stored PDF (ADR 0010). They show white paper in both Light and Dark mode, because they are content. They come last because they are tall: placed higher, they would push the payments and Activity below the fold.

Every value ZDPH § 29 requires stays visible in this view (in the figures or on the PDF pages) and on the PDF.

**Issued view toolbar** (design-system §8.11, the issued view rows): **Duplicate** (tooltip "Copy this document into a new draft"), then, declared last so it sits trailing, one text-only `.borderedProminent` button: **Record Payment…** while the document takes a payment, or **Record Refund…** on an overpaid one (tooltip "Record money returned to the client").
- A settled document shows Duplicate only: a paid invoice or final invoice, a closed advance, an advance deducted by a final invoice, or a document marked for credit note.
- A DDPP shows no toolbar item: it is never duplicated and takes no payment. Its commands stay in the File and Document menus.
- An advance that an issued final invoice deducted, or settled as "Paid in advance", takes no payment, even when it was only partly paid: neither Record Payment… nor ⌘R appears. Money that arrives later is recorded on the final invoice.
- No Print or Save PDF here: the PDF row has them. On an issued advance the toolbar keeps its built Create Final Invoice until the chain line ships; it leaves the toolbar in that change.
- Duplicate is also File ▸ Duplicate as Draft (⌘D) and in the context menu.
- The closing actions (§2d) are in the Document menu and the context menu, never buttons in this view: Close Advance as Unpaid… / Reopen Advance (advances) and Mark for Credit Note… / Remove Credit Note Mark (tax documents).

**Repair mode** (v0.1.x, §2m): the lock line shows `lock.open.fill`, with the tooltip and VoiceOver label "Unlocked for repair" (design-system §8.18), and reads "Repair mode: changes are logged". Every record that §2m unlocks becomes editable in this view (lines, client snapshot, payments, deductions, closing events and header values), and the Rate row offers Change….

**Keyboard** (single keys only while the table has focus, never in a text field; §3.2). No letter keys are bound: with a row selected, ⌘D duplicates it as a draft and ⌘R records a payment.

| Key | Action |
|---|---|
| ↑ ↓, ⇧↑ ⇧↓ | Select or extend the selection; the detail follows |
| ⌘A | Select all in the current filter |
| ↩ | Open: a draft moves focus into its editor in the detail column; an issued document moves focus into the issued view. Implemented explicitly with `onKeyPress(.return)` on the focused Table [S67]: the `primaryAction` docs describe only the double-click on macOS [S69], so that ↩ triggers it by itself is UNVERIFIED. |
| Double-click | The same as ↩ (`contextMenu(forSelectionType:menu:primaryAction:)`: "a double click performs the primary action" on macOS [S69]) |
| ⌫ | Delete the selected drafts (`onDeleteCommand`, as built; undoable, no confirmation). Issued documents in the selection stay. |
| ⎋ | Clear the search, then the selection |
| Drag | Dragging an issued document's row out of the table (to Mail or Finder) carries its PDF file, like Copy (§1.4 Edit). To build; whether Mail accepts the dropped file is UNVERIFIED (§4 task 6). |

**Context menu** (unavailable items are hidden, not dimmed [S47]; no shortcuts are shown: "Show keyboard shortcuts in your app's main menus, not in context menus" [S47]; at most three groups [S47]):
- **One issued document:**
  - Record Payment… (Record Refund… on an overpaid document) · at most one create item, the chain's next step as on the chain line · Duplicate ‹number› as Draft (never on a DDPP, as built) · Save PDF….
    - Create Tax Document for Payment: an advance, other than an EU-goods (§ 64) advance, with a received payment that has no tax document. It acts on the oldest such payment.
    - Create Final Invoice: an advance with at least one payment, not closed and not deducted, once no payment waits for its tax document. On a paid EU-goods advance it is the next step.
  - Close Advance as Unpaid… / Reopen Advance (advances) · Mark for Credit Note… / Remove Credit Note Mark (tax documents: invoices, DDPPs and final invoices).
- **One draft:** Duplicate as Draft | Delete Draft.
- **Several rows:** one item, "Delete 3 Drafts" (one plural key with the count of selected drafts), when the selection holds drafts. It deletes only the drafts, as ⌫ does. Without a draft there is no menu.
- Examples: an unpaid invoice shows Record Payment… · Duplicate FV 2026-0041 as Draft · Save PDF… | Mark for Credit Note…. An issued advance with no payment shows Record Payment… · Duplicate ZF 2026-0003 as Draft · Save PDF… | Close Advance as Unpaid….
- Not in this menu: Open (↩ or double-click), Show PDF in Finder (File and the PDF row) and Show Client (Document ▸ Show Client and the header's client link). Every item listed is also in the menu bar (File, Document, Edit ▸ Delete).

**Search** (toolbar, trailing; one plain field; it searches as you type [S28]):
- It matches the number, the VS, the client name and the amounts (Total and Open: "4840" matches 4 840,00), ignoring case and diacritics, as built. It also matches the client's IČO and VAT ID and the line descriptions.
- A description search also finds a stock item's documents, because picking the item fills Description with its name (§2n). A description edited later may not match; the item's History lists every document that took from it.
- Pressing ↩ in the search field moves focus to the first result (RECOMMENDATION; test). ⎋ clears the field.
- ⌘F (Edit ▸ Find, §1.4) presents and focuses the field; from Overview it switches to Documents first.
- Later (no version set): search tokens for Status, Type, Client, Currency and Month ("Month: 2026-10"), through `searchable(text:tokens:…)` [S63].

**Multi-selection summary** (two or more rows selected). The detail column shows one summary and nothing else: the title "3 selected", then, under the caption "Totals per currency", up to three figures, each with one amount per currency (never summed across currencies). It is the same idea as iDoklad's "Součet" [S113]. The figures follow the §2a aggregation rules:
- "Revenue (tax documents)": tax documents only. A final invoice counts net of the advance tax documents (DDPPs) it deducts. A final invoice whose advances had no tax document (EU goods, "Paid in advance") counts its full value. Advances and drafts are left out.
- "Open balance": invoices and final invoices with an open balance (the Unpaid set).
- "Unpaid advances": open advances with an open balance, shown only when the selection holds one.
- There is no selection bar under the table, and the summary has no buttons.
- The one bulk action is deleting drafts: ⌫, Edit ▸ Delete and the context menu's "Delete 3 Drafts", with one named Undo. Document ▸ Delete Draft stays a single-document command.
- An export of several documents is File ▸ Export for Accountant… (by month, §2h).
- Later (no version set): Save PDFs to Folder… and Print… for several documents. ADR 0010 already defers the first.

**States.**
- *Empty:*
  - Documents: "No documents yet" + New Invoice.
  - Drafts: "No drafts".
  - Unpaid: "Nothing overdue" with `checkmark.circle`, the one calm positive state (design-system §8.10), and the description "Every issued invoice is paid."
  - Search: `ContentUnavailableView.search` [S79].
- *Error:*
  - When the list stops updating, a problem line above the table reads "The document list stopped updating." with the error text and **Try Again**. The last rows stay listed (as built).
  - A PDF that can't be rendered shows the problem line "Preview unavailable." with the error text and **Try Again**, in the PDF row. The document stays intact.
  - Error text sits next to the problem and says how to fix it, with no blame [S45].

**Edge cases.**
- An issued document whose saved PDF was moved in Finder: the app keeps its own frozen copy of the PDF bytes from issue time. The path line then reads "File moved – use Save PDF…", and Show PDF in Finder is disabled (as built).
- The list keeps every row in memory and sorts there (as built), which suits a few documents a month. Lazy loading and sorting in the database wait until the list holds thousands of rows.
- A draft with no client yet shows "(no client)".

**Build status** (main at 18679ea). Anything main shows on these screens that this section doesn't specify goes. To build:
- the table: the DUZP column; ↩, double-click and ⎋; dragging a row's PDF out; each filter's remembered sort; the subtitle as one interpolated key; the Unpaid empty state; the IČO, VAT ID and description search;
- the context menu: Save PDF…, "Delete 3 Drafts", and at most one create item, with Create Tax Document for Payment acting on the oldest payment without one;
- the issued view: the header's Czech title, the reason line, the chain line, the Account, DUZP, Rate and VAT in CZK rows, the language and treatment line, the issue time in the lock line, and Activity;
- the summary's three figures (main shows Total and Outstanding);
- `acceptsPayment` refusing an advance that a final invoice deducted.
### (c) New invoice: fast path, editor, review and issue

**Build status** (main at 18679ea: the first draft editor, ADR 0009 and PR #12; the live PDF preview and the saved-PDF line, PR #14 and ADR 0010). This section stays the target.
- **Goes from main**, because this section doesn't specify it: the editor's Duplicate toolbar item; the Type, Document language, Order reference and Related document number rows; the Due date picker; the "Default account for the currency" item; the Unit chevron menu; the always-shown Discount % and VAT rate columns with their "RC", "—" and "exempt" cells; the per-document Footer text field; the client field's capsule chips and the 15 % accent tint on its suggestions; the green "Ready to issue" chip; the rate line's leading arrow; the inline rate form's date picker; the red outlines on invalid cells and in the rate form (the orange triangle and the fix-it line stay); and in the Issue sheet the series picker, the Legal notes row, the Notes section, the always-shown PDF row and the two "differs from the client's default" rows.
- **To build:** the floating "On issue" date with its set-by-hand flag, Period with its DUZP default (Q3) and the duplicate rules; the period-text shift and the comparison with the client's last invoice; the Description suggestions; natural-language dates; the Due days line; ⌘L inserting below the current line; Add Discount; the type in the window subtitle; the account as text when one fits, with Document ▸ Bank Account ▸; the chain line (§2d); ⌘D in client context; and in the Issue sheet the rows below, one "Checked" tick per ⚠ row, Fill in… and the "Go to Problem" default button.
- **On main since PRs 21 and 22** (ADR 0011, ADR 0012): the EU goods treatment, the split of the client type into goods and services, the rate day (`Document.exchangeRateDay`) with its two texts, and "Paid in advance".
- **Deferred:** the undo stack (ADR 0009). The document window is deferred too: v0.1 edits a draft in the main window's detail column only (§1.1).

**Entry points** (all create a **Draft** with no number):

| Entry | What it does |
|---|---|
| ⌘N | File ▸ New Invoice. In client context (Clients with a client selected) it reads "New Invoice for Acme GmbH" and prefills that client; otherwise the Client field has focus. The draft opens in the main window's detail column. |
| ⌘D | File ▸ Duplicate ‹number› as Draft: the selected document, or in client context the client's last *Faktura*, as a Draft (in the detail column) |
| Client page toolbar (§2e) | New Invoice for this client, and a duplicate of the client's last invoice ("FV 2026-0038") as a Draft: the same commands as ⌘N and ⌘D in client context |

**Client defaults applied automatically.** Per-contact defaults like these exist in Fakturoid and Native Invoice [S105][S136]:
- currency
- document language ("Czech" or "Czech + English": InvoicingCore `DocumentLanguage.czech` / `.english`, design-system §9)
- VAT treatment, from the client type (§2e): "EU business, goods" gives "EU goods, exempt (§ 64)", "EU business, services" gives "EU services, reverse charge", "Business outside the EU, services" gives "Outside EU, services", and the Czech and consumer types give "Czech VAT (rate per line)". The printed Czech wording is ACCT.
  - A new client's type follows the country rule (§2e): an EU country other than CZ with a VAT ID gives "EU business, goods", so its documents start on "EU goods, exempt (§ 64)".
  - An EU country without a VAT ID: "EU business, goods; Issue waits for the VAT ID" (Sasa sells to businesses only for now ("i dont do b2C CURRENTLY", 6 Nov 2026)). Until the VAT ID is added, the Issue sheet blocks (below).
- due days (14 for a new client, §2e)
- the company's bank account for that currency (Settings ▸ Bank Accounts)

There is no DUZP rule per client (RECOMMENDATION, lean pass): a draft with a **Period** (a month) gets that month's last day as its DUZP, and a draft without one keeps "Same as the issue date". Sasa can change the DUZP on any draft. That keeps a field off the client sheet; Q3 asks whether it matches Sasa's practice (ACCT; Fakturoid has a similar switch for recurring invoices [S112]). There is no QR choice and no fixed VS per client: the QR follows the currency, and Issue derives the VS from the number (header form below).

**A client change applies all of its defaults at once**, as built (ADR 0009): currency, VAT treatment, document language, due days and bank account. It also resets the payment and the rate. There is no defaults banner and no rule that keeps edited fields. Prices are never converted. The Issue sheet's one "Differs from Acme's defaults" check row catches a currency or treatment that differs from the client's (below). ⌘Z for a client change waits for the undo stack. The VAT treatment is chosen once per document, and under Czech VAT each line picks its rate (rule 4, line items below).

**Duplicate rules.** Fakturoid, QuickBooks and iDoklad all reset dates on a copy [S101][S125][S114]. This app resets:
- issue date to **"On issue"**: it floats and becomes the actual day of Issue, unless Sasa sets a date by hand
- Period to the source document's period + 1 month
- DUZP by the client rule (for "last day of the billed period": the last day of the new Period)
- due date to issue date + due days
- the rate, re-picked for the new rate day (the DUZP; for § 64 goods the § 22 odst. 1 day; edge cases below) from the stored rates (File ▸ Exchange Rates, §2g); if none covers it, the inline rate form asks for it
- no number

The copy keeps the source document's VAT treatment, as built; the "Differs from Acme's defaults" check row flags a mismatch. It takes the current company footer, not the source's, and it keeps the lines' stock links (§2n). On main the copy is dated today (issue date and DUZP), takes the client's current term and address, and carries no rate.

**Period text in line descriptions is never changed silently** (v0.1). Legal text on an immutable document must not be rewritten unread, and v0.1 has no credit note to fix a misfire such as "Roční hosting 11/2026–10/2027" or "dle smlouvy ze 09/2026".
- Only a single recognised period **at the start or the end** of a line description is shifted, by the same number of months as Period. Line descriptions are document text, so it recognises Czech and English month names and "MM/YYYY". A period in the middle of a line, or a range, is never touched.
- Each shifted text is highlighted in the editor and can be undone with ⌘Z ("Undo Shift Period").
- The Issue sheet lists the changes as a **⚠ Check** row with "before → after" for each line ("Line 1: září 2026 → říjen 2026", quoting the line's own text), so its "Checked" tick must be set before Issue. That costs one keystroke (Space; the tick has initial focus) and guarantees the text was read.
- If this still misfires in testing, drop the shift from v0.1; explicit placeholders ({month}), as in Harvest, arrive with the Phase 2 templates [S138].

**Editor layout** (in the main window's detail column).
- **Toolbar:** the "Draft editor" row of design-system §8.11.
  - Leading: the title "New Invoice" or the client name. Subtitle: the type and the save state, "Invoice · Draft · Saved", "Advance invoice · Draft · Saved" or "Tax document for payment · Draft · Saved".
  - Then the Preview toggle (View ▸ Show/Hide Preview, tooltip "Show or hide the PDF preview") and, declared last so it is trailing, the text-only **prominent "Issue…"** (⌘↩). There is exactly one prominent action and it sits on the trailing edge [S19]; not `.primaryAction`, which is the leading edge on macOS [S141].
  - No Duplicate: File ▸ Duplicate as Draft (⌘D) has it.
  - Issue… uses `.borderedProminent` (as built). Whether that renders as the HIG's toolbar `.prominent` style is **UNVERIFIED** [research]. AppKit has `NSToolbarItem.Style.prominent` (macOS 26) [S94].
- **Preview:** View ▸ Show/Hide Preview (the toolbar toggle) swaps the detail between the editor (min 520 pt) and the live PDF preview, as built.
- **Chain line** (a draft in an advance chain: a tax document for a received payment or a final invoice): the text-only chain line of §2d sits above the header form. It replaces the final invoice's Related document field and the DDPP's read-only related row: the related document is set from the advance, and the line shows it. A final invoice made with Document ▸ Change Type ▸ Final Invoice has no advance to start from; the line shows the advances it deducts, and with none there is no line.
- **Totals bar**, pinned at the top of the editor (`safeAreaInset(edge: .top)`, as built; design-system §8.6). Its figures follow the treatment:
  - Czech VAT on an EUR document: "Base 4 000,00 € · VAT 840,00 € · Total 4 840,00 €" plus "VAT in CZK 20 424,60 Kč" at 24,315 (rule 5).
  - A no-VAT treatment shows one figure with the treatment: "Total 3 142,50 € · Exempt (§ 64)" (EU goods), "Total 3 142,50 € · Reverse charge" (EU services, Acme), "Total … · Outside EU, services" or "Total … · Other exemption". There is no VAT line (rule 4, ACCT).
  - **Amount due appears only when something is deducted.** A final invoice adds the deduction and "Amount due"; under Czech VAT it keeps "VAT after advances". An EU-goods final invoice reads "Total 10 000,00 € · Exempt (§ 64)" / "Paid in advance −4 000,00 €" / "Amount due 6 000,00 €".
  - **The readiness chip shows only while something blocks Issue:** "1 problem" or "2 problems", with `exclamationmark.triangle.fill`, as an orange bordered button that opens the Issue sheet. When the draft is ready, nothing shows: the prominent Issue… is the call to action. Readiness is shown only in this chip and in the sheet.
  - **The rate line** (EUR and USD tax documents): "1 EUR = 24,315 CZK · for 30. 10. 2026 · Typed" with **Change…**, and no leading symbol. The date is the rate's own date, the ČNB publication day used for the document's rate day (rule 6, edge cases below). A fallback rate keeps `calendar.badge.exclamationmark` and its label. A stale rate shows the stale-rate warning (edge cases below).
  - **The rate is typed here in v0.1.** When no stored rate covers the rate day, the inline rate form takes the rate line's place: the same form as in the Issue sheet (edge cases below). Typing the ČNB rate there is the **primary path** (Sasa types the rate for each invoice, §2g).
- **Header form** (a `Grid`, labels on the leading side). Tab moves top to bottom:
  1. **Client:** type-ahead on name, IČO and VAT ID. Suggestion rows use the system selection highlight; their defaults line uses the short forms, e.g. "EUR · 14 days · EU goods, exempt". The last row is "New Client “X”…", which opens the New Client sheet (§2e). Under the field, problem lines (design-system InlineMessage, problem kind: the triangle and the words, no capsule) read **"VAT ID missing"** when the treatment is "EU goods, exempt (§ 64)" or "EU services, reverse charge" and the client has no VAT ID, and **"Address missing"** when the address is empty. The Issue sheet's ⛔ rows still block.
  2. **Issue date:** until Sasa sets a date by hand, it reads "On issue" and floats to the day of Issue. A date set by hand stays (the set-by-hand flag, stored with the draft).
  3. **Period** (month): sets the DUZP to the month's last day (above) and drives the period-text shift.
  4. **DUZP** (label "Date of taxable supply", short form "DUZP"; the English wording is ACCT), with the built "Same as the issue date" toggle and an ℹ line "DUZP 31. 10. = end of period October 2026". Hidden on an advance.
  5. **Due:** one days field with the resulting date as text, "14 days → Thu 19. 11. 2026", and no date picker.
  6. **Currency:** segmented EUR | CZK | USD (also Document ▸ Currency ▸).
  7. **VAT treatment:** a sentence-case pop-up [S30] with a divider after the EU pair: "EU goods, exempt (§ 64)", "EU services, reverse charge" | "Czech VAT (rate per line)", "Outside EU, services", "Other exemption" (also Document ▸ VAT Treatment ▸, in title case, §1.4). The exemption-reference field appears beside it only for "Other exemption". The printed texts are in the design-system §9 legal strings table (ACCT).
  8. **Bank account:** the one account that fits the currency, as plain text. A pop-up appears only when two or more fit, with the default preselected as an ordinary entry (also Document ▸ Bank Account ▸). With no account that fits, there is no account row, and the Issue sheet's ⛔ row "The document has no bank details." blocks Issue.
  - **Not in the header:**
    - Type: Document ▸ Change Type ▸ changes it; the subtitle shows it, and the Issue sheet's Type row confirms it.
    - Document language: the client's default applies; Document ▸ Document Language ▸ changes it, and the Issue sheet's Language row shows it. It sets the document text only, never the UI.
    - VS: assigned at Issue from the number; the Issue sheet's Payment row shows the predicted VS.
    - Order reference: in Notes on PDF (below).
    - Related document: the chain line (above).
  - **The QR follows the currency** (`PaymentInstructions.standard`, ADR 0010): CZK → QR Platba, EUR → EPC QR (SEPA), USD → none. There is no QR when nothing is payable: a DDPP, or a final invoice with an amount due of 0 or less. v0.1 has no QR choice in the editor, on the client or in Settings, and no in-app QR image; the Issue sheet's Payment row names the QR type.
  - **Until Issue, a draft shows the current client card and company profile.** An edit there (a VAT ID, an address, the company DIČ) reaches every open draft, so its problem lines and ⛔ rows clear without re-picking the client. Only the party data is refreshed; the draft's other fields keep their values. Issue takes the snapshot (step 4 below).
  - **Keyboard paths that don't depend on Tab.** Whether a default setup (Full Keyboard Access off) skips segmented controls and pop-ups when tabbing is UNVERIFIED; the HIG treats such controls as Full Keyboard Access territory [S17]. So every pop-up and segmented choice also has a checkmarked Document-menu item: Change Type ▸, Currency ▸, Document Language ▸, VAT Treatment ▸ and Bank Account ▸ (§1.4).
- **Line items** (an editable grid; design-system §8.5):
  - Columns: Description · Qty · Unit · Unit price · [Discount %] · [VAT rate] · Line total (read-only), then the row's problem marker. Five columns show by default.
  - **Unit** is a text field. On macOS 15 and later (behind `if #available`) it offers the built unit list (hod, h, ks, pcs, den, day, MD, km) through `textInputSuggestions(_:)` (macOS 15.0 [S166]); on macOS 14 it is plain text. There is no chevron menu. Units print on the document, so they are document text.
  - **VAT rate appears only under "Czech VAT (rate per line)"** (rule 4): a text field with the built suggestions "21", "12" and "0" (no pop-up, so it needs no Tab-to-control). Under every other treatment the column and all VAT amounts are hidden, and no "RC" cells appear; the header and the totals bar state the treatment once. Neither reverse charge nor an exemption is offered per line: both are document-level treatments (VAT treatment pop-up, ADR 0009). Mixed documents only if the accountant confirms them (ACCT).
  - **Discount %** is hidden until a line has a discount. Add Discount (the line's context menu or Document ▸ Add Discount, with the cursor in a line) shows the column and focuses that line's cell. The column disappears when no line has a discount.
  - Fully empty trailing lines are dropped on save and at issue (all of them, not only the last one); they never count as invalid and never print.
  - Reorder with Document ▸ Move Line Up / Down or the line's context menu; on 27 also by drag: `reorderable()` + `reorderContainer(for:isEnabled:move:)` are **(27)** [S96].
  - **The line's context menu** (unavailable items are hidden, no shortcuts shown): Add Line Item (inserts below this line) · Move Line Up · Move Line Down | Add Discount · Don't Take from Stock (a linked line, when Stock ships) | Delete Line. Move Line Up is left out on the first line and Move Line Down on the last. Every item is also in the Document menu (§1.4).
- **Stock in the lines** (when Stock ships; the item model and the movements are in §2n). Stock never blocks a draft, a review or Issue (§2n rule 2).
  - **No new column.** The Description suggestions (line entry below) also list the stock items whose name matches, first, each with its on-hand figure as secondary text ("120 ks in stock"). They appear on Invoice, Advance invoice and Final invoice drafts, never on a tax document for a received payment.
  - **Picking a stock item** fills Description with the item's name and Unit with its unit, and links the line to the item. **Unit price** is prefilled from the last issued line for that item in the draft's currency; with none, it stays empty. An item has no stored price. Editing the description afterwards keeps the link.
  - **A linked line shows one symbol** at the trailing edge of its Description cell: `shippingbox` (macOS 11.0 in the SF Symbols data that design-system §7 cites), with the tooltip and VoiceOver label "Takes from stock: Bolt M8 (120 ks on hand)".
  - **Unlink:** the line's context menu or Document ▸ Don't Take from Stock, undoable. Picking the suggestion again links the line again.
  - **No match:** the suggestion list ends with "Add “‹typed text›” to Stock…", which opens New Stock Item… prefilled with the name and the line's unit, then links the line, as "New Client “…”…" does in the client field.
  - **Only an Invoice or a Final invoice takes goods out**, at Issue (§2n rule 5). An advance's linked lines take nothing, and Create Final Invoice copies the lines with their links, so the goods leave once, with the final invoice. Duplicate as Draft copies the links. Change Type keeps them; they count again once the type is Invoice or Final invoice.
  - The link lives outside the document (the build's draft-side table): the document JSON, its hash and the PDF never mention stock (§2n rule 4).
- **Notes on PDF:** one disclosure group under the lines holds two fields, **Note** (one-off document text, printed above the lines) and **Order reference**. It is collapsed when both are empty and opens by itself when either has text, for example after Duplicate. There is no per-document footer: every document, DDPPs included, prints the one company footer from Settings ▸ Company, empty by default. New drafts, Duplicate as Draft, Create Final Invoice and Create Tax Document all take the current company footer.

**Line entry, keyboard first.**

| Key | Effect |
|---|---|
| Typing in Description | Suggests earlier lines with their last unit, price, VAT rate and discount (Fakturoid's price list "našeptává" and Invoiceur's reuse of past items are the model [S104][S135]). Stock items come first, when Stock ships (above). |
| Tab | Accepts the suggestion and moves to Qty. Otherwise moves to the next cell (⇧Tab goes back). |
| ↩ in a cell | Commits and moves down to the same column in the next row. On the last row it adds a new line and focuses its Description (RECOMMENDATION, spreadsheet-like; as built). Empty trailing lines are dropped later. |
| ⌘L | Add Line Item: inserts a line below the one that holds the cursor, otherwise at the end, and focuses its Description |
| Delete a line | Document ▸ Delete Line or the line's context menu, with undo. No key: a grid of text fields has no "row focused" state, and ⌘⌫ stays unbound (§3.1). |
| ⎋ in a field | Revert the field (as built, with `onKeyPress(.escape)` on each field [S67]) |

**Fast entry for dates and amounts.**
- Dates (Issue date, DUZP) accept "today", "+14", "-1", "14d", "30.11." and "30.11.2026". The resolved date and weekday show next to the field. Things' parser is the model [S127]. Due takes days, not a date.
- Amounts accept a decimal comma or point and spaces, by the one separator rule in design-system §8.3 (in a comma-grouping locale "1,234" is 1234 and "36,5" is 36.5; rate fields always read "24,315" as 24.315).
- `TextField(value:format:)` leaves the bound value unchanged if parsing fails [S70]. So show an inline error and never lose input.
- When the value commits (per keystroke or on focus loss) is **UNVERIFIED**. The editor must commit on ⌘↩, on selection change and on ⌘W.
- Money is `Decimal`. **One locale rule in both spec files** (design-system §8.2/§8.3): editor **input** uses the **UI locale** and a plain number format (`Decimal.FormatStyle(locale:)`, never `Currency`, so the currency isn't typed twice next to its suffix label); the **preview and PDF** use the PDF locale (Czech formatting in both document languages). The locale is always passed explicitly, because it defaults to `.autoupdatingCurrent` [S71].

**Live preview.**
- Re-render the PDF about 300 ms after typing stops (RECOMMENDATION) and keep the last frame visible to avoid flicker.
- The preview is exactly what will be issued, except for three draft markers (document text, so they keep their Czech): the "KONCEPT / DRAFT" watermark (a fixed mid-grey colour drawn into the PDF, so it survives Dark Mode and printing; design-system §4.1), "Číslo bude přiděleno při vystavení / number assigned at issue" in place of the number, and a "QR po vystavení / QR after issue" placeholder instead of a scannable QR (a draft has no VS yet, so a payment from it couldn't be matched; design-system §8.8). The same applies to Print of a draft. The watermark reads "KONCEPT / DRAFT" on every draft, a Czech-only one included, so anyone who sees a printed draft can tell it apart from a document; the number and QR placeholders, and the QR-unavailable notice, follow the document language (the Czech part alone on a Czech document).
- The draft watermark is always on; it is not a setting.

**Autosave and undo.** Every change saves immediately. There is no Save command and no unsaved dot [S43]. Edits can be undone one by one, with named actions [S42].

**Edge cases in the editor.**
- **Changing the currency with lines filled in** keeps the typed prices, with no conversion offer; the totals bar shows the new currency. Fakturoid also leaves prices unconverted [S104]. The Issue sheet's "Differs from Acme's defaults" row catches a currency that differs from the client's.
- **A rate day whose rate isn't stored yet.** The rate day (the DUZP; for § 64 goods the § 22 odst. 1 day) is the day the document needs the rate for. It is `Document.exchangeRateDay` (ADR 0011, built in PR 21): for a document whose lines are all § 64 goods, the 15th of the month after the supply, or the issue date if the document is issued before that 15th (§ 22 odst. 1 ZDPH); otherwise the DUZP. Mixed documents and DDPPs keep the tax point (ACCT).
  - This is the **common case** for the monthly invoice: the DUZP is the end of the previous month, and the app is offline. In v0.1 it is also the **normal path**, because Sasa types the ČNB rate on the document: "for start everything that nmeeds to be online i willů do manualy, s ill type current cnb rate for each invoice" (Sasa's answer in the proposal doc, 5 Nov 2026).
  - The totals bar and the Issue sheet's Rate row both show the **inline rate form**: the label "EUR rate for 30. 10. 2026 missing", naming the day; one rate field; **Save Rate** (↩, source "Typed"; as built); then the secondary **Import ČNB Rates…** (a file dialog). The form is ExchangeRateRow's missing state (design-system §8.9). There is no date picker in the form; after saving, Change… keeps its own date field for corrections. A bad value shows the orange fix-it line ("Enter the rate as a number, such as 24,315"), with no red outline.
  - In the Issue sheet the rate field has initial focus (as built), and saving re-validates the sheet in place without closing it. In the editor, Document ▸ Enter Rate… moves focus to the form.
  - The rate is also stored (File ▸ Exchange Rates, §2g), so the next document with the same rate date picks it up.
  - The needed publication date is the rate day itself, or for a weekend or holiday the last publication day before it, labelled (rule 6; §2g). Weekday public holidays resolve the same way through the built-in holiday table (§2g).
  - On a goods-only § 64 draft whose issue date floats, the rate day can be the day of Issue, so a rate typed on an earlier day may no longer fit. The Issue sheet resolves the rate again each time it opens (as built) and shows the form when it is needed.
  - A rate dated after the rate day is blocked: "The rate date cannot be after <day>, the day this document needs the rate for." A rate more than 7 days older than the rate day gets the stale-rate check row: "The exchange rate is from {detail}, more than a week before the day the document needs the rate for; check that the rate table is complete." (InvoicingCore `exchangeRateAfterTaxPoint` and `exchangeRateStale`, with the texts built in PR 21; §2g.)
  - Later (v0.2): dropping a ČNB file, with the bank import's drop zone (design-system §8.13). In v0.1 nothing in the window takes a dropped file; File ▸ Import ČNB Rates… and the form's Import ČNB Rates… stay.
  - Q7 (a link to the ČNB page in Sasa's browser) is still open (§6).
- **A document in a month already exported** to the accountant needs its ⚠ tick in the Issue sheet. The month follows the export's rule (§2h): tax documents by DUZP, advances by issue date, § 64 goods by the § 22 odst. 1 day (ACCT).
- **Changing the type in a draft** (Document ▸ Change Type ▸) is allowed between invoice, advance invoice and final invoice, because no number exists yet; a tax document for a received payment keeps its type (§1.4, ADR 0009). Fakturoid locks the type after creation [S104]; that limitation doesn't apply here.

#### The review-and-issue step

This step is irreversible, so it is designed to be quick in the common case and loud only when something is unusual.

- **Trigger:** ⌘↩, the toolbar **Issue…** button (its ellipsis means a sheet follows [S30]), the readiness chip, or Document ▸ Issue….
- **Sheet** (`formSheetSized`, as built: a 560–720 pt width range, plus `presentationSizing(.form)` on macOS 15 and later [S90]; design-system §5.3). Its contents depend on the document kind (design-system §8.16): an advance shows no DUZP, no rate and no VAT in CZK; a DDPP shows no QR; a final invoice shows the advances deducted, or "Paid in advance".
- **Heading:** "Issue invoice FV 2026-0042?" with the number the series will assign, and "Once issued, the document can't be edited or deleted." (as built). There is no series picker: one series per type (§2i).

```
┌────────────────────────────────────────────────────────────────────┐
│ Issue invoice FV 2026-0042?                                        │
│ Once issued, the document can't be edited or deleted.              │
│                                                                    │
│ Type      Invoice – tax document (Faktura – daňový doklad)         │
│ Client    Acme GmbH · VAT ID DE123… · EU services, reverse charge  │
│ Language  Czech + English                                          │
│ Dates     Issued today · DUZP 31. 10. 2026 (end of period)         │
│           · Due 5. 12. 2026                                        │
│ Total     3 142,50 €          VAT  — (daň odvede zákazník)         │
│ Rate      1 EUR = 24,315 CZK · for 30. 10. 2026 · Typed            │
│           · last published                                         │
│ Payment   EPC QR (SEPA) · RB EUR · IBAN … · VS 120260042           │
│                                                                    │
│ Check before issuing                                               │
│  ⚠ Period text changed:                                            │
│     Line 1: September 2026 → October 2026                          │
│     Line 2: September 2026 → October 2026                          │
│     [✓] Checked   (initial focus; Space)                           │
│                                                                    │
│                                           [Cancel]  [ Issue ]      │
└────────────────────────────────────────────────────────────────────┘
```

- **Summary rows**, each only where it applies:
  1. **Type:** "Invoice – tax document (Faktura – daňový doklad)" (`kind.pickerTitle`, as built). An advance adds "· Not a tax document".
  2. **Client:** the name, the VAT ID and the treatment's short form ("EU goods, exempt", "EU services, reverse charge", "Czech VAT", "Outside EU, services", "Other exemption").
  3. **Language:** "Czech + English".
  4. **Dates:** "Issued today · DUZP 31. 10. 2026 (end of period) · Due 5. 12. 2026". An advance has no DUZP. A DDPP's row carries its payment clause: "Payment received 12. 11. 2026 against ZF 2026-0003".
  5. **Total:** the totals grid, with one VAT row per rate under Czech VAT (main shows the total VAT). Under a no-VAT treatment the VAT row carries the printed clause (design-system §9; everything but the brief's "daň odvede zákazník" is ACCT):
     - EU services: "— (daň odvede zákazník)";
     - EU goods: the § 64 clause (`DocumentClause.intraCommunitySupply`, built in PR 21; ACCT);
     - Outside EU: "— (outside the scope of Czech VAT, § 9(1))";
     - Other exemption: "— (exempt, ‹reference›)".
     A final invoice adds Advances deducted (the deducted DDPP numbers and, on EUR and USD, the advances' rates) or Paid in advance, then Amount due.
  6. **Rate** (EUR and USD tax documents): "1 EUR = 24,315 CZK · for 30. 10. 2026 · Typed", plus "· last published" for a rule-6 fallback. When the rate is missing, the inline rate form shows here.
  7. **Payment:** QR type · account · predicted VS. A DDPP's row says that there is no payment request.
  - **PDF**, only when no PDF folder is chosen: "No PDF folder: the PDF stays in the app until you use Save PDF…. Choose a folder in Settings ▸ General."
  - **Stock** (when Stock ships), only when the document takes goods out (linked lines on an Invoice or a Final invoice): "Takes from stock: Bolt M8 −25 (95 left) · Nut M8 −50 (−10 left)". Information only, never a blocker.
  - There is no Legal notes row and no Info section. Every clause the Legal row listed (`DocumentClause.clauses`) sits in the Type, Dates, Total or Rate row. The fallback rate, the period rule and a DUZP in another month than the issue date show in the Rate and Dates rows, not as rows of their own.
- **Buttons:** **Cancel** (⎋ or ⌘.) to the left of **Issue**, the default button (↩), both trailing, as built.
  - Issue does not use the destructive style, because Sasa chose the action deliberately [S25].
  - There is never a "don't ask again" option for Issue.
- **Two severities** below the summary, in this order, so the common case stays at two keystrokes (⌘↩ ↩), or three when a ⚠ row needs its tick (⌘↩ Space ↩):

  | Severity | Rows | Effect |
  |---|---|---|
  | Fix (⛔), "Fix before issuing" | Company profile incomplete (legal name, address, IČO, DIČ); the client's address missing; the client's VAT ID missing under "EU goods, exempt (§ 64)" (§ 64 odst. 1 písm. a) ZDPH) or "EU services, reverse charge", with the client form's goods or services message (§2e); no lines; invalid cells, by line and column; no rate for the rate day (the inline rate form: type the rate in place); a rate dated after the rate day (`exchangeRateAfterTaxPoint`, with the PR 21 text); no bank account for the currency ("The document has no bank details.", `paymentInstructionsMissing`, a blocker for payable kinds as built); number series not confirmed ("Confirm your number series in Settings ▸ Numbering."); an advance already deducted in another issued final invoice; the other built blockers | Issue is disabled. A row whose fix lies outside the draft has **Fill in…**, which opens Settings ▸ Company, Bank Accounts or Numbering, or the client's Edit sheet (§2e, §2j). The default button becomes **"Go to Problem"** and focuses the field. |
  | Check (⚠), "Check before issuing" | One row "Differs from Acme's defaults: currency EUR → CZK · VAT treatment EU services, reverse charge → Czech VAT" (the currency, the treatment or both); the issue-date row with **"Set to today"** (one step), shown only when the date was set by hand and is not today, or when a floating date would move a "Same as the issue date" DUZP into a later month; period text changed in line descriptions (before → after); a total that differs by more than 50 % from the client's last invoice (fixed at 50 %, not a setting); a final invoice that deducts an advance issued under another VAT treatment (ACCT); advances that exceed the supply (validator `advancesExceedSupply`, as built, §2d); a document in a month already exported (edge cases above); the validator's other warnings, as built, such as a rate more than 7 days older than the rate day (`exchangeRateStale`, with the PR 21 text) or an issue date earlier than the last issued document in the same series ("Issue date is earlier than FV 2026-0042"; ⚠ or ⛔ per ACCT) | Each row has its own **"Checked"** tick, and Issue is enabled once every tick is set. The first tick gets initial focus (`defaultFocus`, macOS 13.0 [S145]), so Space sets it without Tab; whether ⇥ reaches the next tick with Full Keyboard Access off is UNVERIFIED (check on device). HIG: make the action available only when the requirements are met [S35]. |

  An issue date never set by hand floats to the day of Issue and gets no row; the Dates row shows "Issued today" and the resulting DUZP, so a floated DUZP is visible before Issue. The set-by-hand flag is stored with the draft, on the draft side and outside the issued snapshot.
- **What Issue does.** Steps 1–5 are one transaction (ADR 0005), so a number is never used up by a document that wasn't issued:
  1. Takes the next number in the document type's series.
  2. Sets the VS from the number (with the series prefix, §2i).
  3. Sets the issue date, if it still floats ("On issue"), to today.
  4. Freezes every field: the rate with its date, source and rate day; snapshots of the company and client (a later address change never touches an issued document); totals; VAT in CZK; the payments it rests on (§2f).
  5. Logs the issue in the audit trail, which the activity shows as "Issued as FV 2026-0042".

  Right after the transaction, as built:
  6. Renders the PDF and **stores its bytes**. QR presentation (size, error correction M, a plain-text block beside it) belongs to the PDF spec [S117][S118].
  7. Writes the PDF to the PDF folder, if one is chosen (Settings ▸ General), as ‹PDF folder›/‹year of issue›/‹number› ‹client›.pdf, e.g. 2026/FV 2026-0042 Acme GmbH.pdf (ADR 0010). The folder is reached through its security-scoped bookmark (as built): `URL.bookmarkData` exists (macOS 10.10) [S97]. Apple's sandbox guide describes security-scoped bookmarks with the User Selected File (Read/Write) capability and names **no separate bookmark entitlement** [S140]. With no folder, the PDF stays in the app until Save PDF….
  - When Stock ships, each linked line of an Invoice or a Final invoice also becomes an "out" movement of the line's quantity, dated the document's DUZP (the day the goods were supplied), with the document as its source. If the line's unit differs from the item's, the quantity is still taken as typed (no unit conversion). Stock never stops Issue (§2n).
- **Afterwards:**
  - The detail column switches to the read-only issued view (§2b). The result line at the top of the content pane reads one sentence: "Issued FV 2026-0042 · PDF saved to ~/…/2026/FV 2026-0042 Acme GmbH.pdf" (the PDF part only when it was written), with its close button and no action buttons (design-system §8.17). Record Payment… is the issued view's prominent toolbar button, and Show PDF in Finder is in its PDF row. The HIG asks for confirmation only of significant completions, built into the UI [S39].
  - The undo stack for that document is cleared, so Undo can never reach back past Issue [S42].
  - Nothing to close: the draft lived in the main window's detail column.
- **If the folder write fails:** the document *is* issued, because the database is the source of truth. The issued view shows the problem message "PDF couldn't be saved to …/Faktury." with **Choose Folder…** and **Save PDF…** (as built).
- **The number is assigned inside the Issue transaction** (the data layer, ADR 0005), so the result line always shows the number actually assigned.

#### Script: "same invoice as last month for Acme, with new hours"

Assumptions:
- Last invoice FV 2026-0038 (Period September 2026) had line 1 "Software development – September 2026, 32 h × 85 €" and line 2 "Hosting – September 2026, 1 × 40 €".
- The new hours are 36,5.
- Acme's treatment is "EU services, reverse charge", so the rate day is the DUZP. The draft has Period October 2026, so its DUZP is 31. 10. 2026 (the period's last day, ACCT).
- The ČNB rate for 30. 10. 2026 is already stored, typed on an earlier document or imported (see the variant below if not).
- Focus starts anywhere in the main window.

| # | Keys | What happens | Keystrokes |
|---|---|---|---|
| 1 | ⌘3 | Clients opens with keyboard focus in its table (§1.2) | 1 |
| 2 | a c m | Type-select selects "Acme GmbH" (§2e). File ▸ Duplicate now reads "Duplicate FV 2026-0038 as Draft". | 3 |
| 3 | ⌘D | A Draft copy of Acme's last invoice is created; the window switches to Documents ▸ Drafts with it selected, and its editor opens in the detail column (as built for a new draft). Period becomes October 2026 and the dates follow the rules. "September 2026" becomes "October 2026" at the end of both lines (highlighted). The rate is picked for the rate day. **Focus lands in line 1 Qty with "32" selected.** | 1 |
| 4 | 3 6 , 5 | The quantity is replaced. The totals bar updates. | 4 |
| 5 | ⌘↩ | The field commits and the review sheet opens: one ⚠ row (the period text, before → after) with its tick focused | 1 |
| 6 | Space | Sets "Checked" after reading the two changed lines | 1 |
| 7 | ↩ | Issued. FV 2026-0042 is assigned, the document locks, and the PDF is saved. The detail shows the issued view; there is nothing to close. | 1 |
| | | **Total** | **12** (8 command keys + 4 characters of data), 0 clicks |

- The count holds if ⌘3 puts focus in the Clients table and type-select works there (UNVERIFIED, §2e).
- **Variant: the month-end rate is missing** (the common case early in the month, §2c edge cases). At step 5 the sheet shows the inline rate form instead of a dead end, with the rate field focused (a ⛔ row comes before any ⚠ tick; as built). Type the ČNB rate and ↩ (e.g. "24,315" ↩ = +7 K): this is the v0.1 path. The sheet re-validates in place. Later (v0.2): dropping a ČNB file onto the sheet (+1 drag).
- If line 2 changes too, add ↩ (move down a row in Qty) plus the new value.
- With FV 2026-0038 already selected in Documents, ⌘D alone starts at step 3.
### (d) The advance flow: advance invoice → payment → tax document for the received payment → final invoice

An **EU-goods advance** below is an advance under the treatment "EU goods, exempt (§ 64)". It gets no tax document for its payments (goods decisions (a); ADR 0012, built in PR 22; ACCT), so its chain skips step 3. Every other treatment keeps the tax-document step, as built (EU services and outside EU: Q5, ACCT).

**Guiding device: the chain line.**
- Every document in an advance chain shows one chain line: under the header in the issued view, and at the top of the editor, above the header form. It is the only place that view shows the chain.
- It is text only, with no symbol, tint or StatusStyle per step. Arrows separate the steps:
  - the other documents are links, named by type and number; the advance's step adds its state;
  - received payments are plain dated steps, and the current document is plain text;
  - a step that doesn't exist yet is plain text;
  - a draft step (a draft tax document or final invoice, which has no number yet) is a link that opens the draft, e.g. "Tax document (draft)".

  `Advance ZF 2026-0003 · Paid → Payment 12. 11. 2026 → Tax document DD 2026-0007 → Final invoice FV 2026-0050`

- Each link has a full accessibility label, e.g. "Advance ZF 2026-0003, paid".
- A final invoice that deducts two advances shows one Advance node per advance. A final invoice made with Document ▸ Change Type ▸ Final Invoice shows the advances it deducts once they are added in the editor; with none, it has no chain line.
- An EU-goods advance has no tax-document step:

  `Advance ZF 2026-0003 · Paid → Payment 12. 11. 2026 → Final invoice`

- **The next step** is one `.bordered` button in the place of the missing step:
  - **Create Tax Document**, for the oldest payment that needs a tax document and has none;
  - **Create Final Invoice**, once every payment's tax document is issued, and on an EU-goods advance once it has a payment (it is never offered Create Tax Document);
  - no button on an unpaid advance (its next step is the toolbar's prominent Record Payment…, §2b), on a closed advance, or while the missing step is a draft, whose link leads on.
- Menu paths: Document ▸ Show Related Documents ▸ lists the chain's other documents, and Document ▸ Create Tax Document for Payment and Create Final Invoice do what the button does (§1.4).
- **Documents ▸ Open advances** (§2b) lists every issued advance that no issued final invoice has deducted or settled as "Paid in advance" and that isn't closed. That includes a paid EU-goods advance waiting for its final invoice. The **Overview queue** (§2a) lists an advance only when it is overdue, or when a payment lacks the tax document the advance needs. A paid EU-goods advance never enters that second group.

**Advance states** (shown in the Status column; symbols, tones and labels in design-system §4.3):

`Awaiting payment` → `Partly paid – tax document missing` → `Partly paid` → `Paid – tax document missing` → `Tax document issued` → `Settled in final invoice` (detail: FV 2026-0050), or `Closed unpaid` (closed without payment).
- Each received payment, partial or not, shows "tax document missing" until its DDPP is issued, and that wins over Overdue.
- When an advance needs no tax document (EU goods, goods decisions (a); other treatments Q5, ACCT), a paid advance shows `Paid`, with the payment date as detail: `Awaiting payment` → `Partly paid` → `Paid` → `Settled in final invoice`.
- An open or partly paid advance past its due date shows Overdue, with the days and the open balance in the detail, unless a tax document is missing.

**Closing an advance or a tax document without a credit note** (v0.1; neither action edits the document, each appends a dated event; wording and accounting effect ACCT):
- **Document ▸ Close Advance as Unpaid…** for an issued advance the client will never pay (scope dropped, or the client paid the final invoice directly). A reason is required.
  - The status becomes "Closed unpaid". The advance leaves Open advances, the Unpaid tile's advances line and the Overview queue, and stays in the CSV with that status.
  - A credit note is the wrong tool here, because an advance is not a tax document.
  - Only an advance with no payment and no deduction can be closed (ADR 0007, as built). Closing one after a partial payment (the received part keeps its DDPP) is ACCT.
- **Document ▸ Mark for Credit Note…** for a tax document (an invoice, a DDPP or a final invoice) issued by mistake. A reason is required. It stops the Overdue nags, sets a CSV flag, and becomes the entry point for Phase 2 credit notes. The credit note (the corrective document) stays the normal fix for a wrong document; Repair mode (§2m) is the last resort.
- **No banner.** In the issued view the header badge reads "Closed unpaid" or "Marked for credit note", with no detail. The reason is one selectable secondary line under the header, its only place in that view. In the Documents table the badge keeps the reason as its detail, as built. The lock line keeps "Corrections via credit note (Phase 2)".
- **Reopening.** On a closed advance the menu row reads **Reopen Advance**; on a marked document it reads **Remove Credit Note Mark**. Neither has an ellipsis, because each acts at once. Each registers a named undo ("Undo Reopen Advance", "Undo Remove Credit Note Mark") that writes the closing event back with its kind and reason. The row's context menu has the same items (§2b).
- Neither closing event, and no reopening, touches stock (§2n).

**Step 1: create the advance** (File ▸ New Advance Invoice ⇧⌘N, which reads "New Advance Invoice for Acme GmbH" with a client selected in Clients, or New Advance Invoice in the client page's New Invoice ▾, §2e).
- The editor has the type Advance invoice. A line at the top of the editor reads "Not a tax document", and the PDF prints the not-a-tax-document clause from design-system §9 (rule 3, ACCT). A goods-only advance prints only "Toto není daňový doklad. / This is not a tax document.", because no tax document follows (PR 22; design-system §9, ACCT).
- There is no DUZP field and no rate is needed. The rate comes with the tax document: a DDPP takes it for its DUZP, the payment day (DDPPs keep the tax point, ACCT), and a final invoice for its rate day (the DUZP; for § 64 goods the § 22 odst. 1 day).
- Under Czech VAT the lines carry the VAT rate that the later tax documents will use. Whether the advance PDF shows a VAT breakdown is ACCT. Under any other treatment the VAT rate column and the VAT amounts are hidden (§2c).
- Lines may link to stock items, as on an invoice, but an advance takes nothing out of stock (§2n).
- Issue works exactly as in §2c. The number comes from the Advance invoices series (ZF), and the QR and payment details print as usual.

**Step 2: payment received** (⌘R or the prominent Record Payment… in the advance's toolbar; ↩ on its Overview queue row when it is overdue).
- This is the Record Payment sheet (§2f).
- After Record (↩) the sheet shows a success step: a `.secondary` `checkmark.circle` with the "Payment recorded" message (main shows a green `checkmark.circle.fill`; the lean design has no green), then one of these:
  - an advance that needs a payment tax document: **Create Tax Document** (↩, prominent) / **Later** (⎋). Later leaves the payment in the Overview queue and the button on the chain line.
  - an EU-goods advance, with the built message "Payment recorded. An advance for EU goods needs no tax document: the final invoice lists it as paid in advance." (PR 22): **Create Final Invoice** (↩, prominent) / **Later** (⎋). Later leaves the advance in Open advances; it doesn't enter the queue.
- Each payment gets its own tax document (one per payment; ACCT).

**Step 3: the tax document for the received payment** (a draft opens prefilled; never for an EU-goods advance):
- Type: Tax document for received payment (PDF title "Daňový doklad k přijaté platbě").
- Client: the same as the advance.
- Reference: InvoicingCore prints `DocumentClause.paymentReceived`, "Daňový doklad k platbě přijaté dne 12. 11. 2026 na základě zálohové faktury č. ZF 2026-0003." (document text; wording ACCT, design-system §9).
- DUZP: the payment date (ACCT).
- Amount: the amount received (gross). The VAT split is computed at the advance's VAT rates, in proportion to the advance's VAT summary rows when it has several (as built; calculation method ACCT).
- Rate: the ČNB rate for its rate day, the DUZP (DDPPs keep the tax point, ACCT), or the last one published before it (rule 6). Sasa types it in the editor's inline rate form when the app has no rate for that day (§2c). VAT in CZK appears when the document is in EUR or USD (rule 5).
- **No QR** and no payment request, because nothing is payable. No stock suggestions either (§2n).
- Issue works as in §2c, with a number from the Tax documents for received payments series (DD). Its status is Paid (design-system §4.3).
- The deadline for issuing it is ACCT, so the app states none. The Overview queue keeps the payment listed until its tax document is issued (§2a).

**Step 4: the final invoice.** It comes from either of two places:
- its advance: the chain line's Create Final Invoice, Document ▸ Create Final Invoice, or the row's context menu;
- Document ▸ Change Type ▸ Final Invoice on a draft, whose deductions are then added in the editor.

The draft:
- The lines are copied from the advance, with their stock links, and stay editable, because this is a draft. Only the final invoice's Issue takes goods out of stock (§2n).
- **Advances deducted**, for an advance with tax documents:
  - Create Final Invoice fills in every issued tax document of the advance that no issued final invoice deducts. While a payment still waits for its tax document, it refuses with "Issue the tax document for the payment of 12. 11. 2026 first; otherwise its amount would not be deducted." (as built).
  - Each row shows the tax document number with its advance ("DD 2026-0007 · advance ZF 2026-0003"), the payment day, the VAT already taxed (in CZK at that tax document's rate) and the amount, with a remove button. **Add Tax Document…** offers the client's other issued tax documents in this currency that no issued final invoice deducts (as built).
  - The PDF prints one row per deduction, "Odečet zálohy – daňový doklad č. DD 2026-0007, platba ze dne 12. 11. 2026" (InvoicingPDF; ACCT). The exact layout of the deduction and of the CZK VAT difference is ACCT.
- **Paid in advance**, for an EU-goods advance (goods decisions (b); ADR 0012, built in PR 22; ACCT):
  - There is no tax document to deduct. Create Final Invoice carries the advance's payments over, one row per payment: advance number · day paid · amount paid, with no tax-document or VAT columns. The refusal above does not apply to EU-goods advances (built in PR 22) and stays for every advance that needs a tax document.
  - Totals: "Total 10 000,00 € · Exempt (§ 64)" / "Paid in advance −4 000,00 €" / "Amount due 6 000,00 €". The § 64 value is never reduced.
  - The PDF heading is "Uhrazené zálohy / Advances paid", with rows such as "Záloha ZF 2026-0003 uhrazena 12. 11. 2026 / Advance ZF 2026-0003 paid on 12. 11. 2026" and the amount (ACCT).
  - Deducting an advance issued under another treatment gives a check row, not a blocker (ACCT).
- Totals: Total → the deduction → **Amount due** (§2c).
- If the amount due is 0, the PDF prints no QR and no payment block (as built), and after Issue the status becomes Paid, with the detail "by advances".
- **If the advances exceed the supply (negative amount due), Issue stays available with a warning** (validator `advancesExceedSupply`, ADR 0004): "The deducted advances exceed the supply; the tax base is negative (§ 37a(2)(b) of the VAT Act)." The PDF prints no QR and no payment block, as for a zero amount due (as built). After Issue the badge follows the settlement the data layer computes: below 0 that is Overpaid (as built), so Record Refund… can return the difference (§2f). It is not Paid (detail "by advances"), which needs an amount due of exactly 0. How the difference is settled is ACCT.
- An advance can be deducted by **one** issued final invoice only; the data layer enforces it for each tax document (ADR 0007). Fakturoid also allows only one final invoice per advance [S109]. If two drafts deduct the same tax document, both show a warning (as built).
- The PDF title in InvoicingCore (`DocumentKind.title`) is "Faktura – daňový doklad (vyúčtování záloh)"; the parenthetical settling wording is ACCT.
- The final invoice is numbered in the Invoices series (FV), as built. A fourth fixed series comes only if the accountant asks (Q2, ACCT).

After Issue:
- Each deducted advance becomes "Settled in final invoice", with the final invoice number in the badge detail. Its chain line links to the final invoice, the only place that link lives.
- An advance that an issued final invoice deducted, or settled as "Paid in advance", takes no further payment, even when it was only partly paid (R065). Money that arrives later is recorded on the final invoice. No menu offers Create Final Invoice on a settled advance; if it is reached anyway, a result line says "This advance is already in final invoice FV …" (PR 22).

**Build status** (main at 18679ea). To build in this flow:
- the chain line in the editor, in place of the final-invoice draft's "Related document number" field and the DDPP's read-only related row (DraftEditorView.swift:532-547); the issued view's part is in §2b;
- the success step's `.secondary` `checkmark.circle` (main draws a green `checkmark.circle.fill`, Sheets.swift:100) and its EU-goods variant (PR 22);
- the closing rows' changeable labels and their named undo (main has a separate Reopen row, Commands.swift:180);
- Paid for a DDPP and for a final invoice settled by advances (main shows "Issued (paid)" and "Paid (by advances)", StatusStyles.swift:176-185);
- `acceptsPayment` refusing an advance that a final invoice deducted or settled (DocumentRow.swift:95-97).
### (e) Clients

**Build status** (main 18679ea):
- **Goes from main:** the Currency and Overdue columns, the Overdue figure, the client inspector (`ClientInspectorView`), the client page's New Advance Invoice toolbar button, and in the client form the CZ country preset and the EU business type for every new client (ClientsView.swift:429 and :432), with its warning "EU reverse charge needs the client's VAT ID; the validator will block issuing without it."
- **To build:** the second lines of Name and Open Balance, and those two headings in title case; IČO in the search and the "Search clients" prompt; type-select; the row context menu; the defaults line as one key with the treatment's short form; email, phone and note under the header; the tabs, with Activity; ↩, double-click and the context menu in the Documents tab; the client page's Duplicate and its tooltips; in the sheet the empty "Choose…" country, the currency rule, the labels "Client type" and "Company ID (IČO)", the format messages at their fields, the VAT ID hints, the duplicate check and the Edit sheet's info line.
- **On main since PR 21** (ADR 0011): the client type's split into "EU business, goods" and "EU business, services", and the treatment short forms.

**Clients list.**
- Layout: sidebar | `Table` (content column) | the client page (detail column). There is no inspector. With no client selected, the detail reads "Select a client" (§1.2). The selection comes back with the window (§1.1 Restore).
- Toolbar (design-system §8.11, Clients list row): New Client (`person.badge.plus`, tooltip "Add a client") · search, prompt "Search clients". Search (⌘F) matches name, IČO and VAT ID.
- Type-select on names: typing "acm" selects the row. `NSTableView.allowsTypeSelect` is AppKit [S86]; whether SwiftUI `Table` does this by itself is **UNVERIFIED**, so wrap it or implement it with `onKeyPress(characters:)` (macOS 14) [S67].
- Because type-select uses the letter keys, **this list has no single-letter actions** (§3.2). ↩ opens the client page.
- Context menu on a row: New Invoice for “Acme GmbH” · Duplicate FV 2026-0038 as Draft | Edit Client…. As in every context menu, an unavailable item is hidden (Duplicate, when the client has no invoice) and no shortcuts show (§2b).

| Column | Content |
|---|---|
| Name | Sorted with `localizedStandard`, so Czech diacritics sort correctly [S59]. A second `rowSecondary` line gives the city and, when there is one, "IČO 12345678" (design-system §5.3). |
| Country | ISO code |
| VAT ID | `amount` text role |
| Open Balance | Per currency, trailing, by the Unpaid rule (§2a). While part of it is overdue, a second `rowSecondary` line says so in words, e.g. "1 200,00 € overdue" (a word, not a colour). |
| Last Document | The issue date of the client's last issued document, trailing; "—" when there is none |

The default sort is Name A–Z.

**Client page** (the detail column), top to bottom:
- **Header:** the name (`screenTitle`) and the address lines. Under them, "IČO 12345678" and "VAT ID DE123456789" as selectable text, so they can be copied (HIG: make useful label text selectable [S56]).
- **Defaults line:** shown once, as one `rowSecondary` line under the IČO / VAT ID line: currency · document language · the default treatment's short form · payment term.
  - Acme's own settings: "EUR · Czech + English · EU services, reverse charge · 30 days". A new German goods client: "EUR · Czech + English · EU goods, exempt · 14 days".
  - The treatment is the short form of the treatment the client type gives ("EU goods, exempt", "EU services, reverse charge", "Czech VAT", "Outside EU, services"): the same words as the client suggestion line and the Issue sheet (§2c), not the client type's name.
  - The line is one interpolated key, not " · " joins. It names no QR, because the QR follows the currency (§2c).
- **Contacts and note:** then the email and the phone, as selectable text, and the client note when it is filled. A client has one email and one phone, as built. Neither opens Mail by itself. Later (no version set): several contacts per client. Later (Phase 2): mail drafts.
- **Figures:** two tiles. **Open balance**, per currency, with the same "… overdue" line when part of it is overdue. **Invoiced this year**, by the Overview's revenue rule (§2a), as built.
- **Tabs** (below).
- **Toolbar** (design-system §8.11, Client page row): New Invoice (`plus`, tooltip "Create an invoice for Acme GmbH") · Duplicate (`plus.square.on.square`, tooltip "Duplicate FV 2026-0038 as a new draft"; disabled when the client has no invoice) · Edit… (`pencil`, tooltip "Edit this client's details").
  - They are the same commands as File ▸ New Invoice for Acme GmbH (⌘N), File ▸ Duplicate FV 2026-0038 as Draft (⌘D, which in client context copies the client's last invoice) and File ▸ Edit Client “Acme GmbH”….
  - New Advance Invoice is ⇧⌘N, which reads "New Advance Invoice for Acme GmbH" here.
  - The page has no buttons in its content.

**Tabs:** Documents · Activity in v0.1. **Items** comes third once Stock ships and a stock item exists (§2n). Later (v0.2): a Payments tab, with the bank import: Date (newest first) · Amount · Document · Account · CZK difference.
- **The control:** on macOS 27, a `Picker` with `PickerStyle.tabs`, which gives a segmented look that "distinguishes tab navigation from value selection", and VoiceOver announces the options as tabs [S89]. Below 27 it is a SwiftUI `TabView`, never `.segmented`: a tab view in the main area, rather than a segmented control [S33][S50]. Labels are in title case. Documents is the default.
- **Menu path:** View ▸ Client Tab ▸ Documents / Activity / Items, checkmarked, enabled while a client page is shown (§1.4), so the tabs have a path that doesn't depend on Tab. Items is listed once Stock ships, and is disabled while no stock item exists. File ▸ Add Note to “Acme GmbH”… shows Activity and focuses "Add a note…".
- **Documents:** the client's documents, newest first: Status · Number · Type · Issued · Due · Total · Open (as built; Type in the §5 short names, text only). ↩ or a double-click shows the document in Documents (the all-documents row, §1.2), and the rows have the Documents context menu (§2b).
- **Activity:** an "Add a note…" field at the top. ↩ saves the note, dated today; its date can be edited.
  - Below the field, notes and system events, newest first, as text with a timestamp.
  - The system events reuse the issued view's activity sentences (Strings.swift:622-631), e.g. "Issued as FV 2026-0042", "Received: 4 840,00 €" and "Closed as unpaid: ‹reason›", plus the repair events with their reason (§2m, v0.1.x).
  - Editing or deleting a note is undoable; ⌫ deletes the selected note (§1.4).
- **Items** (when Stock ships, §2n): Item · Bought This Year · Bought in All · Last Bought (day and document) · Last Price (in the document currency). It is built from the "out" movements of this client's issued documents, so it needs no input. An archived stock item still shows here, because its movements stay. A double-click shows the item in Stock.

**New Client sheet** (File ▸ New Client…, the Clients toolbar's New Client, the empty state's New Client, or "New Client “…”…" in a draft's client field). It is sized by `formSheetSized`: `presentationSizing(.form)` on macOS 15 [S90], a fixed width range on 14 (App/FA/DesignSystem/FormSheetSizing.swift, as built).
- **Fields,** in sections:
  - Name (prefilled from what was typed) · Country · Street · City · Postal code
  - Company ID (IČO) · VAT ID (DIČ) · Client type
  - Email · Phone
  - Currency (EUR / CZK / USD) · Payment term (days) · Document language (Czech / Czech + English) · Note
- **Country:** a pop-up of the ISO countries by English name. It starts empty, on "Choose…" (an explicit empty tag), because most clients aren't Czech (RECOMMENDATION).
- **Client type:** a pop-up, in this order: "EU business, goods", "EU business, services", a divider, "Czech VAT payer", "Czech business, not a VAT payer", "EU consumer", "Business outside the EU, services", "Consumer outside the EU".
  - Each type gives its documents' default treatment (§2c): EU business, goods → "EU goods, exempt (§ 64)"; EU business, services → "EU services, reverse charge"; Business outside the EU, services → "Outside EU, services"; the Czech and consumer types → "Czech VAT (rate per line)". EU consumers buying goods stay on Czech VAT; the distance-sale rules are ACCT.
  - The labels and the rules below are ACCT.
- **Format checks:** the IČO and VAT ID formats are checked inline [S34], with "Company ID is not valid (8 digits with a check digit)." and the VAT ID message. There is no online VIES check, because the app is offline. Later (no version set): a "VIES checked on" date (its ACCT question stays open); until then the client note can record a manual check.

**Defaults for a new client** (Sasa's answers in the proposal doc and in the project chat, 5 Nov 2026). Until Sasa picks a value by hand, Client type, Currency and Document language follow the VAT ID and the country as they are typed.
- **Client type with a VAT ID:** the VAT ID's prefix decides, as InvoicingCore `CustomerVATStatus.inferred` does. A CZ VAT ID → Czech VAT payer; another EU VAT ID → **EU business, goods**, so documents start on "EU goods, exempt (§ 64)"; any other → Business outside the EU, services. Sasa: "99% EU-EU" and "90% goods". "EU business, services" is only picked by hand.
- **Client type without a VAT ID:**
  - CZ → Czech business, not a VAT payer.
  - Another EU country → **EU business, goods; Issue waits for the VAT ID** (Sasa sells to businesses only for now ("i dont do b2C CURRENTLY", 6 Nov 2026); ACCT). This needs `CustomerVATStatus.inferred` changed, because main still gives EU consumer (Party.swift:77). EU consumer stays in the Client type pop-up for a consumer sale picked by hand.
  - Outside the EU → Consumer outside the EU (§ 10h is ACCT; the § 66 export of goods comes later, with the accountant).
- **With no country yet:** Client type "EU business, goods", currency EUR, and no hint.
- **Currency:** CZ → CZK, any other → EUR; USD is picked by hand. Sasa: "for start its enough, you can add dollar". The app sets the currency explicitly, because the core's own default is CZK.
- **Document language:** Czech for CZ, Czech + English otherwise (the InvoicingCore `Customer` default). The sheet follows the country until the language is picked by hand, as built.
- **Payment term: 14 days.** Sasa answered "dunno", so this is the build's default: InvoicingCore `Customer.paymentTermDays` defaults to 14.
- **No footer text:** none prints until Sasa sets one in Settings ▸ Company (§2i).
- **QR:** not a client value; the QR type follows the currency (§2c).
- A value picked by hand never changes by itself. The rule runs only in the New Client sheet; the Edit sheet never re-infers. The pop-ups show the derived values live, so there is no separate summary line.

**VAT ID hint.** While the country is an EU country other than CZ and the VAT ID is empty, a problem-kind line (design-system InlineMessage) shows under Client type. It never blocks Save. The wording is ACCT.
- EU business, goods: "The § 64 exemption needs the client's VAT ID. Add it to issue documents for this client."
- EU business, services: "Reverse charge needs the client's VAT ID. Add it to issue documents for this client."
- Any other type (EU consumer, picked by hand): "The § 64 exemption needs the client's VAT ID." alone, because Czech VAT documents can still be issued.

On a document, a missing client VAT ID under "EU goods, exempt (§ 64)" (§ 64 odst. 1 písm. a) ZDPH) or "EU services, reverse charge" is a ⛔ row in the Issue sheet, with the same message and Fill in… (§2c).

**Required:** name and country ("A name is required.", "A country is required.", as built). Address and VAT ID are not required to save, but a missing one shows as a problem line in the client field ("Address missing", "VAT ID missing") and blocks Issue where the law needs it (§2c).

**Possible duplicate.** When the IČO or the VAT ID matches another client, an inline message reads "Possible duplicate: Acme GmbH – open it?", with Open. Open cancels the sheet and selects that client; when the sheet came from a draft, it picks that client into the draft.

**Save.** ↩ Save (prominent), ⎋ Cancel, as built. Opened from a draft, Save fills the draft's client, applies the defaults and returns focus to the first line's Description; otherwise it selects the new client.

**Edit sheet.** The same form, titled "Client details" (as built) and filled with the client's values. It opens from the client page's Edit…, File ▸ Edit Client “Acme GmbH”…, the row's Edit Client… and Fill in… in the Issue sheet (§2c).
- It never re-infers. When a changed country or VAT ID would give another client type by the rule, an info-kind line under Client type names it, e.g. "Usual client type for this country and VAT ID: Czech VAT payer" (RECOMMENDATION). Sasa changes the type by hand.
- A changed default applies to drafts that pick the client afterwards. Open drafts keep their treatment, and issued documents keep their snapshot.

**States.**
- *Empty:* "No clients yet", the built description and a prominent New Client, as built. It names no shortcut.

**Edge cases.**
- v0.1 has no client delete and no Archive Client, so every client stays listed. Issued documents keep their own snapshot of the client (§2c).
- Later (no version set): Archive Client. A client with documents can only be archived, never deleted, and an archived client's documents stay. The data layer has both on main: `CustomerStore.archive` hides the client from lists and search, and `delete` refuses a client with documents (`customerHasDocuments`). No UI calls them.
### (f) Payments: the record-payment sheet, the list, and bank import (v0.2)

**Record Payment sheet** (⌘R: Document ▸ Record Payment…, the issued view's prominent toolbar button, the document row's context menu, or ↩ on an overdue row of the Overview queue, §2a; `presentationSizing(.form)` on macOS 15 [S90] and a width range on macOS 14, as built).

Title "Record Payment", with the subtitle "FV 2026-0042 · Acme GmbH" from one interpolated key.

| Field | Default | Notes |
|---|---|---|
| Payment date | the date of the last payment recorded in this window, else today (as built) | A date picker; a future date is blocked (as built). If Sasa records payments from a monthly statement (an open question, §6), they are mostly in the past. |
| Amount | the open balance (as built) | A MoneyField in the document's currency. Under it: "Enter an amount, such as 1 234,50" when the text is not a number, and "Enter an amount greater than zero." for 0 or less. iDoklad's *Uhradit* defaults the date to today, and Fakturoid's *Spárovat* prefills the amount [S114][S108]. |
| Note | empty | Optional |

**Outcome**, a live line under Amount, from the open balance, the typed amount and the payment tolerance:
- "Document will be: Paid". Within the tolerance it reads "Paid (0,01 € difference rounded off)", so a rounding cent never leaves a document Partly paid or Overpaid forever.
- "Partly paid – 600,00 € left"
- "Overpaid by 50,00 € – kept as client credit". Overpaid is iDoklad's "Přeplaceno" [S113].
- **Payment tolerance:** one fixed rule, shared with v0.2 matching: ±1 Kč for CZK; ±0,01 in the document currency for EUR and USD until the accountant answers (ACCT).

Buttons: Cancel (⎋) / **Record** (↩). After Record:
- An advance shows the success step of §2d step 2: **Create Tax Document** (↩, prominent) / **Later** (⎋), or, for an EU-goods advance, which needs no payment tax document, **Create Final Invoice** (↩, prominent) / **Later** (⎋).
- Any other document: the sheet closes and the result line (design-system §8.17) reports the payment.

The sheet asks for no rate, and recording a payment never changes the document's own rate. Later (v0.2, with the bank import): an Account field; for an account in another currency than the document, two stored amounts ("Credited to account" and "Settles on the document") with the implied rate shown; and the CZK difference against the document's rate, using the ČNB rate for the payment date by the same "that day or the last one published before it" rule (ACCT; the accounting treatment is ACCT). A rate always shows its own publication date (rule 6).

**Record Refund** is the same sheet in refund mode, for an overpaid document: title "Record Refund", the date reads "Refund date", the note "The overpaid part goes back to the client; the document keeps its payments." (as built), and the button **Record Refund**. It records a negative (outgoing) payment. The Document menu's ⌘R row reads Record Refund… on an overpaid document, so ⌘R opens it there; the issued view's toolbar and the row's context menu show whichever of the two applies. The accounting treatment is ACCT. A surplus that is not refunded stays as client credit.
- Later (no version set): **Apply Credit To…**, which moves a surplus to another open document of the same client and currency. The data layer already has it (`DocumentStore.applyCredit`, ADR 0007).

**Payments list** (sidebar ▸ Payments, ⌘4; no children in v0.1, §1.2).
- A `Table`: Date (default sort, newest first) · Client · Document · Amount · Note. Every header sorts. Amount is `MoneyText` with its currency, so there is no Currency column. A locked payment (edge cases below) shows `lock.fill` beside the amount (as built), with the VoiceOver label "A tax document rests on this payment; it cannot change." (as built) or, for a payment that an EU-goods final invoice settled, "A final invoice settled this payment as paid in advance; it cannot change." (built in PR 22).
- **Data model from day one (v0.1):** every payment stores its kind (received, refund, credit in, credit out) and an optional bank transaction id, which is nil for a payment typed in (`DocumentPayment.kind` and `bankTransactionID`, as built; ADR 0007). So v0.2 can link statement lines to payments already recorded by hand.
- Later (v0.2, with the bank import): the Account, CZK difference and Source columns, one sidebar row per bank account, Unmatched, and the label "Payments & Bank". Statements are what make those columns differ from row to row.
- Toolbar: search only, "Search payments", matching the client, the document number and the note; Edit ▸ Find (⌘F) focuses it. The selected payment's document brings its issued-view items into the detail toolbar (design-system §8.11). There is no Record Payment button and there are no filters.
- Detail column: the selected payment's document, in the issued view (§2b).
- Keys, while the list has focus: ↩ moves focus to the document in the detail column; ⌫ deletes a manual payment that is not locked (Delete Payment below). Edit ▸ Delete does the same. Both are disabled otherwise.
- Context menu: Delete Payment, when allowed.
- Empty: "No payments yet" + "Record Payment… (⌘R) on an issued document lists the payment here." (as built).

**Payment rows in the issued view** (its Payments block, §2b).
- Each row shows date · kind (Received, Refund, Credit applied or Credit moved out, as built) · source (only for a bank-import payment, as built) · note, with the amount trailing. There is no lock glyph: the issued view's lock line is the one lock (design-system §7).
- A locked payment carries one caption line with **Show Document** instead:
  - "Payment is the basis of DD 2026-0003 and can't be deleted" (as built), for a payment that an issued tax document rests on;
  - "A final invoice settled this payment as paid in advance; it cannot change." (PR 22), for a payment that an issued EU-goods final invoice settled as "Paid in advance". Show Document opens that final invoice.
- Context menu: **Open Tax Document** (the payment's tax document is a draft) or **Create Tax Document** (an advance payment without one, never on an EU-goods advance); **Delete Payment** (absent when the payment is locked). The advance's next step is also the chain line's button (§2d).

**Delete Payment** (the Payments list and the issued view):
- A manual payment that is not locked is deleted at once, with no dialog. The result line offers Undo, and Edit ▸ Undo reads "Undo Delete Payment" [S42].
- When the payment's tax document is still a draft, Delete Payment deletes both. One named undo, "Undo Delete Payment", restores the payment and the draft and relinks them. It registers its inverse, so Edit ▸ Redo Delete Payment (⇧⌘Z) works after it. The single Delete Draft and Delete Payment undos register their inverse too.
- Until that combined undo exists, the built confirmation dialog stays: Delete Payment and Draft / Delete Payment Only / Cancel (PaymentDeletion.swift).

Edge cases:
- **Payment dated before the issue date:** a warning.
- **Same document, amount and date as an existing payment:** "Possible duplicate".
- **Payment on a draft:** not possible ("Issue first").
- **A tax document for a received payment:** it is already paid by definition, so there is no Record Payment action.
- **An advance that an issued final invoice deducted, or settled as "Paid in advance",** takes no further payment, so Record Payment… is unavailable on it. Money that arrives later is recorded on the final invoice (§2d).
- **A payment that an issued document rests on is locked.** That means a payment from which an issued DDPP was created, one that let an issued final invoice deduct an advance, and a payment on an EU-goods advance that an issued final invoice settled as "Paid in advance" (PR 22). Delete, Unmatch (v0.2) and changes to the amount or date are blocked; only the note can change. Undo can't help here, because the undo stack is gone after relaunch. If a delete reaches the data layer anyway, it refuses, with the PR 22 texts for the goods case (§5).
- **A payment linked to a bank line (v0.2):** can only be unmatched, not deleted, and the lock above applies to Unmatch too.

**Build status** (main at 18679ea). To build:
- the sheet: the title "Record Payment" (main: "Record payment") and the subtitle as one interpolated key (main joins the number and the client in code, Sheets.swift:51); "Record Refund" (main: "Record refund"); the outcome line and the fixed tolerance; the duplicate and before-issue-date warnings; the result line for a document that is not an advance (main only closes the sheet, Sheets.swift:135);
- the Payments list: the label "Payments" (main: "Payments & Bank", Strings.swift:19); no Source column (main shows it, PaymentsView.swift); search; ↩;
- the issued view's payment rows: no `lock.fill`, and Open Tax Document and Create Tax Document in the context menu instead of on the row (DocumentDetailView.swift:322-334); the goods caption, whose text is PR 22's lock label;
- Delete Payment's combined undo and the redo of each payment and draft deletion (main's Undo restores the payment alone, and offers none after a delete together with the draft, MainSplitView.swift:648-677), after which the dialog goes.

**Bank statement import (v0.2).**
- Raiffeisenbank formats, UNVERIFIED (from the build thread's reading of the bank's internet-banking manual, not confirmed on any page and not in the source list): PDF statements are free. The data formats are a paid service that has to be activated: RB XML (not camt.053), ABO (`*.GPC`) and Gemini (`*.ACE`). The free and paid status and the format names are UNVERIFIED. Several statements can arrive as one ZIP. The parser handles ABO first. The UI below works for any parsed format.

1. **Drop the file** on the window, on the sidebar's Payments row (labelled Payments & Bank from v0.2) or on an account row (`dropDestination(for:isEnabled:action:)`, macOS 26 [S72]). File ▸ Import Bank Statement… does the same through `fileImporter` with the ABO, XML, ZIP and PDF types [S73].
   - Highlight a drop target only when it can accept the file [S36].
2. **Preview sheet.**
   - It shows: file name and checksum (the file is stored untouched); detected format; the detected account, matched by IBAN to Settings ▸ Bank Accounts, or **"Assign to account…"** if unknown; the period; opening and closing balance; "42 transactions · 30 new · 12 already imported (skipped)".
   - PDF statements are stored. Whether their transactions can be parsed depends on the build thread; until then show "Stored – transactions can't be read from this PDF yet; match manually or import an ABO/XML statement".
   - **Import** (↩) opens the triage window.
   - **Ask Sasa now (Q8):** is the paid data-format service active on the account, and what does it cost? Once it is, the import sheet gains a short "how to download the statement as ABO" step.

   **PDF fallback: "match manually"** (the real path while Sasa only has PDFs). The triage window shows the stored statement in a `PDFView` [S78] on one side and the list of open documents on the other. Search finds documents by VS, number, client or amount (⌘F); ⌘R records a payment on the selected document with the Record Payment sheet, whose date and amount Sasa copies from the statement. The statement stays attached as the payment's source file.
3. **Triage window** "Statement 10/2026 · RB EUR".
   - It is **one queue** grouped into lanes, so triage is a straight run down the list with ↓.
   - A tabs filter at the top (All / Already recorded / Matched / Suggested / Unmatched / Outgoing) is there for the mouse.

   | Lane | What lands there | Default |
   |---|---|---|
   | **Already recorded** (checked first) | The line matches a payment Sasa already recorded by hand: same document or VS, same amount, date within ±N days (a setting), same account | Pre-ticked. Accepting **links** the line to that payment (its source changes from Manual to "Confirmed by statement") instead of creating a second payment. Included in the bulk accept. |
   | **Matched** | VS + amount + currency match within the payment tolerance (the one fixed rule, §2f Record Payment). Fakturoid allows up to 1.99 Kč and iDoklad under 1 Kč [S107][S115]. | Pre-ticked. Accepted in bulk with the prominent toolbar item **"Accept Exact Matches (N)"** or Bank ▸ Accept Exact Matches (one placement in the window, one label), and in the palette if it ships with v0.2 (§2k). A Xero product idea for bulk OK has 248 votes and is marked "In development" [S120]. |
   | **Suggested** | VS only (the amount differs, so it would be a partial payment or an overpayment); amount + a payer IBAN already confirmed ≥2 times (Fakturoid's rule [S108]); amount only, when exactly one open document matches | One ↩ per line |
   | **Unmatched** | Incoming lines with no candidate | Find with ⌘F, or mark N |
   | **Outgoing** | Outgoing lines | Categorise: Fees / Software / Rent / Tax / Owner / custom |

   - **Each row** shows the bank line as parsed on the left (date, amount, counterparty, IBAN, VS, message). On the right it shows the candidate document(s), a **reason label** ("VS + amount", "known IBAN", "amount only", "manual"), and the outcome ("→ Paid"). Xero labels each line with its reason and shows the statement line next to the match [S119][S121].
   - **Keys** (only while the list has focus):

     | Key | Action |
     |---|---|
     | ↑ ↓ | Move |
     | ↩ | Accept the suggestion (with no suggestion, open Find) |
     | ⌘F | Find another document. You can select several documents that add up to the line, as in Xero's Find & Match [S122]. |
     | N | Not an invoice: a category popover (1–6 or the first letter) |
     | S | Skip |
     | Space | Quick Look of the candidate PDF |
     | ⌘Z | Undo the last action (named) |

   - After each action, focus moves to the next unresolved line.
4. **Summary:** "Accepted 26 · Not invoices 9 · Skipped 2 · Unresolved 5".
   - Balance check: "Statement closing 12 345,67 € = app 12 345,67 € ✓". Xero compares the statement balance with its own [S119].
   - Unresolved lines stay in Unmatched and in the Overview queue.

Edge cases:
- Overlapping statements are de-duplicated by the bank transaction id, or by a hash of date, amount, counterparty and message.
- Bank lines are matched against **existing manual payments first** (the "Already recorded" lane), so a monthly statement never turns hand-recorded payments into second payments or Overpaid.
- One line can pay several documents, and one document can be paid by several lines.
- A SEPA payment short by a bank fee becomes a partial payment, with an option "write off remainder as fee". ACCT.
- A EUR document paid into the CZK account gets a suggestion with a warning, and accepting it opens the two-amount form (§2f Record Payment, v0.2).
- Outgoing refunds to clients are offered as matches to overpaid documents (they become the "Record Refund" payment).
- Unmatch is blocked for a payment that an issued document rests on (§2f edge cases).

**Monthly cash view per account (v0.2):** sidebar account row ▸ a table per month with opening balance, incoming, outgoing by category and closing balance. Clicking a month filters that account's lines.

### (g) Exchange rates (opened from File)

**In v0.1 Sasa types the rates.** Sasa's answer: "for start everything that nmeeds to be online i willů do manualy, s ill type current cnb rate for each invoice" (proposal doc, 5 Nov 2026).
- The **primary path** is the inline rate form on the document: the draft editor's totals bar and the Issue sheet (§2c). Sasa types the ČNB rate for the document's rate day (the DUZP; for § 64 goods the § 22 odst. 1 day), or for a weekend or holiday the last published rate (the resolver below). Mixed documents and DDPPs keep the tax point (ACCT).
- Every typed rate is also stored, so the next document with the same rate date picks it up. File ▸ Exchange Rates lists the stored rates.
- **Importing a ČNB file stays secondary:** File ▸ Import ČNB Rates…, and the Import ČNB Rates… button of the rates sheet and of the inline rate form. The import is built: InvoicingData `RateStore.importDaily` ("denni_kurz.txt") and `RateStore.importYearly` ("rok.txt"), both parsed by InvoicingCore `CNBRateFile`.

**Exchange Rates sheet** (File ▸ Exchange Rates, no shortcut; no ellipsis, because it asks for no input).
- It is resizable: `presentationSizing(.fitted)` (macOS 15 [S90]) with `frame(minWidth: 560, idealWidth: 640, minHeight: 400, idealHeight: 480)`, as design-system §5.3 sizes it; on macOS 14 the frame alone.
- Title "Exchange Rates".
- Top line: "Latest: EUR 30. 10. 2026 · USD 30. 10. 2026", with "USD —" when no USD rate is stored (`RateStore.latestDay(for:)`, as built).
- One read-only `Table`, Date newest first. Every header sorts.

| Column | Content |
|---|---|
| Date | The day the rate was published for: its own date, never the DUZP or the rate day |
| Currency | EUR or USD; sorting by it groups the two |
| Rate | "1 EUR = 24,315 CZK" (as built), trailing, `.amount` role |
| Source | **"Typed"** or **"ČNB file"**. A typed rate is stored as InvoicingCore `ExchangeRateSource.manual`, an imported one as `.cnb`. |

- The table lists EUR and USD, the v0.1 currencies. Other currencies in an imported file are stored for the Phase 2 "more currencies" work.
- Empty: "No rates yet" + "Rates you type on a document appear here." (design-system §8.10). It has no button of its own, because the sheet's button row carries Import ČNB Rates….
- Buttons: **Import ČNB Rates…** (`.bordered`, leading), which opens a `fileImporter` attached to the sheet [S73], and **Close** (↩ and ⎋). After an import the table updates at once; a file that can't be read shows its message (Importing, below) inline above the buttons.
- A stored rate is not edited in the table. A wrong rate is corrected where it is used: the draft's rate line **Change…** replaces the stored row for that day (§2c). Issued documents keep their own copy (rule 6).

**Typing a rate** (the v0.1 path):
- **Where:** the inline rate form in the editor's totals bar and in the Issue sheet (§2c). Document ▸ Enter Rate… focuses it.
- The form names the day it needs ("EUR rate for 30. 10. 2026 missing") and has one rate field; ↩ saves (§2c). The day is the rate day's publication day (the resolver below).
- **Source:** "Typed".
- **A rate dated after the rate day is blocked:** "The rate date cannot be after <day>, the day this document needs the rate for." (InvoicingCore `DocumentValidator`, `exchangeRateAfterTaxPoint`, with the text built in PR 21.)
- **Stale-rate warning.** A rate more than 7 days older than the rate day gives a ⚠ Check row in the Issue sheet (§2c): "The exchange rate is from {detail}, more than a week before the day the document needs the rate for; check that the rate table is complete." (`exchangeRateStale`, `exchangeRateStaleAfterDays` = 7; text from PR 21.)
- **Optional link (RECOMMENDATION; still open as Q7).** The inline rate form may show **Open ČNB Rates Page**, which opens the ČNB rates page in Sasa's own browser. SwiftUI `Link` (macOS 11.0) opens a URL "in the user's default web browser" when no app claims it [S155]. The app itself still makes no network call (rule 7). That a sandboxed app without network entitlements can open the link is UNVERIFIED; test it in the sandboxed build. The build thread picks the page address.

**Importing a ČNB file** (secondary).
- File ▸ Import ČNB Rates… opens the file importer at window level from any section, without opening the sheet or switching section. The sheet's and the inline form's Import ČNB Rates… open it too (`fileImporter` [S73], as built).
- The result line reports "214 rates imported" or "1 rate imported" (as built).
- A file that can't be read imports nothing (never a half-import, as built): "The file could not be read as a ČNB rate file: parsing stopped at line 12. Nothing was imported." (the line number comes from `CNBRateFile.ParseError.malformedLine`), or "The first line is not the header of a ČNB daily or yearly file. Nothing was imported."
- **A typed and an imported rate for the same day.** The data layer keeps one row per currency and day (`RateStore.save`: "Inserts or replaces"), so an import replaces a typed rate of the same day. A draft takes the new value when it next resolves its rate (as built); issued documents keep their own copy (rule 6).
- Later (no version set): an import preview ("Year 2026 · 214 days · 2. 1.–4. 11. 2026 · 2 new days · 0 changed") that lists value conflicts, typed rates included, and Undo Import ČNB Rates. Later (v0.2): dropping a ČNB file, with the bank import's drop zone (design-system §8.13).

**How the rate for a date is resolved** (rule 6; **ACCT: which ČNB rate legally applies to the rate day**, that day's rate or the previous publication day's depending on publication time, is UNVERIFIED and goes to the accountant). The resolver is built as one unit-tested function, InvoicingCore `ExchangeRateTable.resolve(_:on:)`, and the inline rate form uses it to name the day it asks for. A typed rate covers only its own day.
1. The day has a stored rate (typed or imported): use it.
2. A Saturday, a Sunday or a Czech public holiday: use the rate of the last working day before it, labelled "No rate is published for 1. 11. 2026 (weekend or holiday); the last published rate, for 30. 10. 2026, applies". The holidays come from a built-in table with Easter computed (InvoicingCore `CzechHolidays`, as built), which needs updating only when the holiday law changes.
3. A working day with no row, when the imported ČNB rows of the working days before and after it both exist: the ČNB published none that day, so the last imported rate applies, labelled "The ČNB published no rate for ‹day›; the last published rate, for ‹day›, applies". Typed rates are no evidence of such a gap. That the ČNB publishes only on working days is UNVERIFIED (ACCT: confirm against the ČNB publication calendar, then add an [S#]).
4. Otherwise the rate is **missing**, and the inline rate form asks for the publication day's rate: the day itself, or the last working day before it.
- A rate stored for any other earlier day is never used, because it is not the rate valid on that day. The data layer's `RateStore.rate(for:on:lookup:)` still defaults to `.lastPublishedOnOrBefore`, which with sparse typed rates can be weeks old; the editor and the Issue sheet use the resolver (as built), and the 7-day stale-rate warning catches the rest.

**Build status** (main at 18679ea). Main has Exchange rates as a sidebar section (RatesView.swift) with a currency pop-up, a toolbar Import ČNB Rates…, and a Coverage column with the latest day per currency and the note "The app makes no network calls…"; File ▸ Import ČNB Rates… switches to that section (MainSplitView.swift:414-418). To build: the sheet and its File item, the window-level importer and the empty-state texts (main: "No rates for this currency yet"). The rate day and its two texts are built (PR 21: `Document.exchangeRateDay`, DraftEditorModel.swift:788-835, Strings.swift:516).

### (h) Export and backup (opened from File)

The data is local, so the export and the backup should be instant; anything slow gets determinate progress and Cancel [S38].

**Export for Accountant sheet** (File ▸ Export for Accountant…, no shortcut; `presentationSizing(.form)` on macOS 15 [S90], a width range on macOS 14). The item stays disabled until the export step is built, as on main.

Title "Export for Accountant". From top to bottom:
- The month bar "◀ October 2026 ▶" (the Overview component, §2a), on the previous month by default. The Overview queue's Export Again… opens the sheet on its month (§2a).
- The preview line: "October 2026: 14 documents (2 advances, non-tax) · 9 payments · VAT 42 180 Kč". The VAT is Czech VAT, by the §2a aggregation rules.
- The status line for that month: "Not exported yet", or "Exported on 3. 11. 2026 to ~/…/FA 2026-10", plus "1 document changed after export" when a document was issued in that month, or changed in Repair mode (§2m), after its export. These are the Overview queue row's words (§2a).
- Cancel (⎋) and the prominent default **"Export October 2026…"** (↩). The label follows the month; after an earlier export of that month it reads "Export October 2026 Again…".

↩ opens the save panel in the last export folder (`fileDialogDefaultDirectory`, macOS 14 [research §25]). ↩ there runs a backup first, then writes the month's bundle into one folder, and the result line reads "October 2026 exported · backup made". If the backup fails, the export still writes, the result line reads "October 2026 exported · backup failed: ‹reason›", and the Overview queue's backup row appears (§2a).

The app keeps one export record per month (date and folder). The status line, the Overview queue row (§2a) and the Issue sheet's closed-month check (§2c) read it.

**The bundle is fixed** (no presets and no checkboxes; what it holds is agreed with the accountant, ACCT):
- the Documents CSV and the Payments CSV, with the fixed columns below, in one format agreed with the accountant (delimiter, decimal mark and encoding, ACCT; design-system §9);
- the month's PDFs, only if the accountant wants them (ACCT);
- the Stock list CSV, only once the accountant says it helps and the app has stock items (ACCT, §2n).

**Which documents belong to the month** (ACCT):
- tax documents by DUZP;
- § 64 goods by their § 22 odst. 1 day: the issue date if the document is issued before the 15th of the month after the supply, otherwise that 15th (the goods decisions; ACCT). A mixed document keeps its DUZP (ACCT);
- advances (no DUZP) by issue date, flagged as not tax documents;
- payments by payment date.

The Issue sheet's closed-month check assigns documents to months the same way (§2c).

**CSV columns** (a fixed set, so the column count never varies; final names, delimiter and encoding ACCT):
- Number, Type, **Daňový doklad (ano/ne)**, Issue date, DUZP, Due date, Status
- Client name, IČO, VAT ID, Country, VAT treatment
- Currency, Total; per rate, each in the document currency **and** in CZK: Base21, VAT21, Base12, VAT12, Base0, BaseExempt, BaseRC. Advance rows never fill the VAT columns.
- Rate, RateDate, RateSource, **RateIsFallback**
- **RelatedDocs** (DDPP → its advance; final invoice → the advances and DDPPs it deducts), **DeductedAdvance**, **DeductedVAT_CZK**. For an EU-goods final invoice's "Paid in advance", DeductedAdvance is filled and DeductedVAT_CZK stays empty, because the advance has no tax document and no VAT (goods decisions (b)).
- Paid amount, Paid date, Closing event (closed unpaid / marked for credit note)

**Backup** (File commands; no card and no Settings pane).
- **Fixed behaviour**, from the backup step on, with no options: a backup on the first launch of each day, on quit, and before every export. The last 30 are kept in the backup folder.
- **File ▸ Back Up Now** (no ellipsis) runs at once and reports "Backup made at 9:02" in the result line. The Overview queue's backup row has the same button (§2a).
- **The one setting is the backup folder:** a path control [S49] in Settings ▸ General, under the PDF folder (§2i). Its default is a "Backups" folder next to the data file, which lives in the app's sandbox container (Application Support/FA, AppModel.swift), on the same disk as the data. RECOMMENDATION: local by default, which matches the decision that the audit log never leaves the Mac. Whether Sasa picks a cloud-synced folder stays open for the lead and Sasa (§2m).
- **Caption under the folder:** "Daily and on quit; the last 30 are kept. Last backup: today 9:02." Before the first backup its second sentence reads "No backup yet."; after a failed backup, until one succeeds, "Last backup failed: ‹reason› · last successful 3. 11. 2026". The caption claims nothing about off-site protection: the default folder is on the same disk.
- A failed backup also puts up the Overview queue's backup row at once. The row also appears when the last successful backup is more than 7 days old (§2a).
- **What's included:** the database, with the audit log (§2m) and the stored issued PDFs (ADR 0010), and, in v0.2, the stored statement files. The logo joins once the logo ships (§2i).
- **File ▸ Restore from Backup…** (also the first-run card's link, §2j, and the "Data can't be opened" banner, §2a):
  1. Pick a file.
  2. A preview: backup date, counts, app version.
  3. An **alert**: "Replace current data with the backup from 3. 11. 2026?". Informative text: "Current data will be saved as a backup first." Buttons Cancel / **Restore**.
  - Restoring is an uncommon action that can't be undone, so an alert is right [S25].
  - Determinate progress follows.
- **File ▸ Show Data Folder** shows the data file in Finder (as built). It and the database-error screen are the places that reach the data file's path.

**Build status** (main at 18679ea). Main has Exports & Backup as a sidebar section with two cards (ExportsView.swift); its Export…, Back Up Now… and Restore from Backup… buttons are disabled, as are the File items (Commands.swift:102-108), and Show Data Folder works. To build: the export sheet, the backup and restore with the backup step, Back Up Now without its ellipsis (main: "Back Up Now…", Strings.swift:670), and the folder and caption in Settings ▸ General.

**Naming note.** In Czech, "záloha" means both an *advance* and a *backup*. The English UI keeps the two apart ("Advance", "Backup"), so the clash can't reach the app.
### (i) Settings panes

**Build status** (main 18679ea):
- **Goes from main:** the Documents & PDF, VAT defaults and Backup panes (SettingsView.swift:14) with the PDF switches and the file-name row; General's language and text-size notes and Data file row; Company's VAT payer toggle (fixed to true), Default currency (a draft without a client starts in EUR, set explicitly), Save button and separate Section and Insert fields; Bank Accounts' separate IBAN and Czech account fields and green tick; Numbering's Create Default Series, New Series… and Edit… sheet (name, document types, yearly-restart toggle, VS prefix).
- **To build:** the four panes; the PDF folder control in General, with Forget Folder and its caption; the backup folder (with the backup step); Company fields that commit on their own, the File number field, the "Company ID is not valid" wording and the footer; the one-field account form and Edit ▸ Undo for Remove; Numbering's three fixed sections with Last issued number, the next-number line, one Save, the confirmed flag, the migration rule and the name "Tax documents for received payments".

Rules for every pane:
- Good defaults, and no setting that duplicates a system setting [S29].
- No Light/Dark switch [S15].
- Every pane is a grouped `Form` (`.formStyle(.grouped)` [S1]) with title-case section headers.
- **One save rule.** A value applies as soon as it is committed: a field on ↩ or when focus leaves it, a folder when it is chosen, an account on Add. Numbering is the exception: it keeps one Save, because a used number series can't be changed back. An invalid value shows its inline message at the field and is still kept; Issue blocks where the law needs the value (§2c).

**Panes.** Four, in this order, with their symbols (as built): General (`gearshape`) · Company (`building.2`) · Bank Accounts (`building.columns`) · Numbering (`number`). The window title and restore are in §1.3. A stored pane that no longer exists ("documents", "vat" or "backup") opens General. That `@AppStorage` already falls back to its default for an unknown raw value is UNVERIFIED; test it.

**Fixed rules, not settings.** Each is specified where it applies:
- a new client's payment term (14 days), currency, document language and VAT status, by the country rule (§2e);
- the payment tolerance (§2f);
- the QR type by currency (§2c);
- the total-change check, fixed at 50 % (§2c);
- the PDF path and the backup schedule (General, below);
- the VAT rates: a dated table in InvoicingCore (`CzechVATRates`; 21 / 12 / 0 % since 1 Jan 2024, as built), so a new rate arrives with an app update. The document treatments and their printed texts are in §2c and design-system §9.

Stock adds no setting (§2n).

**General** holds two rows and nothing else.
1. **PDF folder:** an editable pop-up path control (`NSPathControl` in a small `NSViewRepresentable`). An editable pop-up path control's menu "contains an additional Choose command" [S49]. Choose… opens an open panel for folders only, with the prompt "Choose the folder where issued documents are saved as PDF files." (as built). The chosen URL is stored as a security-scoped bookmark (as built). While a folder is set, **Forget Folder** sits beside it.
   - **The folder is the switch.** With a folder, Issue saves each document's PDF at the fixed path ‹PDF folder›/‹year of issue›/‹number› ‹client›.pdf, for example 2026/FV 2026-0042 Acme GmbH.pdf; slash, backslash and colon in the name are replaced (ADR 0010; a default kept without asking, §6). With no folder, the PDF stays in the app until Save PDF…. The PDF is always stored in the database (as built).
   - Caption with a folder: "Issued documents are saved as 2026/FV 2026-0042 Acme GmbH.pdf." (the current year). Without one: "No folder: the PDF stays in the app until you use Save PDF…." The Issue sheet shows its PDF row only when no folder is chosen (§2c).
2. **Backup folder** (ships with the backup step): the same control, without Forget Folder. Its default is a "Backups" folder next to the data file, which lives in the app's sandbox container (Application Support/FA, as built), so it is on the same disk as the data.
   - The behaviour is fixed, with no options: a backup on the first launch of each day, on quit and before every Export for Accountant, and the last 30 are kept (§2h).
   - Caption: "Daily and on quit; the last 30 are kept. Last backup: today 9:02." Before the first backup its second sentence reads "No backup yet." After a failed backup it reads "Last backup failed: ‹reason› · last successful 3. 11. 2026" until a backup succeeds; the Overview queue shows the failure too (§2a). The caption claims nothing about off-site protection.
   - RECOMMENDATION: local by default, which fits the decision that the audit log never leaves the Mac. Whether Sasa picks a cloud-synced folder stays open for the lead and Sasa (§2m).
   - Settings has no Back Up Now or Restore button. Both are File commands (§1.4, §2h).
- **Prototype first.** Two points are UNVERIFIED:
  - (a) whether a URL picked through the control's Choose… panel can be bookmarked with `.withSecurityScope`;
  - (b) that a parent folder picked from the control's pop-up menu never becomes the PDF or backup folder, because the sandbox grants no access to it. The stored bookmark changes only when Choose… returned a URL from the open panel, so a folder dragged onto the control [S49] doesn't change it either.
  - If either fails, General keeps the built folder caption with a **Choose Folder…** button.
- There is no app-language setting: the UI is English only. Whether macOS's per-app language [S9] would show the bonus Czech entries of `DesignSystem.xcstrings` is UNVERIFIED; that mixed UI is not designed.

**Company** is one grouped form. Fields, in order:
- Legal name · Street · City · Postal code
- Country (pop-up, CZ)
- Company ID (IČO) · VAT ID (DIČ)
- Register court: a pop-up whose first item is "Not registered" (as built).
- File number, shown once a court is chosen: one field, for example "C 12345", parsed into `RegistryEntry(court:section:insert:)`. A value without both a section and a number shows "Enter the file number as section and number, such as C 12345."
- Email · Phone. Each prints only when filled.
- Then a section, **Footer text**: multi-line document text, one footer for both document languages. Every document issued after it is set prints it, DDPPs included. It is empty by default: no footer prints until Sasa sets one. New drafts take it (as built).

Rules:
- Inline validation at the field [S34]: "Company ID is not valid (8 digits with a check digit)." (the string the client form shares, §2e) and the VAT ID format check.
- The fields commit on their own (the save rule above), so there is no Save button. An invalid value is kept with its message, and the Issue sheet's ⛔ "Company profile incomplete" row covers what a document needs (§2c). Keeping an invalid value means the profile stores the typed text (to build).
- Caption (as built): "Changes apply to future documents only. Issued documents keep their own copy of these details."
- Later (no version set): a logo, together with the logo on the PDF (ADR 0010).

**Bank Accounts**
- The list has one row per account (as built): the account number as the title (the domestic form for a Czech account, the IBAN otherwise), the caption "IBAN · BIC · bank name", and the currency and **Remove** at the trailing edge.
- **Remove is undoable from the line and from Edit ▸ Undo.** Remove asks nothing. It registers with the Settings window's `UndoManager` as "Undo Remove Bank Account", so Edit ▸ Undo (⌘Z) puts the account back at its old position. The line "Bank account removed" with **Undo** confirms it, with `checkmark.circle` in `.secondary`.
- Caption (as built): "The first account in a currency is printed on documents in that currency; an account without a currency serves the rest." When two accounts fit, the editor still lets Sasa pick either (§2c).
- The form has four fields and **Add**:
  - Account number: one field for an IBAN or a Czech number written as prefix-number/bank code (placeholder "IBAN or 123456789/0800"). The IBAN check digits and the Czech checksums are validated (as built). Error text: "Enter an IBAN or a Czech account number such as 123456789/0800."
  - BIC · Bank name · Currency (Any, EUR, CZK, USD).
- An account has no nickname, no "default for this currency" toggle and no archived state: each issued document keeps its own copy of the account, so Remove with Undo is enough. Later (v0.2): a "print on documents" switch, only if statement import needs an account that never prints.

**Numbering**
- The database creates three series when it is created, one section each:

| Section header | Series name | Pattern | VS prefix | Numbers |
|---|---|---|---|---|
| Invoices | Invoices | FV {YYYY}-{NNNN} | 1 | invoices and final invoices (ACCT) |
| Advance Invoices | Advance invoices | ZF {YYYY}-{NNNN} | 2 | advance invoices |
| Tax Documents for Received Payments | Tax documents for received payments | DD {YYYY}-{NNNN} | none: DD carries no payment request | tax documents for received payments |

- The DD series stays although an EU-goods advance gets no tax document (ADR 0012): other advances still need one.
- Each section has two fields and one live line:
  - **Pattern** ({YYYY}, {YY}, {NNNN}): prefilled, and editable until the first document is issued from that series. Then it is read-only, because the yearly restart follows the pattern.
  - **Last issued number:** empty by default. It takes "FV 2026-0041" or just "2026-0041", parsed with the section's pattern (the prefix is optional). Empty means the series starts at 1. It is read-only after the first issue (as built for the counter).
  - The line "Next number: FV 2026-0042 · VS 120260042 – assigned when you issue". The DD section shows the number only.
- One caption at the top: "Type the last number you issued in your previous tool. Leave it empty to start at 1. It can't be changed after the first document is issued."
- **One prominent Save** for the pane. Edits that aren't saved are dropped when the window closes. A counter never goes backwards: the store's check runs at Save. Save is disabled while a field doesn't parse or two series collide, and the message names both series:
  - "‹Invoices› and ‹Advance invoices› would give documents the same variable symbol. Change one of the patterns."
  - "‹series› and ‹series› would issue the same numbers. Change one of the patterns."
- **The yearly restart follows the pattern** (Sasa's answer, 6 Nov 2026: "YES WHY NOT, JUST HAVE THE NEW YEAR IN THE NUMBER"; ACCT): {YYYY} or {YY} restarts the counter each year, and a pattern without a year token counts on. There is no switch. The core already refuses a yearly restart without a year token (as built).
- **VS rule.** The VS is the series prefix followed by the digits of the number, at most 10 digits in all (Fakturoid's derivation [S106]). The core keeps the prefix and takes as many trailing digits as still fit (as built, ADR 0003 addendum).
  - Example: without prefixes, FV 2026-0042 and ZF 2026-0042 would both become 20260042. With them, FV 2026-0042 → 120260042 and ZF 2026-0042 → 220260042. The prefixes are fixed.
  - The pane blocks patterns whose VS could collide. VS is compared for FV and ZF; numbers across all three.
  - A VS that is unique across series matters for v0.2 auto-matching, which uses VS + amount (Fakturoid and iDoklad both match this way [S107][S115]).
- **Confirmed.** The setup step "Continue your number series" (§2j) is done once this pane has been saved, recorded as a flag in the database. Until then, Issue shows the ⛔ row "Confirm your number series in Settings ▸ Numbering." with Fill in… (§2c).
- **Existing databases.** On open, a database with no series gets the three. One that has series keeps them and gets no second set: they map to the three sections by the default ids (invoice, advance, paymentReceipt), or else by kind (the first series that numbers each kind). Any other series stays stored and numbers nothing new, because there is no series picker; the documents it numbered keep their numbers. The step counts as confirmed when a mapped series has already issued a number (`lastIssuedYear` set), so an updated install neither duplicates series nor blocks Issue after real issuing.

### (j) First-run onboarding

**Build status** (main 18679ea):
- **Goes from main:** the optional ČNB rates and first-client or first-invoice steps, the Open Settings… button on each step, and the green tick.
- **To build:** the card alone on a first-run Overview, and never with the "Data can't be opened" banner (§2a States); the line "Three steps before you can issue the first document."; one Open Settings…; the ticks in `.secondary`; the Restore link; the company step's check; step 3 done by the Numbering pane's Save (main counts any stored series); a draft before setup (R009: without a company profile, main answers ⌘N with "Fill in the company profile in Settings before creating documents.").

Principles:
- Onboarding is "fast, fun, and optional".
- Non-essential setup is postponed.
- There is no licence text, and no tutorial is ever shown again [S40].
- No alert at launch [S25].
- **No import step.** Sasa's current tool is a "poverty self made unsuccesful local app" (Sasa's answer in the proposal doc, 5 Nov 2026), so there is nothing to import. Setup only asks for the last numbers issued (step 3).

1. **The first launch opens the main window on Overview, with the "Getting started" card.** From the top, the card holds:
   - the link **"Moving from another Mac? Restore from Backup…"** (File ▸ Restore from Backup…, §2h). It shows once Restore from Backup… works; until then the command is a disabled File menu item (as on main).
   - the title "Getting started" (`.sectionTitle`) and one line, "Three steps before you can issue the first document."
   - three rows. Each has `checkmark.circle.fill` (done) or `circle` (not done) in `.secondary`, plus its title. VoiceOver reads a row as one element with the value "Done" or "Not done" (as built).
     1. **Company profile** (required to issue): done once legal name, address, Company ID (IČO) and VAT ID (DIČ) are filled and valid, so the Issue sheet's ⛔ "Company profile incomplete" row no longer shows (§2c). RECOMMENDATION: Company has no Save (§2i), so a stored profile alone can't mark the step done.
     2. **Bank accounts** (required for payment details and the QR): done once one account exists (as built). Sasa adds one for each currency in use, from EUR, CZK and USD.
     3. **Continue your number series** (required). In Settings ▸ Numbering, Sasa types the *last number issued in the previous tool* for each series, e.g. "2026-0041". Leave it empty to start at 1. The live line shows "Next number: FV 2026-0042 · VS 120260042 – assigned when you issue", and the collision check shows inline. The step is done once the pane is saved, or by the migration rule (§2i).
   - one prominent **Open Settings…** (`openSettings`, macOS 14 [S76]). It opens the first unfinished pane: Company, then Bank Accounts, then Numbering.

   There is no rates step: Sasa types the ČNB rate on the first EUR or USD invoice (§2c); File ▸ Import ČNB Rates… stays available. There is no first-client or first-invoice step (⌘N and File ▸ New Client… always work) and no Stock step, because stock never blocks invoicing (§2n).
2. **Where the card shows.** Until the three are done and while no document exists, the card is the only content on Overview; once documents exist, it sits above the tiles and queue (for example after the last bank account is removed). The data error banner always wins: the card never covers the "Data can't be opened" banner (§2a States).
3. Once all three are done, the card goes. With no documents yet, the Overview then shows "No documents yet" with New Invoice (§2a). Help ▸ Getting Started shows the card again, all ✓, with a close button (`xmark`, "Close") and without Open Settings… (as built).
4. **Nothing blocks exploring.** ⌘N, File ▸ New Invoice and the toolbar's New Invoice create a draft before setup is finished (R009, to build). If Sasa presses Issue before then, the Issue sheet lists the missing steps as ⛔ rows with **Fill in…**, which opens the pane (§2c).
5. Edge case: a last number lower than the previous tool's real last number would create duplicates. There is no confirmation question: the live Next number line and the Issue sheet's title ("Issue invoice FV 2026-0042?", §2c) show the number before it is assigned.
### (k) Command palette (⌘K): later (v0.2 or after)

Later (v0.2 or after): a command palette. v0.1 has none. ⌘K is unbound and reserved for it (§3.1), and View has no Command Palette… item. The v0.1 keyboard paths are the menu bar, each section's toolbar search (⌘F) and the Help menu's search field (§1.4).

**Constraints the later build keeps.**
- **It mirrors the menus.** One command registry produces both the menu bar and the palette, so the palette can't drift from the menus, which still list every command [S18]. Every palette command is also a menu item; the palette never replaces a menu or a toolbar item.
- **Scope.**
  - All menu commands. A disabled command shows its reason dimmed ("Issue… – no draft selected").
  - Jump to clients and documents by number, VS, amount, client name, IČO or VAT ID.
  - Per-client actions: New Invoice (⌘N), New Advance Invoice (⇧⌘N), Duplicate ‹the client's last invoice› as Draft (⌘D, as in File, §1.4), Add Note to “‹Client›”… and Record Payment… on the oldest open document.
  - Sections and Settings panes. An empty query shows recent items.
  - With a document selected, that document's actions come first, and ↩ runs the top one, as in Raycast [S131].
  - Records and commands only, no natural language (that is the Phase 3 assistant below).
- **Shape.** A sheet on the main window, 560 pt wide (`presentationSizing(.fitted)` on macOS 15 [S90], with a fixed frame width), its text field focused. Results are grouped: Actions for the selection / Clients / Documents / Commands. Each row carries its type label, names its actions and shows its shortcut on the right. ↑↓ moves, ↩ runs, ⎋ closes.
- **⌘N and ⌘D act on the highlighted row, never on the main window's selection behind the sheet.** The palette declares its own buttons for these chords inside the sheet. The documented resolution order is "the key window first, then the main window, and then the command groups" [S147], so the palette's buttons should win over the File-menu commands (UNVERIFIED for a sheet; test it). As a second guard, the selection-based menu commands are disabled while the palette is open.
  - **Acceptance test:** palette open, main-window selection on another client's invoice, type "acm", press ⌘D → the app must duplicate **Acme's** last invoice.
- **Matching** is diacritic-insensitive, so Czech client names and line texts match when typed without accents. Ranking: an exact number first, then a client-name prefix, then commands, with a boost for recent use.
- **Placement.** `presentationPlacement(.center)` is **(27)**, and "only sheet presentations respect this placement" [S146]. How `.center` renders on a Mac is **UNVERIFIED**. Below macOS 27 (gated, §0.1): default placement.
- **⌘K in text views.** The palette must not override ⌘K inside text views. The app has no rich text, and in Apple's text editing ⌘K is "Add a web link" [S8].
- **Phase 3:** the optional on-device AI assistant lives here ("Describe an invoice…"). It only ever creates a **Draft**. It never issues and never sends.

**Build status** (main at 18679ea). Main still has the unused `LayoutMetrics.paletteWidth` (560 pt, DesignTokens.swift:76). To build: remove it; it comes back with the palette.

### (l) Phase 3: iPhone companion (read-only)

**Device.** Sasa's iPhone: "currently 15 pro max 256gb, very soon 18 pro max 256gb (ordering today, but there is shortage so 1-2weeks)" (Sasa's answer in the proposal doc, 5 Nov 2026). So the companion targets the current iOS (RECOMMENDATION; set the exact minimum when Phase 3 starts). Which iOS each phone runs is UNVERIFIED here; check Apple's compatibility list then.

**Structure.**
- A SwiftUI `TabView` (`Tab`, iOS 18 [S91]) with **Overview · Documents · Clients** plus a search tab (`Tab(role: .search)`, which the system places at the trailing end [S54][S28]).
- Each tab has its own `NavigationStack`.
- The tab bar floats on Liquid Glass and can minimise on scroll (`tabBarMinimizeBehavior`, 26.0 [S91]).
- Tabs are for navigation only, never for actions [S54].

**Key screens.**
1. **Overview**
   - Snapshot freshness at the top: "Data from Mac · 5. 11. 2026 14:02". When the snapshot is older than 7 days, a banner in the **orange caution tone with a symbol** (`exclamationmark.triangle`) appears; yellow is never used (design-system §4.4).
   - Overdue total and list, oldest first. Unpaid total. The next due date.
2. **Document detail**
   - Status, totals, open balance, payments and the chain line.
   - **PDF** through `quickLookPreview` (iOS 14 [S77]).
   - **"Mark Payment Received"** creates a *pending payment proposal* labelled "Waiting for Mac". The Mac shows it in the Overview queue for confirmation. The iPhone never changes a document, and it has no Repair mode (§2m).
3. **Client detail**
   - Contacts (call or mail through the phone's own apps, a user action), open balance, documents.
4. **Sync / Data**
   - Receive an encrypted snapshot file by **AirDrop or file-based transfer** only (share sheet on the Mac, Files on the iPhone; protocol for the build thread). This keeps rule 7: the Mac app stays without network entitlements [S139]. That sending through the macOS share sheet / AirDrop needs no network entitlement is UNVERIFIED; test it in the sandboxed build.
   - **Local Wi-Fi sync is out of scope.** It would need `com.apple.security.network.server` and/or `…network.client` on the Mac [S139], which is a change to rule 7 that only Sasa can decide.
   - "Send pending changes to Mac" through the share sheet (`ShareLink` presents the system share UI and sends nothing by itself [research §11]).
   - Never automatic, never iCloud.

**Widgets.**
- Small: overdue total.
- Medium: overdue total plus the next due date.
- Lock Screen rectangular: overdue total.
- Support the accented and vibrant rendering modes [S55].

### (m) Repair mode (v0.1.x)

**Decision.** The proposal doc's decisions table (last row) records: "A Repair mode behind Touch ID or the password will unlock every record, issued documents included; each repair change is written to the audit log, which never leaves the Mac. There is no trace-free mode". It answers Sasa's comment: "itegrity, if shit happens give option for tampering but keep it like you proposed, just some secret undetectable option for me to put in password, id face, fingerprint to have total access and can change things without trace" (proposal doc, 5 Nov 2026). This section designs that decision. **It never designs a trace-free path.** Planned for v0.1.x.

**The normal fix stays the corrective document.** A wrong issued document is fixed with a credit note, the corrective document of Phase 2. Until then, Mark for Credit Note… (§2d) records the mistake. Repair mode is the last resort, for when that path can't help.

**Entry.**
- File ▸ **Repair Mode…** (§1.4). No shortcut (§3.1).
- It is an ordinary, visible menu command, because every command is in the menu bar (§0.1). The protection is the authentication, not hiding.
- A sheet opens first (`presentationSizing(.form)` on macOS 15 [S90], a width range on macOS 14):
  - Title: "Turn On Repair Mode?"
  - Text: "Repair mode unlocks every record, issued documents included. Every change is written to the audit log with a reason. The audit log stays on this Mac."
  - **Reason** (required, one line), e.g. "Wrong client address on FV 2026-0042".
  - Buttons: Cancel (⎋) / **Unlock…** (↩), which starts authentication. Unlock stays disabled until the reason is filled in [S35].

**Authentication.**
- `LAContext.evaluatePolicy(_:localizedReason:)` with the policy `LAPolicy.deviceOwnerAuthentication` [S152][S153]. LAContext and the method are macOS 10.10 and the policy is macOS 10.11, so no gate is needed at the 14.0 target.
  - On macOS this policy authenticates "with Touch ID, Apple Watch, or the user's password" [S153]. If biometry is available, enrolled and not disabled, the system uses it first; otherwise it asks for the password [S153].
  - Sasa asked for "password, id face, fingerprint". On the Mac the policy names Touch ID, Apple Watch and the password [S153]. The iPhone companion never edits (§2l), so Face ID plays no part. The decision names only Touch ID and the password, so confirm with Sasa that an Apple Watch unlock is acceptable (open points below, as design-system §8.18 does).
  - Don't use `deviceOwnerAuthenticationWithBiometrics`: when Touch ID is unavailable or not enrolled it fails, and the fallback is left to the app [S154]. `deviceOwnerAuthentication` falls back to the password by itself [S153].
- The reason in the system prompt reads, e.g., "unlock every record for repair". Apple asks for a short, clear reason that describes the action, without the app name [S152].
- Authenticate again on every entry. Keep `touchIDAuthenticationAllowableReuseDuration` at its default of 0, so an earlier Touch ID unlock is never reused [S152].
- The LAContext page asks for the `NSFaceIDUsageDescription` key in Info.plist when an app allows biometric authentication [S152]. Whether macOS needs it for Touch ID is UNVERIFIED; add it anyway.
- These pages name no entitlement. That the sandboxed app needs none for this is UNVERIFIED; test it in the sandboxed build.
- Cancel or failure: nothing unlocks, and the sheet stays open with the inline line "Not unlocked". Policy evaluation can fail through cancellation by the user or the system [S152].

**What unlocks.** Every record, issued documents included: header fields, lines, dates, the client snapshot, payments an issued document rests on, advance deductions (for EU goods, "Paid in advance"), closing events and rates. Edits and deletes both become possible.
- A change that breaks a rule the app otherwise enforces shows an inline problem message next to the field before it saves: a gap or a duplicate in a number series, a VS that collides, totals that no longer match the stored PDF, a payment that no longer covers its tax document, or an EU-goods advance payment that no longer matches its final invoice's "Paid in advance" (built in PR 22). The legal side of each is ACCT.
- A changed issued document gets a new PDF rendered from the repaired data. The previous PDF bytes stay with the audit event and are never deleted (RECOMMENDATION). Whether the client needs the new PDF, or a corrective document instead, is ACCT.
- **The audit log never unlocks.** It stays append-only; the data layer already enforces that with triggers (Schema.swift). The issued-document locks are triggers too, and so is the stored PDF, which holds one PDF per document (`documentPDF`, ADR 0010). So Repair mode needs a data-layer design from the build thread: each repair change and its audit event in one transaction, and a new PDF beside the kept old bytes.

**How the window shows the mode.**
- A persistent banner across the top of the main window's content: "Repair mode is on. Every change to a locked record is logged." with the button **End Repair Mode** (design-system §8.18). It uses a symbol and the caution tone, never colour alone (design-system §4.4; [S13]).
- The window title area is marked: the subtitle starts with "Repair mode" (`navigationSubtitle` [S100]), e.g. "Repair mode · Unpaid · 3".
- Fields of issued documents become editable. The lock line on an issued document shows `lock.open.fill`, with the tooltip and VoiceOver label "Unlocked for repair", and reads "Repair mode: changes are logged" (§2b).
- File ▸ Repair Mode… reads **End Repair Mode** while the mode is on.
- The banner never hides on a timer (§0.1, principle 7).

**Every change is logged.**
- Each change to a record that is normally locked writes one audit event: the record, the field, the old and the new value, the time, and a **reason**.
- The reason field sits inline next to the change, prefilled with the reason from the entry sheet. Sasa can overwrite it for that change. ↩ saves the change and its reason together (RECOMMENDATION).
- If the audit event can't be written, the change isn't saved (one transaction, as above).
- Undo works inside Repair mode, change by change, with named actions [S42]. An undo is itself a logged change (RECOMMENDATION).
- Each repair event is a row in the issued view's Activity disclosure (§2b) and in the client's Activity tab (§2e). It carries `wrench.and.screwdriver.fill`, the only Activity symbol (design-system §8.15), and one sentence with the field, old → new and the reason; in the client's tab the sentence starts with the document number (RECOMMENDATION). This is where Sasa reads what a repair changed.

**Ending the mode.**
- The banner's **End Repair Mode**, or File ▸ End Repair Mode.
- Quitting the app. The next launch always starts locked; restoring the previous state [S27] never brings the mode back.
- A timeout (RECOMMENDATION): 10 minutes without a change ends the mode. The banner then reads "Repair mode ended after 10 minutes without changes" and stays until Sasa closes it, so nothing changes silently.
- When the mode ends, the result line reads "Repair mode ended · 3 changes logged", from one interpolated key, with its close button only (design-system §8.17). Each change is in its document's Activity (above).

**What it never does.**
- **No trace-free change.** There is no setting, key, gesture or hidden command that changes a record without an audit event.
- It never edits or deletes the audit log.
- **No change leaves the Mac.** Repair mode sends nothing and makes no network call (rule 7). The audit log is never exported or shared: it is not in the Export for Accountant bundle (§2h), the iPhone snapshot (§2l) or any share sheet.
- It isn't available on the iPhone.
- It isn't the normal fix for a wrong document: that stays the credit note (Phase 2).

**Open points for Sasa.**
- **Backups.** A backup holds the whole database, audit log included, so a restore keeps the log (§2h). Sasa mentions "using mainly 8tb cloud". A backup folder in a cloud-synced location would copy the audit log off the Mac. That conflicts with the decision ("which never leaves the Mac"). The default is local: a Backups folder next to the data file, inside the app's container (§2h). Whether Sasa picks a cloud-synced folder, and how that fits the decision, stays open for the lead and Sasa.
- **Apple Watch.** `deviceOwnerAuthentication` accepts a nearby paired Apple Watch [S153], but the decision names only Touch ID and the password. Confirm with Sasa that a watch unlock is acceptable (design-system §8.18).

### (n) Stock: a rough list for reordering

**Version.** Stock ships when the build's roadmap says. Until then none of it shows: no sidebar row, no Stock menu, no New Stock Item…, no stock suggestions in the editor and no Items tab, and ⌘5 stays unassigned (§3.1).

**Build status.** Nothing of Stock is built on main (3ce8589). The build owns the model below and writes its ADR when Stock is scheduled.

**Purpose.** Know roughly how much of what is on the shelf, and what is running low, so Sasa knows what to order. Sasa's words (5 Nov 2026): "I cannot keep perfect track of everything that leaves and is added to the storage/warehouse. So it will be mostly roughly so I know how much of what for ordering etc." The CRM side is a per-client list of the stock items that client bought (Sasa's answer on the design card, 5 Nov 2026: "CRM, customer records").

**Rules the UI keeps** (from the build thread, 5 Nov 2026):
1. **Rough on purpose.** The number on hand is what the app last knew, not a ledger. A count fixes it in one step. The UI shows how fresh a number is ("Counted 3 weeks ago"), never a warning.
2. **Stock never blocks invoicing.** Unknown or negative stock never stops a draft, a review or Issue. The Issue sheet's stock row is information, never a ⚠ or ⛔ row (§2c).
3. **No new settings.** Nothing about stock lives in Settings (§2i). An item's only optional numbers are its reorder level and its starting count.
4. **Issued documents stay untouched.** The link between a line and a stock item lives outside the document, in a table beside it (the build's draft-side table). That table keeps the links after Issue, so Duplicate as Draft and Create Final Invoice can copy them. The document JSON, its hash and the PDF never mention stock. Issue turns each linked line of an Invoice or a Final invoice into an "out" movement.
5. **Only an Invoice or a Final invoice takes goods out.** An advance's lines may link to stock items, and Create Final Invoice copies the lines with their links (§2d). An Advance invoice and a tax document for a received payment never create a movement, so along the advance chain the goods leave stock once, with the final invoice. A tax document for a received payment never shows stock suggestions.
6. **No reversal on a closing event or a repair.** Close Advance as Unpaid…, Mark for Credit Note…, their reopening and a Repair mode change (§2m) don't touch stock, because the goods may or may not have come back. A count or Receive… fixes the number. Later (Phase 2): the credit note, the corrective document, adds the goods back.

**Model the screens show** (the build owns it):
- A **stock item** has a name, a unit (free text, with the suggestions of the line's Unit field, §2c) and an optional reorder level. It can be archived.
- A **movement** has a kind (in, out, count), a day, a quantity (`Decimal`, so "1,5" works), a note and a source (manual, a document line, or a count).
- **On hand = the latest count + the "in" movements after it − the "out" movements after it.** Movements are ordered by day, then by the time they were recorded. With no count yet, on hand starts from 0, so it can go below zero.

**Layout.** Sidebar | items `Table` (content column) | the selected item (detail column). One item is selected at a time. With none selected, the detail reads "Select an item" (title only, as in Clients). The window title is "Stock", or the selected item's name (§1.1). The selection comes back with the window (§1.1 Restore).

**Sidebar row** (§1.2): "Stock", the fifth row, after Payments, with ⌘5 and View ▸ Stock (§1.4). Its symbol is `shippingbox` (macOS 11.0 in the SF Symbols data that design-system §7 cites), so the macOS 14 target has it; confirm the name in the SF Symbols 27 app. The badge counts the Low items: no badge at 0, no tint, and the accessibility value "3 running low". ⌘5 moves keyboard focus into the list, so "bol" typed next reaches type-select (§1.2; UNVERIFIED until checked on macOS 27.2). The Overview has no stock row: the badge does that job.

**Toolbar** (design-system §8.11, the Stock list and Stock item rows; fixed, like every toolbar):
- New Stock Item (`plus`, tooltip "Add a stock item") · search, prompt "Search stock". Search (⌘F) filters by name.
- With an item selected: **Receive…** (text, tooltip "Add goods that arrived") · **Count…** (prominent, trailing, tooltip "Set the number on hand after counting the shelf"). Count… is the detail's one prominent button.
- Take Out… is not a button. It is in the Stock menu and the row's context menu only, because a count fixes the same thing later.

**Items table.**

| Column | Content |
|---|---|
| Item | The name, sorted with `localizedStandard`, so Czech diacritics sort correctly [S59] |
| On Hand | "120 ks", trailing, in the `amount` text role (tabular digits, design-system §3), with the quantity format of design-system §9, never a hand-built one. Below zero it reads "−5 ks" in `.secondary`, never red: red is only Overdue (design-system §4). A running-low item adds the **Low** badge. |
| Reorder At | The item's reorder level, or empty |
| Counted | The latest count's day as a relative date ("3 weeks ago"), or "Never" |

- **Running low** means an item with a reorder level whose on hand is at or below it. Its On Hand cell carries one badge, **Low**: the caution tone with `arrow.down.circle` and the word, never colour alone (design-system §4.3). The symbol's availability at the macOS 14 target is UNVERIFIED (the same SF Symbols app check). An item without a reorder level is never Low.
- **Sort:** Low items first, then Item A–Z, by default. Every header sorts, and View ▸ Sort By ▸ lists the columns (§1.4).
- **Keys** (§3.2): type-select on item names, as in Clients (§2e), so the list has no letter actions. ↩ opens Count… for the selected row. ⌫ (Edit ▸ Delete) deletes an item with no movements, undoably. For an item with movements Edit ▸ Delete is disabled, and Stock ▸ Archive “Bolt M8” applies.
- **Context menu** on a row (unavailable items hidden and no shortcuts shown, as in every context menu, §2b): Count… · Receive… · Take Out… | Archive Item, with Delete in Archive Item's place for an item with no movements.

**Item detail** (detail column), top to bottom. Its content has no buttons.
- **Header:** the name, the unit and the reorder level, each edited in place. A field commits on ↩ or when focus leaves, and each change is undoable. An empty name, or one another item already has, isn't saved: the field returns to the old name and shows the New Stock Item message (below). A new name changes no document, because a line's description is document text. A new unit converts nothing.
- **On hand:** the figure in the `kpi` role ("120 ks"), with "Counted 3 weeks ago" (or "Never counted") under it.
- **History**, newest first, one line per movement: day · change · source · note. For example "4. 11. · −25 · FV 2026-0042 · Acme GmbH", "2. 11. · −2 · Taken out · sample", "1. 11. · +50 · Received · order 118", "28. 10. · Counted 40 (app had 46)". ↩ or a double-click on a line with a document shows that document in Documents. The history is where "who bought this" lives for one item; the client page's Items tab shows the same movements per client (below).
- History lines can't be edited or deleted. Undo takes back the last change, and a count fixes anything older (rule 1).

**Count…** (the stock-take; the one-step correction): ↩ on the row, the detail's Count…, Stock ▸ Count “Bolt M8”… or the context menu. A small sheet, sized by `formSheetSized` like the app's other form sheets (`presentationSizing(.form)` on macOS 15 [S90], a width range on macOS 14, as built):
- Title "Count", with the item's name as the subtitle.
- "On hand: [ 40 ] ks", focused, prefilled with the app's figure and selected, so typing replaces it. 0 or more.
- "Counted on: [today]", with the fast date entry of §2c. A future day isn't accepted.
- Cancel (⎋) / **Save Count** (↩). The history line keeps what the app had, so a count explains itself, and Edit ▸ Undo Count takes it back.

**Receive…** (goods arrived): the detail's Receive…, Stock ▸ Receive “Bolt M8”… or the context menu. The same sheet shape: "Received: [ ] ks" (focused and empty; more than 0) · "On: [today]" · "Note: [ ]", for example the order number. Cancel (⎋) / **Receive** (↩). Undoable.

**Take Out…** (goods left without an invoice: a sample, scrap): Stock ▸ Take Out “Bolt M8”… or the context menu. The same sheet shape: "Taken out: [ ] ks" · "On: [today]" · "Note: [ ]". Cancel (⎋) / **Take Out** (↩). Undoable.

The quantity messages sit at the field: "Enter a quantity greater than zero." (Receive…, Take Out…) and "Enter a quantity of 0 or more." (Count…). Each sheet closes on ↩, and the new figure and history line show the result in place, so there is no result line.

**New Stock Item…** (File ▸ New Stock Item…, the toolbar's New Stock Item, the empty state, or "Add “‹typed text›” to Stock…" in a draft's Description suggestions). Sized by `formSheetSized`, titled "New Stock Item".
- Name (required: "A name is required.", the built message) · Unit (the line's Unit field, §2c; "ks" by default) · On hand now (optional; when filled, it records a count for today) · Reorder at (optional).
- A name that a listed item already has (ignoring case) shows "A stock item named “Bolt M8” already exists." and keeps Add Item disabled, because the editor's suggestions match by name (RECOMMENDATION).
- Cancel (⎋) / **Add Item** (↩). Add Item creates the item, switches to Stock and selects it. Opened from a draft, the sheet is prefilled with the typed name and the line's unit; Add Item links the line to the new item and returns focus to that line's Qty, and the draft stays in place.

**Delete and archive.**
- An item with no movements is deleted with Edit ▸ Delete (⌫) or the context menu's Delete, undoably. Lines in open drafts that link to it lose the link; Undo restores both.
- An item with movements is archived with Stock ▸ Archive “Bolt M8” or the context menu's Archive Item, undoably. It leaves the list and the editor suggestions. Its movements stay, with their documents, so the client page's Items tab still shows it. A line in an open draft keeps its link, and that draft's Issue still records the movement.
- There is no list of archived items; Undo brings an item back.

**In the draft editor** (§2c "Stock in the lines" owns the line behaviour):
- **No new column.** The Description suggestions list the stock items whose name matches first, each with its on-hand figure as secondary text ("120 ks in stock"). They appear on Invoice, Advance invoice and Final invoice drafts, never on a tax document for a received payment (rule 5).
- **Picking a stock item** fills Description with the item's name and Unit with its unit, and links the line. Unit price comes from the last issued line for that item in the draft's currency; with none, it stays empty. An item has no stored price, so there is no price to maintain. Editing the description afterwards keeps the link: the description is document text, and "Bolt M8, zinc" is still the item.
- **A linked line shows `shippingbox`** at the trailing edge of its Description cell, with the tooltip and VoiceOver label "Takes from stock: Bolt M8 (120 ks on hand)". On an advance, which takes nothing (rule 5), it reads "Bolt M8 (120 ks on hand) leaves stock with the final invoice".
- **Unlink** with the line's context menu or Document ▸ Don't Take from Stock, undoably. Picking the suggestion again links the line again.
- **No match:** the suggestions end with "Add “‹typed text›” to Stock…", which opens New Stock Item… (above), as "New Client “…”…" does in the client field (§2e).
- Duplicate as Draft copies the links. Change Type keeps them; they take goods out once the type is Invoice or Final invoice.

**Review and Issue** (§2c):
- The Issue sheet has one conditional row, shown only when the document takes goods out (linked lines on an Invoice or a Final invoice): "Takes from stock: Bolt M8 −25 (95 left) · Nut M8 −50 (−10 left)". Each item appears once, with its lines' quantities added up, and the figure in brackets is the on hand after Issue. Information only, never a blocker (rule 2).
- At Issue, each linked line becomes an "out" movement of the line's quantity, dated the document's DUZP (the day the goods were supplied), with the document as its source. A line whose unit differs from the item's is taken as typed (no unit conversion).

**On the client page (§2e): the CRM view.** The **Items** tab comes third, after Documents · Activity, once Stock ships and a stock item exists (Payments returns in v0.2). Its columns: Item · Bought This Year · Bought in All · Last Bought (day and document) · Last Price (in the document currency). It is built from the "out" movements of that client's issued documents, so it needs no extra input. A double-click shows the item in Stock. Its menu path is View ▸ Client Tab ▸ Items, listed once Stock ships and disabled while no stock item exists (§1.4).

**For the accountant (§2h).** The Stock list CSV joins the fixed export bundle only once the accountant says it helps and the app has stock items (ACCT). It then has one row per item: its on hand on the month's last day, the day it was last counted, and the month's in and out quantities. Quantities only: the app holds no purchase prices. **ACCT:** whether this list helps the accountant (for example at the year-end count), whether they need values, and the column names.

**Menus and keys** (every command is in the menu bar, §0.1; the tables are in §1.4 and §3):
- File ▸ **New Stock Item…**, with the other New items. No shortcut.
- A top-level **Stock** menu after Document, the app's second menu of its own: Count “Bolt M8”… · Receive “Bolt M8”… · Take Out “Bolt M8”… | Archive “Bolt M8”. With no item selected they read Count… · Receive… · Take Out… · Archive Item, disabled, never with an empty name. Archive is enabled only for an item with movements. None has a shortcut.
- Edit ▸ Delete (⌫) for an item with no movements, undoable.
- Document ▸ Don't Take from Stock, with the cursor in a linked line.
- View ▸ Stock ⌘5, and View ▸ Client Tab ▸ Items.
- In the list: type-select, ↩ Count… and ⌫ Delete; no letter actions (§3.2).

**States.**
- *Empty:* "No stock items yet" · "Add the things you keep on the shelf to see what's running low." · a prominent **New Stock Item…**. It names no shortcut.
- *Never counted:* Counted reads "Never", and on hand is the sum of the movements, from 0.
- *Below zero:* "−5 ks" in `.secondary`, with no warning (rule 2). A count fixes it.

**Edge cases.**
- **A DUZP on or before the item's latest count:** the "out" movement keeps its day, so on hand doesn't change, because the count already saw the goods gone. The Issue sheet's row says so: "Bolt M8 −25 (40 left, counted after the DUZP)".

**Budgets** (§4 counting rules: a chord or a typed character is 1 K):
- Recount one item: ⌘5 · "bol" (type-select) · ↩ (Count…) · "40" · ↩ = **8 K**.
- Goods arrived: ⌘5 · "bol" · Receive… (the detail's toolbar button, 1 C) · "50" · ↩ = **7 K + 1 C**; through the Stock menu or the context menu, **7 K + 2 C**.
- Invoice a stock item: the same as §4 task 2 (pick the suggestion with ⇥). The stock step costs no extra key.
- If ⌘5 leaves focus in the sidebar (the §1.2 device check), the first two tasks gain one ⇥.

---

## 3. Keyboard shortcut map

### 3.1 Complete table

**This is the one authoritative keyboard map for the app.** design-system §8.11a only points here.

Each entry was checked against:
- **A:** Apple's HIG table of standard macOS shortcuts [S17]
- **B:** Apple Support "Mac keyboard shortcuts" (published 14 Sep 2026) [S8]
- **C:** system-reserved keys (Control-F-keys, Spotlight, screenshots and the others listed in research §8)

**Build status** (main 18679ea). Goes from main: ⌥⌘N on New Client… (Commands.swift:90), View ▸ Show/Hide Inspector with ⌥⌘I (Commands.swift:142), and ⌘5 and ⌘6 on the Exchange rates and Exports & Backup sections (Navigation.swift:66–67). To build: ⌘D in client context, ↩ in the lists through `onKeyPress(.return)`, and type-select (§3.2).

| Keys | Command | Scope | A: HIG standard | B: Apple Support | Verdict |
|---|---|---|---|---|---|
| ⌘, | Settings… | global | Open settings | — | ✅ standard |
| ⌘H / ⌥⌘H / ⌘Q | Hide / Hide Others / Quit | global | standard | — | ✅ standard |
| ⌘N | New Invoice (prefills the client in client context) | global | "Open a new document" | — | ✅ standard meaning |
| ⇧⌘N | New Advance Invoice (same rule) | global | not listed | Finder: new folder (Finder only) | ✅ OK. Shift as a secondary modifier "that complements a related shortcut" [S17]. DDPPs and final invoices come from the chain, not from a shortcut. |
| — | Add Note to “‹Client›”… | client context | — | — | No shortcut on purpose: the HIG warns against "adding a modifier to an existing shortcut for an unrelated command" [S17]. File menu and the Activity tab's composer (§2e). |
| ⌘D | Duplicate ‹number› as Draft (client context: the client's last invoice) | document selected, or client context | not listed. ⇧⌘S = "Duplicate the active document" | Finder: "Duplicate the selected files"; in Open/Save dialogs, Desktop | ✅ Matches Finder's meaning. Inside Open/Save panels ⌘D selects the Desktop [S8]; that the panel takes it before our menu item does is UNVERIFIED, so test it. ⇧⌘S stays unbound rather than reused. |
| ⌘↩ | Issue… | draft focused | not listed | not listed | ⚠ No conflict found. **Test** that text fields don't swallow it (UNVERIFIED). |
| ⌘R | Record Payment… (reads Record Refund… on an overpaid document) | issued document selected | not listed | Finder: show original; "in some apps … refresh or reload" | ✅ The app has nothing to reload |
| ⌘L | Add Line Item | editor | not listed | not listed (⌥⌘L is Finder Downloads) | ✅ |
| — | Delete Line · Move Line Up / Down | editor | — | ⌘⌫ = "Move the selected item to the Trash" [S8] | **No shortcut in v0.1.** Document menu and the row's context menu; drag on 27. A menu key equivalent like ⌘⌫ would fire even while a cell's text field is being edited, and what ⌘⌫ does inside a text field is UNVERIFIED (test it). |
| — | Count… · Receive… · Take Out… · Archive Item (when Stock ships) | stock item selected | — | — | No shortcuts (§1.4). ↩ on the selected Stock row opens Count… (§3.2). |
| — | Repair Mode… / End Repair Mode (v0.1.x) | global | — | — | **No shortcut** on purpose (RECOMMENDATION): it unlocks every record, so no stray chord should start it. File menu only (§2m). |
| ⌘K | Later (v0.2 or after): Command Palette… (§2k). Unbound and reserved in v0.1. | global | not listed | Finder: Connect to Server; text editing: "Add a web link" | ✅ when it ships: the app has no rich-text fields. Revisit if any are added. |
| ⌘P | Print… | document selected | Print | — | ✅ standard |
| ⌘W / ⌥⌘W | Close / Close All | window | standard | — | ✅ |
| ⌘M / ⌥⌘M | Minimize / Minimize All | window | standard | — | ✅ |
| ⌘Z / ⇧⌘Z | Undo / Redo | global | standard | — | ✅ |
| ⌘X ⌘C ⌘V ⌥⇧⌘V ⌘A | Cut / Copy / Paste / Paste and Match Style / Select All | global | standard | — | ✅ |
| ⇧⌘A | Deselect All | lists | standard | — | ✅ Reserved; "Accept Exact Matches" (v0.2) deliberately does **not** use it |
| ⌫ (⌦) | Delete (a draft, a client note, a manual payment that is not locked; a stock item with no movements, when Stock ships) | focused list | standard Delete item | ⌘⌫ = Move to Trash in Finder [S8] | ✅ Through `onDeleteCommand` [S68]. ⌘⌫ is left unbound. Not for line items (no row-focus state in a grid of text fields). |
| ⌘F / ⌥⌘F | Find… (system) or Search… / Jump to Search Field (§1.4) | global | "Open a Find window" / "Jump to the search field control" | — | ✅ The closest equivalent |
| ⌘1…⌘4 | Sections: Overview, Documents, Clients, Payments (⌘5 Stock when it ships) | main window | not listed | Finder: view modes ⌘1–⌘4 (Finder only) | ⚠ OK. **Test on the Czech layout**, where the number row isn't digits unshifted. `keyboardShortcut(…localization: .automatic)` may remap it [S65] (UNVERIFIED). |
| (system) | Show/Hide Sidebar | window | — | — | ⚠ The `SidebarCommands` default shortcut is UNVERIFIED |
| ⌥⌘T | Show/Hide Toolbar | window | standard: "Show or hide a toolbar" [S17] | — | ✅ as a standard. That `ToolbarCommands` generates exactly ⌥⌘T is not stated on its docs page: UNVERIFIED, check the generated menu. |
| ⌃⌘F | Enter/Exit Full Screen | window | standard (system) | — | ✅ |
| ⌘+ (⇧⌘=) / ⌘− | Bigger / Smaller Text | global | "Increase / Decrease the size of the selection" | — | ✅ reasonable reuse; ⚠ test the Czech layout: "+" sits unshifted on the 1 key there, so ⌘+ and ⌘1 may collide (UNVERIFIED; no Apple page found). Record the result. |
| ⌘0 | Actual Size | global | not listed | not listed | ⚠ UNVERIFIED as a convention; harmless |
| ⌘? | Opens the Help menu (system); FA Help only while it is not replaced (§1.4) | global | "Open the app's Help menu" | — | ✅ standard; ⚠ on the Czech layout "?" needs a test |
| ↩ / ⎋ / ⌘. | Default button / Cancel / Cancel | dialogs | standard | — | ✅ |

**Never bound** (left to the system or reserved by Apple's tables):
- ⌘S, ⇧⌘S, ⌘O, ⇧⌘P (Page Setup), ⌘E ("Use the selection for a find operation"), ⌘G and ⇧⌘G, ⌘J ("Scroll to a selection"; implement the standard behaviour in lists), ⌘T, ⌘B, ⌘I, ⌘U, ⌘[ and ⌘] (align), ⌘; and ⌘:.
- ⌥⌘I, reserved for its HIG meaning "Display an inspector window" [S17]. v0.1 has no inspector (§1.2). `InspectorCommands` is never used either: its shortcut is ⌃⌘I [S62].
- Every ⌃ combination, Control-F1…F7, ⌘Space variants, ⌘Tab, ⌥⌘Esc, ⌥⌘D, ⌥⌘8, ⌃⌘Space, ⌃Space and ⌃⌥Space (input sources) [S17].
- ⇧⌘Q and ⌥⇧⌘Q (Log Out) and ⌘\` / ⇧⌘\` (switch windows of the front app) [S17][S8].
- ⇧⌘3, ⇧⌘4 and ⇧⌘5 (screenshots and screen recording) [S8], and ⇧⌘6 ("In macOS 27 Golden Gate or later with Siri AI (Beta) turned on, ask Siri about the selected area") [S8].
- **The app defines no custom Control shortcuts.** That follows the HIG's "avoid Control" [S17].

**Unassigned in v0.1** (free, not reserved, so a later section or command can take them):
- ⌘5 until Stock ships (then Stock, §1.2), and ⌘6.
- ⌥⌘N: New Client… has no shortcut (§1.4).
- ⇧⌘E: Export for Accountant… has no shortcut (§1.4, §2h).
- ⌘Y: v0.1 has no Quick Look. Finder uses ⌘Y for Quick Look [S8].

**Czech keyboard (QWERTZ) note.** All primary actions use **letters** with ⌘ or ⇧⌘, or ↩. Digit and punctuation shortcuts (⌘1…⌘5, ⌘+, ⌘−, ⌘?) are secondary conveniences, and each has a pointer alternative (the sidebar row or the menu item). HIG: avoid extra modifiers on characters that aren't on every keyboard [S17]. Things notes that shortcuts adapt to keyboard layouts from macOS 12 on [S128]. Test every shortcut on Sasa's actual layout.

### 3.2 Single-key actions inside a focused list

**Research basis.** Single keys act only while a list or page has focus, never inside text fields:
- iÚčto: E edit, K duplicate, T print, ← → previous/next document; "not in text fields" [S116]
- Fakturoid: shortcuts "mimo textová pole" [S102]
- Raycast: ↩ runs the first action [S131]

Letter actions such as iÚčto's and Linear's (X, J and K [S129]) are left out of v0.1: ⌘ chords do those jobs, and in the lists that type-select, letters select by name. SwiftUI's `onKeyPress` only fires while its view has focus [S67].

**Rules.**
1. A single key acts only while the list has keyboard focus. As soon as a text field or search field has focus, the keys type.
2. **No letter actions in v0.1.** With a document row selected, ⌘D duplicates it as a draft and ⌘R records a payment. In the lists that use type-select (Clients, the client picker and, once it ships, Stock), typing always selects by name.
3. Every single-key action also has a menu or pointer path: a menu item, the row's button, a double-click, the context menu or Edit ▸ Delete. Touch users and Full Keyboard Access users still reach everything [S53][S16].
4. **Check type-select first.** v0.1 sends no letters to `onKeyPress`, so the spike checks only whether type-select works in a SwiftUI `Table` (Clients, Stock) on macOS 14 and 27.2. `allowsTypeSelect` is AppKit's, and it defaults to true [S86]; whether SwiftUI's `Table` is `NSTableView`-backed and type-selects by itself is UNVERIFIED (§2e). If it doesn't, implement it with `onKeyPress(characters:)` [S67] (§2e). The v0.2 triage letters get the same check: if type-select takes N or S, the letters go and Bank ▸ Not an Invoice ▸ and Bank ▸ Skip stay.

| List | ↩ | ⌫ | Other keys |
|---|---|---|---|
| Documents | Open: a draft moves focus into its editor, an issued document into the issued view (a double-click does the same, §2b) | Delete the selected drafts (undoable) | ⎋ clears the search, then the selection |
| Overview queue | Run the row's action: Record Payment…, Create Tax Document for Payment, Export Again… or Back Up Now (§2a) | — | — |
| Payments | Focus the document in the detail column | Delete a manual payment that is not locked (§2f) | — |
| Clients | Open the client page | — | Letters type-select by name |
| Stock (when it ships) | Count… | Delete an item with no movements (undoable) | Letters type-select by name |
| Bank triage (v0.2) | Accept | — | N Not an invoice · S Skip · R (PDF fallback: record on the selected document) · Space Quick Look of the candidate PDF (left to the Bank area, §2f) |

↑↓, ⇧↑↓ and ⌘A keep their system behaviour in every list.

Line items have no single-key actions: the grid is made of text fields, so every key types. Delete Line and Move Line are in the Document menu and the row's context menu (§2c).

---

## 4. Click and keystroke budgets: top 8 tasks

Counting rules:
- A chord counts as 1 keystroke (K), and each typed character counts as 1.
- C means a pointer click.
- "Other tool" means a typical web invoicing tool modelled on the flows Fakturoid and iDoklad document [S101][S104][S108][S113][S114]. **Those counts are ESTIMATES, not timed.** They leave out login and page loads.
- "This app" counts assume a client named "Acme GmbH" (typed as "acm"), the invoice FV 2026-0042 and the advance ZF 2026-0003. A search path assumes the typed number's document is the first result, and a queue path that the wanted row is the first one.
- The counts are for macOS 27.2, which Sasa runs. On macOS 14, ⌘F may switch to Documents without focusing the field, so a search path can cost 1 C more (§1.4).
- There is no command palette in v0.1 (⌘K is reserved, §2k). The paths use the menus, the section shortcuts and each section's search (⌘F).
- A section shortcut puts keyboard focus in that section's list (§1.2), and type-select in the Clients table is UNVERIFIED (§2e). If focus stays in the sidebar, a path that types or uses the arrows right after ⌘1 or ⌘3 gains one ⇥.

| # | Task (frequency) | Other tool: path (ESTIMATE) | Other: count | This app: path | This app: count |
|---|---|---|---|---|---|
| 1 | Repeat last month's invoice with new hours (several per month) | Invoices → search client → open last → "… Více" → Duplicate (about 2 clicks [S101]) → click qty and type → edit the period text by hand → create → download PDF | ~9 C + ~18 K | ⌘3 · acm · ⌘D · 36,5 · ⌘↩ · Space (tick the period-text check) · ↩ (§2c script). No ⌘W: the draft lives in the main window. **If the rate for the rate day is missing** (the rate day is the DUZP; for § 64 goods the § 22 odst. 1 day; here it is the month-end DUZP, so this is common early in the month): + "24,315" ↩ in the Issue sheet's inline rate form (+7 K). Later (v0.2, with the bank import's file drop): + 1 drag of a ČNB file onto the sheet. | **12 K, 0 C** (19 K with the rate step) |
| 2 | New invoice for an existing client, 2 lines from history | + New → client: type and pick → line 1: type and pick suggestion → qty → add row → line 2: type and pick → qty → create → PDF | ~9 C + ~13 K | ⌘N · acm · ↩ · Konz · ⇥ · 8 · ↩ (new row) · Ces · ⇥ · 1 · ⌘↩ · ↩ (the empty trailing line is dropped automatically) | **19 K, 0 C** |
| 3 | Morning check: what's overdue or unpaid (daily) | Open Overview or the list → Overdue tab | ~2 C | The app reopens where it was [S27] · ⌘1 | **1 K** (0 if already on Overview) |
| 4 | Record a full payment on an invoice (several per week) | Search (1 C + ~6 K) → open → *Uhradit* or paid dialog (~2 C) | ~3 C + ~6 K | From the Overview queue: ⌘1 · ↓ · ⌘R · ↩; ↩ on the row can stand in for ⌘R, because it opens Record Payment…. From search, on Overview or in Documents: ⌘F · 0042 · ↩ · ⌘R · ↩. On Overview, ⌘F switches to Documents and focuses its search (§2a, §2b). | **4 K** (queue) / **8 K** (search) |
| 5 | Advance paid → tax document issued (per advance) | Open advance → mark paid (~3 C) → "…" → create tax doc (~2 C) → save (1 C) | ~6 C | Overdue advance, from the queue: ⌘1 · ↓ · ⌘R · ↩ (payment) · ↩ (Create Tax Document, the success step's default) · ⌘↩ · ↩ (the DDPP is issued); ↩ on the row can stand in for ⌘R. Before its payment is recorded, the queue lists an advance only while it is overdue (§2a, §2d). Otherwise ⌘F · 0003 · ↩ replaces ⌘1 · ↓, or two clicks do: Documents ▸ Open advances, then the advance (§2b). **EU goods (§ 64):** the payment gets no tax document (goods decisions (a); ADR 0012, built in PR 22). The success step's ↩ is Create Final Invoice, and the final invoice draft opens with its "Paid in advance" row (§2d). Its ⌘↩ · ↩ may come later, when the goods ship. The counts are the same; from search, the draft is reached in 9 K. | **7 K** (queue) / **11 K** (search) / **2 C + 5 K** (Open advances); +7 K when the new document's rate is missing (task 1) |
| 6 | Find a document and attach its PDF to an email (several per week) | Search (1 C + 4 K) → open → download PDF → Mail: attach from Downloads (~3 C) | ~5 C + 4 K | ⌘F · 0042 · ↩ (to the first result, §2b) · drag the row to Mail. From Clients, Payments or Stock, ⌘2 comes first, because ⌘F there focuses that section's own search. The drag carries the PDF file, like Copy (§1.4 Edit; to build); whether Mail accepts the dropped file is UNVERIFIED. | **6 K + 1 drag** (7 K + 1 drag from Clients, Payments or Stock) |
| 7 | Add a CRM note after a call (weekly) | Contacts → search → open → edit note → save | ~5 C + ~4 K + text | ⌘3 · acm · File ▸ Add Note to “Acme GmbH”… (2 C; it shows the client's Activity tab with "Add a note…" focused, §2e; the tab is to build) · ‹text› · ↩ (saves the note) | **5 K + 2 C + text** |
| 8 | Monthly close: CSV for the accountant + backup (monthly) | Export menu → choose month → export → download (backup is not applicable on the web) | ~5 C | File ▸ Export for Accountant… (2 C; disabled until the export step is built, as on main) · ↩ ("Export October 2026…"; the sheet opens on the previous month) · ↩ (save panel; the backup runs first, §2h) | **2 C + 2 K** |

**Stock** (when it ships, §2n): recounting one item costs 8 K, and goods arrived 7 K + 1 C.

**Bonus (v0.2): triage a statement of 30 lines** (20 exact, 8 suggested, 2 fees), from an ABO or XML statement.
- This app: 1 C on "Accept Exact Matches (20)" + 8 × ↩ + 2 × (N + category key) = **1 C + 12 K**. If the command palette ships with v0.2 (§2k), ⌘K · "acce" · ↩ (6 K) replaces the click: 18 K with no click.
- Xero-style: one OK per line, **30 C** [S120][S121]. Xero's "Bulk OK" idea has been "in development" since 17 Nov 2025 (status checked 2026-11-05) [S120], so this may change once it ships.
- With a PDF-only statement there is no triage: the "match manually" fallback (§2f) costs about ⌘F · VS · ↩ · ⌘R · date · ↩ per line.

**Acceptance test.** The invoicing research set a target of at most 8 keystrokes, no mouse and under 20 s for a repeat invoice. Task 1 needs 8 command keystrokes (⌘3, the three letters "acm", ⌘D, ⌘↩, Space and ↩; Space is the deliberate tick on changed period text), plus the characters of the new data (here 4, so 12 in total). That meets the target when it counts command keys. The review step should keep the target at **8 command keys + data**, plus the rate step on the days the rate for the rate day is still missing.

---

## 5. UI labels per screen (English)

- **The UI is English only** (How to read this), so this table has no Czech UI column. Czech stays only where the text prints on a document or is a legal string; those rows say **document text** and give the Czech.
- Standard system items (Undo, Copy, Close, Minimize, Print and the like) come from macOS. They are not listed here.
- These are **UI labels**. PDF wording belongs to the PDF spec, and anything legal there is ACCT, except the brief's own terms. Legal and tax strings, here or on the PDF, come from the design-system §9 legal-strings table; every Czech term below marked ACCT waits for the accountant.
- **This is the only label table.** design-system.md uses these labels (sidebar, short type names, states).
- Status badges use sentence case (design-system §9). Counts use one plural key, and a line that joins a number with words uses one interpolated key (design-system §9).

**Sidebar and global**

| Label | Notes |
|---|---|
| Overview | |
| Documents | One selectable row that shows all documents; no "All" row and no "Documents" header (§1.2) |
| Drafts | |
| Unpaid | Its badge counts overdue documents; accessibility value and tooltip "N overdue" (§1.2) |
| Open advances | |
| All Documents | View ▸ Filter ▸ (§1.4) |
| Clients | |
| Payments | v0.2 restores "Payments & Bank" with one row per bank account and Unmatched (§2f) |
| Stock | When Stock ships (§2n); accessibility value "3 running low" |
| Unpaid · 7 · 3 overdue | Documents subtitle on Unpaid; one interpolated key (§1.2) |
| Select a document / Select a client / Select an item | Title-only detail placeholders |
| Search documents / Search clients / Search payments / Search stock | One prompt per section (§1.4) |

**Document types and states**

| Label | Notes |
|---|---|
| Invoice – tax document | **document text:** "Faktura – daňový doklad" (PDF title; brief) |
| Advance invoice | **document text:** "Zálohová faktura" (PDF title; brief) |
| Tax document for received payment | **document text:** "Daňový doklad k přijaté platbě" (PDF title; brief) |
| Final invoice | **document text:** the PDF title is "Faktura – daňový doklad (vyúčtování záloh)" (InvoicingCore `DocumentKind.title`; the parenthetical is ACCT; §2d) |
| Issue sheet Type row and issued view header: the English name plus the Czech title, e.g. "Advance invoice (Zálohová faktura)" | The Czech part is document text (design-system §9) |
| Short type names (Type column): Invoice · Advance · Tax doc (payment) · Final | Text only, with the long title as tooltip |
| Invoice · Draft · Saved / Advance invoice · Draft · Saved / Tax document for payment · Draft · Saved | Editor window subtitle (§2c) |
| Draft | |
| Issued | |
| Partly paid | |
| Paid | Also a DDPP and a final invoice settled by advances (detail "by advances"), and a paid EU-goods advance (detail: the payment date) (design-system §4.3) |
| Overpaid | |
| Overdue · +12 days · 1 000,00 € left | One detail format in both spec files |
| Awaiting payment | |
| Partly paid – tax document missing | |
| Paid – tax document missing | |
| Tax document issued | |
| Settled in final invoice (number in the detail) | cs wording ACCT, not shown in the English UI (design-system §9) |
| Closed unpaid | ACCT (wording and accounting effect, §0 rule 1, §2d) |
| Marked for credit note | ACCT (wording and accounting effect, §0 rule 1, §2d) |
| Close Advance as Unpaid… / Reopen Advance | ACCT (wording and accounting effect, §0 rule 1, §2d) |
| Mark for Credit Note… / Remove Credit Note Mark | ACCT (wording and accounting effect, §0 rule 1, §2d) |
| Locked | |
| Not a tax document (the advance's legal line in the app) | The brief's Czech short form "Není daňovým dokladem" isn't shown in the English UI |
| This is not a tax document. A tax document will be issued upon receipt of the payment. (English gloss on a bilingual advance PDF, services or Czech VAT) | **document text:** "Toto není daňový doklad. Daňový doklad bude vystaven po přijetí platby." (InvoicingCore `DocumentClause.notATaxDocument`, ACCT) |
| This is not a tax document. (English gloss on a bilingual goods-only EU advance PDF) | **document text:** "Toto není daňový doklad." (`DocumentClause.notATaxDocumentForGoods`, built in PR 22; no payment tax document follows, §2d; ACCT) |
| Draft markers on a draft PDF | **document text:** "KONCEPT / DRAFT", "Číslo bude přiděleno při vystavení / number assigned at issue", "QR po vystavení / QR after issue" (§2c); the watermark always prints both languages, the number and QR placeholders only their Czech part on a Czech document |

**Overview**

| Label | Notes |
|---|---|
| Needs attention / All caught up | |
| Unpaid / Overdue | Tiles (§2a) |
| 7 documents / 3 documents · oldest 23 days | Plural keys ("1 document", "oldest 1 day") |
| Unpaid advances: 2 · 3 000,00 € · 1 overdue | Its own link to Documents ▸ Open advances (§2a) |
| Issued in November / 9 documents | |
| VAT for November by DUZP (CZK) | Czech VAT only (§2a) |
| EU services, reverse charge: base 80 000 Kč | |
| 23 days overdue | Queue row |
| Payment received, tax document missing | Queue row |
| October 2026 · 1 document changed after export · Export Again… | Queue row (§2h) |
| Last backup 9 days ago · Back Up Now / No backup yet / Backup failed: ‹reason› | Queue row (§2h) |
| Data can't be opened · Try Again · Show Data Folder · Restore from Backup… | Load failure (§2a) |
| No documents yet / Press ⌘N to create your first invoice. | Empty state |
| New Invoice | Toolbar; tooltip "Create a new invoice" |
| Previous month / Next month | |
| Getting started / Three steps before you can issue the first document. | Getting started card (§2j) |
| Company profile / Bank accounts / Continue your number series | Its rows; "Done" / "Not done" |
| Open Settings… / Moving from another Mac? Restore from Backup… / Close | |

**Documents list, editor and issue**

| Label | Notes |
|---|---|
| New Invoice / New Advance Invoice | |
| Duplicate as Draft / Duplicate FV 2026-0041 as Draft | Tooltip "Copy this document into a new draft" |
| Delete 3 Drafts | Plural key |
| 3 selected / Totals per currency | Multiple selection (§2b) |
| Revenue (tax documents) / Open balance / Unpaid advances | Summary row (§2b) |
| Show this client in Clients | Tooltip on the client name |
| Issued 5. 11. 2026 at 19:02 · locked. Corrections via credit note (Phase 2). | Lock line |
| Czech + English · EU goods, exempt | The issued view's language · treatment line |
| Issued as FV 2026-0042 / Received: 1 000,00 € / PDF saved to … / Closed as unpaid: … | Activity sentences |
| Issue… | |
| Issue | |
| Issue invoice FV 2026-0042? | |
| Once issued, the document can't be edited or deleted. | |
| Fix before issuing / Check before issuing | Issue sheet sections (§2c) |
| Checked | One tick per check row |
| Go to Problem / Set to today / Fill in… | |
| 1 problem / N problems | Readiness chip; it shows only while something blocks Issue (design-system §8.3) |
| Differs from Acme's defaults: … | Check row |
| No PDF folder: the PDF stays in the app until you use Save PDF…. Choose a folder in Settings ▸ General. | Issue sheet PDF row, only with no PDF folder |
| Takes from stock: Bolt M8 −25 (95 left) · Nut M8 −50 (−10 left) | Issue sheet row, information only (§2n) |
| Number assigned at issue | |
| Client | |
| Issue date | |
| On issue | An issue date not set by hand (§2c) |
| Period | |
| Date of taxable supply (short: DUZP) | **document text:** "DUZP · Datum uskutečnění zdanitelného plnění" (ACCT) |
| Same as the issue date | DUZP toggle, as built |
| Due: 14 days → Thu 19. 11. 2026 | Days field with the resulting date as text |
| Currency: EUR / CZK / USD | |
| Document language: Czech / Czech + English | Document ▸ Document Language ▸; InvoicingCore `DocumentLanguage.czech` / `.english` |
| VAT treatment | |
| EU goods, exempt (§ 64) / EU services, reverse charge │ Czech VAT (rate per line) / Outside EU, services / Other exemption | Editor pop-up, sentence case, divider after the EU pair (ADR 0011, built in PR 21). The printed texts are **document text** in design-system §9 (ACCT) |
| EU Goods, Exempt (§ 64) / EU Services, Reverse Charge │ Czech VAT / Outside EU, Services / Other Exemption | Document ▸ VAT Treatment ▸, title case |
| EU goods, exempt / EU services, reverse charge / Czech VAT / Outside EU, services / Other exemption | Short forms: Issue sheet client summary, client suggestion line, language · treatment line |
| Reverse-charge clause on the PDF | **document text:** "daň odvede zákazník" (brief) |
| § 64 exemption reference on the PDF | **document text:** the § 29 odst. 2 písm. a) reference, design-system §9 (ACCT) |
| EUR rate for 30. 10. 2026 missing | Inline rate form (§2c) |
| Save Rate · Import ČNB Rates… · Change… | Save Rate as built |
| Enter Rate… | Document ▸ Enter Rate… focuses the form |
| Open ČNB Rates Page | Optional link (RECOMMENDATION, Q7, §2g) |
| The rate date cannot be after ‹day›, the day this document needs the rate for. | Blocker (PR 21) |
| The exchange rate is from {detail}, more than a week before the day the document needs the rate for; check that the rate table is complete. | Check row (PR 21) |
| Bank account | Plain text; a pop-up only when two or more accounts fit (§2c) |
| The document has no bank details. | Blocker for payable kinds |
| Variable symbol | |
| ČNB rate · rate date · source | |
| Typed / ČNB file | Rate sources |
| Description / Qty / Unit / Unit price / Discount / VAT rate | VAT rate only under Czech VAT |
| Base / VAT / Total / Amount due | Amount due only when something is deducted |
| Total 3 142,50 € · Exempt (§ 64) | Totals bar under a no-VAT treatment (§2c) |
| VAT in CZK | |
| Advances deducted | **document text:** "Odečet záloh" (caption), one "Odečet zálohy – daňový doklad č. …, platba ze dne …, sazba DPH … %" line per tax document and rate (`PDFStrings.deductionLine`) and the clause `DocumentClause.advancesDeducted` on the final invoice (ACCT, design-system §9) |
| Paid in advance | EU-goods final invoice (§2d). **document text:** heading "Uhrazené zálohy / Advances paid", row "Záloha ZF 2026-0003 uhrazena 12. 11. 2026 / Advance ZF 2026-0003 paid on 12. 11. 2026" (ACCT) |
| (DDPP reference line) | **document text:** InvoicingCore prints `DocumentClause.paymentReceived`: "Daňový doklad k platbě přijaté dne … na základě zálohové faktury č. …." (ACCT; design-system §9) |
| Add Line Item / Add Discount | Add Line Item inserts below the current line |
| Notes on PDF: Note / Order reference | Disclosure group under the lines (§2c) |
| Save PDF… | |
| Show PDF in Finder | |
| PDF saved | |
| Corrections via credit note (Phase 2) | **document text** (Phase 2): "Dobropis / opravný daňový doklad" (ACCT) |
| Show Related Documents ▸ Advance ZF … / Tax Document DD … / Final Invoice FV … / Final Invoice (Draft) | Document menu (§1.4, §2d) |
| Create Tax Document / Create Final Invoice / Later | The chain line's next-step button and the Record Payment success step (§2d) |
| This advance is already in final invoice FV … | Transient result line only (§2d) |
| 120 ks in stock / Takes from stock: Bolt M8 (120 ks on hand) / Add “‹typed text›” to Stock… / Don't Take from Stock | Editor stock links (§2n) |
| Bolt M8 (120 ks on hand) leaves stock with the final invoice | Tooltip on a linked advance line (§2n) |

**Clients**

| Label | Notes |
|---|---|
| New Client… / New Client “…”… | |
| Edit Client “Acme GmbH”… / Edit Client… | File menu (§1.4) |
| Add Note to “Acme GmbH”… / Add Note… / Add a note… | |
| Search clients | |
| Open Balance / Last Document | Column headings, title case (the built ones read "Open balance" and "Last document") |
| Open balance / Invoiced this year | Client page tiles (§2e) |
| 1 200,00 € overdue | |
| Documents / Activity / Items | Client page tabs; Items once Stock ships and a stock item exists (§2e) |
| Item / Bought This Year / Bought in All / Last Bought / Last Price | Items tab columns (§2e, §2n) |
| Client type | Pop-up (§2e) |
| EU business, goods / EU business, services │ Czech VAT payer / Czech business, not a VAT payer / EU consumer / Business outside the EU, services / Consumer outside the EU | Its seven values (ADR 0011, built in PR 21) |
| Usual client type for this country and VAT ID: Czech VAT payer | Edit sheet info line (RECOMMENDATION) |
| Company ID (IČO) / VAT ID (DIČ) | |
| Choose… | Country pop-up, empty at first |
| Company ID is not valid (8 digits with a check digit). | |
| Possible duplicate: Acme GmbH – open it? | |
| VAT ID missing / Address missing | Problem lines under the client field |
| Reverse charge needs the client's VAT ID. Add it to issue documents for this client. | Under Client type, EU business, services (ACCT) |
| Reverse charge needs the client's VAT ID. | Short form (ACCT) |
| The § 64 exemption needs the client's VAT ID. Add it to issue documents for this client. | Under Client type, EU business, goods (ACCT) |
| The § 64 exemption needs the client's VAT ID. | Short form (ACCT) |

**Payments**

| Label | Notes |
|---|---|
| Record Payment… / Record Payment | Menu item / sheet title |
| Record Refund… / Record Refund | Menu item / sheet title; tooltip "Record money returned to the client" |
| Record | |
| Payment date / Refund date / Amount / Note | |
| Enter an amount, such as 1 234,50 / Enter an amount greater than zero. | |
| Document will be: Paid / Paid (0,01 € difference rounded off) / Partly paid – 600,00 € left / Overpaid by 50,00 € – kept as client credit | Outcome line (§2f) |
| Payment is the basis of DD 2026-0003 and can't be deleted · Show Document | Lock caption |
| A final invoice settled this payment as paid in advance; it cannot change. | Lock caption and VoiceOver label (PR 22) |
| Final invoice … settled the other side of this credit as paid in advance, so the credit cannot be deleted. | Refusal (PR 22) |
| Final invoice … settled this advance as paid in advance; without this payment the advance's money would no longer match it, so it cannot be deleted. | Refusal (PR 22) |
| Undo Delete Payment / Redo Delete Payment | |
| Apply Credit To… | Later (v0.2) |
| Later (v0.2): Payments & Bank · Import Bank Statement… · Statement · Already recorded / Matched / Suggested / Unmatched / Outgoing · Accept / Accept Exact Matches (N) · Not an invoice / Skip / Unmatch · Fees / Software / Rent / Tax / Owner · CZK difference · Credited to account / Settles on the document | Bank import (§2f). The Czech accounting term "Kurzový rozdíl" is ACCT (design-system §9) |

**Exchange rates**

| Label | Notes |
|---|---|
| Exchange Rates | File menu item and sheet title, no ellipsis (§2g) |
| Latest: EUR 30. 10. 2026 · USD 30. 10. 2026 | Sheet top line ("USD —" when none) |
| Import ČNB Rates… / Close | Sheet buttons |
| No rates yet / Rates you type on a document appear here. | Empty state |
| 214 rates imported / 1 rate imported | Result line, plural key |
| Typed / ČNB file | Rate sources |
| No rate is published for ‹day› (weekend or holiday); the last published rate, for ‹day›, applies / The ČNB published no rate for ‹day›; … | Resolver lines, as built (§2g) |

**Exports and backup**

| Label | Notes |
|---|---|
| Export for Accountant… | File menu; sheet title "Export for Accountant" |
| Not exported yet / Exported on 3. 11. 2026 to ~/…/FA 2026-10 | Sheet status line |
| 1 document changed after export | |
| Export October 2026… / Export October 2026 Again… | |
| October 2026 exported · backup made / October 2026 exported · backup failed: ‹reason› | Result line |
| Back Up Now | No ellipsis: it asks for nothing |
| Backup made at 9:02 | Result line |
| Daily and on quit; the last 30 are kept. Last backup: today 9:02. | Settings ▸ General caption; the second sentence becomes "No backup yet." or "Last backup failed: ‹reason› · last successful 3. 11. 2026" |
| Restore from Backup… | |
| (CSV column) | "Daňový doklad (ano/ne)": CSV text for the accountant; CSV names are ACCT (§2h) |

**Stock (when Stock ships, §2n)**

| Label | Notes |
|---|---|
| Item / On Hand / Reorder At / Counted | Column headings |
| Low | Badge on the On Hand cell (caution, design-system §4.3) |
| Never / Counted 3 weeks ago / Never counted | |
| New Stock Item / New Stock Item… | Toolbar (tooltip "Add a stock item"); File menu and empty state |
| Count… / Receive… | Detail buttons; tooltips "Set the number on hand after counting the shelf" / "Add goods that arrived" |
| Count “Bolt M8”… / Receive “Bolt M8”… / Take Out “Bolt M8”… / Archive “Bolt M8” | Stock menu; with no item selected "Count…" / "Receive…" / "Take Out…" / "Archive Item", disabled |
| Archive Item / Delete | Context menu |
| On hand / Counted on / Save Count | Count sheet |
| Received / On / Note / Receive | Receive sheet |
| Taken out / On / Note / Take Out | Take Out sheet |
| Name / Unit / On hand now / Reorder at / Add Item | New Stock Item sheet |
| A name is required. / A stock item named “Bolt M8” already exists. / Enter a quantity greater than zero. / Enter a quantity of 0 or more. | Inline messages |
| Received / Taken out / Counted 40 (app had 46) | History words |
| No stock items yet / Add the things you keep on the shelf to see what's running low. | Empty state |
| Takes from stock: … (40 left, counted after the DUZP) | Issue sheet variant |

**Repair mode (v0.1.x)**

| Label | Notes |
|---|---|
| Repair Mode… / End Repair Mode | File menu; no shortcut (§1.4, §3.1, §2m) |
| Turn On Repair Mode? | Entry sheet title (§2m) |
| Reason | Required |
| Unlock… | Starts Touch ID or the password |
| Not unlocked | After a cancel or a failure |
| Repair mode is on. Every change to a locked record is logged. · End Repair Mode | Banner (§2m) |
| Repair mode: changes are logged | Lock line on an issued document |
| Repair mode ended after 10 minutes without changes | Banner after the timeout |
| Repair mode ended · N changes logged | Result line, one interpolated key, close button only |
| Unlocked for repair | Open-lock tooltip and VoiceOver label (design-system §8.18) |

**Settings**

| Label | Notes |
|---|---|
| General / Company / Bank Accounts / Numbering | The four panes (§2i) |
| PDF folder / Backup folder / Forget Folder / Choose Folder… | General; Choose Folder… is the fallback only |
| Choose the folder where issued documents are saved as PDF files. | Open-panel prompt |
| Issued documents are saved as 2026/FV 2026-0042 Acme GmbH.pdf. / No folder: the PDF stays in the app until you use Save PDF…. | PDF folder captions |
| Legal name / Registered office / Company ID (IČO) / VAT ID (DIČ) / File number | Company. **document text** (PDF labels): "Obchodní firma" (ACCT) · "IČO" · "DIČ" · "spisová značka" (brief) |
| Enter the file number as section and number, such as C 12345. | |
| Footer text | Company. The text itself is document text that Sasa types; empty by default |
| Account number / IBAN or 123456789/0800 / Currency: Any | Bank Accounts; the second is the placeholder |
| Enter an IBAN or a Czech account number such as 123456789/0800. | |
| Bank account removed / Undo Remove Bank Account | |
| Invoices / Advance Invoices / Tax Documents for Received Payments | Numbering section headers |
| Pattern / Last issued number | Numbering fields |
| Next number: FV 2026-0042 · VS 120260042 – assigned when you issue | Live line; the DD section shows the number only |
| Type the last number you issued in your previous tool. Leave it empty to start at 1. It can't be changed after the first document is issued. | Numbering caption |
| ‹Invoices› and ‹Advance invoices› would give documents the same variable symbol. Change one of the patterns. / ‹series› and ‹series› would issue the same numbers. Change one of the patterns. | Collision messages |
| Save | Numbering only (§2i) |
| Confirm your number series in Settings ▸ Numbering. | Issue sheet blocker until Numbering is confirmed |

**iPhone (Phase 3)**

| Label | Notes |
|---|---|
| Overview / Documents / Clients / Search | |
| Data from Mac · date | |
| Mark Payment Received | |
| Waiting for Mac | |

---

## 6. Open design questions for Sasa (max 8)

Answered questions keep their numbers, because other files refer to them by number.

1. **Which macOS is on your Mac today? Answered.** "27.2, english" and "m1 pro 32gb ram 200gb bandwith 256gb disk - using mainly 8tb cloud / macOS 27.2 (the newest one, im just updating it right now)" (Sasa's answer in the proposal doc, 5 Nov 2026). Decision (build thread): the app keeps targeting macOS 14.0, with `#if compiler(>=6.2)` and `if #available` gates, while CI builds on the `macos-15` runner with Xcode 26.3 (macOS 26 SDK, since PR 20). When to raise the target is the build's call; the design recommends macOS 27.0 for that raise (§0.1). The macOS 27.0 APIs need the macOS 27 SDK, which ships with Xcode 27 (design-system §2), so a raise made on Xcode 26 can reach at most Fallback A (macOS 26.1).
2. **Your current numbering.**
   - What format, and what are the last issued numbers, for invoices, advances and tax documents?
   - Does each series restart every year? **Answered:** yes, with the year in the number (Sasa's answer, 6 Nov 2026: "YES WHY NOT, JUST HAVE THE NEW YEAR IN THE NUMBER"). The restart follows `{YYYY}` in the pattern, with no switch (§2i).
   - Final invoices share the FV series (three fixed series, §2i). A fourth fixed series only if the accountant asks. (ACCT for the rules; we need your format to continue it.)
3. **DUZP on monthly invoices.** The design gives an invoice with a Period (a month) that month's last day as its DUZP, and any other invoice its issue date; you can change it on each draft. Is that how you date them? (ACCT.)
4. **Languages. Partly answered.**
   - App: English only. Sasa answered "en" and commented: "czech is not needed anywhere. its jsut a very little bonus that i might not use. dont bother if not super easy to implement, maybe version 10.9 or omething ahah" (proposal doc, 5 Nov 2026). There is no in-app language switch, and Czech UI is out of scope.
   - Documents: InvoicingCore `DocumentLanguage` settles it. Czech customers get "Czech" (`.czech`, Czech only); foreign customers get "Czech + English" (`.english`, bilingual, Czech first). Each client and each document can change it. Both would print Czech number and date formats ("1 234,50 €", "5. 11. 2026"). This is a RECOMMENDATION, still open for Sasa and the accountant (design-system §9). Still open for the accountant: the English gloss of each legal string (ACCT, design-system §9).
5. **Advances for EU clients. Partly answered.** EU goods (§ 64): an advance needs no "Daňový doklad k přijaté platbě", because § 28 odst. 1 písm. d) ZDPH covers only the supplies under písm. a) and b), not the intra-EU goods of písm. c), and § 20a odst. 2 applies only to a taxable supply (the build's reading, checked by the design thread in the ZDPH text; ACCT; §2d). Still open: advances on EU services (reverse charge) and outside EU. (ACCT.)
6. **PDF filing. Default kept without asking.** One folder chosen in Settings ▸ General, a subfolder per year, and the file name "FV 2026-0042 Acme GmbH.pdf" (ADR 0010, §2i). Tell us if you file PDFs differently.
7. **ČNB rates. Partly answered.** Sasa types the rate by hand: "for start everything that nmeeds to be online i willů do manualy, s ill type current cnb rate for each invoice" (proposal doc, 5 Nov 2026). Typing the rate on the document is the v0.1 path (§2c, §2g). Still open: would a link that opens the ČNB rates page in your own browser be acceptable (the app itself still makes no network call)? §2g sketches it as a RECOMMENDATION. The data layer already reads both the daily and the yearly ČNB file, so the secondary import takes either.
8. **Raiffeisenbank statements.** Are statements as data (ABO, RB XML or Gemini) a paid service in RB internet banking, with PDF free? UNVERIFIED. Is the service active, or worth its price? With ABO or XML, v0.2 can match payments automatically; with PDF only, matching stays manual (§2f). Also: do you record payments as they arrive, or in one go from the monthly statement? That decides whether the "Payments recorded up to" caption under the Overview tiles ships before v0.2 (§2a).

**Asked on cards in the design thread (5 Nov 2026), answered 6 Nov 2026:**
- A new EU client without a VAT ID: "EU business, goods"; Issue waits for the VAT ID (Sasa sells to businesses only for now ("i dont do b2C CURRENTLY", 6 Nov 2026); §2e).
- The yearly restart of the number series: yes (Q2, §2i).

**For the accountant (ACCT), added by the lean pass:** whether the Stock list CSV helps (for example at the year-end count), whether it needs values, and its column names (§2n); the month in which a § 64 document counts in the export (the § 22 odst. 1 day, §2h).

**Project inputs added 5 Nov 2026:** Sasa's GUI rule ("Let's keep it precise and clean. No need to rush. Hopefully the gui won't be bilions of setting and icons and menus but nice intuitive easy to use and fast."), the stock request ("I cannot keep perfect track of everything that leaves and is added to the storage/warehouse. So it will be mostly roughly so I know how much of what for ordering etc."), the design-card answer "CRM, customer records", and "90% goods".

---

## Sources

Numbers 74, 85, 88, 95, 111, 123, 124, 126, 132, 137, 149 and 150 are not used and are not reused. After the lean pass (6 Nov 2026) no section cites S12, S22, S24, S31, S32, S37, S41, S48, S51, S52, S61, S81, S82, S84, S87, S93, S103, S110, S130, S133, S134, S148 or S151; their entries stay so that the numbers stay stable.

Apple platform and support:
- [S1] Adopting Liquid Glass. https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- [S2] UIDesignRequiresCompatibility. https://developer.apple.com/documentation/bundleresources/information-property-list/uidesignrequirescompatibility
- [S3] WWDC26 Platforms State of the Union. https://developer.apple.com/videos/play/wwdc2026/102/
- [S4] macOS 27 release notes. https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes ; Xcode 27.2 release notes: https://developer.apple.com/documentation/xcode-release-notes/xcode-27_2-release-notes
- [S5] macOS 27 Golden Gate compatible computers (WebFetch summary). https://support.apple.com/en-us/127255
- [S6] macOS Tahoe 26 compatible computers (WebFetch summary). https://support.apple.com/en-us/122867
- [S7] MacBook Pro (14-inch, 2021) tech specs, M1 Pro (WebFetch summary). https://support.apple.com/en-us/111902
- [S8] Mac keyboard shortcuts, published 14 Sep 2026 (WebFetch summary, opened for this spec and again in the review pass: Command-Delete, Shift-Command-Q, Command-Grave accent, Shift-Command-5, Shift-Command-6). https://support.apple.com/en-us/102650
- [S9] Change the language your Mac uses (per-app language). https://support.apple.com/guide/mac-help/change-the-system-language-mh26684/mac

Human Interface Guidelines (pattern `https://developer.apple.com/design/human-interface-guidelines/<slug>`):
- [S10] designing-for-macos
- [S11] layout
- [S12] typography
- [S13] color
- [S14] materials
- [S15] dark-mode
- [S16] accessibility
- [S17] keyboards
- [S18] the-menu-bar
- [S19] toolbars
- [S20] sidebars
- [S21] split-views
- [S22] panels
- [S23] lists-and-tables
- [S24] sheets
- [S25] alerts
- [S26] windows
- [S27] launching
- [S28] search-fields
- [S29] settings
- [S30] buttons
- [S31] pull-down-buttons
- [S32] combo-boxes
- [S33] segmented-controls
- [S34] text-fields
- [S35] entering-data
- [S36] drag-and-drop
- [S37] charts
- [S38] loading (and progress-indicators)
- [S39] feedback
- [S40] onboarding
- [S41] offering-help
- [S42] undo-and-redo
- [S43] file-management
- [S44] printing
- [S45] writing
- [S46] menus
- [S47] context-menus
- [S48] image-wells
- [S49] path-controls
- [S50] tab-views
- [S51] scroll-views
- [S52] icons
- [S53] gestures
- [S54] tab-bars
- [S55] widgets
- [S56] labels

SwiftUI, AppKit and Foundation docs (pattern `https://developer.apple.com/documentation/<path>`):
- [S57] swiftui/sidebarcommands (opened for this spec; the page states no default shortcut)
- [S58] swiftui/navigationsplitview
- [S59] swiftui/table ; swiftui/tablecolumn/init(_:value:comparator:)
- [S60] swiftui/tablecolumncustomization
- [S61] swiftui/view/inspector(ispresented:content:)
- [S62] swiftui/inspectorcommands ("keyboard shortcut of Control-Command-I"; opened for this spec)
- [S63] swiftui/view/searchable(text:placement:prompt:) ; swiftui/view/searchable(text:tokens:placement:prompt:token:) ; swiftui/view/searchfocused(_:)
- [S64] swiftui/commandmenu ; swiftui/commandgroupplacement
- [S65] swiftui/view/keyboardshortcut(_:modifiers:localization:)
- [S66] swiftui/view/focusedscenevalue(_:_:)
- [S67] swiftui/view/onkeypress(characters:phases:action:) ; swiftui/view/onkeypress(_:action:)
- [S68] swiftui/view/ondeletecommand(perform:) (opened for this spec)
- [S69] swiftui/view/contextmenu(forselectiontype:menu:primaryaction:)
- [S70] swiftui/textfield/init(_:value:format:prompt:)-3fh51
- [S71] foundation/decimal/formatstyle/currency/init(code:locale:)
- [S72] swiftui/view/dropdestination(for:isenabled:action:)
- [S73] swiftui/view/fileimporter(ispresented:allowedcontenttypes:allowsmultipleselection:oncompletion:)
- [S75] swiftui/windowgroup/init(for:content:) ; swiftui/openwindowaction ; swiftui/window
- [S76] swiftui/settings ; swiftui/settingslink ; swiftui/opensettingsaction
- [S77] swiftui/view/quicklookpreview(_:) (opened for this spec)
- [S78] pdfkit/pdfview
- [S79] swiftui/contentunavailableview
- [S80] swiftui/view/badge(_:)-8adyq
- [S81] charts/barmark (no longer used in v0.1: the VAT chart became a table)
- [S82] swiftui/view/safeareabar(edge:alignment:spacing:content:)
- [S83] swiftui/toolbarcontent/visibilitypriority(_:)
- [S84] swiftui/toolbarspacer
- [S86] appkit/nstableview/allowstypeselect
- [S87] tipkit/tip
- [S89] swiftui/pickerstyle/tabs (macOS 27.0; opened for this spec)
- [S90] swiftui/view/presentationsizing(_:) (macOS 15.0; opened for this spec)
- [S91] swiftui/tab (iOS 18.0 / macOS 15.0) ; swiftui/view/tabbarminimizebehavior(_:) (26.0) (both opened for this spec)
- [S92] appkit/nsworkspace/activatefileviewerselecting(_:) (macOS 10.6; opened for this spec)
- [S93] swiftui/menu/init(_:content:primaryaction:)
- [S94] updates/swiftui ; updates/appkit
- [S96] swiftui/view/reordercontainer(for:isenabled:move:) (macOS 27.0; used with `reorderable()` on the `ForEach`, [S148])
- [S97] foundation/url/bookmarkdata(options:includingresourcevaluesforkeys:relativeto:) (macOS 10.10; opened for this spec)
- [S98] swiftui/labeledcontent
- [S99] swiftui/view/copyable(_:)
- [S100] swiftui/view/navigationsubtitle(_:)

Invoicing and productivity products:
- [S101] https://www.fakturoid.cz/podpora/nastaveni/tipy-ke-zrychleni
- [S102] https://www.fakturoid.cz/podpora/nastaveni/klavesove-zkratky
- [S103] https://www.fakturoid.cz/blog/2026/06/29/navigacni-paleta
- [S104] https://www.fakturoid.cz/podpora/faktury/vytvoreni-faktury
- [S105] https://www.fakturoid.cz/podpora/kontakty/individualni-nastaveni-kontaktu
- [S106] https://www.fakturoid.cz/podpora/faktury/variabilni-symbol
- [S107] https://www.fakturoid.cz/podpora/automatizace/parovani-plateb-s-bankou
- [S108] https://www.fakturoid.cz/podpora/automatizace/nesparovane-platby
- [S109] https://www.fakturoid.cz/podpora/faktury/zalohova-faktura
- [S110] https://www.fakturoid.cz/podpora/faktury/qr-kod-na-fakture
- [S112] https://www.fakturoid.cz/podpora/automatizace/pravidelne-faktury
- [S113] https://www.idoklad.cz/podpora/faktury-vydane
- [S114] https://www.idoklad.cz/podpora/ovladani-aplikace
- [S115] https://www.idoklad.cz/?p=12492
- [S116] https://www.iucto.cz/app/uploads/2026/08/iucto-klavesove-zkratky.pdf
- [S117] https://qr-platba.cz/wp-content/uploads/1645-standard-qr-v1-2-cerven-2021.pdf
- [S118] https://europeanpaymentscouncil.eu/sites/default/files/kb/file/2022-09/EPC069-12%20v3.0%20Quick%20Response%20Code%20-%20Guidelines%20to%20Enable%20the%20Data%20Capture%20for%20the%20Initiation%20of%20an%20SCT_0.pdf
- [S119] https://xero.com/us/accounting-software/reconcile-bank-transactions
- [S120] https://productideas.xero.com/forums/967136-banking-chart-of-accounts/suggestions/44988634-reconciliation-bulk-ok-for-reconciling-bank-tr (status re-checked 2026-11-05 through WebFetch: "In development" since 17 Nov 2025, 248 votes)
- [S121] https://marcandrews.com/xero-bank-reconciliation-tutorial-uk-step-by-step-guide/ (third-party)
- [S122] https://help.1stformations.co.uk/accounting-service/using-xeros-find-and-match-function (third-party)
- [S125] https://quickbooks.intuit.com/learn-support/en-us/help-articles/how-to-duplicate-an-invoice-or-an-estimate/00/261891
- [S127] https://culturedcode.com/things/support/articles/9780167/
- [S128] https://culturedcode.com/things/blog/2021/10/all-things-speed/
- [S129] https://linear.app/docs/select-issues.md
- [S130] https://linear.app/changelog/2021-03-25-keyboard-shortcuts-help
- [S131] https://manual.raycast.com/action-panel
- [S133] https://help.superhuman.com/article/478-superhuman-command
- [S134] https://help.superhuman.com/hc/en-us/articles/47278253460499-Undo
- [S135] https://apps.apple.com/app/invoiceur/id6761061911
- [S136] https://apps.apple.com/cy/app/native-invoice/id1557682334
- [S138] https://www.getharvest.com/blog/2019/03/two-new-changes-to-help-you-automatically-send-monthly-recurring-invoices

Added in the review pass (Apple docs read as DocC JSON on 2026-11-05; pattern `https://developer.apple.com/documentation/<path>`):
- [S139] bundleresources/entitlements/com.apple.security.network.client ; bundleresources/entitlements/com.apple.security.network.server (macOS 10.7)
- [S140] security/accessing-files-from-the-macos-app-sandbox (security-scoped bookmarks with the User Selected File capability; no separate bookmark entitlement named)
- [S141] swiftui/toolbaritemplacement/primaryaction ("In macOS … the location for the primary action is the leading edge of the toolbar") ; swiftui/toolbaritemplacement/automatic
- [S142] swiftui/navigationsplitviewvisibility ("Some platforms don't respect every option. For example, macOS always displays the content column.")
- [S143] swiftui/commandgroup/init(replacing:addition:) (macOS 11.0) ; swiftui/commandgroupplacement/newitem ("By default, this group includes … New")
- [S144] swiftui/windowgroup (titles appear in "The list of new windows that someone can open using the File > New menu"; File > New Window passes a `nil` value)
- [S145] swiftui/view/defaultfocus(_:_:priority:) (macOS 13.0)
- [S146] swiftui/view/presentationplacement(_:) ; swiftui/presentationplacement (macOS 27.0)
- [S147] swiftui/view/keyboardshortcut(_:modifiers:) ("On macOS, the system looks in the key window first, then the main window, and then the command groups"; quoted in the SwiftUI APIs research notes, kept in the design thread)
- [S148] swiftui/dynamicviewcontent/reorderable() (macOS 27.0; "within a reorderable container")
- [S151] HIG boxes (pattern above for HIG pages)

Added for Sasa's answers (Apple docs read as DocC JSON on 2026-11-05; pattern `https://developer.apple.com/documentation/<path>`):
- [S152] localauthentication/lacontext (macOS 10.10; an app that allows biometric authentication includes `NSFaceIDUsageDescription` in Info.plist) ; localauthentication/lacontext/evaluatepolicy(_:localizedreason:reply:) (macOS 10.10; also `evaluatePolicy(_:localizedReason:) async throws -> Bool`; the reason should be short and clear and leave out the app name; evaluation can fail through cancellation by the user or the system) ; localauthentication/lacontext/touchidauthenticationallowablereuseduration (macOS 10.12; "The default value is `0`, meaning that Touch ID authentication isn't reused")
- [S153] localauthentication/lapolicy/deviceownerauthentication (macOS 10.11; "in macOS with Touch ID, Apple Watch, or the user's password"; "In macOS, the system simultaneously looks for a nearby, paired Apple Watch running watchOS 6 or later, and tries to use that in parallel."; when biometry isn't available, the system asks for the user's password)
- [S154] localauthentication/lapolicy/deviceownerauthenticationwithbiometrics (macOS 10.12.2; fails when Touch ID is unavailable or not enrolled; on the fallback button "your app should provide an alternate mechanism")
- [S155] swiftui/link (macOS 11.0; SwiftUI opens a Universal Link in its app if possible, "or in the user's default web browser if not")

Added in the lean pass (Apple docs read as DocC JSON on 2026-11-05; pattern `https://developer.apple.com/documentation/<path>`):
- [S156] swiftui/windowgroup/init(id:content:) (macOS 11.0, deprecated 15.0: "Use the initializer which takes an escaping content builder instead.")
- [S157] swiftui/windowgroup/init(id:makeContent:) (macOS 11.0, not deprecated)
- [S158] swiftui/view/searchable(text:isPresented:placement:prompt:) (macOS 14.0; "Marks this view as searchable with programmatic presentation of the search field.")
- [S159] swiftui/commandgroupplacement/textediting (in macOS by default: the Find, Spelling and Grammar, Substitutions, Transformations and Speech submenus)
- [S160] swiftui/commandgroupplacement/toolbar (in macOS by default: Show/Hide Toolbar, Customize Toolbar)
- [S161] swiftui/commandgroupplacement/sidebar (in macOS by default: Show/Hide Sidebar, Enter/Exit Full Screen)
- [S162] swiftui/commandgroupplacement/saveitem (in macOS by default: Close, Save, Save As/Duplicate, Revert to Saved)
- [S163] swiftui/commandgroupplacement/printitem (in macOS by default: Page Setup, Print)
- [S164] swiftui/commandgroupplacement/windowarrangement (in macOS by default: Bring All to Front)
- [S165] swiftui/commandgroupplacement/help (in macOS by default: App Help)
- [S166] swiftui/view/textinputsuggestions(_:) (macOS 15.0; "Configures the text input suggestions for this view.")

Project inputs (not numbered): Sasa's answers and comments in the proposal doc, 5 Nov 2026 (linked from the project thread), and Sasa's messages of 5 Nov 2026 listed under §6 (the GUI rule, the stock request, "CRM, customer records", "90% goods").

Research notes this spec builds on (kept in the design thread, not in this repository): Apple design language, macOS HIG, SwiftUI APIs, and the invoicing UX research.
