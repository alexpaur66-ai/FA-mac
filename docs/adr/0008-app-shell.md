# ADR 0008: App shell

Date: 2026-11-05 · Status: accepted, open to the adversarial review

## Context

The core (ADR 0002–0004, 0006), the data layer (ADR 0005, 0007) and the design system (docs/design,
PR 7) exist, but nothing opens the database and shows a window. docs/design/screens-flows.md specifies
one window with a sidebar, a documents table with an inspector, an overview, clients, payments, rates,
exports and settings. Saša answered on 5 Nov 2026: English-only interface, an M1 Pro on macOS 27.2 with
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
- **Navigation**: one three-column `NavigationSplitView`. The sidebar holds the sections and the
  document smart filters as `SidebarItem`, a raw-representable value restored with `@SceneStorage`; the
  inspector is the design's right column. `DocumentSmartFilter.matches` is the single definition of each
  filter, shared by the list, the sidebar badges and the menu. The document selection is cut down to
  the rows the filter and the search show, so the detail column, the menu bar and ⌫ act only on
  visible rows.
- **Errors are sentences.** A failed action shows one line from `ErrorText` (what happened, how to fix
  it) beside the place it was taken: in the sheet, in the detail, or in the result line at the top of the
  content column of every section (design-system.md §8.17); a result that can be taken back carries Undo. If the live observation fails, the document list shows the error
  inline with a Try again button that restarts it.
- **Menu bar through focused scene values.** `MainActions` carries closures; `AppCommands` reads
  `@FocusedValue(\.mainActions)`, so menu items enable per window. Shortcuts follow
  screens-flows.md: ⌘N / ⇧⌘N / ⌥⌘N new documents, ⌘1–⌘6 sections, ⌥⌘I inspector, ⌘R record payment,
  ⌘+ / ⌘− / ⌘0 text scale.
- **Strings**: `enum L` wraps `LocalizedStringResource(key, defaultValue:, table: "App")` with English
  defaults in code and no catalog shipped, because Saša wants an English interface only; Czech stays on
  the documents for Czech customers (InvoicingCore). Adding a language later is an App.xcstrings file, no
  code change. Dates, money and counts always go through the system formatters.
- **Text scale** (View ▸ Bigger / Smaller / Actual Size) is kept in `AppModel`, persisted in
  UserDefaults, 1.0–2.0 in five steps, and applied through the design system's environment value.
- **Settings** is the standard Settings scene: General, Company, Bank accounts, Numbering (defaults
  FV `{YYYY}-{NNNN}` with VS prefix 1 for invoices and final invoices, ZF with prefix 2, DD without a
  prefix), Documents & PDF, VAT defaults, Backup; the window reopens on the pane viewed last. The Overview
  shows a "Getting started" card until company, bank account and series exist; the ČNB rates are optional,
  because the rate is typed on the document.
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
- Exports and backups show their cards and commands with the controls disabled until the export step;
  PDF rendering arrived with ADR 0010.
- The Payments section loads payments per issued document; the data layer should gain
  `payments(filter:)` across documents.
- Carried from the ADR 0007 review: a prefix collision between series is warned about in the Numbering
  pane, not enforced; `observeStates`' fixed `today` is handled by the midnight restart.

## Amendments (PR 18, follow-ups of the design check)

- The result line sits at the top of the content column; Delete Draft and Delete Payment have no
  confirmation and register an undo instead (the line offers Undo; ⌘Z works too). Undo of a deleted
  draft writes it back under its id and relinks a payment tax document to its payment.
- Record Payment… applies only to an issued document with an open balance; an overpaid document offers
  Record Refund… as its own command. The Document menu, the context menu and the detail's toolbar share
  one `DocumentActions` value, so they never disagree.
- The inspector exists in Overview, Documents, Clients and Payments & Bank; Exchange rates and Exports &
  Backup disable View ▸ Show Inspector. Clients has its own inspector with the client's defaults.
- A Client menu (New Invoice for ‹client›, New Advance Invoice for ‹client›, Edit Client Details…),
  Help ▸ Getting Started, and Window ▸ Main Window that brings the existing window to the front.
- Payments & Bank keeps its selection per window and lists Date · Client · Document · Amount · Source · Note.
- The client form has a country pop-up and a VAT treatment pop-up; new clients default to EUR, 14 days
  and EU reverse charge (decision of 5 Nov 2026). The company's term and footer live in Documents & PDF.
- The Numbering pane and the series sheet compare the variable symbols of a sample number across series,
  preview the next number as the store assigns it today, and lock year and counter once the app issued a
  number from the series.
