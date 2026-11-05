# ADR 0003: Payment QR strings (QR platba and SEPA EPC QR)

Date: 2026-11-05 · Status: accepted, open to the adversarial review

## Decision

- Two payload generators live in `InvoicingCore/Payments`; drawing the QR image is the app's job
  (Core Image), so the core stays free of graphics and testable on Linux.
- QR platba (SPAYD 1.0, specification at qr-platba.cz, read 5 Nov 2026): header `SPD*1.0`, fields
  `KEY:VALUE` joined by `*`, no trailing `*`. Emitted keys: ACC (IBAN, `+BIC` when known), AM (two
  decimals, ≤ 9 999 999,99), CC, RF, RN, DT, PT, MSG, X-VS, X-SS, X-KS. The optional CRC32 field is
  not produced: the specification page does not define the exact string it is computed over and no
  bank requires it.
- MSG and RN are by default stripped of diacritics, upper-cased and whitespace-collapsed so they fit
  the QR alphanumeric mode the specification recommends; `*` and `%` are always percent-encoded;
  characters outside ISO-8859-1 are percent-encoded as UTF-8 (the mechanism the specification names).
  Length limits are enforced after encoding and reported as errors, never truncated silently.
- Payment symbols are emitted with their digits as entered (leading zeros kept), so the QR matches
  the symbol printed on the document.
- SEPA EPC QR (EPC069-12 v3.1, 19 March 2024, read from the EPC PDF on 5 Nov 2026): version 002 by
  default (BIC optional), character set 1 (UTF-8, so Czech names keep their diacritics), LF
  separators, the last populated element without a separator, payload ≤ 331 bytes, amounts
  `EUR` + two decimals within 0.01…999 999 999.99, structured remittance ≤ 35 as an ISO 11649
  creditor reference, unstructured ≤ 140, the two mutually exclusive. The QR image must use error
  correction level M and at most version 13; the generator exposes both constants.
- `CreditorReference` implements ISO 11649 (RF + check digits + ≤ 21 characters) with the IBAN
  mod-97 routine, so EU customers' payments can carry a machine-readable invoice reference.
- `BIC` validates only the ISO 9362 shape (8 or 11 characters, first six letters).

## Alternatives rejected

- Keeping diacritics in QR platba messages: legal in the format but forces the QR into byte mode
  and larger codes; Czech banking apps display upper-case ASCII messages without complaint.
- Silently truncating overlong messages as the specification allows the reader to do: the document
  would show one text and the QR another.
- Version 001 EPC QR by default: it demands a BIC the user may not know; 002 is the EEA default.

## Consequences

- The document layer decides what goes into MSG and remittance (document number, variable symbol),
  and chooses QR platba for CZK accounts and the EPC QR for EUR; both can be printed side by side.
- Tests pin the specification example string from qr-platba.cz and the EPC element order.
