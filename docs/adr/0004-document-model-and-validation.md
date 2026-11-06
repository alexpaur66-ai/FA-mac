# ADR 0004: Document model, totals, deadlines and validation

Date: 2026-11-05 · Status: accepted, open to the adversarial review

## Context

v0.1 issues four kinds of documents (proposal, "Document types"): the regular invoice, the advance
request, the tax document for a received payment and the final invoice that deducts advances. Every
tax document must carry the items of § 29 ZDPH and the business-letter data of § 435 občanského
zákoníku, must be issued within the § 28 deadline, and must show the VAT in CZK (§ 29 odst. 1 písm. l),
§ 4 odst. 8). The arithmetic of lines and rates is ADR 0002; this ADR covers the document around it.

## Decisions

- One `Document` type for all four kinds, distinguished by `DocumentKind`. The kind decides whether the
  document is a tax document (everything but the advance request), whether it deducts advances (the
  final invoice only) and which clauses it prints. Four separate types would repeat every field and
  every rule for a difference of two flags.
- The supplier and the customer are stored on the document as `Party` snapshots, not as references.
  An issued document must read later exactly as it was issued (§ 35 ZDPH), whatever happens to the
  company profile or the customer card.
- Dates: `issueDate` (písm. g)), `taxPointDate` (písm. h): the date of taxable supply, or the day the
  payment was received on a payment tax document; nil on an advance request) and `dueDate`. The
  "tax point" used for rates, deadlines and the exchange rate is `taxPointDate ?? issueDate`.
- Advance deductions (§ 37a) are rows on the final invoice, one per payment tax document and VAT
  treatment, carrying the base, the VAT, the rate and the exchange rate the advance was taxed at. The final invoice's
  tax base per treatment is the base of the supply minus the deducted bases; a positive difference is
  taxed at the rate of the day of supply, a negative one at the rate applied to the advance
  (§ 37a odst. 2). An advance taxed under another taxable rate kind than any line (a 2023 advance at
  the reduced 15 % for a supply now at the standard rate) is deducted from the document's taxable
  supply when there is exactly one taxable group, so § 37a odst. 1 takes one difference for the one
  supply; otherwise, and for advances under a treatment without Czech VAT and no line, it appears as a
  deduction-only row, and a taxed deduction-only row next to a taxable supply raises the
  `advanceRateDiffers` warning. Each summary row also carries the percentage its VAT was computed at
  (`appliedRatePercent`), which is what the document prints with the row (§ 29 odst. 1 písm. k)). When
  no advance is deducted the VAT is exactly the calculator's, so a regular invoice never changes.
- A deduction is in the final invoice's currency: `AdvanceDeduction.currency` records the currency of
  the payment tax document (nil on data stored before the field existed) and a deduction in another
  currency is an error. Deducting the same payment tax document twice under the same treatment is an
  error too.
- The amount due is, per summary row, the gross of the supply minus the gross of the advances actually
  paid when the advances were taxed at the row's own rate, so a haléř of rounding in the recomputed
  § 37a VAT never changes what the customer is asked to pay; where the rates differ it is the taxable
  base plus the VAT, because § 37a moves the tax.
- The payment tax document built from an advance request splits the received amount across the
  request's VAT treatments in proportion to their gross on the request, one gross line per treatment,
  the last line taking the rounding remainder; the user may edit the lines when the customer
  designated the payment differently.
- Mixed rates between advance and supply (§ 37a odst. 3) are not computed automatically; the validator
  raises a warning for the accountant.
- CZK equivalents convert the base and the VAT of each summary row separately with
  `ExchangeRate.toCZK`, rounded to haléře, and the totals are sums of the rows, so the CZK summary
  always adds up. The rate is stored on the document itself (§ 4 odst. 8: the rate valid on the day the
  obligation arose), never looked up again later. A row with a negative difference is converted at the
  exchange rate that was applied to the advance (§ 37a odst. 2 písm. b), verified against the 2026 text:
  "sazba daně a kurz … které byly uplatněny při přiznání daně z úplaty"), which the deduction carries from
  the payment tax document; the row records the rate it used and the document prints it in a clause.
  When the row's advances were converted at different rates, or a deduction has none (data before the
  field existed), the document's rate is used and the `advanceExchangeRateDiffers` warning asks the
  accountant, as § 37a odst. 3 is not computed.
