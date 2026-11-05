# ADR 0009: Draft editor and Issue

Date: 2026-11-05 · Status: accepted, open to the adversarial review

## Context

The shell (ADR 0008) shows drafts read-only. docs/design/screens-flows.md §2c specifies the editor: the
header fields, the lines grid, the totals bar with the readiness chip, autosave, and the review-and-issue
sheet with three severities; §2d specifies the advance flow from the payment to the tax document and the
final invoice. The data layer validates (ADR 0004) and issues in one transaction (ADR 0005); payments and
closing events are ADR 0007. Saša types the ČNB rate per document, invoices in EUR and CZK with USD in
the list, and uses an English interface.

## Decisions

- **One `DraftEditorModel` per selected draft.** Every edit goes through `update`, which recomputes
  the totals and the validation issues and schedules a 400 ms debounced `saveDraft`; `saveNow` runs when
  the editor disappears, before Issue, and when another draft is selected. The window owns the model
  (`MainSplitView.editor`) and replaces it when the selected draft changes, so Document ▸ Issue… (⌘↩)
  reaches the editor on screen. The model never writes a document that is no longer a draft,
  nor one that was deleted: Delete Draft discards the editor's pending save first, because `saveDraft`
  inserts a missing id. When the old editor's last save fails as another document is selected, the
  window says the last changes were not saved. A fully empty trailing line is dropped on save and at
  issue and is never validated (screens-flows.md §2c). The editor validates with `forIssue: false`; the
  number is assigned and checked by `DocumentStore.issue`.
- **Document-level VAT treatment, per-line Czech rate.** `TreatmentChoice` (Czech VAT, EU reverse
  charge, outside the EU, exempt with its reference) applies to every line; under Czech VAT each line
  picks standard, reduced or zero. Mixed treatments are not offered: the spec leaves them to the
  accountant and the validator's `mixedTreatments` stays the guard.
- **A client change applies the client's defaults** (currency, language, due days, treatment) and
  resets the payment, the rate and the advances deducted (the previous client's receipts). This is simpler than the spec's "only untouched fields" rule and is
  what a new draft does anyway; prices are never converted.
- **Dates.** Moving the issue date keeps the term, so the due date moves with it. The tax point is
  either "same as the issue date" or an explicit day; advances have no tax point. "Same as the
  issue date" stores the issue date in `taxPointDate` and follows issue-date changes, because the
  validator requires a stored tax point on a tax document (§ 29 odst. 1 písm. h) ZDPH,
  `taxPointDateMissing`). A payment tax document's tax point is the day the payment was received: the
  editor shows it read-only and `DocumentStore.checkReceipt` refuses any other day. There is no floating
  "on issue" date: an issue date other than today is a ⚠ row in the sheet with "Set to today". The
  per-client DUZP rule (end of the billed period) waits for the accountant's answer.
- **Exchange rate.** A foreign-currency tax document takes `RateStore.rate(for:on:)` for its tax point;
  the rule-6 fallback (last published rate) is shown as ℹ. Without any rate the inline form saves a
  typed rate for that day (`ExchangeRateSource.manual`) and the document takes it at once; a rate stored for
  that day meanwhile (an import) is taken instead of being overwritten. The rate is read again when the
  review sheet opens and at Issue. CZK
  documents and advances need none.
- **Bank account.** A nil payment means the company's account for the currency, which
  `DocumentStore.issue` fills together with the variable symbol and the series' prefix; the header offers
  the profile's other accounts of that currency. The editor validates a preview with that account filled
  in, so the sheet shows no false "no bank details" row and an account in another currency shows before
  issue.
- **Advances deducted** on a final invoice: "Add tax document…" lists the client's issued payment tax
  documents in the same currency that no final invoice deducts yet (`deduction(ofReceipt:)`) and adds
  their `advanceDeductions(totals:)` rows, which carry the advance's rate and exchange rate
  (§ 37a odst. 2 písm. b) ZDPH). A listed receipt that another issued final invoice already deducts is a
  ⛔ row naming that invoice.
- **The review-and-issue sheet** has the spec's three severities. ⛔: validator errors, a missing rate
  (shown as the inline form), no numbering series (with a Settings link), an issue date before the series
  year and a receipt deducted elsewhere disable Issue; the readiness chip counts the same rows. ⚠: validator
  warnings and an issue date other than today need the "Checked" box, which has the default focus. ℹ:
  the rate fallback and a tax point in another month. Issue is `saveNow` then
  `DocumentStore.issue(id:seriesID:)`; afterwards the list switches from Drafts to All, keeps the document
  selected and shows "Issued FV …". The sheet predicts the number with `peekNextNumber`; the number
  is assigned at issue (ADR 0005).
- **The advance flow.** Record Payment on an advance ends with "Create Tax Document" (default) or
  "Later": `Document.paymentTaxDocument` → `saveDraft` → `attachReceipt`, and the draft opens in the
  editor. After "Later" (or once that draft is deleted) the payment's row in the advance's detail offers
  Create Tax Document, and so does Document ▸ Create Tax Document for Payment when exactly one received
  payment has none; a payment with a draft tax document offers Open Tax Document. Only these actions
  create a payment tax document: the Type picker does not offer it, and its type cannot be changed.
  Create Final Invoice… (Document menu and the detail of an issued advance) builds a final invoice draft
  with the advance's lines, client and notes and the deductions of its issued receipts; it is refused
  with the reason while a received payment of the advance has no issued tax document.
  Duplicate as Draft (⌘D) copies lines, client, currency, language and notes with today's dates and the
  client's current term and address; never the number, rate, payment or deductions.
