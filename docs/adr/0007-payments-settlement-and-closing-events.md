# ADR 0007: Payments, settlement, deduction links and closing events

Date: 2026-11-05 · Status: accepted, open to the adversarial review

## Context

ADR 0005 stored payments as money received against an issued document. The screens (docs/design/
screens-flows.md §2b, §2d, §2f) need more: refunds and credit moved between documents, the status badge
computed from the document, its payments and two closing events that may be added beside an issued
document without changing it, and the rule that an advance is deducted by one final invoice only. The
design thread also found that two numbering series with the same template give the same variable
symbol to their n-th documents of a year (ADR 0003 addendum).

## Decisions

- **Payment kinds with a signed amount.** `documentPayment.kind` is `received`, `refund`, `creditIn` or
  `creditOut`; `amount` is positive for the incoming kinds and negative for the outgoing ones, and a
  `CHECK` constraint enforces the sign. The net paid amount of a document is the plain sum of its
  payments, so every balance query stays one `SUM`. A refund (`recordRefund`) is the positive sum
  returned, stored negative; from a bank statement it must come from a debit line, and allocation against
  a transaction is checked on absolute values, so one debit line can be split like one credit line.
- **Applied credit is two linked rows.** `applyCredit(from:to:amount:on:)` writes a `creditOut` on the
  overpaid document and a `creditIn` on the one it pays, each naming the other (`relatedPaymentID`), in
  one transaction. The credit may exceed neither what the source was overpaid nor what the target still
  owes. Deleting one leg deletes the other; a leg whose receipt is issued locks both.
- **Only incoming payments have a receipt.** `attachReceipt` and the receipt checks refuse a refund or a
  credit-out leg; a credit applied to an advance request is money received on it and may have one.
- **Deduction links are written when a final invoice is issued.** For each payment tax document a final
  invoice deducts, `advanceDeduction` records the final invoice, the receipt and the advance request the
  receipt's payment was received on (numbers denormalised, because issued numbers never change). A
  partial unique index makes a receipt deductible by one final invoice only (`advanceAlreadyDeducted`
  rolls the issue back, so the number is not consumed); the rows are frozen by triggers like the final
  invoice itself. A deducted number the database does not know (a receipt issued before the app) is
  allowed and named in the audit event, so the first year's final invoices can still be issued; a known
  number must be an issued payment tax document in the same currency and for the same customer.
- **Closing events live beside the document.** `documentClosure` holds one event per issued document:
  `closedUnpaid` for an advance request with no payments and no deduction ("Uzavřít zálohu bez
  úhrady…"), or `markedForCreditNote` for a tax document ("Označit k opravě dobropisem…"). Both need a
  reason, both are audited, `reopen` removes the event (audited). An advance closed as unpaid takes no
  payments until it is reopened. The document row stays frozen; the law has nothing to say about these
  events, they are the app's own bookkeeping (ACCT for the wording).
- **The state is computed, never stored.** `DocumentStore.state(for:today:)`, `states(_:today:)` and the
  `observeStates` observation give a `DocumentState` per document: the settlement (`draft`, `open`,
  `partlyPaid`, `paid`, `overpaid`, `settledByAdvances`, `closedUnpaid`), the net paid and outstanding
  amounts, overdue and days overdue (issued, open or partly paid, not closed, due date before today;
  payment tax documents are never overdue), whether every received payment of an advance has its issued
  tax document, which final invoices deducted it, and the closing event. It is computed from the rows in
  one read with three aggregate queries, so a list of a thousand documents costs four statements, and a
  GRDB `ValueObservation` can watch it. The design system's `DocumentStateInputs` is filled from it one
  to one, with `taxDocumentRequired` fixed to true until the customer setting exists (screens-flows §6,
  question 5). A final invoice whose advances exceed the supply reads as overpaid: the customer holds the
  difference.
- **The variable symbol takes the series prefix.** `issue` derives the symbol with the series'
  `variableSymbolPrefix` (ADR 0003 addendum); a draft that brought its own symbol keeps it. The prefix is
  stored with the series and editable like its name.
- **Integrity on demand.** `verifyIntegrity(id:)` recomputes the SHA-256 of an issued document's snapshot
  and compares it with the stored hash (§ 35a odst. 3 ZDPH).
- **Schema v1 is changed in place** because nothing has been released; from the first release on, every
  change is a new migration (ADR 0005).

## Alternatives rejected

- A `status` column updated on the document row for paid/overdue/closed: the row is frozen, the facts
  change daily (overdue), and a stored status drifts from the payments.
- Separate tables for refunds and credits: three sums instead of one, and the bank matching would have to
  know three shapes of a payment.
- Refusing a final invoice that deducts a receipt the database does not know: it would block the first
  final invoices after moving from another tool.
- Deleting closing events silently: `reopen` is an audited action, like the close.

## Consequences

- The UI builds badges from `DocumentState` without reading payments itself; lists observe
  `observeStates` and re-render on any change.
- The v0.2 bank import gets refunds for free: a debit line matched to an overpaid document becomes a
  `refund` payment.
- Open for later: a customer setting for advances without payment tax documents (question 5), a payment
  `source` for credit notes (Phase 2), and the per-country variable symbol habits of EU customers, who pay
  by the ISO 11649 reference instead.
