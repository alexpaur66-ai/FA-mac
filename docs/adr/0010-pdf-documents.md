# ADR 0010: PDF documents

Date: 2026-11-05 · Status: accepted, open to the adversarial review

## Context

Every document must leave the app as a PDF: the customer gets it, the accountant files it and § 35 ZDPH
keeps it for ten years. docs/design/screens-flows.md §2b specifies the preview of an issued document in
the detail column, §2c the live preview of a draft with three draft markers and the issue step that
renders the PDF, stores its bytes and writes the file into a chosen folder, §1.4 Save PDF…, Show PDF in
Finder and Print… (⌘P), §2i the Documents & PDF pane. design-system.md fixes the PDF locale (Czech number
and date formats in both document languages, §9), the QR code size (about 30 mm, error correction M,
§5.3), the watermark colour (§4.1) and the rule that every printed legal string comes from InvoicingCore.
ADR 0001 chose Core Graphics for PDFs and Core Image for QR codes; ADR 0003 keeps the payloads in the core
and leaves the image to the app.

## Decisions

- **A third package target, `InvoicingPDF`** (Apple-only, depends on InvoicingCore), renders a `Document`
  into PDF bytes with Core Graphics and Core Text: `DocumentPDF.render(_:)`. It lives in the package, not
  in the app, so the macOS CI job tests it: every kind renders, the § 29 elements appear in the extracted
  text, the QR code on the page decodes (Vision) to the core's payment string, sixty lines paginate with
  running headers and "Strana n / N". The app has no compiler in the cloud, so the renderer is where the
  tests must be.
- **One A4 layout for the four kinds**, varied by the kind: an advance request prints no date of supply
  and the not-a-tax-document clause; a payment tax document prints "Datum přijetí platby", the
  payment-received clause, "Uhrazeno" instead of "K úhradě" and no payment block or QR; a final invoice
  prints the deduction rows in the VAT summary and names every deducted tax document (§ 37a ZDPH); a
  document without Czech VAT prints no rate, base or VAT columns and no VAT totals (§ 29 odst. 3 písm. e)
  ZDPH), only the clause. The VAT in CZK appears with its base and the rate on foreign-currency documents
  that charge VAT (§ 29 odst. 1 písm. l), the exchange-rate clause explains it (§ 4 odst. 8).
- **Bilingual means Czech first, English after a slash** on every caption (`DocumentLabel`), two-line
  table headers, the English title under the Czech one, and both sentences of every clause; the
  reverse-charge clause prints once because its English text already starts with the prescribed Czech
  wording. Number and date formats stay Czech (`cs_CZ`) on both languages, as the design system
  recommends; the accountant may still ask for a change (ACCT). Country names come from the locale of the
  document language, so a German customer reads "Germany" on a bilingual document and "Německo" on a
  Czech one.
- **Three draft markers**: the "KONCEPT / DRAFT" watermark across every page in a fixed mid-grey at
  18 % alpha, "Číslo bude přiděleno při vystavení" in place of the number, and a dashed "QR po vystavení"
  box in place of the code, because a draft has no variable symbol to match a payment against. The
  draft preview takes the company's account for the currency as its payment block, since Issue fills the
  same account in (ADR 0009).
- **The QR code is vector**: Core Image computes the module grid, the renderer fills one square per
  dark module, so the code stays sharp at any zoom and in print. 85 pt (about 30 mm), level M; QR platba
  for CZK, the EPC code for EUR, as `PaymentInstructions.standard` decides.
- **Helvetica**, 9 pt body, on white: it is on every Mac, embeds as a subset and has the Czech glyphs. The
  colours are fixed sRGB values; a PDF has no appearance.
- **Stored bytes.** The data layer gains `documentPDF` (migration v2): the PDF of an issued document is
  stored once, with its SHA-256 and the time of rendering, and SQLite triggers refuse to change or delete
  the bytes (`storePDF` returns the stored copy on a second call). The row also remembers where the app
  last wrote the file. A document issued before this step is rendered from its frozen snapshot the first
  time its PDF is needed. The database stays the source of truth: when the file write fails the document
  is issued and the PDF is stored, and the detail offers Save PDF….
- **The PDF folder** is a security-scoped bookmark in UserDefaults, chosen in Settings ▸ Documents & PDF
  through the open panel (the entitlement `com.apple.security.files.bookmarks.app-scope` is already in
  FA.entitlements). "Save PDF automatically when issuing" (on) and "Subfolder per year" (on) are the two
  switches; the file name is fixed to "{number} {client}.pdf" with `/`, `\` and `:` replaced. Save PDF…
  opens a save panel in that folder; Show PDF in Finder is disabled with "File moved – use Save PDF…"
  when the remembered file is gone.
- **Preview as page images.** The detail column shows the pages as Retina bitmaps drawn by PDFKit on
  white, stacked inside the detail's scroll view, so there is no scroll view inside a scroll view. The
  draft editor's View ▸ Show Preview swaps the editor for the same view, re-rendered about 300 ms after
  the last edit. Print… prints through `PDFView.printOperation` and the system print panel.
- **The preview and the PDF actions live in the main window.** An issued document's detail shows the
  PDF row (the saved file, or "kept in the app"), Save PDF…, Show PDF in Finder (disabled while the file
  is missing; the app keeps its own frozen copy) and Print…, then the pages. On a draft, View ▸ Show/Hide
  Preview and the toolbar toggle swap the editor's content for the live preview, rendered 300 ms after the
  last change; the toolbar, Issue and the review sheet stay. File ▸ Save PDF…, Show PDF in Finder and
  Print… (⌘P) follow the selected document; a draft prints as its watermarked preview. After Issue the
  result line names the file written; when the write fails the document is issued anyway and the detail
  shows a banner with Choose Folder… and Save PDF…. The review sheet's PDF row predicts the file from the
  predicted number. The document window of screens-flows.md §1.1 waits.

## Alternatives rejected

- SwiftUI `ImageRenderer` for the PDF: pagination and exact text metrics are not under the app's control,
  and the result is not testable in the package.
- HTML through WebKit: a web view in a sandboxed offline app, fonts and page breaks at the mercy of the
  engine, no tests.
- A `PDFView` inside the detail: a scroll view inside the detail's scroll view traps the wheel; the page
  images scroll with the rest and match the spec's white paper in both appearances.
- Drawing the QR code as a bitmap: blurry at zoom and in print; the module grid is a few hundred squares.
- Re-rendering the stored PDF when the renderer changes: the stored bytes are evidence of what was sent.

## Consequences

- An issued document's PDF is reproducible from its snapshot but never replaced; a renderer fix changes
  only documents issued afterwards.
- Deferred, the spec stays the target: the company logo on the PDF (the profile has no logo yet), Quick
  Look with Space, the PDF on the pasteboard for Copy, the "PDFs of the month" export, bulk Save PDFs to
  Folder…, and a dedicated document window with the editor and the preview side by side.
- ACCT items the renderer carries: the VAT summary row labels ("Tuzemsko 21 %", "EU – přenesená daňová
  povinnost (PDP)", "Mimo EU", "Osvobozeno"), the deduction line "Odečet zálohy – daňový doklad č. …,
  platba ze dne …", whether an advance request shows its VAT breakdown (it does, as information), and the
  Czech formats on English documents.
