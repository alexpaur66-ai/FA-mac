# ADR 0012: Advances paid on EU goods

Date: 2026-11-05 · Status: accepted, open to the adversarial review

## Context

Most of Saša's sales are goods to businesses in other member states, exempt under § 64 odst. 1 ZDPH
(ADR 0011). Until now every advance request went through the flow of ADR 0007: a payment received, its
payment tax document (daňový doklad k přijaté platbě) within 15 days, and the final invoice deducting that
document under § 37a. For a § 64 supply the flow asks for a document the law does not.

Read on 5 Nov 2026 from the full text of ZDPH in force from 1 Jan 2026 (downloaded from e-Sbírka,
`/mnt/project-files/zakony/` in the project):

- § 2 odst. 2: a taxable supply (zdanitelné plnění) is one that is subject to tax and not exempt. A § 64
  supply is exempt.
- § 20a odst. 2: a payment received before a taxable supply makes the tax due on the day it is received.
  It speaks of taxable supplies only.
- § 22 odst. 1: a § 64 supply is declared on the 15th day of the month after it, or on the earlier issue
  date. Unlike § 24a odst. 3 for services, § 22 has no rule for payments received before the supply.
- § 28 odst. 1 písm. d): a tax document for a received payment is required only when a duty to declare
  the tax or the supply arose on the day it was received.

So a payment on an advance for § 64 goods needs no payment tax document, and the final invoice has
nothing to deduct under § 37a: it states the whole exempt value and lowers only what is left to pay. This
reading is on the accountant's checklist (ACCT).

The names, the wording and the steps are the design thread's spec of 5 Nov 2026.

## Decisions

- **`PaidAdvance`**, a row of a final invoice: the advance's number, the day it was paid, the amount and
  currency, the stored payment's id (`paymentID`, nil for an advance from before the app) and the
  advance's treatment (`advanceTreatment`). `Document.paidAdvances` is optional, so a snapshot saved before
  the field decodes as nil and encodes as before, and no stored hash changes.
- **Totals**: `DocumentTotals.paidInAdvance` is the sum of the rows in the document's currency, and
  `amountDue` is what the summary leaves due minus it. The § 64 value, the summary and every figure the
  souhrnné hlášení will read stay the full supply. `dueBeforePaidInAdvance` is the amount due before the
  advances paid. The payment QR codes ask for the balance.
- **Validator**: errors when a document other than a final invoice lists advances paid
  (`paidAdvancesOnWrongKind`), a row has no advance number (`paidAdvanceNumberMissing`), a row is zero or
  negative (`paidAdvanceAmountNotPositive`), in another currency (`paidAdvanceCurrencyDiffers`), or names a
  payment twice (`paidAdvanceListedTwice`). Warnings when the advance was issued under another treatment
  (`paidAdvanceTreatmentDiffers`: the accountant decides whether that payment needed a tax document, ACCT)
  and when the advances paid exceed the total (`paidInAdvanceExceedsTotal`). One issue per rule names every
  advance it concerns.
- **PDF** (ACCT): a totals row "Uhrazené zálohy / Advances paid" with the minus sum before "K úhradě",
  and below the summary the same heading with one line per row: "Záloha ZF 2026-0003 uhrazena
  12. 11. 2026 / Advance ZF 2026-0003 paid on 12. 11. 2026: −4 000,00 €". No tax document, rate or VAT
  column, and the summary is not reduced. The goods advance request itself prints only "Toto není daňový
  doklad. / This is not a tax document." without the sentence that promises a tax document on payment
  (`DocumentClause.notATaxDocumentForGoods`); an advance with any other line keeps that sentence.