- **Deferred from §2c**, the spec stays the target: the period-text shift and the comparison with the
  client's last invoice, the live PDF preview and the saved-PDF line, the command palette, natural
  language dates, the "Go to problem" default button, dropping a ČNB file onto the sheet, the undo stack.

## Alternatives rejected

- Per-line treatment pickers: mixed documents are rare and an accountant's decision.
- An editor window per draft: the spec's detail-column editor keeps the one window of ADR 0008.
- Reserving the number when the draft is created: numbers must have no gaps and follow the issue
  date (ADR 0005), so only Issue takes one.

## Consequences

- At the minimum detail width the lines grid scrolls sideways instead of clipping the rate and line
  total columns, and the totals bar wraps with the readiness chip below the figures. A final invoice's
  bar shows Total, − advances, Amount due and the VAT after the deduction next to the VAT in CZK.
- A numeric cell keeps text that is not a number, outlined in red, and writes nothing until it is fixed.
- Autosave persists half-typed drafts; the validator decides at issue, not at save, and the chip
  shows the count of blocking problems live.
- macOS moves keyboard focus to a checkbox only with Full Keyboard Access on; the Checked box has the
  default focus, and the mouse always works. The common case stays ⌘↩ ↩.
- Open: the customer setting for advances without a tax document (screens-flows.md §6, question 5),
  the per-client DUZP rule, ⌘D from the Clients section, PDF rendering and the QR code on the PDF.

## Amendments (design check of PR 12, November 2026)

The design check of the editor (`design/pr12-design-check.md`) changed these decisions; the rest of this
ADR stands.

- **Rate resolution** (E026): the rate of the tax point is the stored rate of that day. On a weekend or a
  Czech public holiday (zákon č. 245/2000 Sb.) it is the stored rate of the last working day before it.
  On a working day without a row that lies between imported ČNB rows of the previous and the next working
  day, it is the previous row (the ČNB published nothing that day). Otherwise the rate is missing and the
  sheet asks for it: never an arbitrary earlier rate. The ℹ row says which day's rate is used and why.
- **Promoted problems** (E032): a missing company IČO and, except on a payment tax document, a missing
  bank account in the document's currency are ⛔, not ⚠.
- **Issue sheet** (E073, E011): with a rate missing, the rate field has the default focus, before the
  Checked box. Create Final Invoice has no ellipsis: it opens the draft directly. The summary names the QR
  code the document gets (QR Platba, EPC QR (SEPA) or none) and the legal notes the PDF prints; a
  payment tax document and a final invoice with nothing due show no payment row.
- **Payment tax document** (E022, E101): an issued payment tax document carries no payment instructions,
  the payment it documents has been received. Its draft must stay linked to its payment: the editor blocks
  Issue when the link is gone and says to delete the draft and create the tax document again from the
  payment's row. Deleting a payment that has a draft tax document asks whether to delete the draft too;
  the store deletes both in one transaction. The store itself does not refuse an unlinked receipt: a
  receipt issued before its payment was recorded still names its advance
  (`aReceiptIssuedBeforeItsPaymentStillNamesItsAdvance`).
- **Client type-ahead**: the editor draws its own suggestion list under the client field (↓ ↑ pick, ↩
  takes the highlighted client, Esc reverts) with a "New Client “X”…" row that opens the client sheet
  with the typed name and puts the saved client into the draft. `textInputSuggestions` is macOS 15 only
  and has no such row; the VAT-rate cell uses it where available.
- **Rates**: Change… on a resolved rate replaces the stored rate of its day, so a mistyped manual rate is
  not frozen at issue and reused by the next document with that date.
- **Keyboard**: Document ▸ Add Line Item (⌘L), Delete Line, Move Line Up/Down (no shortcuts, §1.4), Change Type,
  Currency, Document Language, VAT Treatment and Enter Rate… act on the editor of the selected draft.
  Duplicate moved to File ▸ New (⌘D) and names the document it copies.
- **Numbers**: a numeric cell accepts either decimal separator (`DecimalInput`): with both kinds present
  the last one is the decimal separator; a lone separator is a grouping separator only when it is the
  locale's and the groups have three digits. An invalid cell is a ⛔ row with a fix-it example.
- **Lists and focus**: opening a draft clears the Documents search, and the row of the draft being edited
  stays listed whatever the search says. A new draft opens with the cursor in the client field (no client)
  or the first line; an opened draft in the first line's quantity.
- **Quit** writes the open draft at once (`NSApplication.willTerminateNotification`), so autosave's delay
  loses nothing.
- **Deferred to a later PR**: the QR type pop-up and the VS row (E059), item history (E062), the currency
  banner (E025), the series-order warning (E033), E098 and E100 (they wait on Saša's answers), the
  New ▸ submenu (E001), the "D" key (E018) and `textInputSuggestions` for the client field.
