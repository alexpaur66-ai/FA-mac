# ADR 0006: Parties: IČO, DIČ and VAT ID, postal address, registry entry, bank connection, customer

Date: 2026-11-05 · Status: accepted (the code merged in PR #4 after the review team's pass; this record
was written afterwards and describes the code as merged)

## Context

Every tax document names the supplier and the customer with their seat and their tax identifiers
(§ 29 odst. 1 písm. a) až d) ZDPH; the customer's DIČ may be left out only when none was assigned,
§ 29 odst. 3 písm. b)). A Czech company's business documents must also carry its IČO and its entry in
the commercial register with the court, the oddíl and the vložka (§ 435 odst. 1 občanského zákoníku).
The customer's VAT standing decides the default VAT treatment of the lines: Czech VAT, reverse charge
within the EU, or outside the scope of Czech VAT for businesses in third countries. The app is offline
(ADR 0001), so nothing can be looked up in ARES or VIES: the value types check what a shape check can
check and leave the rest to the user and the accountant.

## Decisions

- `Party` is a value type: name, `PostalAddress`, optional `IdentificationNumber` (IČO), optional
  `VATIdentifier` (DIČ or a foreign VAT ID), optional `RegistryEntry`, email and phone. Documents store
  `Party` snapshots (ADR 0004), so a party has no identity of its own; `Customer` wraps a party with an
  id for the light CRM.
- `IdentificationNumber` holds exactly eight digits. Input may contain spaces and fewer digits; it is
  left-padded with zeros, as the registers print "00006947". The modulo-11 check must pass (the first
  seven digits weighted 8…2, summed; the check digit is (11 − sum mod 11) mod 10), otherwise the
  initialiser returns nil. Decoding goes through the same initialiser, so stored data cannot carry an
  invalid IČO.
- `VATIdentifier` checks the shape only: whitespace, hyphens and dots are removed, 4 to 16 ASCII
  characters remain, two letters followed by letters and digits. Non-ASCII input is rejected before
  uppercasing, because uppercasing would fold "ß" to "SS" and change the length. A Czech number must be
  eight digits that pass the IČO check (companies) or nine or ten digits (natural persons). Greece's
  ISO code "GR" is accepted and stored as the VAT prefix "EL"; `isEU` covers the prefixes of the 27
  member states; Northern Ireland's "XI" is left out because it applies to goods only and this app
  invoices services. Whether a foreign number is registered (VIES) cannot be checked offline, so the
  document validator asks the user to confirm it instead.
- `PostalAddress` normalises on init and on decode: trimmed street and city, uppercase ISO 3166-1
  alpha-2 country code, Czech postal codes stored as five digits and printed as "110 00". The street
  may hold a second line separated by any newline, "\r\n" from pasted Windows text included. The country
  line is printed for foreign addresses, or always when the document asks for it (documents for foreign
  customers name the supplier's country too); the caller passes the localised country name, otherwise
  the ISO code is printed.
- `RegistryEntry` is failable: § 435 odst. 1 requires both the oddíl and the vložka, so an entry with
  either empty is nil instead of printing "vložka .". The section's first letter is capitalised ("c"
  becomes "C", "dr" becomes "Dr", "Dr" stays). `RegistryCourt` enumerates the seven courts that keep the
  register, each with the nominative, the instrumental ("vedeném Městským soudem v Praze") and an
  English name, so the register sentence is built from grammar-safe parts rather than typed by hand.
- `CustomerVATStatus` has six cases: `czechVATPayer`, `czechNonPayer`, `euBusiness`, `euConsumer`,
  `nonEUBusiness`, `nonEUConsumer`. The default treatment follows the general place-of-supply rule for
  services (§ 9 ZDPH): Czech VAT for Czech customers and for consumers everywhere, reverse charge for an
  EU business with a VAT ID, outside the scope of Czech VAT for a business outside the EU. The document
  must carry the customer's VAT ID for `czechVATPayer` and `euBusiness` (§ 29 odst. 1 písm. d)). Goods
  and the special services of § 10 to § 10i differ, so the user can override the treatment on each
  line; § 10h for consumers outside the EU is the accountant's call. When no status is given it is
  inferred from the VAT identifier and the country of the seat: a Czech identifier means a Czech VAT
  payer, an EU prefix an EU business, any other identifier a non-EU business; without an identifier a
  customer in CZ is a non-payer and a customer elsewhere a consumer (EU by the prefix list, "GR"
  counted as "EL").
- `Customer` = id, `Party`, `vatStatus`, `currency` (default CZK), `paymentTermDays` (default 14),
  `DocumentLanguage` (default Czech for a Czech address, otherwise English) and notes.
- `BankConnection` is the account the supplier wants to be paid to: an `IBAN` always, an optional `BIC`
  for payments from abroad, the bank name and the account's currency (nil when the account is
  multi-currency or unknown). It can be built from a Czech domestic account number and fails when that
  number does not form a valid IBAN. A Czech document prints the domestic form when there is one,
  otherwise the formatted IBAN. `IBAN` and `CzechBankAccount` are the banking types of the core
  foundation (ADR 0002); `BIC` belongs to the payment strings (ADR 0003).

## Alternatives rejected

- Looking up IČO and DIČ in ARES or VIES when a customer is entered: needs the network entitlement the
  app deliberately lacks (ADR 0001). The IČO check digit catches typing errors; foreign VAT IDs are
  confirmed by the user.
- A free-text register sentence typed by the user: declension mistakes and a missing oddíl or vložka
  would print on every document. The court enumeration carries the grammar instead.
- Storing the Greek prefix as entered ("GR"): a Greek business would look like a non-EU customer and
  lose the reverse charge. It is stored as "EL", as VAT law writes it.
- Per-country checks of foreign postal codes and VAT-number shapes: more than 27 formats to keep
  current offline, for little gain. Only Czech values are checked; per-country warnings may come later.

## Consequences

- Decoding stored data re-applies the checks: a snapshot with an invalid IČO, an invalid VAT ID or an
  empty registry section fails to decode instead of printing wrong data. Such data can only come from a
  bug, because the validator runs before a document is issued and the stores save what the types
  accepted (ADR 0005).
- The UI shows the IČO and the DIČ with validation feedback as they are typed, the register entry as a
  court picker plus oddíl and vložka fields, and the customer's VAT status with the inferred default
  and the VAT treatment it implies.
- Noted for later, not defects: a warning when a Czech DIČ does not match the IČO; a per-country shape
  warning for foreign VAT numbers; a switch for a customer outside the EU without a VAT ID (business or
  consumer; today a consumer, so Czech VAT is charged by default); per-country postal code checks.