- **Data, schema v3** (ADR 0005, append-only):
  - The `paidAdvance` table links an issued final invoice to each payment it settled: the payment (unique,
    so one final invoice settles a payment), the advance request, the numbers and the amount in minor units.
    Written in the issue transaction (`linkPaidAdvances`) and frozen by triggers like the final invoice: no
    update, no delete, and no insert that would replace a link (its id or its payment).
  - A row must name a stored payment received on the issued advance request of that number, for the same
    customer and currency, on the row's day and for at most the payment's amount, without an issued payment
    tax document (such a payment is deducted under § 37a instead) and settled by no other final invoice
    (`advanceAlreadySettled`). What final invoices settle on one advance may not exceed what it holds after
    refunds, less what its payments with an issued payment tax document received, which a final invoice
    deducts under § 37a instead (an advance that took such documents before v3; `paidAdvancesExceedPaid`).
    An advance number the database does not know is allowed without a payment and named in the audit event
    (`externalPaidAdvances`), as ADR 0007 does for deductions; a known number without a payment is refused.
    Any refusal rolls the issue back, so no number is used up.
  - A settled payment is locked: triggers stop changes to its money and its deletion, the store refuses a
    payment tax document for it (`paymentSettled`, also when such a draft is issued), and deleting the other
    leg of an applied credit that was settled is refused (`relatedPaymentSettled`). A refund or credit moved
    away from the advance may take only what the final invoices did not settle and its issued payment tax
    documents do not cover (`refundExceedsAvailable`). Deleting a payment row of such an advance is refused
    when the advance would then hold less than those two together, or keep money no final invoice can list
    because a payment was settled net of the refund or credit deleted (`paymentBacksSettlement`).
  - Two document columns spare the lists a snapshot decode: `paidInAdvance` (minor units, NULL when none)
    and `treatments` (the lines' treatments as a JSON array). Rows written before v3 have NULL in both:
    they had no advances paid, and the store reads their treatments from the snapshot.
- **States**: an issued advance request whose lines are all § 64 goods has `taxDocumentRequired` false,
  which the badge rules already knew (screens-flows.md §6, question 5): it reads "Paid" after its payment,
  and "Settled in final invoice" once a final invoice settled one of its payments (`deductedInFinal`,
  `deductedBy`). An advance with any other line keeps the payment tax document flow, and so does one whose
  payments already have a payment tax document (a draft or an issued one, made before v3), so its badges and
  tax documents read as before.
- **App** (design thread's names):
  - Record Payment on a goods advance ends with "Payment recorded. An advance for EU goods needs no tax
    document: the final invoice lists it as paid in advance." and the default button "Create Final
    Invoice" (↩), with Later (⎋). Create Tax Document is not offered for such an advance. Once a final
    invoice settled the advance, the step says "Payment recorded. An advance for EU goods needs no tax
    document." with Later only: the Document menu offers no second final invoice for it either, and Create
    Final Invoice reached any other way names the final invoice instead of drafting one.
  - Create Final Invoice from a goods advance lists its open payments under "Paid in advance" instead of
    refusing while they have no tax document. Each payment is offered for at most what the advance still
    holds.
  - The editor's final invoice shows the "Paid in advance" section when it has § 64 lines or rows: one row
    per payment ("ZF 2026-0003 · paid 12. 11. 2026", the amount, a remove button), "Add Paid Advance…" for
    the client's other open goods advances in the document's currency, and the conflicts with other drafts
    in the same place as for deductions. The deductions section stays for a final invoice that is not all
    goods.
  - The totals bar and the Issue sheet show "Paid in advance −4 000,00 €" between the total and the amount
    due. The detail shows "Paid in advance" with links to the advances, "Settled in" on the advance, and a
    lock with "Payment is settled in <number> and can't be deleted" on a settled payment row.
  - The Overview counts a final invoice's advances paid in its month's revenue, since they had no tax
    document of their own, and leaves goods advances out of the received-without-tax-document queue.

## Not covered yet

- The editor offers stored payments only. An advance paid before the app can be listed by number without a
  payment in the data layer, but there is no field to type one yet.
- The accountant export (CSV) is not built. When it is: `DeductedAdvance` filled, `DeductedVAT_CZK`
  empty for advances paid, per the design thread's spec.
- An advance with § 64 lines and lines under another treatment keeps the payment tax document flow. Mixed
  documents are the accountant's call (ADR 0011).
- Payments & Bank shows a settled payment like any other; deleting it there shows the store's refusal.
- The § 22 month of the final invoice, as in ADR 0011, needs the accountant's confirmation before the
  export.

## Alternatives rejected

- A payment tax document with a § 64 reference and a § 37a deduction on the final invoice: the law does
  not ask for the document, and the deduction would lower the exempt value the souhrnné hlášení reports.
- Lowering the summary or the lines by the advance: the exempt value of the supply is the full price.
- One row per advance request instead of per payment: a payment is what gets locked and what the bank line
  matches, and an advance paid in two parts has two days.
- Recomputing the advances paid when the final invoice is opened: an issued document shows what was
  issued, and the snapshot holds it.

## Consequences

- An advance for EU goods goes Advance → Payment → Final invoice without a tax document in between.
- The data layer already accepts an advance paid before the app by its number and names it in the audit
  event, so a field to type one is a UI change only.
- The wording of the PDF lines, the missing tax document and the full § 64 value are on the accountant's
  checklist before the first real goods advance.
