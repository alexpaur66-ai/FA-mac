# ADR 0011: EU goods exempt under § 64

Date: 2026-11-05 · Status: accepted, open to the adversarial review

## Context

Until now the core knew one treatment for an EU business: the reverse charge for a service with the
place of supply in the customer's state (§ 9 odst. 1 ZDPH), printed with „daň odvede zákazník“
(§ 29 odst. 2 písm. c)). On 5 Nov 2026 Saša answered that about 90 % of the sales are goods. Goods
dispatched or transported from the Czech Republic to a business registered for VAT in another member
state are not reverse charged: the supply is exempt with the right to deduct under § 64 odst. 1, and a
goods invoice with the services clause would be a wrong tax document.

The rules below were read on 5 Nov 2026 from the full text of ZDPH in force from 1 Jan 2026 (downloaded
from e-Sbírka, `/mnt/project-files/zakony/` in the project) and Article 138 of Directive 2006/112/EC on
EUR-Lex (consolidated version of 1 Jan 2025):

- § 64 odst. 1: a supply of goods to a person registered for VAT in another member state is exempt with
  the right to deduct when (a) that person gave the supplier its VAT ID, (b) the goods are dispatched or
  transported from the Czech Republic to another member state by the supplier, the customer or a third
  person authorised by either of them, and (c) the supplier reports the supply in the souhrnné hlášení.
- § 29 odst. 2 písm. a): the document cites the provision of the exemption; § 29 odst. 3 písm. e) bod 1:
  no rate and no tax on an exempt supply.
- § 28 odst. 9 písm. a): the document is issued within 15 days after the end of the month of the supply.
- § 22 odst. 1: the supply is declared on the 15th day of the month after the supply, or on the issue
  date when the document was issued before that day.
- § 102 odst. 1 písm. a): the supply goes into the souhrnné hlášení.

The names and the order in the app are the design thread's (5 Nov 2026).

## Decisions

- **`VATTreatment.intraCommunityGoods`**, a new case: no Czech VAT, the customer's VAT ID from another
  member state required (`requiresCustomerVATID`), reported in the souhrnné hlášení
  (`reportedInECSalesList`). Existing documents are untouched, as no stored value changes meaning.
- **The clause** `DocumentClause.intraCommunitySupply` is the § 29 odst. 2 písm. a) reference, not
  „daň odvede zákazník“: "Dodání zboží do jiného členského státu, osvobozeno od daně podle § 64 odst. 1
  zákona č. 235/2004 Sb., o dani z přidané hodnoty." On a bilingual document the English line adds
  Article 138 of the Directive: "Intra-Community supply of goods, exempt from VAT under Section 64(1) of
  the Czech VAT Act and Article 138 of Council Directive 2006/112/EC." Both are ACCT.
- **PDF**: no rate, base or VAT columns (as for every treatment without Czech VAT, ADR 0010), the
  summary caption "EU – dodání zboží, osvobozeno (§ 64) / intra-Community supply of goods, exempt"
  (ACCT) and "—" in the rate cell.
- **Validator**: a missing customer VAT ID, or one that is not from another EU member state, is an error
  with its own messages citing § 64 odst. 1 písm. a) and § 29 odst. 1 písm. d)
  (`intraCommunityGoodsVATIdentifierRequired`, `intraCommunityGoodsVATIdentifierNotEU`). The warning
  about a tax point after the issue date is a services rule (§ 21 odst. 3, ADR 0004); goods may be
  invoiced before they leave, so a document whose lines are all § 64 goods does not get it.
- **Deadline** (`IssueDeadline`): 15 days after the end of the month of the supply.
- **Reporting day** (`ReportingDay.day(treatment:taxPoint:issueDate:)`): the § 22 day for § 64 goods,
  the tax point for every other treatment. It is there for the accountant export, which is not built
  yet. The Overview VAT figure counts Czech VAT only and does not change.
- **Client VAT status**: `euBusiness` splits into `euBusinessGoods` (the status an EU VAT ID now
  implies) and `euBusinessServices`, which keeps the stored value "euBusiness", so a client saved before
  keeps the reverse charge. `defaultServiceTreatment` is renamed `defaultTreatment`. There is no new
  client field.
- **App** (design thread's names):
  - The editor's pop-up lists "EU goods, exempt (§ 64)" and "EU services, reverse charge", a divider,
    then "Czech VAT (rate per line)", "Outside EU, services" and "Other exemption". Document ▸ VAT
    Treatment has the same order in title case, with no ellipsis, as no item opens a dialog.
  - The client suggestion line and the Issue summary use the short forms ("EU goods, exempt", "EU
    services, reverse charge", "Czech VAT", "Outside EU, services", "Other exemption").
  - The totals bar and the Issue sheet show "Exempt (§ 64)" with a dash in the VAT place. This is
    interim: the design thread's proposed cuts give every treatment without Czech VAT "Total · <short
    form>".
  - A § 64 line's VAT rate cell reads "exempt". The "VAT ID missing" chip shows for goods as for
    services.
  - The client form offers "EU business, goods", "EU business, services" and "Business outside the EU,
    services". A new client starts as "EU business, goods". A goods client without a VAT ID gets "The
    § 64 exemption needs the client's VAT ID. Add it to issue documents for this client."; the services
    sentence stays.
  - Duplicate as Draft keeps the source's treatment. The existing "differs from the client's default"
    check catches a services invoice to a goods client and the other way round.

## Not covered yet

- **Advances on § 64 goods** come with the next PR, to the design thread's spec: no payment tax
  document (§ 28 odst. 1 písm. d) asks for one only when a duty to declare arose on the payment day; the
  advance rule of § 20a odst. 2 covers taxable supplies, which an exempt supply is not (§ 2 odst. 2), and
  § 22 has no rule for payments), and the final invoice lowers the amount due without a § 37a deduction
  (ACCT). Until then the advance flow is unchanged and offers a payment tax document that a § 64
  advance does not need, so advances for EU goods should wait.
- Goods exported outside the EU (§ 66), distance sales to EU consumers, triangular trade and call-off
  stock are not offered. They are for the accountant when such a client appears.
- The proof that the goods left the country (§ 64 odst. 1 písm. b)) is kept outside the app.
- The month a § 64 supply counts in for the accountant export follows the § 22 day; the accountant
  confirms this before the export is built.

## Alternatives rejected

- `.exempt(reference: "§ 64 odst. 1")`: the free exemption does not require the customer's VAT ID, is
  not reported in the souhrnné hlášení and has the § 28 odst. 8 deadline. All three are wrong for goods.
- A goods-or-services flag on each line: the treatment is chosen per document; mixed documents are the
  accountant's call (screens-flows.md §2c).
- One EU business status with the kind guessed from the lines: a new document needs the client's usual
  kind before it has lines.

## Consequences

- A client saved as an EU business before this change reads "EU business, services" and keeps the
  reverse charge until its status is switched to goods.
- The clause, the PDF caption and the § 22 month are on the accountant's checklist before the first real
  goods invoice.
