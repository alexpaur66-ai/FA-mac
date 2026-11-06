# ADR 0008: App shell

Date: 2026-11-05 · Status: accepted, open to the adversarial review

## Context

The core (ADR 0002–0004, 0006), the data layer (ADR 0005, 0007) and the design system (docs/design,
PR 7) exist, but nothing opens the database and shows a window. docs/design/screens-flows.md specifies
one window with a sidebar, a documents table, an overview, clients, payments and settings (the lean
design pass of 6 Nov 2026 removed the inspector and moved rates, export and backup into the File menu). Saša answered on 5 Nov 2026: English-only interface, an M1 Pro on macOS 27.2 with
an English system language, EUR and CZK with USD in the list, the ČNB rate typed per document, no
existing data to import.

## Decisions

- **One `AppModel`** (`@MainActor @Observable`) opens the database once at launch and holds `Stores`, a
  value with the database and its seven stores, which the views receive explicitly. There is no
  singleton and no store in the environment, so previews and tests build their own `Stores`. An open
  error is shown inline in the window (`DatabaseErrorView`), never as a modal alert, so the window
  exists and the text can be copied.
- **Database location** `Application Support/FA/fa.sqlite` inside the sandbox container. The
  environment variables `FA_DATABASE_PATH` and `FA_IN_MEMORY_DATABASE=1` override it for tests and
  previews. The live file never goes into a synced folder (docs/setup-mac.md).
- **Live state from one observation.** `DocumentListModel` runs `DocumentStore.observeStates` with
  `for try await` on the main actor and restarts it on `.NSCalendarDayChanged`, so the "today" the states
  are computed for moves at midnight (the open question of ADR 0007). Every list, badge count and smart
  filter derives from that one array; a view loads on its own only detail data (payments, deductions,
  audit) with `.task(id:)`.
- **Navigation**: one three-column `NavigationSplitView` with no inspector column. The sidebar holds
  Overview, Documents (a selectable row showing all documents, with Drafts, Unpaid and Open advances under
  it), Clients and Payments as `SidebarItem`, a raw-representable value restored with `@SceneStorage`;
  rows of earlier versions restore to the nearest row. `DocumentSmartFilter.matches` is the single
  definition of each filter, shared by the list, the sidebar badges, the window subtitle and
  View ▸ Filter ▸. The document selection is cut down to
  the rows the filter and the search show, so the detail column, the menu bar and ⌫ act only on
  visible rows.
- **Errors are sentences.** A failed action shows one line from `ErrorText` (what happened, how to fix
  it) beside the place it was taken: in the sheet, in the detail, or in the result line at the top of the
  content column of every section (design-system.md §8.17); a result that can be taken back carries Undo. If the live observation fails, the document list shows the error
  inline with a Try again button that restarts it.
- **Menu bar through focused scene values.** `MainActions` carries closures; `AppCommands` reads
  `@FocusedValue(\.mainActions)`, so menu items enable per window. Shortcuts follow
  screens-flows.md: ⌘N / ⇧⌘N new documents, ⌘1–⌘4 sections (⌘5 Stock when it ships), ⌘R record
  payment (or refund), ⌘+ / ⌘− / ⌘0 text scale. ⌥⌘N, ⌘5 and ⌘6 are unassigned in v0.1; ⌥⌘I is never
  bound. Toolbars are fixed sets per screen (design-system.md §8.11), the prominent item text only and
  last.
- **Strings**: `enum L` wraps `LocalizedStringResource(key, defaultValue:, table: "App")` with English
  defaults in code and no catalog shipped, because Saša wants an English interface only; Czech stays on
  the documents for Czech customers (InvoicingCore). Adding a language later is an App.xcstrings file, no
  code change. Dates, money and counts always go through the system formatters.
- **Text scale** (View ▸ Bigger / Smaller / Actual Size) is kept in `AppModel`, persisted in
  UserDefaults, 1.0–2.0 in five steps, and applied through the design system's environment value.
- **Settings** is the standard Settings scene with four panes (lean pass set-01, PR 31): General (the PDF
  folder), Company (with the footer), Bank Accounts, Numbering (defaults FV `{YYYY}-{NNNN}` with VS prefix
  1 for invoices and final invoices, ZF with prefix 2, DD without a prefix). There are no Documents & PDF,
  VAT defaults or Backup panes; their contents are fixed rules, General or the File menu. Every pane but
  Numbering stores a field as soon as it is committed. The window reopens on the pane viewed last. The Overview
  shows a "Getting started" card until company, bank account and series exist. *Amended by the lean pass
  (other-04, other-15):* the card has those three steps only and one Open Settings… button for the first
  unfinished pane; on a first run it is the Overview's only content, and a data error replaces it.
