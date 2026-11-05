# ADR 0005: SQLite data layer — snapshots, frozen documents, audit trail

Date: 2026-11-05 · Status: accepted, open to the adversarial review

## Context

ADR 0001 chose SQLite through GRDB and promised frozen issued documents with an audit log. The core
(ADR 0002–0004) now has every value the app stores: `Document`, `Customer`, `CompanyProfile`,
`DocumentNumberSeries`, `ExchangeRate`. This ADR fixes how they are kept on disk and what the stores
guarantee. § 35 ZDPH keeps tax documents for ten years; § 35a odst. 3 asks electronic storage to keep
data that guarantee the authenticity of origin and the integrity of the document.

## Decisions

- **One SQLite file, one `DatabaseQueue`.** A single-user Mac app needs one writer; every `write` is a
  transaction. Rollback-journal mode (SQLite's default), not WAL: no `-wal`/`-shm` sidecar files, so a
  copy of the file taken while the app is closed is a complete backup, and Time Machine sees one file.
- **Snapshot plus columns.** Documents, customers and the profile are stored as JSON (sorted keys) of the
  InvoicingCore value, next to the columns the lists, filters and reports need (kind, status, number,
  dates, customer, totals in minor units, CZK VAT, variable symbol). The snapshot is the legal artefact and
  reads back exactly as written; the columns are derived from it on every save. Lines are inside the
  snapshot: nothing queries lines yet, and a `documentLine` table can be filled from the snapshots by a
  later migration if reporting needs it.
- **Issued documents are frozen twice.** `DocumentStore` refuses to update or delete an issued row, and
  SQLite triggers abort any `UPDATE` or `DELETE` of a row whose status is `issued`, and any `INSERT` that
  would overwrite it through `REPLACE` (same id, or an issued number), so no code path, not even raw SQL,
  can change an issued document. Payments and audit events live in their own tables.
  Corrections are new documents (§ 45, Phase 2).
- **Issuing is one transaction.** `issue` takes the next number from the series, completes the payment
  instructions (variable symbol and ISO 11649 reference from the number, the profile's account for the
  currency when the draft has none), runs `DocumentValidator`, computes the totals, writes the frozen row
  with the SHA-256 of its snapshot, advances the series and appends the audit event. A validation error
  rolls everything back, so a number is never consumed by a document that was not issued. `issue` refuses
  a series whose kinds do not include the document's kind (an empty set means any kind).
- **The counter never moves backwards.** Saving a series keeps the stored year and counter when they are
  ahead of the ones given, whatever the template, so a stale copy or a new template carries on from the
  last issued number instead of issuing a counter of the year again.
- **Numbers are unique in the database**, not only in the series: a partial unique index on
  `document.number` (where not null) catches a second series that produces the same text.
- **Audit trail.** `auditEvent` is append-only: the stores only insert, and triggers abort any update or
  delete of an event. It records create/update/delete of drafts,
  issue (with number, series and hash), payments, customer and profile changes, rate imports, statement
  imports and matches. It is the evidence of what changed and when.
- **Storage forms.** Ids are text UUIDs; days are ISO `YYYY-MM-DD` text (sortable, comparable in SQL);
  timestamps ISO 8601 UTC text; amounts integer minor units with the currency code beside them (ADR
  0001); exchange rates as the ČNB decimal text so no digit is lost; enums by raw value.
- **Exchange rates are imported, not fetched.** The app has no network entitlement (ADR 0001). The
  `RateStore` imports the ČNB daily and yearly text files the user downloads, or a rate typed in, and
  answers "the rate valid on day X" the ČNB way: the last rate published on or before the day.
- **Bank statements are in schema v1** (`bankStatement`, `bankTransaction`, `documentPayment` with an
  optional link to the transaction) although the parsers come with v0.2, so the first release's
  database never needs a destructive migration for the feature Saša asked for first.
- **A payment carries its receipt.** `documentPayment.receiptDocumentID` points to the payment tax
  document issued for an advance payment (`DocumentStore.attachReceipt`, which checks that the payment is
  on an advance request, that the receipt is a payment tax document naming that request and its customer,
  and its currency and amount). The check runs again on every save of the linked draft and when it is
  issued, so the issued receipt always matches its payment. A receipt belongs to at most one payment (store
  check plus a partial unique index). While that document is issued the payment is locked by the store
  and by triggers (update, delete and `REPLACE`), because the issued receipt rests on it; a deleted draft
  receipt unlinks itself (`ON DELETE SET NULL`). Where a payment came from is derived, not stored: a
  `bankTransactionID` means a bank import, nil means the user typed it in. The payments linked to one bank
  transaction never add up to more than its credit, so one transfer may be split across several documents
  but is never counted twice; a transaction with payments cannot be unmatched or ignored. Agreed with the
  design thread for the payments table and the v0.2 "already recorded" lane.
- **Matches target issued documents.** `setMatch` links a transaction only to an issued document
  (`.automatic`/`.manual` with a document, `.unmatched`/`.ignored` without one). Should a draft still be
  matched (older data, raw SQL), deleting it returns the transaction to the unmatched list with an audit
  event, so an incoming payment never drops out of every list.
- **Migrations are append-only.** `DatabaseMigrator` with named migrations; `v1` is never edited after
  release, every schema change is a new migration.

## Alternatives rejected

- Core Data / SwiftData: opaque schema migration, no SQL for reports, SwiftData still immature on
  macOS 14; GRDB gives plain SQLite with typed records.
- Normalised line and VAT-row tables from the start: more code and more places to drift from the
  snapshot; nothing reads them yet.
- WAL mode: faster concurrent reads, but three files to back up and a `.sqlite-wal` that can hold
  committed data the user does not see when copying "the database file".
- Soft deletes for issued documents: the law wants the document kept, not flagged; nothing may change it.