- The exchange rate is required on every tax document in a foreign currency. Without Czech VAT (reverse
  charge, outside the EU; judged per summary row, not on the net VAT, so rows that net to zero still
  need it) it is a warning, because no CZK tax amount is printed, but the souhrnné
  hlášení still needs CZK values. A rate dated after the tax point is an error; a rate more than seven
  days before it is a warning ("the rate table is probably incomplete"): the ČNB publishes every
  working day, so a gap longer than a long weekend means missing data, not a holiday. The seven-day
  limit is the answer to the review team's open question on `ExchangeRateTable` and is for the
  accountant to confirm.
- `DocumentValidator` returns issues, never throws: errors block issuing, warnings are shown. Every
  issue has a stable code, an optional line id and messages in Czech and English, so the UI never
  composes legal texts itself. Dates travel in `detail` as ISO strings and are printed the Czech way in
  Czech messages. An address is complete with a street, a city and a two-letter country code.
- A tax point after the issue date is a warning, not an error: a service is deemed supplied no later
  than the day its tax document is issued (§ 21 odst. 3), so the message recommends DUZP = issue date
  for supplies with Czech VAT, but goods may be invoiced before delivery and EU services follow
  § 24a odst. 2.
- The § 28 deadline is the strictest over the document's treatments: 15 days from the tax point for
  supplies taxed or exempt in the Czech Republic (odst. 8), 15 days from the end of the month for
  services with the place of supply abroad and advances on them (odst. 9 písm. b)–d)). A late
  document is a warning, because the law does not forbid issuing it, it only makes it late.
- Clauses are derived, not typed: "Daň odvede zákazník" for reverse charge (the Czech wording is
  prescribed by § 29 odst. 2 písm. c), so it stays on English documents, followed by an English
  explanation citing Article 196 of Directive 2006/112/EC), the exemption reference, the outside-scope
  note, "not a tax document" on advance requests, the payment-received sentence, the advances-deducted
  sentence, the exchange-rate note and, after it, the advance-rate note for a negative difference.
- Payment QR codes are built from the document and its totals: QR platba for CZK, the EPC code for EUR
  (ADR 0003). The variable symbol and the ISO 11649 reference are derived from the document number by
  default and stored with the document, so a renumbering scheme later cannot change an issued code.
- Negative quantities are rejected for now; corrective tax documents (§ 45) are Phase 2 and will come
  with their own kind and rules rather than as negative lines on an invoice. Negative prices are allowed
  only as discounts inside a positive document: a negative amount due or a negative VAT summary row is
  an error on every kind except the final invoice (where advances above the supply stay a warning), and
  a payment tax document must be for a positive amount.

## Alternatives rejected

- Separate types per document kind: duplicated rules, no shared validation.
- Looking the exchange rate up at print time: the printed CZK amount could change after issue.
- Converting the EUR totals once and deriving the CZK VAT from the CZK base: the VAT is what the law
  wants in CZK, and the row-by-row conversion keeps the printed summary consistent.
- Throwing validation: a document with three problems should show three problems, not the first one.

## Amendments (PR 21, EU goods, November 2026)

ADR 0011 adds goods supplied to a business in another member state, exempt under § 64 odst. 1; the rest
of this ADR stands.

- **Treatments**: `VATTreatment.intraCommunityGoods` joins Czech VAT, the reverse charge, outside the
  EU and the other exemptions. It needs the customer's VAT ID from another member state (an error
  without it, § 64 odst. 1 písm. a)) and goes into the souhrnné hlášení.
- **Deadline**: 15 days after the end of the month of the supply (§ 28 odst. 9 písm. a)).
- **Tax point after the issue date**: not warned on a document whose lines are all § 64 goods, as goods
  may be invoiced before they leave.
- **Exchange rate**: § 4 odst. 8 asks for the rate of the day the obligation to declare the tax or the
  supply arose. On a document whose lines are all § 64 goods that is the § 22 odst. 1 day
  (`Document.exchangeRateDay`: the 15th of the month after the supply, or the earlier issue date), not
  the tax point, and the error for a rate dated after the day and the seven-day staleness warning use
  that day. Every other document, a mixed one and a payment tax document included, keeps the tax point
  (ACCT).
- **Clauses**: the § 64 reference replaces „daň odvede zákazník“ on goods; the English line adds Article
  138 of Directive 2006/112/EC.