- **Accent colour** is the asset-catalog colour `AccentColor` (light, dark, both high-contrast
  variants, the same values as `Brand.accent`), named by `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`,
  so system controls and the design system agree.
- **Deployment target stays 14.0** with the design system's `#available` gates. Saša runs macOS 27.2, so
  the minimum rises once CI builds with Xcode 26 or later (CI is macos-15 with Xcode 16.4 today).

## Alternatives rejected

- A global environment object or singleton for the stores: hides the dependency and makes previews and
  tests order-dependent.
- A document-based app (`DocumentGroup`): the data is one database, not files.
- Per-view database queries: duplicated filter logic and badges that disagree with the list.
- A Czech string catalog now: not wanted; the design system keeps its cs entries at no cost.
- An alert for the open error: a blocked window whose text cannot be copied.

## Consequences

- The shell lists, filters, inspects and settles documents and creates drafts, but does not yet edit
  draft lines or issue documents; the editor and the Issue sheet are the next PR (the Issue… menu item
  exists and is disabled).
- Export and backup are File commands; the export opens a sheet. Both stay disabled until the export
  and backup steps; PDF rendering arrived with ADR 0010.
- The Payments section loads payments per issued document; the data layer should gain
  `payments(filter:)` across documents.
- Carried from the ADR 0007 review: a prefix collision between series is warned about in the Numbering
  pane, not enforced; `observeStates`' fixed `today` is handled by the midnight restart.

## Amendments (PR 18, follow-ups of the design check)

- The result line sits at the top of the content column; Delete Draft and Delete Payment have no
  confirmation and register an undo instead (the line offers Undo; ⌘Z works too). Undo of a deleted
  draft writes it back under its id and relinks a payment tax document to its payment (as the payment is
  now: recorded again by an earlier Undo, or left alone when it has another tax document by then). Undo of
  Delete Payment Only relinks the draft tax document that was kept. The line's Undo carries out its own
  registration, not the top of the window's stack, and takes it off the stack; after ⌘Z it is cleared.
  Delete Payment and Draft in Payments deletes the draft too, as in the detail.
- Record Payment… applies only to an issued document with an open balance; on an overpaid document the
  same ⌘R row reads Record Refund… (lean pass). The Document menu, the context menu and the detail's toolbar share
  one `DocumentActions` value, so they never disagree.
- Superseded by the lean pass: the inspector is gone everywhere (its values moved into the issued view
  and the client page), and so is the Client menu: its items are File ▸ New Invoice / New Advance Invoice
  (which name the client in client context), Duplicate (the client's last invoice) and Edit Client “…”….
  Help ▸ Getting Started and Window ▸ Main Window stay.
- Payments keeps its selection per window and lists Date · Client · Document · Amount · Note, with search;
  as in Documents, a selection the search hides is dropped, so ⌫ and the menus act only on visible rows.
- The client form has a country pop-up and a VAT treatment pop-up; new clients default to EUR, 14 days
  and the client's VAT status from the goods-decisions country rule (goods decisions of 5 Nov 2026; ADR
  0011). The footer lives in Company, one for both document languages (answers R033); a new client's
  payment term is a fixed 14 days, and each client keeps its own term.
- The Numbering pane and the series sheet compare the variable symbols and the document numbers of a
  sample number across series (two series issuing the same numbers get a warning),
  preview the next number as the store assigns it today, and lock year and counter once the app issued a
  number from the series.
- The issued view's Activity maps the audit actions to sentences. The store also records `create` and
  `update` for every draft save: the first `create` shows as "Draft created", autosaves are not listed.

## Amendments (lean design pass, 6 Nov 2026)

- Four sidebar rows; Exchange rates and Exports & Backup are no longer sections. File ▸ Exchange Rates
  opens a read-only sheet (Date · Currency · Rate · Source, Import ČNB Rates…, Close); File ▸ Import ČNB
  Rates… opens the file importer from any section without switching, and reports in the result line.
- Drafts shows its count; Unpaid shows the overdue count in red with `exclamationmark.circle` while
  something is overdue. The Overdue and This month filters are gone; Unpaid sorts by due date, so overdue
  rows come first. The Documents subtitle reads "Unpaid · 7 · 3 overdue".
- The Documents, Overview and Clients selections are kept per window (`@SceneStorage`); restored ids
  that no longer exist are dropped once the documents have loaded.
- With several documents selected, the detail column alone shows the summary under the §2a rules:
  revenue (tax documents), open balance (the Unpaid set) and unpaid advances. The selection bar is gone.
- The closing rows of the Document menu read their reopening on a closed or marked document.
