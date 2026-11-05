# FA-mac: Screens & Flows spec

Date: 2026-11-05 · Role: Mac UX (speed first) · Status: draft for Sasa's review, updated with Sasa's answers in the proposal doc (5 Nov 2026) · Covers v0.1, v0.1.x (Repair mode), v0.2 and Phase 3 (iPhone)

## How to read this

- **This whole document is a design proposal (RECOMMENDATION).** Statements about Apple platforms, APIs, the HIG or other products carry a source tag **[S#]**. The numbered list of sources is at the end.
- **UNVERIFIED** marks anything that no opened page confirms. Test it before building on it.
- **ACCT** marks anything that needs to be confirmed with the accountant. This covers all legal or tax wording and treatment beyond what the project brief states.
- **The UI is English only.** Sasa answered "en" for the interface language and commented: "czech is not needed anywhere. its jsut a very little bonus that i might not use. dont bother if not super easy to implement, maybe version 10.9 or omething ahah" (Sasa's answer in the proposal doc, 5 Nov 2026).
  - Every UI label in this spec is English: sidebar, menus, toolbars, buttons, column headers, badges, empty states, hints, sheets and palette entries. Czech UI is out of scope.
  - Czech appears only in **document text**: what prints on the PDF (titles, legal and tax strings), the column names of the accountant's CSV (ACCT, §2h), and what Sasa types into a document (line descriptions, units, footer text).
  - The only language control sets document text, never the UI: "Document language: Czech / Czech + English" on each document (its default for new clients is in Settings ▸ General, §2i), mapped to InvoicingCore `DocumentLanguage.czech` ("cs", Czech only, for Czech customers) and `.english` ("en", bilingual, Czech first then English, for foreign customers).
  - The Czech entries in `DesignSystem.xcstrings` stay as a free bonus from the build thread. Nothing in this spec depends on them.
- The only legal wording used verbatim in this spec is the wording from the brief: "Faktura – daňový doklad", "Zálohová faktura", "Daňový doklad k přijaté platbě", "Není daňovým dokladem" (the brief's short form; the English UI shows "Not a tax document" instead, and the PDF prints the InvoicingCore clause from design-system §9, ACCT) and "daň odvede zákazník". Everything else printed on a PDF is ACCT, except the **Design** strings (the draft markers, the QR captions and the QR-unavailable notice, the continuation marker and the bank label), which carry no legal or tax meaning. **All printed and legal strings, with their status (Brief, Design or ACCT), are kept in one reviewed table: design-system §9 "Legal and tax strings".** Czech terms in this spec such as "přenesená daňová povinnost", "Osvobozeno", "Tuzemsko", "Mimo EU", "DUZP / Datum uskutečnění zdanitelného plnění", "Obchodní firma", "Kurzový rozdíl", "Konečná faktura" and "Odečtené zálohy" are **ACCT: confirm with accountant** wherever they appear. In the app they appear only in document text, if at all.
- **Cross-references.** design-system.md owns the tokens, colours, status styles, components and the toolbar table (§8.11). This spec owns the screens, flows, menus and the **one authoritative keyboard map (§3.1)**.
- Notation:
  - ⌘ = Command, ⇧ = Shift, ⌥ = Option, ⌃ = Control, ↩ = Return, ⌫ = Delete, ⎋ = Esc.
  - A chord such as ⌘K counts as **1 keystroke**. Each typed character counts as 1.
- Example data:
  - Client "Acme GmbH": EUR, document language "Czech + English", EU reverse charge, EPC QR, 30 days (set by hand; a new client starts at 14 days, §2e), DUZP rule "last day of the billed period".
  - Numbers are shown as "FV 2026-0042". The number format itself is an open question (Q2).
  - Amounts and dates in UI examples are written in Czech formats. The UI formats them with the UI locale; the PDF uses Czech formats (RECOMMENDATION; confirm with Sasa and the accountant, design-system §9).

## 0. Ground rules the UI enforces (domain rules, from the brief)

1. **Issued documents are immutable.**
   - There is no edit and no hard delete.
   - Corrections come only through a credit note, which arrives in Phase 2.
   - The one exception is **Repair mode** (v0.1.x, §2m): behind Touch ID or the password, every record unlocks, and every change is written to the audit log. There is no trace-free mode.
   - Payments, notes, file exports and two dated **closing events** may be *added* around an issued document. They never change it. The closing events are v0.1 actions so that nothing nags forever (§2d): "Close Advance as Unpaid…" for advances, and "Mark for Credit Note…" for tax documents. Wording and accounting effect: ACCT.
   - **A payment that an issued document rests on is locked too** (§2f): it can't be deleted, unmatched, or have its amount or date changed.
2. **The number is assigned at issue.**
   - It comes from one series per document type and is continuous, with no gaps.
   - Drafts have no number. Deleting a draft never uses up a number.
3. **"Zálohová faktura" is not a tax document.**
   - It prints the not-a-tax-document clause from design-system §9 (InvoicingCore `DocumentClause.notATaxDocument`: "Toto není daňový doklad. Daňový doklad bude vystaven po přijetí platby.", ACCT). The in-app banner reads "Not a tax document" (English UI); the brief's Czech short form "Není daňovým dokladem" isn't shown in the app.
   - It has no DUZP field. ACCT: confirm that no date of supply should print.
4. **Reverse charge** is a **document-level** VAT treatment (RECOMMENDATION; design-system §8.5 uses the same rule). It prints the clause "daň odvede zákazník" (the brief's exact string).
   - **ACCT: to verify** that a reverse-charge document shows no VAT rate and no VAT amount, and cite the legal source once the accountant confirms it.
   - The English wording of the clause is ACCT.
5. **EUR documents that carry VAT** also show the VAT amount in CZK. USD documents follow the same rule (ACCT).
6. **Exchange rate.**
   - **ACCT: to verify** which ČNB rate applies: the rate for the DUZP day, or the last rate published before it, or (depending on publication time) the previous publication day's rate. Cite the legal source once the accountant confirms it. The design below assumes "the DUZP day's rate, or the last one published before it".
   - The rate, the date it was published for, and its source are stored on the document. The UI always shows the rate's own date, never the DUZP (P6).
   - A fallback (a weekend or holiday) is labelled.
   - In v0.1 Sasa types the rate on each EUR or USD document (§2c). Importing a ČNB file is the secondary path (§2g).
7. **The app never sends anything and makes no network calls.**
   - The App Sandbox runs without network entitlements: `com.apple.security.network.client` and `com.apple.security.network.server` stay off [S139].
   - Exports and PDFs only go to folders Sasa chooses.
   - Phase 3 keeps this rule by limiting iPhone transfer to AirDrop and file-based exchange (§2l). Local Wi-Fi sync would need the client and/or server network entitlement [S139] and is out of scope unless Sasa decides to relax this rule.

## 0.1 Platform stance

- **Sasa's Mac:** an M1 Pro with 32 GB, on **macOS 27.2** with **English** as the system language. Sasa's answer in the proposal doc, 5 Nov 2026: "27.2, english" and "m1 pro 32gb ram 200gb bandwith 256gb disk - using mainly 8tb cloud / macOS 27.2 (the newest one, im just updating it right now)". This answers Q1.
  - An M1 Pro Mac (the 14- or 16-inch MacBook Pro from 2021) is on the compatibility lists for both 26 and 27 [S5][S6][S7].
- **Design for Liquid Glass from day one.** Xcode 27.2 ships the macOS 27.2 SDK [S4]. Apps built with Xcode 27 always use Liquid Glass, because `UIDesignRequiresCompatibility` is ignored when building for macOS 27 [S2][S3].
- **Deployment target (decision, build thread):** the app keeps targeting **macOS 14.0**.
  - CI is the `macos-15` runner with Xcode 16.4 (macOS 15 SDK). So every macOS 26 API sits behind `#if compiler(>=6.2)`, and every macOS 27 API sits behind the compiler check for the Swift version of the macOS 27 SDK. Each one also gets an `if #available` check and a macOS 14 fallback ([README.md](README.md), Platform policy).
  - The minimum rises once CI builds with Xcode 26 or later. For that raise the design recommends **macOS 27.0**: Sasa's Mac already runs 27.2, and nothing in 27.1 or 27.2 is needed (design-system §2). The macOS 27.0 APIs need the macOS 27 SDK, which ships with Xcode 27 (design-system §2), so a raise made on Xcode 26 can reach at most Fallback A (macOS 26.1).
  - APIs that need 27 are marked **(27)** in this spec; each is on the design-system §2 list; the macOS 15 and 26 APIs are gated too (design-system §2, Fallback A row). Until the raise, each (27) API is gated and uses the fallback that design-system §2 names.
- **Standard components only in v0.1:** `NavigationSplitView`, `Table`, `inspector`, toolbars, sheets.
  - They pick up glass automatically [S1].
  - **No custom glass on content.** The tables, the invoice editor and the PDF preview are content. The HIG says "Don't use Liquid Glass in the content layer" [S14].
- **Speed principles** used on every screen:
  1. **Prefill from the client.** Every new document inherits the client's defaults.
  2. **Undo instead of confirm.** The single exception is **Issue**, which can't be undone. That follows the HIG alert rule for uncommon destructive actions that can't be undone [S25][S42]. Entering Repair mode (v0.1.x, §2m) is not a confirm: it asks for a reason and for Touch ID or the password.
  3. **Every command is in the menu bar**, so the app can be run keyboard-only [S10]. Shortcuts are shown there. The command palette mirrors the menus and never replaces them [S18].
  4. **Single-key actions only inside a focused list**, never while a text field has focus. This is the pattern used by iÚčto, Fakturoid, Linear and Raycast [S116][S102][S129][S131]. `onKeyPress` only fires when its view has focus [S67].
  5. **Critical information goes at the top**, never only at the bottom of a window [S11][S26].
  6. **Launch instantly and restore the previous state**: section, selection, filters, any open document windows [S27]. There is no splash screen.
  7. **Nothing is time-boxed.** No banner, toast or confirmation hides on a timer; each stays until the next action or an explicit close [S16]. Repair mode's timeout ends the mode but never hides its notice (§2m).

---

## 1. Information architecture

### 1.1 Windows (scenes)

| Window | Scene | Purpose | Notes |
|---|---|---|---|
| Main window | `WindowGroup` with an id; **one main window** (RECOMMENDATION) | Sidebar navigation across all sections; **drafts are edited in place** in its detail column (§2c) | Don't use `Window` for the main scene: "If your app uses a single window as its primary scene, the app quits when the window closes" [S75]. A `WindowGroup` doesn't enforce one instance, so: the File menu replaces the system New group (`CommandGroup(replacing: .newItem)` [S143]; by default `.newItem` "includes … New" [S143]), which removes File ▸ New Window, and Window ▸ Main Window reopens the main window through `openWindow(id:)` if it was closed. The exact `WindowGroup` initialiser with an id for 26/27 is UNVERIFIED (`init(id:content:)` is listed as deprecated at macOS 15.0). |
| Document window (optional) | `WindowGroup(for: Document.ID)` + `openWindow` | **Only through Document ▸ Open in New Window or the context menu.** Shows the editor and the live preview side by side; after Issue the same window shows the issued, read-only document | If a window for that value already exists, `openWindow` brings it to the front [S75]. The HIG: "avoid opening new windows as default behavior unless it benefits your user experience", but "consider providing the option to view content in a new window" from a context menu or the File menu [S26]. WindowGroup titles appear in the File ▸ New list, and File ▸ New Window passes a `nil` value [S144]; since File ▸ New is replaced (above), this group never offers an empty editor. Test on device. |
| Statement triage (v0.2) | `WindowGroup(for: Statement.ID)` | Match bank lines | Kept out of File ▸ New in the same way. |
| Settings | `Settings` scene (macOS only) | App-level configuration (§2i) | It enables the app's Settings item and ⌘, [S76]. |
| Command palette | Sheet on the key window | ⌘K (§2k) | Standard component, so there is no custom window UI [S26]. `presentationSizing` is available from macOS 15 [S90]. |

Window titles are the section name, the document number or a name (a client; for a draft its client, or "New Invoice" before one is chosen), never the app name. Keep them under 15 characters where the name allows ("Documents", "FV 2026-0042", "Acme GmbH", "New Invoice") [S19]. The subtitle carries the filter or state through `navigationSubtitle` [S100].

### 1.2 Main window sidebar

There are at most 2 levels [S20]. Icons follow the accent colour on 27 [S3]. Overdue gets a fixed red tint because it carries meaning [S20]. Counts are badges [S80]. Nothing critical goes at the bottom of the sidebar [S20].

This is **the** sidebar; design-system §5.1 and §7 refer to it.

| # | Section | Children (smart filters) | Shortcut | Content column | Detail column |
|---|---|---|---|---|---|
| 1 | Overview | — | ⌘1 | Tiles, VAT table and attention queue (§2a) | The selected queue item's document (Record Payment and payments, then the PDF pages); with nothing selected, a calm placeholder |
| 2 | Documents | All · Drafts (badge) · Unpaid · Overdue (badge, red) · This month · Open advances (badge) | ⌘2 | One `Table` with filters (§2b) | Issued view, or the draft editor in place |
| 3 | Clients | — | ⌘3 | Clients table (§2e) | Client detail |
| 4 | Payments & Bank | All payments · v0.2: one row per bank account · Unmatched (badge) | ⌘4 | Payments list (§2f) | The payment's document |
| 5 | Exchange rates | — | ⌘5 | Rates list (§2g): typed and imported rates together; a warning badge when needed rates are missing | Coverage panel |
| 6 | Exports & Backup | — | ⌘6 | The two cards (§2h) | Export history and backup list |

**One three-column `NavigationSplitView` for every section.** The docs say "macOS always displays the content column" [S142], so a section can't drop it; each section fills the content column as listed above (RECOMMENDATION). The sidebar's SF Symbols are in design-system §7 (checked against SF Symbols data up to macOS 26; confirm them in the SF Symbols 27 app).

The sidebar is visible by default ("Avoid hiding the sidebar by default" [S20]) and collapses automatically when the window gets narrow.

### 1.3 Settings window panes

The Settings window uses a toolbar of panes. It always shows the active pane, its title is the pane name, and it reopens on the pane Sasa viewed last [S29]. There are seven panes:

| Pane | Contents |
|---|---|
| General | Default document language for new clients, PDF folder (path control [S49]), start-up behaviour. No app-language setting: the UI is English only. |
| Company | Legal name, registered office, IČO, DIČ, spisová značka, logo (image well [S48]), contact details |
| Bank accounts | Accounts: name, currency (EUR, CZK or USD), IBAN, BIC, Czech account number; default account per currency |
| Numbering | One series per document type: pattern, next number, VS rule and VS preview, collision check |
| Documents & PDF | Default due days (14), footer texts for Czech and bilingual documents (empty until Sasa sets one), file-name pattern, auto-save on issue, QR defaults, payment tolerance |
| VAT defaults | Rates (21 / 12 / 0), treatments, the default treatment for a new client (EU reverse charge) and how the client's country adjusts it, reverse-charge clause |
| Backup | Backup folder, automatic backups, how many to keep, Back Up Now, Restore… |

Details are in §2i.

### 1.4 Menu bar: every command

Menu order: App, File, Edit, View, Document, Client, (v0.2 Bank), Window, Help [S18]. The app-specific menus are `CommandMenu`s, which sit between View and Window in the order they are declared [S64]. There is no Format menu, because the app has no formatted text editing [S18].

Menu rules:
- Unavailable items are disabled, never hidden [S18].
- An ellipsis means that more input follows [S46].
- On 27, action items show no icons [S4].
- What the Document and Client menus act on comes from `focusedSceneValue`, so the menu bar always follows the current window's selection [S66].
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
| New Invoice | ⌘N | Always. If a client is the current selection, it is prefilled. |
| New Advance Invoice | ⇧⌘N | Always. Prefilled the same way. |
| New ▸ Tax Document for Received Payment… | — | An advance with a received payment that has no tax document is selected (otherwise it asks which advance). DDPPs and final invoices come from the chain (§2d), not from scratch. |
| New ▸ Final Invoice… | — | An advance or a client is selected |
| New Client… | ⌥⌘N | Always (opens the New Client sheet, §2e) |
| — | | |
| Duplicate as Draft (the title names the source, e.g. "Duplicate FV 2026-0041 as Draft") | ⌘D | A document is selected. In client context it acts on that client's last invoice. |
| — | | |
| Import ČNB Rates… | — | Always (drag and drop also works anywhere). Takes the ČNB daily or yearly file. This is the secondary rate path: in v0.1 Sasa types the rate on the document (§2c, §2g). |
| Import Bank Statement… (v0.2) | — | Always |
| Export for Accountant… | — | Always |
| — | | |
| Back Up Now | — | Always |
| Restore from Backup… | — | Always |
| — | | |
| Repair Mode… (v0.1.x) | — | Always. Asks for a reason, then Touch ID or the password. While the mode is on, the item reads **End Repair Mode** (§2m). |
| — | | |
| Save PDF… | — | One or more issued documents are selected. Drafts can only produce a watermarked preview. |
| Show PDF in Finder | — | An issued document has a saved PDF (uses `activateFileViewerSelecting` [S92]) |
| Print… | ⌘P | A document is selected (prints its PDF through the system print panel [S44]). A draft prints with the fixed-colour "KONCEPT / DRAFT" watermark and the "QR po vystavení / QR after issue" placeholder ("QR po vystavení" alone on a Czech document; document text, §2c) instead of a scannable QR (design-system §8.8). |
| — | | |
| Close | ⌘W | — |

The five New items above are the whole **File ▸ New** group: the menu is built with `CommandGroup(replacing: .newItem)` [S143], so the system's New Window item and the WindowGroup titles that SwiftUI lists under File ▸ New [S144] never appear. Whether the system item would otherwise also claim ⌘N is UNVERIFIED; the replacement makes it moot.

Deliberately left out:
- **Open (⌘O), Save (⌘S), Save As/Duplicate (⇧⌘S) and Page Setup (⇧⌘P).** Drafts autosave, so no Save is needed [S43]. The PDF is a fixed A4 page. These shortcuts stay **unbound** and are never reused for anything else (§3).

**Edit**

| Item | Shortcut | Notes |
|---|---|---|
| Undo ‹action› / Redo ‹action› | ⌘Z / ⇧⌘Z | The title names the target, e.g. "Undo Record Payment" [S42]. Issue never appears here. |
| Cut / Copy / Paste / Paste and Match Style | ⌘X / ⌘C / ⌘V / ⌥⇧⌘V | Copy on a document row puts the PDF file and a plain-text summary on the pasteboard (multiple representations [S36]; `copyable` [S99]). Whether Mail accepts the pasted file is **UNVERIFIED**. |
| Delete | ⌫ | Works on a focused list: drafts, notes and manual payments that no issued document rests on (§2f), always with undo. Disabled for issued documents. Uses `onDeleteCommand`, which fires on ⌫ or ⌦ while the view has focus [S68]. Line items are deleted through Document ▸ Delete Line or the row's context menu, not ⌫ (§2c). |
| Select All | ⌘A | — |
| Find ▸ Search… / Jump to Search Field | ⌘F / ⌥⌘F | Both focus the toolbar search (`searchFocused`, macOS 15 [S63]) |
| Spelling and Grammar ▸, Substitutions ▸, Start Dictation, Emoji & Symbols | system | Only in text fields [S18] |

**View**

| Item | Shortcut | Notes |
|---|---|---|
| Show/Hide Sidebar | system default from `SidebarCommands` | The default shortcut is **UNVERIFIED**: the doc page doesn't state it [S57]. |
| Overview, Documents, Clients, Payments & Bank, Exchange Rates, Exports & Backup | ⌘1 … ⌘6 | Section navigation, not window navigation [S18] |
| Command Palette… | ⌘K | §2k |
| — | | |
| Show/Hide Inspector | ⌥⌘I | Custom command. **Don't** include `InspectorCommands`, because its built-in shortcut is ⌃⌘I [S62]. The HIG says to avoid Control [S17], and the standard shortcut for an inspector is ⌥⌘I [S17][S8]. |
| Show/Hide Preview | — | A draft in the editor: swaps the main-window detail between editor and PDF preview. A document window shows both side by side. |
| Filter ▸ All / Drafts / Unpaid / Overdue / This Month / Open Advances | — | Shown with a checkmark |
| Sort By ▸ ‹columns› | — | Mirrors the table headers |
| Quick Look | ⌘Y (and Space in lists) | The same keys Finder uses [S8]. Uses `quickLookPreview` [S77]. |
| — | | |
| Bigger Text / Smaller Text / Actual Size | ⌘+ (⇧⌘=) / ⌘− / ⌘0 | Scales **every content surface** (tables, editor, inspector, Overview, totals, sheets) from 100 to 200 % [S16] (design-system §3). ⌘0 is **UNVERIFIED** as a convention; it isn't in Apple's tables. |
| Show/Hide Toolbar, Customize Toolbar… | ⌥⌘T / — | `ToolbarCommands`. ⌥⌘T is the HIG standard for "Show or hide a toolbar" [S17]; the `ToolbarCommands` docs page doesn't state the key it generates, so check the generated menu (UNVERIFIED). |
| Enter/Exit Full Screen | ⌃⌘F | System |

**Document** (app-specific; applies to the selected document, the draft in the detail column, or a document window)

| Item | Shortcut | Enabled when |
|---|---|---|
| Issue… | ⌘↩ | A draft is focused (in the main-window detail, a document window, or a draft selected in the list) |
| Record Payment… | ⌘R | An issued document with an open balance is selected |
| Create Tax Document for Payment | — | An advance with a received payment that has no tax document yet |
| Create Final Invoice | — | An advance is selected |
| — | | |
| Add Line Item | ⌘L | Editor |
| Delete Line | — | Editor, with the cursor in a line. **No shortcut** (⌘⌫ stays unbound, §3.1); also in the row's context menu. Undoable. |
| Move Line Up / Move Line Down | — | Editor, with the cursor in a line. No shortcut on purpose, to keep custom shortcuts few [S17]. Dragging also works on 27. |
| Change Type ▸ Invoice / Advance Invoice / Final Invoice | — | Draft (checkmark on the current type). Not on a tax document for a received payment: that type is created only from its payment and can't be changed (§2d, ADR 0009). |
| Currency ▸ EUR / CZK / USD · Document Language ▸ Czech / Czech + English · VAT Treatment ▸ … · QR ▸ QR Platba / EPC QR (SEPA) / None | — | Draft. Checkmarked items, so every header control has a path that doesn't depend on Tab (§2c). Also in the palette. |
| Apply Client Defaults | — | Draft |
| Enter Rate… | — | A draft in EUR or USD. Moves focus to the draft's inline rate form (§2c), or opens Change… when a rate is already set. The v0.1 rate path. |
| — | | |
| Close Advance as Unpaid… | — | An issued, unpaid advance (§2d) |
| Mark for Credit Note… | — | An issued tax document (§2d) |
| — | | |
| Show Client | — | — |
| Show Related Documents | — | Shows the advance → payment → tax document → final invoice chain |
| Open in New Window | — | From the main window: the only way to open a document window (§1.1) |

**Client** (items carry no shortcuts. In client context ⌘N and ⌘D already prefill this client, so repeating the shortcuts here would create duplicates.)

| Item | Shortcut |
|---|---|
| New Invoice for ‹Client› | (⌘N in client context) |
| New Advance Invoice for ‹Client› | (⇧⌘N in client context) |
| Repeat Last Invoice (FV …) | (⌘D in client context) |
| Add Note… | — |
| Show Documents / Show Payments / Show Activity | — |
| Edit Client Details | — (focuses the inspector) |
| Archive Client | — (only clients with no open balance; archived clients disappear from the pickers) |

**Bank (v0.2)**

| Item | Shortcut | Notes |
|---|---|---|
| Accept Suggestion | ↩ in the triage list | — |
| Accept Exact Matches (N) | — | The same command as the prominent toolbar item (its only placement in the window) and a palette command. No shortcut: ⇧⌘A is Deselect All. |
| Find Document for Line… | ⌘F in the triage window | — |
| Not an Invoice ▸ categories | N in the triage list | Menu and palette are the fallback if type-select eats N (§3.2) |
| Skip | S in the triage list | Same fallback |
| Unmatch | — | Undoable. Blocked when an issued document rests on the payment (§2f). |
| Show Monthly Cash View | — | — |

**Window**: Minimize ⌘M · Zoom · Bring All to Front · **Main Window** (reopens it if closed) · the list of open windows (main window plus any document windows, listed alphabetically) [S18].

**Help**:
- The system search field. It also searches menu items, so it works as a built-in "palette lite".
- FA Help ⌘?
- Keyboard Shortcuts (a searchable overlay; Linear's searchable shortcut help is the model [S130])
- Getting Started (reopens the setup checklist in §2j)

---

## 2. Screen specs

### (a) Overview

**Purpose.** Open the app and see what needs doing, and how the month looks, in under a second.

**Layout.**
- Sidebar | Overview in the **content** column | the selected queue item's document in the detail column, or a calm placeholder when nothing is selected (§1.2). macOS always displays the content column [S142], so this is the buildable form of "one screen of attention". No inspector by default.
- The content scrolls. The toolbar follows design-system §8.11: a leading title "Overview" and a **New ▾** split button (`Menu(_:content:primaryAction:)`: click = New Invoice; the menu lists Advance / Final… / Tax document… [S93]) next to Search.

**Content, top to bottom.**

1. **Month bar**: "◀ November 2026 ▶". The default is the current month, and one click goes to the previous one.
2. **Four number tiles.**
   - Each tile has a symbol, a label and a value. Colour is never the only signal [S13][S37].
   - Amounts use `.monospacedDigit()` (RECOMMENDATION, design-system §3; not from the typography HIG).
   - Clicking a tile opens the matching Documents filter.
   - **Caption under the tiles:** "Payments recorded up to 31. 10. 2026" (the latest recorded payment date; in v0.2, the last imported statement period per account). It tells Sasa that "Overdue" may include clients who already paid after that date.
   - Every figure follows the **aggregation rules** below.

   | Tile | Main value | Secondary line |
   |---|---|---|
   | Unpaid | Open balances of Faktura and Konečná only: "18 400,00 € + 35 000 Kč". Currencies are never summed silently. | "≈ 482 300 Kč at document rates · 7 documents" · a separate line "Unpaid advances: 2 · 3 000,00 €" |
   | Overdue | "6 200,00 €" (Faktura and Konečná) | "3 documents · oldest 23 days" · overdue advances counted on their own line |
   | Issued in November | Counts per type: "Invoice 6 · Advance 2 · Tax doc (payment) 1" | Revenue from tax documents only, per currency |
   | VAT for November (CZK) | "42 180 Kč" | Reverse-charge base in CZK shown separately. ACCT: how reverse-charge supplies are reported. |

   **Aggregation rules** (RECOMMENDATION; every rule marked ACCT is confirmed with the accountant). The same rules feed the tiles, the VAT table, the selection totals (§2b) and the CSV (§2h); design-system §8.6 points here.

   | Figure | Counts | Never counts |
   |---|---|---|
   | VAT (tile, VAT table, CSV VAT columns) | Tax documents only: Faktura, DDPP, and the final invoice **net of** the advance VAT its DDPPs already taxed. Grouped by DUZP month (ACCT). | Zálohová faktura (not a tax document); the same advance money a second time in the final invoice's gross |
   | Revenue in "Issued in ‹month›" | Tax documents, as above: a final invoice counts **net of** the advances it deducts (the app shell, PR #11) | Advances; drafts |
   | Unpaid, Overdue | Open balances of Faktura and Konečná. DDPPs are paid by definition. | Advances (they get their own "Unpaid advances" line); an advance already deducted by an issued final invoice; a `closedUnpaid` advance; a document marked for credit note |
   | Unpaid advances line | Open advances that no final invoice has deducted and that aren't closed | — |
   | CSV rows | Every issued document, with a "Daňový doklad ano/ne" column | Advance rows never fill the VAT columns |
3. **"Needs attention" queue.**
   - It is a keyboard-navigable list. ↑↓ selects, ↩ runs the row's main action, Space previews the PDF. The groups appear in this order:
     1. Overdue documents, oldest first: "FV 2026-0031 · Beta s.r.o. · 23 days overdue · 1 200 €" with the action **Record Payment**. Advances closed as unpaid and documents marked for credit note never appear.
     2. Advances with a received payment that has no tax document (paid in full or in part): **Create Tax Document**.
     3. **"Month-end rates missing"**, from the first day of each month until the last day of the previous month is covered: **Enter Rate…** first, then **Import ČNB Rates…**. Enter Rate… is the v0.1 path (Sasa types the ČNB rate, §2c); it opens the rate sheet with the needed date and currency prefilled (§2g). This is the most common blocker of the monthly invoice (§2c), so it shows before any draft needs it.
     4. Other missing ČNB rates needed by drafts or payments: **Enter Rate…** first, then **Import ČNB Rates…**.
     5. Drafts older than 7 days: **Open**.
     6. (v0.2) Unmatched bank lines: **Triage**.
     7. Backup older than 7 days: **Back Up Now**.
     8. Optional light-CRM nudge, off by default: "Not invoiced for 2 months".
   - This follows Fakturoid's unpaired payments and its "Dlouho nefakturovaní" contacts [S107][S102], and iDoklad's notifications widget [S115].
4. **VAT table** (v0.1; no chart). The brief asks for a "VAT summary per month in CZK", so v0.1 shows a plain 12-row `Table`: Month · Base (CZK) · VAT (CZK) · Reverse-charge base (CZK), newest first, selectable, copyable and exportable. Selecting a month filters Documents to it. A chart can come later; it would follow the HIG chart rules [S37].

**Primary and secondary actions.**
- ↩ runs the selected queue item's action.
- ⌘N creates a new invoice.
- Clicking a tile opens its filter.

**States.**
- *Empty (first run):* the "Getting started" checklist (§2j) plus `ContentUnavailableView` "No documents yet" with a **New Invoice** button [S79].
- *Loading:* the data is local, so this should be instant. If aggregation takes longer than about 100 ms, show placeholder tiles with `.redacted(reason: .placeholder)` [S38].
- *Error* (the database can't be opened): an inline banner "Data can't be opened" with **Restore from Backup…** and **Show Data Folder**. Never an alert at launch [S25].

**Edge cases.**
- Mixed currencies: show them per currency. The CZK equivalent always says which rate it uses.
- Overpaid documents show as client credit and are left out of Unpaid; the credit can be applied or refunded (§2f).
- Dates are local calendar dates with no time zone maths.
- Once every queue group is empty, the queue shows "All caught up".

### (b) Documents (Table + preview + inspector)

**Purpose.** Find, check and act on any document with the keyboard.

**Layout.** The three-column `NavigationSplitView` [S58]: sidebar | `Table` (content column) | detail (issued view, or the draft editor in place), plus a trailing `inspector` (⌥⌘I).
- The inspector's presented state is restored by the framework [S61].
- Column minimum widths keep the dividers visible [S21]: sidebar 180, content 360, detail 520, window minimum 1080 pt; the inspector closes below 1320 pt (design-system §5.3).

**Toolbar:** the "Documents list" row of the toolbar table in design-system §8.11 (the one toolbar table). In short:
- *Leading:* sidebar toggle, title "Documents", subtitle with the filter and count ("Overdue · 3").
- *Centre (customizable):* New ▾ (split button; its menu has at least three items, as the HIG asks of pull-downs [S31]), Duplicate, Record Payment, Print. New and Record Payment get `visibilityPriority(.high)` (macOS 26.1) so they survive in narrow windows [S83]; groups are separated with `ToolbarSpacer(.fixed)` [S84].
- *Trailing:* Search, then the Inspector toggle [S19].
- No prominent button here. The prominent primary action lives in the editor (Issue) and in the issued document view (Record Payment): one per context, trailing [S19]. Don't place it with `.primaryAction`, which is the leading edge on macOS [S141].

**Table columns.**
- Columns can be resized, reordered and hidden. Each column needs a `customizationID` [S60].
- The column state persists with `@SceneStorage` [S60].
- The table doesn't sort itself, so the model re-sorts when the sort order changes [S59].

| Column | Default | Align | Content |
|---|---|---|---|
| Status | visible | leading | StatusBadge (design-system §4.3): symbol + word, e.g. Draft, Issued, Awaiting payment, Partly paid, Paid, Overpaid, and Overdue with the detail "+12 days · 1 000,00 € left". Overdue replaces the word, tone and symbol; the detail keeps the days and the open balance. Exception: an advance with a received payment that still lacks its tax document shows that instead (design-system §4.3, Label order). Never colour alone [S13]. |
| Number | visible | leading | "FV 2026-0042"; drafts show "—" |
| Type | visible | leading | Short type names from §5: Invoice / Advance / Tax doc (payment) / Final |
| Client | visible | leading | Name, middle-truncated [S23] |
| Issued | visible | trailing | Date. For drafts, the planned issue date in grey. |
| Due | visible | trailing | Date |
| Total | visible | trailing | "4 840,00 €" (monospaced digits) |
| Open | visible | trailing | Open balance in the document currency |
| DUZP | hidden | trailing | Date of taxable supply (the header uses the short form) |
| VS | hidden | trailing | Variable symbol |
| VAT in CZK | hidden | trailing | — |
| Currency | hidden | leading | — |
| Paid on | hidden | trailing | — |

- **Default sort:** Issued, newest first. Drafts sort by their planned date, so they show up near the top.
- **Per-filter default sorts:**
  - Overdue: Due, oldest first.
  - Unpaid: Due, oldest first.
  - Drafts: last modified, newest first.
  - Open advances: Issued, oldest first.
- **What Unpaid and Overdue count:** invoices and final invoices only, the same set as the Overview tiles (§2a aggregation rules). The sidebar's Overdue badge counts the same set. An overdue advance stays under Open advances, where its status badge shows Overdue (the app shell, PR #11).
- Each filter remembers its own sort. iDoklad likewise remembers the last filter [S114].

**Detail column.**
- **Issued documents:** a summary header (number, type, client link, status badge, total, open balance and due date; the critical numbers sit at the top [S11]), then the payments and the actions, then the PDF row (Save PDF…, Show PDF in Finder, Print…) and the page images of the stored PDF (ADR 0010). The pages come last because they are tall: placed above the payments, they would push Record Payment and the payment list below the fold.
- The page images show white paper in both Light and Dark mode, because they are content.
- **Drafts are edited right here** (§2c): selecting a draft shows its editor in the detail column; ↩ in the table moves focus into it. Document ▸ Open in New Window opens the same draft in its own window.

**Inspector** (it follows the selection and updates automatically [S22]); derived information only, design-system §8.12:
- Rate block: "24,315 CZK/EUR · ČNB 30. 10. 2026, last published · Typed" ("ČNB file" for an imported rate). The date shown is always the rate's own publication date; a fallback is labelled.
- VAT recap per rate, with CZK amounts.
- Payment details and QR preview (bank account, VS).
- Payments list with **+ Record**.
- The document chain (§2d).
- PDF file: path and saved time.
- Activity.
- For issued documents, the frozen header values (dates, VS, currency, document language, VAT treatment) as read-only `LabeledContent`.
- **With several rows selected**, the inspector shows the count, totals per currency, and the bulk actions (Save PDFs to Folder…, Export CSV…, Print).

**Issued document view** (this view is the same in the main window detail and in its own window):
- Every field is read-only (`LabeledContent` [S98]).
- A lock line explains the state: "Issued 5. 11. 2026 · locked. Corrections via credit note (coming in Phase 2)". The Czech title of the credit note is ACCT (Phase 2). In Repair mode (§2m) the line reads "Repair mode: changes are logged".
- The prominent primary action is **Record Payment**.
- **Duplicate as Draft** is offered as the way to make a similar document.
- The two closing actions (§2d) sit in the Document menu and the context menu, never as buttons in this view: Close Advance as Unpaid… (advances) and Mark for Credit Note… (tax documents).

**Keyboard** (single keys only when the table has focus; §3.2). If SwiftUI's `Table` turns out to be `NSTableView`-backed with type-select on (its default is true [S86]; whether it applies here is UNVERIFIED), letter keys may never reach `onKeyPress`. Prototype on macOS 26/27 before committing; every letter below has a ⌘ chord:

| Key | Action |
|---|---|
| ↑ ↓, ⇧↑ ⇧↓ | Select or extend the selection; the detail follows |
| ↩ | Open: a draft moves focus into its editor in the detail column; an issued document moves focus into its detail (the prominent Record Payment, or the first control when nothing is payable). Implemented explicitly with `onKeyPress(.return)` on the focused Table [S67]: the `primaryAction` docs describe only the double-click on macOS [S69], so that ↩ triggers it by itself is UNVERIFIED. |
| Double-click | The same as ↩ (`contextMenu(forSelectionType:menu:primaryAction:)`: "a double click performs the primary action" on macOS [S69]) |
| Space | Quick Look of the PDF [S8][S77] |
| D | Duplicate as Draft (= ⌘D) |
| R | Record Payment (= ⌘R) |
| ⌫ | Delete draft (undoable). Does nothing on issued documents. |
| ⌘A | Select all in the current filter, then act on all of them |
| ⎋ | Clear the search, then the selection |

**Context menu** (unavailable items are hidden, not dimmed [S47]; at most 3 groups):
- Open · Open in New Window
- Record Payment… · Duplicate as Draft
- Save PDF… · Show PDF in Finder · Quick Look
- Delete Draft (drafts only) · Close Advance as Unpaid… (advances) · Mark for Credit Note… (tax documents)

**Search** (toolbar, trailing; it searches as you type [S28]):
- It searches number, VS, client name, IČO and VAT ID, amount ("4840" matches 4 840,00) and line descriptions.
- Matching ignores diacritics (RECOMMENDATION).
- **Tokens:** Status, Type, Client, Currency, Month ("Month: 2026-10") (`searchable(text:tokens:…)` [S63]).
- Pressing ↩ in the search field moves focus to the first result (RECOMMENDATION; test).

**Selection status bar** (bottom, small and non-critical, **information only**): the HIG says to avoid "critical information or actions in a bottom bar" and to use it "only to display a small amount of information" [S26].
- "3 selected · 9 600,00 € + 12 000 Kč": the count and the totals per currency only, the same idea as iDoklad's "Součet" [S113]. Totals follow the §2a aggregation rules.
- No buttons here. Bulk actions on the selection (Save PDFs to Folder…, Export CSV…, Print) are in the toolbar, the menus, the context menu and the inspector's multi-selection view.

**States.**
- *Empty:*
  - All: "No documents yet" + New Invoice.
  - Overdue: "Nothing overdue".
  - Drafts: "No drafts".
  - Search: `ContentUnavailableView.search` [S79].
- *Error:* a PDF that can't be rendered shows "Preview unavailable" inline with Retry. The document stays intact. Error text sits next to the problem and says how to fix it, with no blame [S45].

**Edge cases.**
- An issued document whose saved PDF was moved in Finder: the app keeps its own frozen copy of the PDF bytes from issue time. Show PDF in Finder is then disabled with a tooltip "File moved – use Save PDF…".
- With thousands of rows, the Table loads lazily and sorting happens in the database.
- A draft with no client yet shows "(no client)".

### (c) New invoice: fast path, editor, review and issue

**Build status.** The first draft editor (ADR 0009, PR #12) leaves these items for later: the period-text shift and the comparison with the client's last invoice, the command palette (§2k), natural-language dates, the "Go to Problem" default button, dropping a ČNB file onto the sheet, and the undo stack. It has no floating "On issue" date (an issue date other than today is a ⚠ row with "Set to today") and no per-client DUZP rule yet. The live PDF preview and the saved-PDF line came with PR #14 (ADR 0010); the document window with editor and preview side by side still waits. This section stays the target for them.

**Entry points** (all create a **Draft** with no number):

| Entry | What it does |
|---|---|
| ⌘N | New Invoice. The client is prefilled from the current selection; otherwise the Client field has focus. The draft opens in the main window's detail column. |
| ⌘D | Duplicate the selected document, or in client context the client's last *Faktura*, as a Draft (in the detail column) |
| ⌘K, then type a client | The palette offers "New Invoice – Acme" and "Repeat Last Invoice – Acme" (§2k) |
| Client detail buttons | New Invoice · Repeat Last Invoice (with the number shown) |

**Client defaults applied automatically.** Per-contact defaults like these exist in Fakturoid and Native Invoice [S105][S136]:
- currency
- document language ("Czech" or "Czech + English": InvoicingCore `DocumentLanguage.czech` / `.english`, design-system §9)
- VAT treatment (Czech 21 % / EU reverse charge / Outside EU; the printed Czech wording is ACCT). A new client starts on EU reverse charge (§2e).
- QR type (QR Platba / EPC QR (SEPA) / None)
- due days (14 for a new client, §2e)
- bank account for that currency
- the DUZP rule: "issue date" or "last day of the billed period" (ACCT; Fakturoid has a similar switch for recurring invoices [S112]). The billed period is the header's **Period** field (a month), so the rule never depends on the day Sasa happens to issue.
- optional fixed VS (Fakturoid's "pevný VS" [S106])

If Sasa changes the client in a draft, every field Sasa hasn't touched takes the new client's defaults. Edited fields keep their values, and a banner offers "Apply Acme's defaults (EUR · Czech + English · reverse charge · 30 days)".

In the first editor (ADR 0009) a client change applies all of the new client's defaults and resets the payment and the rate; prices are never converted. The untouched-fields rule and its banner stay the target. The VAT treatment is chosen once per document, and under the Czech treatment each line picks its rate, as rule 4 and the lines grid below already say.

**Duplicate rules.** Fakturoid, QuickBooks and iDoklad all reset dates on a copy [S101][S125][S114]. This app resets:
- issue date to **"On issue"**: it floats and becomes the actual day of Issue, unless Sasa sets a date explicitly
- Period to the source document's period + 1 month
- DUZP by the client rule (for "last day of the billed period": the last day of the new Period)
- due date to issue date + due days
- the rate, re-picked for the new DUZP from the Rates list (if none covers it, the inline rate form asks for it)
- no number

**Period text in line descriptions is never changed silently** (v0.1). Legal text on an immutable document must not be rewritten unread, and v0.1 has no credit note to fix a misfire such as "Roční hosting 11/2026–10/2027" or "dle smlouvy ze 09/2026".
- Only a single recognised period **at the start or the end** of a line description is shifted, by the same number of months as Period. Line descriptions are document text, so it recognises Czech and English month names and "MM/YYYY". A period in the middle of a line, or a range, is never touched.
- Each shifted text is highlighted in the editor and can be undone with ⌘Z ("Undo Shift Period").
- The Issue sheet lists the changes as a **⚠ Check** row with "before → after" for each line ("Line 1: září 2026 → říjen 2026", quoting the line's own text), so the "Checked" checkbox must be ticked before Issue. That costs one keystroke (Space; the checkbox has initial focus) and guarantees the text was read.
- If this still misfires in testing, drop the shift from v0.1; explicit placeholders ({month}), as in Harvest, arrive with the Phase 2 templates [S138].

**Editor layout** (in the main window's detail column by default; the same editor in a document window after Open in New Window).
- **Toolbar:** the "Draft editor" row of design-system §8.11.
  - Leading: title "New Invoice" or the client name. Subtitle: "Draft · Saved".
  - Centre: Preview toggle · Duplicate.
  - Trailing: Inspector toggle and a **prominent "Issue…"** button. There is exactly one prominent action and it sits on the trailing edge [S19]; not `.primaryAction`, which is the leading edge on macOS [S141].
  - Whether `.glassProminent` or `.borderedProminent` renders as the HIG's toolbar `.prominent` style is **UNVERIFIED** [research]. AppKit has `NSToolbarItem.Style.prominent` (macOS 26) [S94].
- **Preview:** in the main-window detail, View ▸ Show/Hide Preview (the toolbar toggle) swaps the detail between the editor (min 520 pt) and the live PDF preview. A document window shows both side by side: editor min 520 pt, preview min 360 pt, thin divider [S21].
- **Totals bar** pinned at the top of the editor with `safeAreaBar(edge: .top)` (macOS 26) [S82], so it gets the scroll edge effect and needs no custom background [S11][S51]:
  - Reverse-charge example (Acme): "Base 3 142,50 € · Reverse charge · Total 3 142,50 € · Amount due 3 142,50 €". There is no VAT line (rule 4, ACCT).
  - Czech 21 % on an EUR document: "Base 4 000,00 € · VAT 840,00 € · Total 4 840,00 € · Amount due 4 840,00 €" plus "VAT in CZK 20 424,60 Kč" at 24,315 (rule 5). Amount due shows on an invoice, an advance and a final invoice, never on a DDPP (design-system §8.6).
  - plus the **one readiness chip**: "✓ Ready to issue" or "2 problems". Clicking it opens the review-and-issue sheet, which lists the problems with "Go to Problem". Readiness is shown only in this chip and in the sheet.
  - **The rate (EUR and USD documents) is typed here in v0.1.** When no stored rate covers the DUZP, the bar shows the inline rate form, the same one as in the Issue sheet (edge cases below). Typing the ČNB rate there is the **primary path** (Sasa types the rate for each invoice, §2g). When a stored rate covers the DUZP, the bar adds nothing, and the rate shows in the inspector's ExchangeRateRow (design-system §8.9).
- **Header form** (a `Grid`, labels on the leading side). **This is the only place for header fields**; the inspector never repeats them, and Tab reaches every one:
  - Client: type-ahead on name, IČO and VAT ID, with caution chips "VAT ID missing" / "Address missing"; the last row is "New Client “X”…", which opens the New Client sheet (§2e).
  - **Until Issue, a draft shows the current client card and company profile.** An edit there (a VAT ID, an address, the company DIČ) reaches every open draft, so its chips and ⛔ rows clear without re-picking the client. Only the party data is refreshed; the draft's other fields keep their values. Issue takes the snapshot (step 4 below). Build note: not built yet. The first editor keeps the parties copied when the client was picked and when the draft was created (editor design check, E024).
  - Type pop-up: each English name with its Czech document title, e.g. "Advance invoice (Zálohová faktura)" (document text, design-system §9) (also Document ▸ Change Type ▸). It offers Invoice, Advance invoice and Final invoice; on a tax document for a received payment it is read-only (§1.4, ADR 0009).
  - Issue date: "On issue" until Sasa sets one (it then becomes the day of Issue).
  - Period (month): drives the DUZP rule and the period-text shift.
  - DUZP (label "Date of taxable supply", short form "DUZP"; the English wording is ACCT), with an ℹ line "DUZP 31. 10. = end of period October 2026". Hidden for an advance invoice.
  - Due, as both "30 days" and a date, linked.
  - Currency: segmented EUR | CZK | USD (also Document ▸ Currency ▸).
  - Document language: segmented Czech | Czech + English [S33], mapped to InvoicingCore `DocumentLanguage.czech` / `.english` (also Document ▸ Document Language ▸). It sets the document text only, never the UI.
  - VAT treatment: pop-up [S30] (also Document ▸ VAT Treatment ▸). Labels ACCT.
  - Bank account: filtered by currency.
  - QR type: pop-up (also Document ▸ QR ▸).
  - VS: "Assigned at issue", unless the client has a fixed VS.
  - **Build note (v0.1):** the client model has no QR-type or fixed-VS field yet, and the first editor has no QR-type pop-up and no VS row. The QR type follows the currency alone: CZK → QR Platba, EUR → EPC QR (SEPA), USD → None (`PaymentInstructions.standard`, ADR 0010), and Issue assigns the VS. The client rule in §2i stays the target. When the pop-up and the VS row are built, the pop-up defaults from the currency and the VS row reads "Assigned at issue" until the client model has those fields.
  - **Keyboard paths that don't depend on Tab.** Whether a default setup (Full Keyboard Access off) skips segmented controls and pop-ups when tabbing is UNVERIFIED; the HIG treats such controls as Full Keyboard Access territory [S17]. So every non-text control above also has a checkmarked Document-menu item and a palette command.
- **Line items** (an editable grid; design-system §8.5):
  - Columns: drag handle (27) · Description · Qty · Unit · Unit price · Discount % · VAT rate · Line total (read-only).
  - Unit is a combo box (ks, hod, den, MD, km, or free text; units print on the document, so they are document text) [S32]. SwiftUI has no combo box, so either wrap `NSComboBox` or use `textInputSuggestions` (macOS 15) [research §18].
  - **VAT rate follows the document treatment** (rule 4): under the Czech treatment it is a text field with suggestions "21", "12" and "0" (no pop-up, so it needs no Tab-to-control). Neither reverse charge nor exempt is offered per line: both are document-level treatments (VAT treatment pop-up, ADR 0009). Under EU reverse charge the column shows "RC" (tooltip "EU reverse charge"; RECOMMENDATION), is locked, and all VAT amounts are hidden. Outside EU and exempt: ACCT. Mixed documents only if the accountant confirms them.
  - Fully empty trailing lines are dropped on save and at issue (all of them, not only the last one); they never count as invalid and never print. The first editor drops only the last one, as ADR 0009 words it (editor design check, E021).
  - Reorder by drag: `reorderable()` + `reorderContainer(for:isEnabled:move:)` are **(27)** [S96]. Otherwise Document ▸ Move Line Up / Down.
- **Notes on PDF** (above and below the lines) sit under a disclosure control.
- **Inspector** (derived information only, design-system §8.12):
  - Rate block (ExchangeRateRow, design-system §8.9): the rate, its own date and its source ("Typed" or "ČNB file"), with **Change…** to type a different rate.
  - VAT recap with CZK.
  - Payment details preview (IBAN, BIC, VS, QR placeholder "QR after issue").
  - The document chain, PDF file, activity.

**Line entry, keyboard first.**

| Key | Effect |
|---|---|
| Typing in Description | Suggests earlier lines with their last unit, price, VAT rate and discount (Fakturoid's price list "našeptává" and Invoiceur's reuse of past items are the model [S104][S135]) |
| Tab | Accepts the suggestion and moves to Qty. Otherwise moves to the next cell (⇧Tab goes back). |
| ↩ in a cell | Commits and moves down to the same column in the next row. On the last row it adds a new line and focuses its Description (RECOMMENDATION, spreadsheet-like). Empty trailing lines are dropped later. |
| ⌘L | Add Line Item |
| Delete a line | Document ▸ Delete Line or the row's context menu, with undo. No key: a grid of text fields has no "row focused" state, and ⌘⌫ stays unbound (§3.1). |
| ⎋ in a field | Revert the field. `onExitCommand` fires on Esc while the view has focus; whether it fires while a text field is being edited is UNVERIFIED, so prototype it and fall back to `onKeyPress(.escape)` or revert on focus loss. |

**Fast entry for dates and amounts.**
- Dates accept "today", "+14", "-1", "14d", "30.11." and "30.11.2026". The resolved date and weekday show next to the field. Things' parser is the model [S127].
- Amounts accept a decimal comma or point and spaces, by the one separator rule in design-system §8.3 (in a comma-grouping locale "1,234" is 1234 and "36,5" is 36.5; rate fields always read "24,315" as 24.315).
- `TextField(value:format:)` leaves the bound value unchanged if parsing fails [S70]. So show an inline error and never lose input.
- When the value commits (per keystroke or on focus loss) is **UNVERIFIED**. The editor must commit on ⌘↩, on selection change and on ⌘W.
- Money is `Decimal`. **One locale rule in both spec files** (design-system §8.2/§8.3): editor **input** uses the **UI locale** and a plain number format (`Decimal.FormatStyle(locale:)`, never `Currency`, so the currency isn't typed twice next to its suffix label); the **preview and PDF** use the PDF locale (Czech formatting in both document languages). The locale is always passed explicitly, because it defaults to `.autoupdatingCurrent` [S71].

**Live preview.**
- Re-render the PDF about 300 ms after typing stops (RECOMMENDATION) and keep the last frame visible to avoid flicker.
- The preview is exactly what will be issued, except for three draft markers (document text, so they keep their Czech): the "KONCEPT / DRAFT" watermark (a fixed mid-grey colour drawn into the PDF, so it survives Dark Mode and printing; design-system §4.1), "Číslo bude přiděleno při vystavení / number assigned at issue" in place of the number, and a "QR po vystavení / QR after issue" placeholder instead of a scannable QR (a draft has no VS yet, so a payment from it couldn't be matched; design-system §8.8). The same applies to Print and Quick Look of a draft. The watermark reads "KONCEPT / DRAFT" on every draft, a Czech-only one included, so anyone who sees a printed draft can tell it apart from a document; the number and QR placeholders, and the QR-unavailable notice, follow the document language (the Czech part alone on a Czech document).

**Autosave and undo.** Every change saves immediately. There is no Save command and no unsaved dot [S43]. Edits can be undone one by one, with named actions [S42].

**Edge cases in the editor.**
- **Changing the currency with lines filled in** shows an inline banner: "Prices were not converted. Convert at 24,315?" with Undo. Fakturoid silently leaves prices unconverted [S104].
- **A DUZP whose rate isn't stored yet.** This is the **common case** for the monthly invoice: the DUZP is the end of the previous month, and the app is offline. In v0.1 it is also the **normal path**, because Sasa types the ČNB rate on the document: "for start everything that nmeeds to be online i willů do manualy, s ill type current cnb rate for each invoice" (Sasa's answer in the proposal doc, 5 Nov 2026).
  - The Overview queue warns from the first of the month ("Month-end rates missing", §2a).
  - The totals bar and the Issue sheet both show the **inline rate form**: "EUR rate for 30. 10. 2026 missing", a rate field with the needed publication date prefilled, ↩ saves (source "Typed"); a secondary **Import ČNB Rates…** button follows (design-system §8.9). The rate also goes into the Rates list (§2g), so the next document with the same rate date picks it up. The form is ExchangeRateRow's missing state (design-system §8.9).
  - The needed publication date is the DUZP itself, or for a weekend or holiday the last publication day before it, labelled (rule 6; §2g). Weekday public holidays resolve the same way through the built-in holiday table (§2g).
  - The sheet is also a **drop target for a ČNB file**, the secondary path (§2g). Either way the sheet re-validates in place and doesn't close.
  - A typed rate dated after the DUZP is blocked, and one more than 7 days older than the DUZP gets the stale-rate warning (§2g).
  - Q7 (a link to the ČNB page in Sasa's browser) is still open; §2g sketches it (RECOMMENDATION).
- **A DUZP in a month already exported to the accountant** requires a checkbox in the review sheet.
- **Changing the type in a draft** is allowed between invoice, advance invoice and final invoice, because no number exists yet; a tax document for a received payment keeps its type (§1.4, ADR 0009). Fakturoid locks the type after creation [S104]; that limitation doesn't apply here.

#### The review-and-issue step

This step is irreversible, so it is designed to be quick in the common case and loud only when something is unusual.

- **Trigger:** ⌘↩, the toolbar **Issue…** button (its ellipsis means a sheet follows [S30]), the readiness chip, or Document ▸ Issue….
- **Sheet** (sized with `presentationSizing(.form)`, macOS 15 [S90]; no fixed width, design-system §5.3). Its contents depend on the document kind (design-system §8.16): an advance shows no DUZP, no rate and no VAT in CZK; a DDPP shows no QR; a final invoice shows the advances deducted.

```
┌──────────────────────────────────────────────────────────────┐
│ Issue invoice FV 2026-0042?                                  │
│ Once issued, the document can't be edited or deleted.        │
│                                                              │
│ Type        Invoice – tax document (Faktura – daňový doklad) │
│ Client      Acme GmbH · VAT ID DE123… · reverse charge       │
│ Language    Czech + English                                  │
│ Dates       Issued 5. 11. 2026 · DUZP 31. 10. 2026 · Due …   │
│ Total       3 142,50 €          VAT  — (daň odvede zákazník) │
│ Rate        24,315 CZK/EUR · for 30. 10. 2026 · Typed        │
│ Payment     RB EUR · IBAN … · EPC QR (SEPA) · VS 120260042   │
│ PDF         ~/Documents/Faktury/2026/FV 2026-0042 Acme.pdf   │
│                                                              │
│ Changes vs FV 2026-0038 (last to Acme)                       │
│  ⚠ Period text changed – check before issuing:               │
│     Line 1: September 2026 → October 2026                    │
│     Line 2: September 2026 → October 2026                    │
│     [✓] Checked   (initial focus; Space)                     │
│  ℹ Rate fallback: DUZP 31. 10. is a Saturday → ČNB 30. 10.   │
│  ℹ DUZP 31. 10. = end of period October 2026                 │
│  ℹ Total +14 % (3 142,50 € vs 2 760,00 €)                    │
│                                                              │
│                                     [Cancel]  [ Issue ]      │
└──────────────────────────────────────────────────────────────┘
```

- **Buttons:** Cancel on the leading side (⎋ or ⌘.). **Issue** on the trailing side as the default button (↩).
  - Issue does not use the destructive style, because Sasa chose the action deliberately [S25].
  - There is never a "don't ask again" option for Issue.
- **Three severities**, so the common case stays at two keystrokes (⌘↩ ↩), or three when a ⚠ row needs its tick (⌘↩ Space ↩):

  | Severity | Examples | Effect |
  |---|---|---|
  | Info (ℹ) | Fallback rate used; DUZP from the period rule; DUZP in a different month from the issue date; total within ±50 % of the client's last invoice; an issue date that is still "on issue" | Shown only. ↩ issues. |
  | Check (⚠) | Period text changed in line descriptions (before → after); VAT treatment or currency differs from the client default; total differs by more than 50 % from the last invoice (the threshold is a setting); DUZP in a month already exported; an issue date **set explicitly** to a day other than today (the row also offers **"Set to today"**, one step); issue date earlier than the last issued document in the same series ("Issue date is earlier than FV 2026-0042"; ⚠ or ⛔ per ACCT); a rate more than 7 days older than the DUZP (InvoicingCore `exchangeRateStale`, §2g) | A **"Checked"** checkbox must be ticked before Issue is enabled. It gets initial focus (`defaultFocus`, macOS 13.0 [S145]), so Space ticks it without Tab. HIG: make the action available only when the requirements are met [S35]. |
  | Blocking (⛔) | Company profile incomplete (IČO, DIČ, address); client address or VAT ID missing for reverse charge; no lines; no rate for the DUZP (shown as the inline rate form: type the rate in place); a rate dated after the DUZP (InvoicingCore `exchangeRateAfterTaxPoint`); no bank account for the currency; numbering series not set up; an advance already deducted in another issued final invoice | Issue is disabled. The default button becomes **"Go to Problem"** and focuses the field. |

- **What Issue does, as one transaction:**
  1. Takes the next number in the series.
  2. Sets the VS, unless the client has a fixed one.
  3. Sets the issue date, if it was still "on issue", to today.
  4. Freezes every field: rate and its date and source; snapshots of the company and client (a later address change never touches an issued document); totals; VAT in CZK; the payments it rests on (§2f).
  5. Renders the PDF and **stores its bytes**.
  6. Writes the PDF to the configured folder. The folder is reached through a security-scoped bookmark: `URL.bookmarkData` exists (macOS 10.10) [S97], and `fileImporter` URLs are security-scoped [S73]. Apple's sandbox guide describes security-scoped bookmarks with the User Selected File (Read/Write) capability and names **no separate bookmark entitlement** [S140].
  7. Logs "Issued FV 2026-0042" in the client's activity.
- **Afterwards:**
  - The detail column (or the document window) switches to the read-only issued view, with the line "Issued FV 2026-0042 · PDF saved · [Show in Finder] [Record Payment]". The HIG asks for confirmation only of significant completions, built into the UI [S39].
  - The undo stack for that document is cleared, so Undo can never reach back past Issue [S42].
  - Nothing to close in the main window. A document window closes with ⌘W.
- **If the folder write fails:** the document *is* issued, because the database is the source of truth. A banner appears: "PDF couldn't be saved to …/Faktury – [Choose Folder…] [Save PDF…]".
- **Two windows issuing at the same time:** numbering is serialised, and the sheet's predicted number refreshes live. If the number changed, the confirmation line shows the number actually assigned.

#### Script: "same invoice as last month for Acme, with new hours"

Assumptions:
- Last invoice FV 2026-0038 (Period September 2026) had line 1 "Software development – September 2026, 32 h × 85 €" and line 2 "Hosting – September 2026, 1 × 40 €".
- The new hours are 36,5.
- Acme's DUZP rule is "last day of the billed period" (ACCT), so Period October 2026 gives DUZP 31. 10. 2026.
- The ČNB rate for 30. 10. 2026 is already in the Rates list, typed on an earlier document or imported (see the variant below if not).
- Focus starts anywhere in the main window.

| # | Keys | What happens | Keystrokes |
|---|---|---|---|
| 1 | ⌘K | The palette opens with its field focused | 1 |
| 2 | a c m | The top row is "Acme GmbH", with its actions named on the right: "↩ Open · ⌘N New Invoice · ⌘D Repeat Last (FV 2026-0038 · 2 760,00 €)" | 3 |
| 3 | ⌘D | The palette's own ⌘D acts on the **highlighted row (Acme)**, never on the main window's selection behind the sheet (§2k): a Draft is created and opens in the main window's detail column. Period becomes October 2026 and the dates follow the rules. "September 2026" becomes "October 2026" at the end of both lines (highlighted). The rate is picked for the DUZP. **Focus lands in line 1 Qty with "32" selected.** | 1 |
| 4 | 3 6 , 5 | The quantity is replaced. The totals bar updates. | 4 |
| 5 | ⌘↩ | The field commits and the review sheet opens: one ⚠ row (the period text, before → after) with the checkbox focused, plus ℹ rows | 1 |
| 6 | Space | Ticks "Checked" after reading the two changed lines | 1 |
| 7 | ↩ | Issued. FV 2026-0042 is assigned, the document locks, and the PDF is saved. The detail shows the issued view; there is no window to close. | 1 |
| | | **Total** | **12** (8 command keys + 4 characters of data), 0 clicks |

- **Variant: the month-end rate is missing** (the common case early in the month, §2c edge cases). At step 5 the sheet shows the inline rate form instead of a dead end, with the rate field focused (a ⛔ row comes before any ⚠ checkbox; RECOMMENDATION). Type the ČNB rate and ↩ (e.g. "24,315" ↩ = +7 K): this is the v0.1 path. Dragging a ČNB file onto the sheet (+1 drag) also works. The sheet re-validates in place.
- If line 2 changes too, add ↩ (move down a row in Qty) plus the new value.
- An alternative start without the palette: ⌘3, type-select "acm" in Clients, then ⌘D. That gives the same count.

### (d) The advance flow: advance invoice → payment → tax document for the received payment → final invoice

**Guiding device: the chain strip.**
- It appears at the top of every document in a chain, in the detail view, the inspector and the editor.
- Each finished step is a `Link` or `Button` drawn with an SF Symbol and the StatusStyle of that step (design-system §4.3), never a typed glyph. The next step is a button. Each step has a full accessibility label, e.g. "Advance ZF 2026-0003, paid". Example (symbols shown as words):

  `[checkmark] Advance ZF 2026-0003 → [checkmark] Payment 12. 11. 2026 → [button] Create Tax Document → [circle] Final invoice`

- The "Open advances" filter and the Overview queue list every chain that has a pending step, except closed advances.

**Advance states** (shown in the Status column; symbols, tones and labels in design-system §4.3):

`Awaiting payment` → `Partly paid – tax document missing` → `Partly paid` → `Paid – tax document missing` → `Tax document issued` → `Settled in final invoice` (detail: FV 2026-0050), or `Closed unpaid` (closed without payment). Each received payment, partial or not, shows "tax document missing" until its DDPP is issued, and that wins over Overdue. When the client's advances need no tax document (Q5, ACCT), a paid advance shows `Paid`. Otherwise an open or partly paid advance past its due date shows Overdue, with the days and the open balance in the detail.

**Closing an advance or a tax document without a credit note** (v0.1; neither action edits the document, each appends a dated event; wording and accounting effect ACCT):
- **Document ▸ Close Advance as Unpaid…** for an issued advance the client will never pay (scope dropped, or the client paid the final invoice directly). A reason is required. The status becomes "Closed unpaid"; the advance leaves Unpaid, Overdue, Open advances and the queue; it stays in the CSV with that status. A credit note is the wrong tool here, because an advance is not a tax document. Closing an advance after a partial payment (the received part keeps its DDPP) is ACCT.
- **Document ▸ Mark for Credit Note…** for a tax document issued by mistake. A reason is required. It stops the Overdue nags, shows a banner on the document ("Marked for credit note – credit notes arrive in Phase 2"), sets a CSV flag, and becomes the entry point for Phase 2 credit notes. The credit note (the corrective document) stays the normal fix for a wrong document; Repair mode (§2m) is the last resort.

**Step 1: create the advance** (⇧⌘N, the palette "advance acme", or the client's New Advance Invoice).
- The editor has the type Advance invoice. A banner in the editor reads "Not a tax document", and the PDF prints the not-a-tax-document clause from design-system §9 (rule 3, ACCT).
- There is no DUZP field and no rate is needed. The tax document later takes the rate for its own DUZP.
- Lines carry the VAT rate that the later tax documents will use. Whether the advance PDF shows a VAT breakdown is ACCT.
- **"When paid, prepare"** pop-up, the same idea as Fakturoid's "S platbou vystavit" [S109]:
  - choices: Tax document draft / Final invoice draft / Nothing
  - default for Czech 21 %: tax document draft
  - default for reverse charge and outside EU: ACCT and Q5
- Issue works exactly as in §2c. The number comes from the advance series, and QR and payment details print as usual.

**Step 2: payment received** (⌘R, or R in a focused list, on the advance, or from the Overview queue).
- This is the Record Payment sheet (§2f).
- After ↩ the sheet shows a success state. Its **default button is "Create Tax Document"** (↩), and **Later** (⎋) puts the chain in the attention queue.
- Each payment gets its own tax document (one per payment; ACCT).

**Step 3: the tax document for the received payment** (a draft opens prefilled):
- Type: Tax document for received payment (PDF title "Daňový doklad k přijaté platbě").
- Client: the same as the advance.
- Reference: "K záloze ZF 2026-0003, platba ze dne 12. 11. 2026" (document text; wording ACCT).
- DUZP: the payment date (ACCT).
- Amount: the amount received (gross). The VAT split is computed at the advance's VAT rate (calculation method ACCT).
- Rate: the ČNB rate for the DUZP, or the last one published before it (rule 6), typed in the editor when the Rates list doesn't have it (§2c). VAT in CZK appears when the document is in EUR or USD (rule 5).
- **No QR** and no payment request, because nothing is payable.
- Issue works as in §2c, with a number from the tax-document series. Its status is "Issued (paid)".
- The deadline for issuing it is ACCT. The app shows an age counter in the queue ("paid 3 days ago") rather than stating a legal deadline.

**Step 4: the final invoice** (Document ▸ Create Final Invoice on the advance, or New ▸ Final Invoice… from the client).
- The lines are copied from the advance and stay editable, because this is a draft.
- An **"Advances deducted"** section (the PDF heading "Odečtené zálohy" is document text, ACCT) lists every paid, unsettled advance for this client in this currency:
  - the originating advance is ticked; the others are offered unticked
  - each row shows the advance number, its tax document number(s), the amount paid, and the VAT already taxed (in CZK at each tax document's rate)
  - the exact layout of the deduction and of the CZK VAT difference is ACCT
- Totals: Total → − advances → **Amount due**.
- If the amount due is 0, the QR is suppressed, and after Issue the status becomes "Paid (by advances)".
- **If the advances exceed the supply (negative amount due), Issue stays available with a warning** (validator `advancesExceedSupply`, ADR 0004): "Advances exceed the invoice – refund or credit note handling is Phase 2 (ACCT)". The QR and the payment request are suppressed, as for a zero amount due (RECOMMENDATION). After Issue the badge follows the settlement the data layer computes; it is not "Paid (by advances)", which needs an amount due of exactly 0.
- An advance can be deducted by **one** issued final invoice only. Fakturoid also allows only one final invoice per advance [S109]. If two drafts deduct the same advance, both show a warning.
- The PDF title in the merged core (`DocumentKind.title`) is "Faktura – daňový doklad (vyúčtování záloh)"; the parenthetical settling wording is ACCT.
- After Issue, each deducted advance becomes "Settled in final invoice", with the final invoice number in the badge detail.
- The final invoice uses the Faktura series by default, with an optional separate series. ACCT, and part of Q2.

### (e) Clients

**Clients list.**
- Layout: sidebar | `Table` | client detail + inspector.
- Type-select on names: typing "acm" jumps to the row. `NSTableView.allowsTypeSelect` is AppKit [S86]; whether SwiftUI `Table` does this by itself is **UNVERIFIED**, so wrap it or implement it with `onKeyPress(characters:)` (macOS 14) [S67].
- Because type-select uses the letter keys, **this list has no single-letter actions** (§3.2).

| Column | Default | Content |
|---|---|---|
| Name | visible | Sorted with `localizedStandard`, so Czech diacritics sort correctly [S59] |
| Country | visible | ISO code |
| VAT ID | visible | — |
| Currency | visible | Default currency |
| Open balance | visible | Per currency |
| Overdue | visible | Amount or "—" |
| Last document | visible | Date |
| Company ID | hidden | IČO |
| Document language | hidden | Czech or Czech + English |
| VAT treatment | hidden | — |

The default sort is Name A–Z.

**Client detail.**
- **Header:** name, address, country. IČO and DIČ/VAT ID are selectable text, so they can be copied (HIG: make useful label text selectable [S56]). Default chips: "EUR · Czech + English · EU reverse charge · EPC QR (SEPA) · 30 days" (Acme's own settings).
- **Tiles:** Open balance, Overdue, Invoiced this year, Last payment.
- **Actions:** New Invoice (⌘N), Repeat Last Invoice "FV 2026-0038" (⌘D), New Advance Invoice (⇧⌘N), Add Note.
- **Tabs:** Documents · Payments · Activity.
  - A tab view in the main area, rather than a segmented control [S33][S50].
  - On 27, `PickerStyle.tabs` gives a segmented look that "distinguishes tab navigation from value selection", and VoiceOver announces the options as tabs [S89].
- **Documents tab:** the same columns as §2b (Status, Number, Type, Issued, Due, Total, Open), newest first.
- **Payments tab:** Date (newest first), Amount, Document, Account, CZK difference.
- **Activity tab:** a timeline, newest first, that mixes:
  - **notes**: manual, dated today by default, date editable; edit and delete are undoable
  - **system events**: "Issued FV …", "Payment 4 840 € received", "Advance settled"
  - At the top sits a composer, "Add a note…". ↩ saves. Typing a newline with ⌥↩ is **UNVERIFIED** for a SwiftUI text field; test it.

**Inspector** (editable):
- legal name, address, country, IČO, DIČ/VAT ID
- the format of IČO and VAT ID is checked inline [S34]; there is no online VIES check, because the app is offline
- defaults (§2c list), contacts (name, role, email, phone, each copyable), internal note
- Contacts never open an email automatically. Mail drafts are Phase 2.

**New Client sheet** (⌥⌘N, File ▸ New Client…, the Clients toolbar, or "New Client “…”…" in a draft's client field; `presentationSizing(.form)` [S90]):
- **Fields:** name (prefilled from what was typed), country (pop-up with type-ahead; no preset, because most clients aren't Czech; RECOMMENDATION), address, IČO, VAT ID / DIČ. IČO and VAT ID get an inline format check [S34]; there is no online VIES check, because the app is offline. An optional "VIES checked on" date field records a manual check (ACCT).
- **Defaults for a new client** (from Sasa's answers in the proposal doc, 5 Nov 2026):
  - VAT treatment: **EU reverse charge**. Sasa: "99% EU-EU". Czech VAT payers and clients outside the EU stay possible per client, through the country rule below or by hand.
  - Payment term: **14 days**. Sasa answered "dunno", so this is the build's default: InvoicingCore `Customer.paymentTermDays` defaults to 14.
  - Currency: EUR, CZK or USD. Sasa: "for start its enough, you can add dollar". It follows the country: CZ → CZK, any other → EUR; USD is picked by hand (RECOMMENDATION). The app sets it explicitly, because the core's own default is CZK.
  - Document language: Czech for a Czech address, Czech + English otherwise (the InvoicingCore `Customer` default).
  - No footer text: none prints until Sasa sets one in Settings ▸ Documents & PDF (§2i).
- **Derived defaults, shown live** under the fields as one line, e.g. "DE + VAT ID → EU reverse charge · EUR · Czech + English · EPC QR (SEPA) · 14 days". Each can be changed later in the inspector.
- **How the country adjusts the VAT treatment** (labels and rules ACCT): CZ → Czech 21 %; another EU country **with** a VAT ID → EU reverse charge; another EU country **without** a VAT ID → Czech 21 % with an inline warning "Reverse charge needs the client's VAT ID"; outside the EU with a VAT ID → Outside EU; outside the EU without one → Czech 21 % (InvoicingCore `CustomerVATStatus.nonEUConsumer`; § 10h is ACCT); Outside EU can still be set by hand.
- **Required:** name and country. Address and VAT ID are not required to save, but a missing one shows as a caution chip in the client picker and blocks Issue where the law needs it (§2c).
- **↩** creates the client. Opened from a draft, it fills the draft's client, applies the defaults and returns focus to the first line's Description; otherwise it selects the new client.

**States.**
- *Empty:* "No clients yet" + New Client.
- A client found with the same IČO or VAT ID: an inline "Possible duplicate: Acme GmbH – open it?".

**Edge cases.**
- A client with issued documents can't be deleted, only **archived**. Issued documents keep their own snapshot of the client.
- Changing a client's country makes a banner suggest the VAT treatment that fits the new country. It changes only future drafts.

### (f) Payments: the record-payment sheet, the list, and bank import (v0.2)

**Record Payment sheet** (⌘R, or R in a focused list; `presentationSizing(.form)` [S90]).

Title: "Record payment – FV 2026-0042 · Acme GmbH".

| Field | Default | Notes |
|---|---|---|
| Payment date | **the last payment date entered in this session**, else today | Sasa records most payments from a monthly statement, so they are almost always in the past. The field shows the weekday and the rate date next to it ("Thu 29. 10. · ČNB rate 29. 10."). Accepts "-1", "today", "30.10."; a future date is blocked. |
| Amount | the open balance | iDoklad's *Uhradit* defaults the date to today, and Fakturoid's *Spárovat* prefills the amount [S114][S108] |
| Account | the default account for the document currency | Choosing an account in another currency switches the amount to two fields (below) |
| Currency | the account's currency | Shown next to the amount; it follows the account |
| Note | empty | — |

**Account currency ≠ document currency** (e.g. a EUR invoice paid into the CZK account; ACCT for the accounting): the single Amount becomes two fields, and both amounts are stored:
- "Credited to account", in the account currency (what the bank credited)
- "Settles on the document", in the document currency, prefilled at the ČNB rate for the payment date and editable
- the implied rate is shown ("= 24,402 Kč/€"); the outcome line and the CZK difference are computed from these two numbers.

Computed lines, live:
- For EUR documents: "Document rate 24,315 (ČNB 30. 10., last published) · Rate for payment date 24,402 (ČNB 13. 11.) · **CZK difference +421,08 Kč**". Rates always show their own publication date, never the DUZP (rule 6).
  - The payment-date rate follows the same "that day or the last one published before it" rule (ACCT).
  - The accounting treatment is ACCT.
  - If that rate is missing, show the inline rate form "EUR rate for 16. 11. missing" (as in §2c; typing it is the v0.1 path). The payment can still be saved, and the difference shows as "pending".
- **Outcome**, one of:
  - "Document will be: Paid". Within the **payment tolerance** (one setting in Settings ▸ Documents & PDF, shared with v0.2 matching: CZK ±1 Kč, EUR and USD to be agreed, ACCT) the line reads "Paid (0,01 € difference rounded off)", so a rounding cent never leaves a document Partly paid or Overpaid forever.
  - "Partly paid – 1 000,00 € left"
  - "Overpaid by 50,00 € – kept as client credit". Overpaid is iDoklad's "Přeplaceno" [S113].

Buttons: Cancel (⎋) / **Record** (↩). An advance then gets the follow-up step from §2d.

**Resolving an overpayment** (v0.1; accounting treatment ACCT). An overpaid document offers, in the Document menu, its context menu and its Payments tab:
- **"Apply Credit To…"**: pick another open document of the same client and currency; the app records a credit-source payment on it and reduces the surplus.
- **"Record Refund…"**: a negative (outgoing) payment with date and account.

Edge cases:
- **Payment dated before the issue date:** a warning.
- **Same document, amount and date as an existing payment:** "Possible duplicate".
- **Payment on a draft:** not possible ("Issue first").
- **A tax document for a received payment:** it is already paid by definition, so there is no Record Payment action.
- **A payment that an issued document rests on is locked.** That means a payment from which an issued DDPP was created, or one that let an issued final invoice deduct an advance. Delete, Unmatch (v0.2) and changes to amount or date are blocked; only the note can change. The sheet and the payment row show inline: "Payment is the basis of DD 2026-0003 – can't be deleted" with a **"Show Document"** link. Undo can't help here, because the undo stack is gone after relaunch.
- **A payment only drafts depend on:** delete is allowed with a warning ("2 drafts are based on this payment"), and those drafts are flagged.
- **Any other manual payment:** delete is possible, with undo.
- **A payment linked to a bank line (v0.2):** can only be unmatched, not deleted, and the lock above applies to Unmatch too.

**Payments list** (sidebar ▸ Payments & Bank ▸ All payments):
- Columns: Date (default sort, newest first) · Client · Document(s) · Amount · Currency · Account · CZK difference · Source (Manual / Confirmed by statement / Statement / Credit) · Note. A locked payment shows `lock.fill` beside the amount.
- **Data model from day one (v0.1):** every payment stores a `source` (manual, statement, credit, refund) and an optional `bankLineID`, so v0.2 can link statement lines to payments already recorded by hand.
- Filters: This month · per account · (v0.2) Unassigned.
- Single keys: ↩ opens the document, Space previews it, ⌫ deletes a manual payment that nothing issued rests on (undoable).

**Bank statement import (v0.2).**
- Raiffeisenbank formats, UNVERIFIED (from the build thread's reading of the bank's internet-banking manual, not confirmed on any page and not in the source list): PDF statements are free. The data formats are a paid service that has to be activated: RB XML (not camt.053), ABO (`*.GPC`) and Gemini (`*.ACE`). The free and paid status and the format names are UNVERIFIED. Several statements can arrive as one ZIP. The parser handles ABO first. The UI below works for any parsed format.

1. **Drop the file** on the window, on the Payments & Bank section or on an account row (`dropDestination(for:isEnabled:action:)`, macOS 26 [S72]). File ▸ Import Bank Statement… does the same through `fileImporter` with the ABO, XML, ZIP and PDF types [S73].
   - Highlight a drop target only when it can accept the file [S36].
2. **Preview sheet.**
   - It shows: file name and checksum (the file is stored untouched); detected format; the detected account, matched by IBAN to Settings ▸ Bank accounts, or **"Assign to account…"** if unknown; the period; opening and closing balance; "42 transactions · 30 new · 12 already imported (skipped)".
   - PDF statements are stored. Whether their transactions can be parsed depends on the build thread; until then show "Stored – transactions can't be read from this PDF yet; match manually or import an ABO/XML statement".
   - **Import** (↩) opens the triage window.
   - **Ask Sasa now (Q8):** is the paid data-format service active on the account, and what does it cost? Once it is, the import sheet gains a short "how to download the statement as ABO" step.

   **PDF fallback: "match manually"** (the real path while Sasa only has PDFs). The triage window shows the stored statement in a `PDFView` [S78] on one side and the list of open documents on the other. Search finds documents by VS, number, client or amount (⌘F); R or ⌘R records a payment on the selected document with the Record Payment sheet, whose date and amount Sasa copies from the statement. The statement stays attached as the payment's source file.
3. **Triage window** "Statement 10/2026 · RB EUR".
   - It is **one queue** grouped into lanes, so triage is a straight run down the list with ↓.
   - A tabs filter at the top (All / Already recorded / Matched / Suggested / Unmatched / Outgoing) is there for the mouse.

   | Lane | What lands there | Default |
   |---|---|---|
   | **Already recorded** (checked first) | The line matches a payment Sasa already recorded by hand: same document or VS, same amount, date within ±N days (a setting), same account | Pre-ticked. Accepting **links** the line to that payment (its source changes from Manual to "Confirmed by statement") instead of creating a second payment. Included in the bulk accept. |
   | **Matched** | VS + amount + currency match within the payment tolerance (the one shared setting, §2f Record Payment). Fakturoid allows up to 1.99 Kč and iDoklad under 1 Kč [S107][S115]. | Pre-ticked. Accepted in bulk with the prominent toolbar item **"Accept Exact Matches (N)"**, Bank ▸ Accept Exact Matches, or the palette (one placement in the window, one label). A Xero product idea for bulk OK has 248 votes and is marked "In development" [S120]. |
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
- A EUR document paid into the CZK account gets a suggestion with a warning, and accepting it opens the two-amount form (§2f Record Payment).
- Outgoing refunds to clients are offered as matches to overpaid documents (they become the "Record Refund" payment).
- Unmatch is blocked for a payment that an issued document rests on (§2f edge cases).

**Monthly cash view per account (v0.2):** sidebar account row ▸ a table per month with opening balance, incoming, outgoing by category and closing balance. Clicking a month filters that account's lines.

### (g) Exchange rates

**In v0.1 Sasa types the rates.** Sasa's answer: "for start everything that nmeeds to be online i willů do manualy, s ill type current cnb rate for each invoice" (proposal doc, 5 Nov 2026).
- The **primary path** is the inline rate form on the document in the draft editor (§2c). Sasa types the ČNB rate for the DUZP, or for a weekend or holiday the last published rate (the resolver below).
- Every typed rate is also saved in this section's list, so the next document with the same rate date picks it up.
- The **ČNB file import stays as a secondary action** here. It is already built: InvoicingData `RateStore.importDaily` ("denni_kurz.txt") and `RateStore.importYearly` ("rok.txt"), both parsed by InvoicingCore `CNBRateFile`. The app shell's Rates view (build thread) has the file importer and a coverage view.

**Layout.** Sidebar | rates `Table` | coverage panel. The toolbar is the "Exchange rates" row of design-system §8.11: **Add Rate…** (typing) and **Import ČNB Rates…** (a ČNB file).

**Rates list.** Typed and imported rates sit in one table. Default sort: Date, newest first.

| Column | Content |
|---|---|
| Date | The day the rate was published for: its own date, never the DUZP |
| Rate | "1 EUR = 24,315 Kč" |
| Source | **"Typed"** or **"ČNB file"**. A typed rate is stored as InvoicingCore `ExchangeRateSource.manual`, an imported one as `.cnb`. |
| Added | When it was typed or imported |
| Used by | Number of documents |

The currency pop-up defaults to EUR; USD is the other foreign currency in v0.1. Other currencies in an imported file are stored for the Phase 2 "more currencies" work.

**Typing a rate** (the v0.1 path):
- **Where:** the inline rate form in the editor's totals bar and in the Issue sheet (§2c), the Record Payment sheet (§2f), Document ▸ Enter Rate…, the Overview queue's **Enter Rate…** (§2a), **Enter Rate…** beside each date in "Needed rates" (below), and **Add Rate…** in the toolbar.
- **Rate sheet.** Outside a draft (Add Rate…, the Overview queue, Needed rates), the fields below open in a small rate sheet (`presentationSizing(.form)` [S90]).
- **Fields:** date, currency, amount (1), rate. From a document or the queue, the date and currency are prefilled with the rate date that is needed. ↩ saves.
- **Source:** "Typed".
- **A rate dated after the DUZP is blocked** (InvoicingCore `DocumentValidator`, `exchangeRateAfterTaxPoint`).
- **Stale-rate warning.** A rate more than 7 days older than the DUZP gives a ⚠ Check row in the Issue sheet (§2c). The core's text: "The exchange rate is from {detail}, more than a week before the date of supply; check that the rate table is complete." (InvoicingCore `exchangeRateStale`, `exchangeRateStaleAfterDays` = 7.)
- **Optional link (RECOMMENDATION; still open as Q7).** The inline rate form may show **Open ČNB Rates Page**, which opens the ČNB rates page in Sasa's own browser. SwiftUI `Link` (macOS 11.0) opens a URL "in the user's default web browser" when no app claims it [S155]. The app itself still makes no network call (rule 7). That a sandboxed app without network entitlements can open the link is UNVERIFIED; test it in the sandboxed build. The build thread picks the page address.
- **A typed and an imported rate for the same day.** The import preview lists the day as a conflict and offers to keep the typed value or take the imported one. Drafts follow the choice. Issued documents never change, because they store their own copy. The data layer keeps one row per currency and day (`RateStore.save`: "Inserts or replaces"), so keeping the typed value means skipping that day in the import (build thread).

**Coverage panel** (detail column).
- A month grid with one mark per day, each drawn as an SF Symbol plus the day number, never as a typed glyph. Each cell has a VoiceOver label, e.g. "4. 11. 2026, rate published, 24,315" or "2. 11. 2026, rate missing, needed by a draft":
  - a rate is stored (typed or imported): `checkmark.circle.fill`
  - non-publication day (uses the rate of dd.mm.; when ČNB publishes is UNVERIFIED, see the resolver below): `circle`
  - missing and needed: `exclamationmark.circle.fill` in the caution tone, plus the word "missing" in the cell's tooltip
  - future: no mark
- Below it, always as text, **"Needed rates"**: every date a draft or payment needs but the data doesn't cover. Each has **Enter Rate…**. This list, not the grid, is the primary way to see what is missing.

**Importing a ČNB file** (secondary).
- Drop a ČNB daily or yearly `.txt` anywhere on the window (`dropDestination`, macOS 26 [S72]), or use File ▸ Import ČNB Rates… or the toolbar's Import ČNB Rates… (`fileImporter` with `.plainText` [S73]).
- A TipKit tip shown once: "Drop a ČNB rates file here" [S87][S41].
- **The preview sheet** reads "Year 2026 · 214 days · 2. 1.–4. 11. 2026 · 2 new days · 0 changed" and lists any value conflicts, typed rates included. **Import** (↩).
- Import can be undone ("Undo Import ČNB Rates") [S42].
- If the file can't be parsed, show inline "This doesn't look like a ČNB rates file" with the line number where parsing stopped (`CNBRateFile.ParseError.malformedLine` carries it). Never a half-import.

**How the rate for a date is resolved** (rule 6; **ACCT: which ČNB rate legally applies to DUZP D**, that day's rate or the previous publication day's depending on publication time, is UNVERIFIED and goes to the accountant). The resolver is **one unit-tested function**, and the inline rate form uses it to prefill the date it asks for. Typed rates are sparse, so a typed rate covers only its own day; an imported file covers its whole span.
1. The date has a stored row (typed or imported): use it.
2. The date is inside an imported file's span but has no row: treat it as a non-publication day (a weekend or holiday). That ČNB publishes only on working days is UNVERIFIED (ACCT: confirm against the ČNB publication calendar, then add an [S#]). Use the last earlier row and label it "last published rate, dd.mm.".
3. Any other date:
   - A Saturday or Sunday resolves to the Friday before it, if that Friday has a row.
   - A **Czech public holiday** on a weekday resolves the same way, to the last working day before it, using a small built-in table of Czech public holidays taken from an official calendar (RECOMMENDATION; the table needs a yearly check). Without it, the label "last published rate (weekend/holiday)" could never appear after a holiday.
   - Otherwise the rate is **missing**, and the inline rate form asks for it: for a weekday, that day's rate; for a weekend or holiday, the last working day's rate.
- The data layer's `RateStore.rate(for:on:lookup:)` defaults to `.lastPublishedOnOrBefore`: the last rate on or before the day. With sparse typed rates that rate can be weeks old, so the resolver adds the rules above, and the 7-day stale-rate warning catches the rest.

**Edge cases.**
- Rates used by issued documents can be corrected in the table, but that never affects those documents. Show "used by 3 issued documents (unchanged)".

### (h) Exports & Backup

The section shows two cards. The data is local, so both should be instant, with determinate progress and Cancel for anything slow [S38].

**Export for Accountant.**
- Month picker; the default is the previous month.
- **Which documents belong to the month:** tax documents by **DUZP** (ACCT); advances (no DUZP) by issue date, flagged as non-tax. Payments by payment date.
- Checkboxes: Issued documents CSV ✓ · Payments CSV ✓ · PDFs of the month to a folder (default as agreed with the accountant, ACCT).
- **Preset:** "For the accountant (Excel CZ)" or "Machine (ISO)". The delimiter, decimal mark and encoding of the Excel preset are agreed with the accountant (ACCT); whether their Excel reads ISO dates and "." decimals as numbers is UNVERIFIED and depends on their tool (design-system §9).
- Preview line: "October 2026: 14 documents (2 advances, non-tax) · 9 payments · VAT 42 180 Kč" (VAT per the §2a aggregation rules).
- The default button **"Export October 2026…"** (↩) opens a save panel in the last export folder (`fileDialogDefaultDirectory`, macOS 14 [research §25]). Saving with ↩ finishes.
- A checkbox **"Also back up now"** is on by default.
- **Export history** (detail column): month · exported on · preset · file. A document issued later into an already exported month marks the row **"Changed after export: 1 document"** with an **"Export Again"** button. The closed-month warning in the review sheet reads the same history.
- **CSV columns** (fixed set, so the column count never varies; final names, delimiter and encoding ACCT):
  - Number, Type, **Daňový doklad (ano/ne)**, Issue date, DUZP, Due date, Status
  - Client name, IČO, VAT ID, Country, VAT treatment
  - Currency, Total; per rate, each in the document currency **and** in CZK: Base21, VAT21, Base12, VAT12, Base0, BaseExempt, BaseRC. Advance rows never fill the VAT columns.
  - Rate, RateDate, RateSource, **RateIsFallback**
  - **RelatedDocs** (DDPP → its advance; final invoice → the advances and DDPPs it deducts), **DeductedAdvance**, **DeductedVAT_CZK**
  - Paid amount, Paid date, Closing event (closed unpaid / marked for credit note)

**Backup.**
- **Back Up Now** (one click). Shows "Last backup: today 9:02 · ~/Backups/FA" (path control [S49]).
- What's included: the database (with the audit log, §2m), the stored issued PDFs, the logo, and (v0.2) the stored statement files.
- **Restore from Backup…:**
  1. Pick a file.
  2. A preview: backup date, counts, app version.
  3. An **alert**: "Replace current data with the backup from 3. 11. 2026?". Informative text: "Current data will be saved as a backup first." Buttons Cancel / **Restore**.
  - Restoring is an uncommon action that can't be undone, so an alert is right [S25].
  - Determinate progress follows.

**Naming note.** In Czech, "záloha" means both an *advance* and a *backup*. The English UI keeps the two apart ("Advance", "Backup"), so the clash can't reach the app.
- Palette results always carry a type label.

### (i) Settings panes

All panes follow the HIG Settings rules [S29]:
- Good defaults.
- No setting that duplicates a system setting.
- No Light/Dark switch [S15].
- Labels end with a colon. (This comes from the HIG Combo boxes page, "end them with a colon" [S32], and the Boxes page, which appends a colon to a box title in a settings pane [S151]; it is not on the Settings page.)
- `Form` with `.formStyle(.grouped)` [S1].

**General**
- **No app-language setting.** The UI is English only (How to read this), so the app has no language switch. Whether macOS's per-app language setting [S9] would pick up the bonus Czech entries in `DesignSystem.xcstrings` is UNVERIFIED; that mixed UI is out of scope and not designed.
- Default document language for new clients: **By address** (the default: Czech for a Czech address, Czech + English otherwise, as the InvoicingCore `Customer` default does) / Czech / Czech + English.
- PDF folder (path control [S49]).
- On launch: "Restore last view" (default) [S27].

**Company**
- Legal name, registered office, IČO, DIČ, spisová značka, phone and email (printed if filled).
- Logo: an image well that accepts drop and paste and reverts to none when cleared [S48].
- Inline validation of IČO and DIČ format [S34].
- Changes apply only to future issues. Issued documents keep their snapshot, and the pane says so.

**Bank accounts**
- List and form: name ("RB EUR"), currency (EUR, CZK or USD), IBAN (checksum validated), BIC, Czech account number + bank code (CZK), "default for this currency", "print on documents".
- An account used by issued documents can only be archived.

**Numbering**
- One row per series: Invoice (final invoices included by default, ACCT), Advance invoice, Tax document for received payment.
  - Each row has: name, pattern with tokens (`{YYYY}`, `{NNNN}`) and a live preview, **next number**, and the yearly-restart policy (ACCT).
- **The next number is editable only until the first document of that series is issued in the app.** After that it is read-only, because the series must stay gapless.
- **VS rule.** By default the VS is the digits of the number, at most 10 digits (Fakturoid's derivation [S106]), plus a series prefix so that two series never produce the same VS.
  - Example: FV 2026-0042 and ZF 2026-0042 would both become 20260042. The default prefixes are therefore FV 1 and ZF 2, and none for DD, which carries no payment request: FV 2026-0042 → 120260042. The user can change them per series.
  - The core applies the prefix within the 10-digit limit, keeping the prefix. The per-series prefix lands with the build's next data-layer PR, with an ADR 0003 addendum.
  - The pane blocks patterns whose VS could collide.
  - A VS that is unique across series matters for v0.2 auto-matching, which uses VS + amount (Fakturoid and iDoklad both match this way [S107][S115]).

**Documents & PDF**
- Default due days: **14** for a new client. InvoicingCore `Customer.paymentTermDays` defaults to 14. Sasa answered "dunno" on payment terms (proposal doc, 5 Nov 2026), so this is the build's default. Each client can change it (§2e).
- Footer text (multi-line, document text): one for Czech documents and one for Czech + English documents. **Empty by default:** no footer prints until Sasa sets one.
- File-name pattern with a preview ("{number} {client}.pdf"), plus an optional subfolder per year.
- "Save PDF automatically when issuing" (on).
- **Payment tolerance** (one setting for Record Payment and v0.2 matching): CZK ±1 Kč; EUR and USD to be agreed (ACCT).
- **QR defaults:** Czech client + CZK → QR Platba; EU client + EUR → EPC QR; otherwise none, so a USD document has no QR. It is overridable per client. Fakturoid prints no QR for clients outside CZ and SK [S110], which is exactly the gap for Sasa's EU clients.
- QR presentation (size, error correction M, a plain-text block beside it) belongs to the PDF spec [S117][S118].
- The draft watermark is always on (not a setting).

**VAT defaults**
- Rates 21 / 12 / 0, plus the treatments Czech 21 %, EU reverse charge, Outside EU and Exempt. Each has a one-line description of what it changes on the document.
- The reverse-charge clause is fixed as "daň odvede zákazník" (document text). The English text is ACCT. The texts for outside EU and exempt are ACCT.
- **Default treatment for a new client: EU reverse charge.** Sasa: "99% EU-EU" (proposal doc, 5 Nov 2026). The client's country then adjusts it (ACCT): CZ → Czech 21 %; another EU country with a VAT ID → EU reverse charge; another EU country without a VAT ID → Czech 21 % with an inline warning; outside the EU with a VAT ID → Outside EU; outside the EU without one → Czech 21 % (InvoicingCore `CustomerVATStatus.nonEUConsumer`; § 10h is ACCT); Outside EU can still be set by hand. The New Client sheet shows the result live (§2e).
- Rate changes over time (a new rate from a given date) are out of scope for v0.1 and flagged for later.

**Backup**
- Backup folder (path control).
- Automatic backup: daily on the first launch of the day, and on quit (RECOMMENDATION).
- Keep the last 30.
- Remind when the last backup is more than 7 days old (this feeds the Overview queue).
- Back Up Now · Restore….

### (j) First-run onboarding

Principles:
- Onboarding is "fast, fun, and optional".
- Non-essential setup is postponed.
- There is no licence text, and no tutorial is ever shown again [S40].
- No alert at launch [S25].
- **No import step.** Sasa's current tool is a "poverty self made unsuccesful local app" (Sasa's answer in the proposal doc, 5 Nov 2026), so there is nothing to import. Setup only asks for the last numbers issued (step 3).

1. **The first launch opens the main window on Overview.** Instead of empty tiles it shows a **"Getting started"** card with a checklist. Each item opens the relevant Settings pane (`openSettings`, macOS 14 [S76]) or a small sheet, and gets a ✓ when done:
   1. **Company profile** (required to issue).
   2. **Bank accounts** (required for payment details and QR): one for each currency Sasa uses, from EUR, CZK and USD.
   3. **Continue your number series** (required).
      - For each series, Sasa types the *last number issued in the previous tool*, e.g. "2026-0041".
      - The app infers the pattern and shows "Next number: 2026-0042 – assigned when you issue".
      - "Start from 1" is the alternative.
      - The VS preview and collision check are shown inline.
   4. **First client / first invoice** (optional): buttons. There is no rates step: Sasa types the ČNB rate on the first EUR or USD invoice (§2c). Importing a ČNB file stays possible in Exchange rates (§2g).
   - A link at the top, **"Moving from another Mac? Restore from Backup…"**.
2. The checklist hides once the required items are done, and Help ▸ Getting Started reopens it.
3. **Nothing blocks exploring.** If Sasa presses Issue before setup is finished, the review sheet lists the missing items as ⛔ with **"Fill in…"**.
4. Edge case: entering a last number lower than the previous tool's real last number would create duplicates. The step asks for a check: "Is 2026-0041 the last number you issued in 2026?".

### (k) Command palette (⌘K): recommendation **for** v0.1, with a tight scope

**Why ship it in v0.1.**
- The Czech tools Sasa could compare against added exactly this in 2026: Fakturoid's ⌘K navigation palette (June 2026) and iÚčto's ⌘K, which "jumps to any section or runs an action" (August 2026) [S103][S116].
- The keyboard-first apps that showed the pattern list each command's shortcut beside it, so people learn the shortcuts along the way [S131][S133].
- It enables the 12-keystroke repeat-invoice script and most of the budgets in §4.
- **It is cheap if built right.** One command registry produces both the menu bar and the palette. The palette therefore can't drift from the menus, which must still list every command [S18].

**Risks and mitigations.**
- *It replaces menus:* never. Every palette command is also a menu item.
- *Mouse users miss it:* the toolbar and menus stay complete.
- *Effort:* it is limited to records and commands; there is no natural language (that is Phase 3 AI).

**Scope v0.1.**
1. All menu commands. Disabled commands show the reason dimmed ("Issue… – no draft selected").
2. Jump to clients and documents: by number, VS, amount, client name, IČO or VAT ID.
3. Per-client actions:
   - New Invoice (⌘N)
   - Repeat Last Invoice (⌘D)
   - New Advance Invoice (⇧⌘N)
   - Add Note
   - Record Payment on the oldest open document
4. When the palette opens with a document selected, that document's actions come first. ↩ runs the top one, as in Raycast [S131].
5. Sections and Settings panes.
6. An empty query shows recent items.

**Behaviour.**
- A sheet 560 pt wide (`presentationSizing(.fitted)` with a fixed frame width, design-system §5.3) with its text field focused.
- Results are grouped: Actions for the selection / Clients / Documents / Commands. The shortcut sits on the right, and each row names its actions.
- ↑↓ moves, ↩ runs, ⎋ closes.
- **Row actions with ⌘N / ⌘D act on the highlighted row, never on the main window's selection behind the sheet.** The palette declares its own buttons for these chords inside the sheet. The documented resolution order is "the key window first, then the main window, and then the command groups" [S147], so the palette's buttons should win over the File-menu commands (UNVERIFIED for a sheet; test it). As a second guard, the selection-based menu commands are disabled while the palette is open.
  - **Acceptance test:** palette open, main-window selection on another client's invoice, type "acm", press ⌘D → the app must duplicate **Acme's** last invoice.
- Matching is diacritic-insensitive, so Czech client names and line texts match when typed without accents. Each result carries its type label.
- Ranking: an exact number first, then a client-name prefix, then commands, with a boost for recent use.
- `presentationPlacement(.center)` is **(27)**; `PresentationPlacement` has `.automatic`, `.center`, `.leading` and `.trailing`, and "only sheet presentations respect this placement" [S146]. How `.center` renders on a Mac is **UNVERIFIED**. Below macOS 27 (the gated fallback while the target is 14.0, §0.1): default placement.
- The palette must not override ⌘K inside text views. The app has no rich text, and in Apple's text editing ⌘K is "Add a web link" [S8].

**Phase 3:** the optional on-device AI assistant lives here ("Describe an invoice…"). It only ever creates a **Draft**. It never issues and never sends.

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
   - Status, totals, open balance, payments and the chain strip.
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
- File ▸ **Repair Mode…** (§1.4), and the same command in the palette (§2k). No shortcut (§3.1).
- It is an ordinary, visible menu command, because every command is in the menu bar (§0.1). The protection is the authentication, not hiding.
- A sheet opens first (`presentationSizing(.form)` [S90]):
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

**What unlocks.** Every record, issued documents included: header fields, lines, dates, the client snapshot, payments an issued document rests on, advance deductions, closing events and rates. Edits and deletes both become possible.
- A change that breaks a rule the app otherwise enforces shows an inline ⚠ next to the field before it saves: a gap or a duplicate in a number series, a VS that collides, totals that no longer match the stored PDF, a payment that no longer covers its tax document. The legal side of each is ACCT.
- A changed issued document gets a new PDF rendered from the repaired data. The previous PDF bytes stay with the audit event and are never deleted (RECOMMENDATION). Whether the client needs the new PDF, or a corrective document instead, is ACCT.
- **The audit log never unlocks.** It stays append-only; the data layer already enforces that with triggers. The issued-document locks are triggers too, so Repair mode needs a data-layer design from the build thread: each repair change and its audit event in one transaction.

**How the window shows the mode.**
- A persistent banner across the top of every window's content (the main window and any document windows): "Repair mode is on. Every change to a locked record is logged." with the button **End Repair Mode**. It uses a symbol and the caution tone, never colour alone (design-system §4.4; [S13]).
- The window title area is marked: the subtitle starts with "Repair mode" (`navigationSubtitle` [S100]), e.g. "Repair mode · Overdue · 3".
- Fields of issued documents become editable. The lock line on an issued document reads "Repair mode: changes are logged".
- File ▸ Repair Mode… reads **End Repair Mode** while the mode is on.
- The banner never hides on a timer (§0.1, principle 7).

**Every change is logged.**
- Each change to a record that is normally locked writes one audit event: the record, the field, the old and the new value, the time, and a **reason**.
- The reason field sits inline next to the change, prefilled with the reason from the entry sheet. Sasa can overwrite it for that change. ↩ saves the change and its reason together (RECOMMENDATION).
- If the audit event can't be written, the change isn't saved (one transaction, as above).
- Undo works inside Repair mode, change by change, with named actions [S42]. An undo is itself a logged change (RECOMMENDATION).
- Repair events show in the document's and the client's Activity (§2e) with a "Repair" label and the reason (RECOMMENDATION).

**Ending the mode.**
- The banner's **End Repair Mode**, or File ▸ End Repair Mode.
- Quitting the app. The next launch always starts locked; restoring the previous state [S27] never brings the mode back.
- A timeout (RECOMMENDATION): 10 minutes without a change ends the mode. The banner then reads "Repair mode ended after 10 minutes without changes" and stays until Sasa closes it, so nothing changes silently.
- When the mode ends, an inline result line reads "Repair mode ended · 3 changes logged · Show Log" (design-system §8.17). Show Log lists that session's audit events, read-only: record, field, old → new, time, reason.

**What it never does.**
- **No trace-free change.** There is no setting, key, gesture or hidden command that changes a record without an audit event.
- It never edits or deletes the audit log.
- **No change leaves the Mac.** Repair mode sends nothing and makes no network call (rule 7). The audit log is never exported or shared: it is not in the accountant's CSV (§2h), the iPhone snapshot (§2l) or any share sheet.
- It isn't available on the iPhone.
- It isn't the normal fix for a wrong document: that stays the credit note (Phase 2).

**Open points for Sasa.**
- **Backups.** A backup holds the whole database, audit log included, so a restore keeps the log (§2h). Sasa mentions "using mainly 8tb cloud". A backup folder in a cloud-synced location would copy the audit log off the Mac. That conflicts with the decision ("which never leaves the Mac"). The lead and Sasa decide how backups and a cloud-synced folder fit the decision. This spec makes no recommendation until then.
- **Apple Watch.** `deviceOwnerAuthentication` accepts a nearby paired Apple Watch [S153], but the decision names only Touch ID and the password. Confirm with Sasa that a watch unlock is acceptable (design-system §8.18).

---

## 3. Keyboard shortcut map

### 3.1 Complete table

**This is the one authoritative keyboard map for the app.** design-system §8.11a only points here.

Each entry was checked against:
- **A:** Apple's HIG table of standard macOS shortcuts [S17]
- **B:** Apple Support "Mac keyboard shortcuts" (published 14 Sep 2026) [S8]
- **C:** system-reserved keys (Control-F-keys, Spotlight, screenshots and the others listed in research §8)

| Keys | Command | Scope | A: HIG standard | B: Apple Support | Verdict |
|---|---|---|---|---|---|
| ⌘, | Settings… | global | Open settings | — | ✅ standard |
| ⌘H / ⌥⌘H / ⌘Q | Hide / Hide Others / Quit | global | standard | — | ✅ standard |
| ⌘N | New Invoice (prefills the client in client context) | global | "Open a new document" | — | ✅ standard meaning |
| ⇧⌘N | New Advance Invoice | global | not listed | Finder: new folder (Finder only) | ✅ OK. Shift as a secondary modifier "that complements a related shortcut" [S17]. DDPPs and final invoices come from the chain, not from a shortcut. |
| ⌥⌘N | New Client… | global | not listed | Finder: new Smart Folder (Finder only) | ⚠ OK but low frequency; Option is "sparingly" [S17]. Still related to ⌘N (both create something). |
| — | Add Note… | client context | — | — | No shortcut on purpose: the HIG warns against "adding a modifier to an existing shortcut for an unrelated command" [S17]. Client menu, composer, palette. |
| ⌘D | Duplicate as Draft / Repeat Last Invoice (client context) | global | not listed. ⇧⌘S = "Duplicate the active document" | Finder: "Duplicate the selected files"; in Open/Save dialogs, Desktop | ✅ Matches Finder's meaning. Inside Open/Save panels ⌘D selects the Desktop [S8]; that the panel takes it before our menu item does is UNVERIFIED, so test it. ⇧⌘S stays unbound rather than reused. |
| ⌘↩ | Issue… | draft focused | not listed | not listed | ⚠ No conflict found. **Test** that text fields don't swallow it (UNVERIFIED). |
| ⌘R | Record Payment… (R in a focused list) | issued document selected | not listed | Finder: show original; "in some apps … refresh or reload" | ✅ The app has nothing to reload |
| ⌘L | Add Line Item | editor | not listed | not listed (⌥⌘L is Finder Downloads) | ✅ |
| — | Delete Line · Move Line Up / Down | editor | — | ⌘⌫ = "Move the selected item to the Trash" [S8] | **No shortcut in v0.1.** Document menu and the row's context menu; drag on 27. A menu key equivalent like ⌘⌫ would fire even while a cell's text field is being edited, and what ⌘⌫ does inside a text field is UNVERIFIED (test it). |
| — | Repair Mode… / End Repair Mode (v0.1.x) | global | — | — | **No shortcut** on purpose (RECOMMENDATION): it unlocks every record, so no stray chord should start it. File menu and palette only (§2m). |
| ⌘K | Command Palette… | global | not listed | Finder: Connect to Server; text editing: "Add a web link" | ✅ No rich-text fields in the app. Revisit if any are added. |
| ⌘Y | Quick Look | list or preview | not listed | Finder: Quick Look | ✅ The same meaning as Finder |
| ⌘P | Print… | document selected | Print | — | ✅ standard |
| ⌘W / ⌥⌘W | Close / Close All | window | standard | — | ✅ |
| ⌘M / ⌥⌘M | Minimize / Minimize All | window | standard | — | ✅ |
| ⌘Z / ⇧⌘Z | Undo / Redo | global | standard | — | ✅ |
| ⌘X ⌘C ⌘V ⌥⇧⌘V ⌘A | Cut / Copy / Paste / Paste and Match Style / Select All | global | standard | — | ✅ |
| ⇧⌘A | Deselect All | lists | standard | — | ✅ Reserved; "Accept Exact Matches" deliberately does **not** use it |
| ⌫ (⌦) | Delete (draft, note, unlocked manual payment) | focused list | standard Delete item | ⌘⌫ = Move to Trash in Finder [S8] | ✅ Through `onDeleteCommand` [S68]. ⌘⌫ is left unbound. Not for line items (no row-focus state in a grid of text fields). |
| ⌘F / ⌥⌘F | Search… / Jump to Search Field | global | "Open a Find window" / "Jump to the search field control" | — | ✅ The closest equivalent |
| ⌘1…⌘6 | Sections | main window | not listed | Finder: view modes ⌘1–⌘4 (Finder only) | ⚠ OK. **Test on the Czech layout**, where the number row isn't digits unshifted. `keyboardShortcut(…localization: .automatic)` may remap it [S65] (UNVERIFIED). |
| ⌥⌘I | Show/Hide Inspector | window | "Display an inspector window" | "Show or hide the inspector window" | ✅ standard. **Don't** use `InspectorCommands` (⌃⌘I) [S62]. |
| (system) | Show/Hide Sidebar | window | — | — | ⚠ The `SidebarCommands` default shortcut is UNVERIFIED |
| ⌥⌘T | Show/Hide Toolbar | window | standard: "Show or hide a toolbar" [S17] | — | ✅ as a standard. That `ToolbarCommands` generates exactly ⌥⌘T is not stated on its docs page: UNVERIFIED, check the generated menu. |
| ⌃⌘F | Enter/Exit Full Screen | window | standard (system) | — | ✅ |
| ⌘+ (⇧⌘=) / ⌘− | Bigger / Smaller Text | global | "Increase / Decrease the size of the selection" | — | ✅ reasonable reuse; ⚠ test the Czech layout: "+" sits unshifted on the 1 key there, so ⌘+ and ⌘1 may collide (UNVERIFIED; no Apple page found). Record the result. |
| ⌘0 | Actual Size | global | not listed | not listed | ⚠ UNVERIFIED as a convention; harmless |
| ⌘? | FA Help | global | "Open the app's Help menu" | — | ✅ standard; ⚠ on the Czech layout "?" needs a test |
| ↩ / ⎋ / ⌘. | Default button / Cancel / Cancel | dialogs | standard | — | ✅ |

**Never bound** (left to the system or reserved by Apple's tables):
- ⌘S, ⇧⌘S, ⌘O, ⇧⌘P (Page Setup), ⌘E ("Use the selection for a find operation"), ⌘G and ⇧⌘G, ⌘J ("Scroll to a selection"; implement the standard behaviour in lists), ⌘T, ⌘B, ⌘I, ⌘U, ⌘[ and ⌘] (align), ⌘; and ⌘:.
- Every ⌃ combination, Control-F1…F7, ⌘Space variants, ⌘Tab, ⌥⌘Esc, ⌥⌘D, ⌥⌘8, ⌃⌘Space, ⌃Space and ⌃⌥Space (input sources) [S17].
- ⇧⌘Q and ⌥⇧⌘Q (Log Out) and ⌘\` / ⇧⌘\` (switch windows of the front app) [S17][S8].
- ⇧⌘3, ⇧⌘4 and ⇧⌘5 (screenshots and screen recording) [S8], and ⇧⌘6 ("In macOS 27 Golden Gate or later with Siri AI (Beta) turned on, ask Siri about the selected area") [S8].
- **The app defines no custom Control shortcuts.** That follows the HIG's "avoid Control" [S17].

**Czech keyboard (QWERTZ) note.** All primary actions use **letters** with ⌘ or ⇧⌘, or ↩. Digit and punctuation shortcuts (⌘1–6, ⌘+, ⌘−, ⌘?) are secondary conveniences, and each has a mouse or palette alternative. HIG: avoid extra modifiers on characters that aren't on every keyboard [S17]. Things notes that shortcuts adapt to keyboard layouts from macOS 12 on [S128]. Test every shortcut on Sasa's actual layout.

### 3.2 Single-key actions inside a focused list

**Research basis.** Single keys while a list or page has focus, and never inside text fields, are used by:
- iÚčto: E edit, K duplicate, T print, ← → previous/next document; "not in text fields" [S116]
- Fakturoid: shortcuts "mimo textová pole" [S102]
- Linear: X, J and K [S129]
- Raycast: ↩ runs the first action [S131]
- Superhuman: Z to undo [S134]

On the Mac, Space = Quick Look [S8]. SwiftUI's `onKeyPress` only fires while its view has focus [S67].

**Rules.**
1. A single key acts only while the list has keyboard focus. As soon as a text field or search field has focus, the keys type.
2. Each single key is its ⌘ shortcut without the ⌘ (D = ⌘D, R = ⌘R). That makes them learnable, and the menus teach them.
3. **Lists that use type-select** (Clients, and the client picker) get **no** letter actions. Typing there always selects by name.
4. Every single-key action also exists as a menu item and in the context menu. Touch users and Full Keyboard Access users still reach everything [S53][S16].
5. **Prototype first.** If SwiftUI `Table`/`List` are `NSTableView`-backed on macOS (UNVERIFIED), type-select is on by default (`allowsTypeSelect` defaults to true [S86]) and may consume letter keys before `onKeyPress` sees them, in the Documents list too. Build a `Table` + `onKeyPress` spike on macOS 26/27 before committing. Every letter keeps a modifier or menu fallback: D = ⌘D, R = ⌘R, Space = ⌘Y, ↩ = Open via `onKeyPress(.return)` or double-click; in triage, N and S fall back to Bank ▸ Not an Invoice ▸ and Bank ▸ Skip (menu and palette). If the spike fails, the letter keys are dropped and the ⌘ chords stay.

| List | ↩ | Space | D | R | N | S | ⌫ |
|---|---|---|---|---|---|---|---|
| Documents | Open | Quick Look | Duplicate as Draft | Record Payment | — | — | Delete draft |
| Overview queue | Row action | Quick Look | — | Record Payment | — | — | — |
| Payments | Open document | Quick Look | — | — | — | — | Delete manual payment (not when an issued document rests on it) |
| Clients | Open | — | — | — | — | — | — (archive is in the menu only) |
| Bank triage (v0.2) | Accept | Quick Look | — | R (PDF fallback: record on the selected document) | Not an invoice | Skip | — |

Line items have no single-key actions: the grid is made of text fields, so every key types. Delete Line and Move Line are in the Document menu and the row's context menu (§2c).

---

## 4. Click and keystroke budgets: top 8 tasks

Counting rules:
- A chord counts as 1 keystroke (K), and each typed character counts as 1.
- C means a pointer click.
- "Other tool" means a typical web invoicing tool modelled on the flows Fakturoid and iDoklad document [S101][S104][S108][S113][S114]. **Those counts are ESTIMATES, not timed.** They leave out login and page loads.
- "This app" counts assume a client named "Acme" and a document number ending in 0042.

| # | Task (frequency) | Other tool: path (ESTIMATE) | Other: count | This app: path | This app: count |
|---|---|---|---|---|---|
| 1 | Repeat last month's invoice with new hours (several per month) | Invoices → search client → open last → "… Více" → Duplicate (about 2 clicks [S101]) → click qty and type → edit the period text by hand → create → download PDF | ~9 C + ~18 K | ⌘K · acm · ⌘D · 36,5 · ⌘↩ · Space (tick the period-text check) · ↩ (§2c script). No ⌘W: the draft lives in the main window. **If the month-end rate is missing** (common early in the month): + "24,315" ↩ in the sheet's inline rate form (+7 K; the v0.1 path), or + 1 drag of a ČNB file onto the sheet. | **12 K, 0 C** (19 K or 12 K + 1 drag with the rate step) |
| 2 | New invoice for an existing client, 2 lines from history | + New → client: type and pick → line 1: type and pick suggestion → qty → add row → line 2: type and pick → qty → create → PDF | ~9 C + ~13 K | ⌘N · acm · ↩ · Konz · ⇥ · 8 · ↩ (new row) · Ces · ⇥ · 1 · ⌘↩ · ↩ (the empty trailing line is dropped automatically) | **19 K, 0 C** |
| 3 | Morning check: what's overdue or unpaid (daily) | Open Overview or the list → Overdue tab | ~2 C | The app reopens where it was [S27] · ⌘1 | **1 K** (0 if already on Overview) |
| 4 | Record a full payment on an invoice (several per week) | Search (1 C + ~6 K) → open → *Uhradit* or paid dialog (~2 C) | ~3 C + ~6 K | From the Overview queue: ⌘1 · ↓ · R · ↩. From search: ⌘F · 0042 · ↩ · R · ↩. | **4 K** (queue) / **8 K** (search) |
| 5 | Advance paid → tax document issued (per advance) | Open advance → mark paid (~3 C) → "…" → create tax doc (~2 C) → save (1 C) | ~6 C | ⌘1 · ↓ · R · ↩ (payment) · ↩ ("Create Tax Document") · ⌘↩ · ↩ | **7 K** |
| 6 | Find a document and attach its PDF to an email (several per week) | Search (1 C + 4 K) → open → download PDF → Mail: attach from Downloads (~3 C) | ~5 C + 4 K | ⌘K · 0042 · ↩ (selects it) · drag the row or preview to Mail | **6 K + 1 drag** |
| 7 | Add a CRM note after a call (weekly) | Contacts → search → open → edit note → save | ~5 C + ~4 K + text | ⌘K · acm · ↓↓↓ ("Add Note – Acme") · ↩ · ‹text› · ↩ | **9 K + text** |
| 8 | Monthly close: CSV for the accountant + backup (monthly) | Export menu → choose month → export → download (backup is not applicable on the web) | ~5 C | ⌘6 · ↩ ("Export October 2026…", backup ticked) · ↩ (save panel) | **3 K** |

**Bonus (v0.2): triage a statement of 30 lines** (20 exact, 8 suggested, 2 fees), from an ABO or XML statement.
- This app: 1 C on "Accept Exact Matches (20)" (or ⌘K · "acce" · ↩ = 6 K from the palette) + 8 × ↩ + 2 × (N + category key) = **1 C + 12 K** (or 18 K with no click).
- Xero-style: one OK per line, **30 C** [S120][S121]. Xero's "Bulk OK" idea has been "in development" since 17 Nov 2025 (status checked 2026-11-05), so this may change once it ships.
- With a PDF-only statement there is no triage: the "match manually" fallback (§2f) costs about ⌘F · VS · ↩ · R · date · ↩ per line.

**Acceptance test.** The invoicing research set a target of at most 8 keystrokes, no mouse and under 20 s for a repeat invoice. The script now needs 8 command keystrokes (the extra one is the deliberate tick on changed period text), plus the characters of the new data (here 4, so 12 in total). That meets the target when it counts command keys. The review step should keep the target at **8 command keys + data**, plus the rate step on the days the month-end rate is still missing.

---

## 5. UI labels per screen (English)

- **The UI is English only** (How to read this), so this table has no Czech UI column. Czech stays only where the text prints on a document or is a legal string; those rows say **document text** and give the Czech.
- Standard system items (Undo, Copy, Close, Minimize, Print and the like) come from macOS. They are not listed here.
- These are **UI labels**. PDF wording belongs to the PDF spec, and anything legal there is ACCT, except the brief's own terms. Legal and tax strings, here or on the PDF, come from the design-system §9 legal-strings table; every Czech term below marked ACCT waits for the accountant.
- **This is the only label table.** design-system.md uses these labels (sidebar, short type names, states).
- Status badges use sentence case (design-system §9).

**Sidebar and global**

| Label | Notes |
|---|---|
| Overview | |
| Documents | |
| All | |
| Drafts | |
| Unpaid | |
| Overdue | |
| This month | |
| Open advances | |
| Clients | |
| Payments & Bank | |
| All payments | |
| Unmatched | |
| Exchange rates | |
| Exports & Backup | |
| Search documents, clients and commands… | |
| Command Palette | |

**Document types and states**

| Label | Notes |
|---|---|
| Invoice – tax document | **document text:** "Faktura – daňový doklad" (PDF title; brief) |
| Advance invoice | **document text:** "Zálohová faktura" (PDF title; brief) |
| Tax document for received payment | **document text:** "Daňový doklad k přijaté platbě" (PDF title; brief) |
| Final invoice | **document text:** the PDF title is "Faktura – daňový doklad (vyúčtování záloh)" (InvoicingCore `DocumentKind.title`; the parenthetical is ACCT; §2d) |
| Type pop-up and Issue sheet: the English name plus the Czech title, e.g. "Advance invoice (Zálohová faktura)" | The Czech part is document text (design-system §9) |
| Short type names (chips, Type column): Invoice · Advance · Tax doc (payment) · Final | |
| Draft | |
| Issued | |
| Partly paid | |
| Paid | |
| Overpaid | |
| Overdue · +12 days · 1 000,00 € left | One detail format in both spec files |
| Awaiting payment | |
| Partly paid – tax document missing | |
| Paid – tax document missing | |
| Tax document issued | |
| Settled in final invoice (number in the detail) | cs wording ACCT, not shown in the English UI (design-system §9) |
| Issued (paid) | |
| Paid (by advances) | |
| Closed unpaid | ACCT (wording and accounting effect, §0 rule 1, §2d) |
| Marked for credit note | ACCT (wording and accounting effect, §0 rule 1, §2d) |
| Close Advance as Unpaid… / Mark for Credit Note… | ACCT (wording and accounting effect, §0 rule 1, §2d) |
| Locked | |
| Not a tax document (in-app banner) | The brief's Czech short form "Není daňovým dokladem" isn't shown in the English UI |
| This is not a tax document. A tax document will be issued upon receipt of the payment. (English gloss on a bilingual advance PDF) | **document text:** "Toto není daňový doklad. Daňový doklad bude vystaven po přijetí platby." (InvoicingCore `DocumentClause.notATaxDocument`, ACCT) |
| Draft markers on a draft PDF | **document text:** "KONCEPT / DRAFT", "Číslo bude přiděleno při vystavení / number assigned at issue", "QR po vystavení / QR after issue" (§2c); the watermark always prints both languages, the number and QR placeholders only their Czech part on a Czech document |

**Overview**

| Label | Notes |
|---|---|
| Needs attention | |
| All caught up | |
| Issued in November | |
| VAT for November | |
| Unpaid advances | |
| Payments recorded up to 31. 10. 2026 | |
| Month-end rates missing | |
| Enter Rate… · Import ČNB Rates… | The two actions of a missing-rate queue item, in this order (§2a) |
| Getting started | |

**Documents list, editor and issue**

| Label | Notes |
|---|---|
| New Invoice | |
| New Advance Invoice | |
| Duplicate as Draft | |
| Repeat Last Invoice | |
| Issue… | |
| Issue | |
| Issue invoice FV 2026-0042? | |
| Once issued, the document can't be edited or deleted. | |
| Checked | |
| Go to Problem | |
| Ready to issue | |
| Number assigned at issue | |
| Assigned at issue | The VS row of a draft (§2c) |
| Client | |
| Issue date | |
| On issue | |
| Set to today | |
| Period | |
| Date of taxable supply (short: DUZP) | **document text:** "DUZP · Datum uskutečnění zdanitelného plnění" (ACCT) |
| Due date / Due in | |
| Currency: EUR / CZK / USD | |
| Document language: Czech / Czech + English | InvoicingCore `DocumentLanguage.czech` / `.english` |
| VAT treatment | |
| Czech 21 % / EU reverse charge / Outside EU / Exempt | UI labels. The printed texts are **document text** in design-system §9: "Tuzemsko 21 % · EU – přenesená daňová povinnost (PDP) · Mimo EU · Osvobozeno" (ACCT) |
| Reverse-charge clause on the PDF | **document text:** "daň odvede zákazník" (brief) |
| EUR rate for 30. 10. 2026 missing | |
| Enter Rate… · Change… | |
| Open ČNB Rates Page | Optional link (RECOMMENDATION, §2g) |
| QR after issue | |
| Bank account | |
| QR code: QR Platba / EPC QR (SEPA) / None | "QR Platba" is the name of the Czech QR payment standard [S117] |
| Variable symbol | |
| ČNB rate · rate date · source | |
| Typed / ČNB file | Rate sources |
| Last published rate | |
| Description / Qty / Unit / Unit price / Discount / VAT rate | |
| Base / VAT / Total / Amount due | |
| VAT in CZK | |
| Advances deducted | **document text:** "Odečet záloh" (caption), one "Odečet zálohy – daňový doklad č. …, platba ze dne …, sazba DPH … %" line per tax document and rate (`PDFStrings.deductionLine`) and the clause `DocumentClause.advancesDeducted` on the final invoice (ACCT, design-system §9) |
| (DDPP reference line) | **document text:** "K záloze …, platba ze dne …" (ACCT); InvoicingCore prints `DocumentClause.paymentReceived` (design-system §9) |
| When paid, prepare | |
| Add Line Item | |
| Apply client defaults | |
| Prices were not converted | |
| Save PDF… | |
| Show PDF in Finder | |
| Quick Look | |
| PDF saved | |
| Corrections via credit note (Phase 2) | **document text** (Phase 2): "Dobropis / opravný daňový doklad" (ACCT) |

**Clients**

| Label | Notes |
|---|---|
| New Client… | |
| VAT ID missing / Address missing | |
| VIES checked on | ACCT |
| Open balance | |
| Invoiced this year | |
| Last document | |
| Activity | |
| Add a note… | |
| Contacts | |
| Archive Client | |
| Possible duplicate | |
| Reverse charge needs the client's VAT ID | New Client sheet warning (ACCT) |

**Payments and bank**

| Label | Notes |
|---|---|
| Record Payment… | |
| Record | |
| Payment date / Amount / Account / Note | |
| CZK difference | The Czech accounting term "Kurzový rozdíl" is ACCT (design-system §9) |
| Credited to account / Settles on the document | |
| Document will be: Paid | |
| Apply Credit To… / Record Refund… | |
| Payment is the basis of DD 2026-0003 – can't be deleted · Show Document | |
| Create Tax Document | |
| Later | |
| Import Bank Statement… | |
| Statement | |
| Already recorded / Matched / Suggested / Unmatched / Outgoing | |
| Accept / Accept Exact Matches (N) | |
| Not an invoice / Skip / Unmatch | |
| Fees / Software / Rent / Tax / Owner | |

**Exchange rates**

| Label | Notes |
|---|---|
| Add Rate… / Enter Rate… | Typing, the v0.1 path (§2g) |
| Import ČNB Rates… | Secondary: File menu and toolbar |
| Needed rates | |
| Non-publication day | |
| Typed / ČNB file | Rate sources |
| Used by | |
| Last published rate (weekend/holiday) | |

**Exports and backup**

| Label | Notes |
|---|---|
| Export for Accountant… | |
| Export October 2026… | |
| For the accountant (Excel CZ) / Machine (ISO) | |
| Changed after export: 1 document · Export Again | |
| Also back up now | |
| Back Up Now | |
| Restore from Backup… | |
| Last backup | |
| (CSV column) | "Daňový doklad (ano/ne)": CSV text for the accountant; CSV names are ACCT (§2h) |

**Repair mode (v0.1.x)**

| Label | Notes |
|---|---|
| Repair Mode… / End Repair Mode | File menu and palette; no shortcut (§1.4, §3.1, §2m) |
| Turn On Repair Mode? | Entry sheet title (§2m) |
| Reason | Required |
| Unlock… | Starts Touch ID or the password |
| Not unlocked | After a cancel or a failure |
| Repair mode is on. Every change to a locked record is logged. · End Repair Mode | Banner (§2m) |
| Repair mode: changes are logged | Lock line on an issued document |
| Repair mode ended after 10 minutes without changes | Banner after the timeout |
| Repair mode ended · N changes logged · Show Log | Result line |
| Unlocked for repair | Open-lock tooltip and VoiceOver label (design-system §8.18) |

**Settings**

| Label | Notes |
|---|---|
| General | |
| Company | |
| Bank accounts | |
| Numbering | |
| Documents & PDF | |
| VAT defaults | |
| Backup | |
| Next number | |
| Last issued number | |
| Continue your number series | |
| Legal name / Registered office / Company ID (IČO) / VAT ID (DIČ) / File number | **document text** (PDF labels): "Obchodní firma" (ACCT) · "IČO" · "DIČ" · "spisová značka" (brief) |
| Payment tolerance | |
| Footer text | The text itself is document text that Sasa types; empty by default |
| Save PDF automatically when issuing | |
| Default document language: By address / Czech / Czech + English | |

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

1. **Which macOS is on your Mac today? Answered.** "27.2, english" and "m1 pro 32gb ram 200gb bandwith 256gb disk - using mainly 8tb cloud / macOS 27.2 (the newest one, im just updating it right now)" (Sasa's answer in the proposal doc, 5 Nov 2026). Decision (build thread): the app keeps targeting macOS 14.0, with `#if compiler(>=6.2)` and `if #available` gates, while CI builds on the `macos-15` runner with Xcode 16.4 (macOS 15 SDK). The minimum rises once CI builds with Xcode 26 or later; the design recommends macOS 27.0 for that raise (§0.1). The macOS 27.0 APIs need the macOS 27 SDK, which ships with Xcode 27 (design-system §2), so a raise made on Xcode 26 can reach at most Fallback A (macOS 26.1).
2. **Your current numbering.**
   - What format, and what are the last issued numbers, for invoices, advances and tax documents?
   - Does each series restart every year?
   - Should final invoices share the invoice series? (ACCT for the rules; we need your format to continue it.)
3. **DUZP on monthly invoices.** Do you use the issue date, or the last day of the billed period (the invoice's "Period" month)? We make it a per-client default. (ACCT.)
4. **Languages. Partly answered.**
   - App: English only. Sasa answered "en" and commented: "czech is not needed anywhere. its jsut a very little bonus that i might not use. dont bother if not super easy to implement, maybe version 10.9 or omething ahah" (proposal doc, 5 Nov 2026). There is no in-app language switch, and Czech UI is out of scope.
   - Documents: InvoicingCore `DocumentLanguage` settles it. Czech customers get "Czech" (`.czech`, Czech only); foreign customers get "Czech + English" (`.english`, bilingual, Czech first). Each client and each document can change it. Both would print Czech number and date formats ("1 234,50 €", "5. 11. 2026"). This is a RECOMMENDATION, still open for Sasa and the accountant (design-system §9). Still open for the accountant: the English gloss of each legal string (ACCT, design-system §9).
5. **Advances for EU reverse-charge clients.** Do you issue a "Daňový doklad k přijaté platbě" for each advance payment, or go straight to the final invoice? This sets the default for "When paid, prepare". (ACCT.)
6. **PDF filing.** One folder, or subfolders per year or per client? What file-name pattern (e.g. "FV 2026-0042 Acme.pdf")?
7. **ČNB rates. Partly answered.** Sasa types the rate by hand: "for start everything that nmeeds to be online i willů do manualy, s ill type current cnb rate for each invoice" (proposal doc, 5 Nov 2026). Typing the rate on the document is the v0.1 path (§2c, §2g). Still open: would a link that opens the ČNB rates page in your own browser be acceptable (the app itself still makes no network call)? §2g sketches it as a RECOMMENDATION. The data layer already reads both the daily and the yearly ČNB file, so the secondary import takes either.
8. **Raiffeisenbank statements.** Are statements as data (ABO, RB XML or Gemini) a paid service in RB internet banking, with PDF free? UNVERIFIED. Is the service active, or worth its price? With ABO or XML, v0.2 can match payments automatically; with PDF only, matching stays manual (§2f).

---

## Sources

Numbers 74, 85, 88, 95, 111, 123, 124, 126, 132, 137, 149 and 150 are not used and are not reused.

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

Project inputs (not numbered): Sasa's answers and comments in the proposal doc, 5 Nov 2026 (linked from the project thread).

Research notes this spec builds on (kept in the design thread, not in this repository): Apple design language, macOS HIG, SwiftUI APIs, and the invoicing UX research.
