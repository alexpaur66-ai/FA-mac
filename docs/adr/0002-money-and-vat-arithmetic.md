# ADR 0002: Money and VAT arithmetic

Date: 2026-11-05 · Status: accepted, open to the adversarial review

## Decision

- All amounts are `Decimal`. `Double` never appears in `InvoicingCore`; tests build decimals from
  text, never from floating-point literals.
- Rounding is half away from zero (`NSDecimalNumber.RoundingMode.plain`), the arithmetic rounding
  used on Czech documents, to the currency's minor units (2 for CZK and EUR). Other modes exist
  only for explicit callers.
- Line total = quantity × unit price × (1 − discount %), rounded to the document scale.
- Tax is computed per rate on the summed base of that rate (§ 37 písm. a) ZDPH), not by adding
  rounded per-line taxes. Per-line tax is shown for information only and may differ by a haléř
  from the summary; the summary is what the document reports.
- Gross pricing uses the coefficient of § 37 písm. b): base = gross ÷ 1.21 (or 1.12), tax = gross − base,
  again on the summed gross per rate.
- Lines without Czech VAT (reverse charge § 9 odst. 1 to an EU business, services outside the EU,
  exempt supplies) form their own summary rows with no rate and zero tax; exempt rows are grouped by
  the provision they cite.
- VAT percentages are looked up by date: 21/15 from 2013, 21/15/10 from 2015, 21/12 from 1 Jan 2024.
  A kind that did not exist on the document date is an error, not zero.
- Exchange rates are stored the ČNB way (amount of currency → CZK, three decimals) with the day they
  are valid for and their source. For a day without a published rate (weekend, holiday) the table
  returns the last rate published on or before that day; whether that matches the company's
  accounting policy is for the accountant to confirm (§ 4 odst. 8 ZDPH).
- Storage form of money is integer minor units plus the currency code; `Money.minorUnits` and
  `Money(minorUnits:currency:)` are the only conversions. `Money.minorUnitsIfRepresentable` is the
  same conversion returning nil for an amount outside the `Int64` range, where `minorUnits` traps
  instead of storing a wrong integer. The minor units of a currency follow from its code alone
  (0 for JPY, KRW and ISK, 2 otherwise), so a stored code always restores the same scale.

## Alternatives rejected

- Summing rounded per-line tax: drifts from base × rate on documents with many small lines and
  would make the summary disagree with § 37 arithmetic.
- Banker's rounding as the default: not what Czech documents use.
- Storing rates as CZK per unit: loses the published form for currencies quoted per 100 or 1000
  and makes the label on the document differ from the ČNB table.

## Consequences

- `VATCalculator.compute` is a pure function of lines, pricing mode, date and scale; it has no
  state and is fully covered by `Tests/InvoicingCoreTests/VATTests.swift`.
- Rounding of a CZK total to whole crowns and the handling of that rounding difference in VAT is a
  separate, later decision (document model PR).
