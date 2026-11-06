# ADR 0014: Repair mode

Date: 2026-11-06 · Status: accepted, open to the adversarial review

## Context

The proposal doc's decisions table records: "A Repair mode behind Touch ID or the password will unlock every
record, issued documents included; each repair change is written to the audit log, which never leaves the
Mac. There is no trace-free mode". The design spec is screens-flows.md §2m. It leaves the data-layer design
to the build: the locks on issued documents, their stored PDF and the audit log are SQLite triggers
(Schema.swift), so a repair needs a way through the first two and none through the third. Repair mode ships
in parts. This change builds the mode and the repair of an issued document's header values that change no
amount: the client's details as printed, the due date, the order reference and the note.

## Decisions

1. **The lock opens per transaction, never per session.** Schema v9 adds `repairUnlock`. The triggers
   `document_frozen_update` and `documentPDF_frozen` now fire only while that table is empty. A repair
   (`RepairStore.repair`) inserts its token, writes, and deletes the token before the transaction commits.
   Writes are serialised on one queue, so no other write ever sees the lock open, and a crash rolls the
   token back with everything else. A trigger cannot read a TEMP table, hence a real one. Deleting an issued
   document stays refused, and so does any change to the audit log.
2. **Every changed field is one audit event, in the same transaction.** Action `repair` on the document,
   with `field` (a `RepairField` raw value), `old`, `new`, `reason` and the new snapshot hash. If an event
   can't be written, nothing is saved. A reason is required (`reasonRequired`), and a repair that changes
   nothing is refused (`nothingChanged`). There is no API that changes a locked record without its events.
3. **A repair can't add a problem.** The repaired document goes through `DocumentValidator` (as at Issue).
   An error the repair adds refuses it (`validationFailed`). An error the document already had, from a rule
   added after it was issued, doesn't block it.
4. **The old PDF is kept.** The app renders the new PDF from `RepairStore.preview` and hands it to the
   repair. The stored bytes move to `documentPDFHistory` (append-only by trigger), the new ones replace them
   in `documentPDF`, and a `pdfReplaced` event records both hashes. A file the user saved before keeps the
   old PDF until they save again.
5. **The snapshot hash follows the repair.** The row is rebuilt from the repaired document like at Issue, so
   `verifyIntegrity` holds, and the accountant export sees the new hash: the month shows "changed after
   export" (§2h).
6. **The mode lives in the app, not the data.** `RepairModeModel` asks `LAContext` with
   `deviceOwnerAuthentication` and a fresh context each time. It ends on End Repair Mode, on a restore, after
   10 minutes without a change, and on quit, since it is never stored. Undo of a repair is itself a repair,
   logged with "Undo: ‹reason›". The window drops these Undo steps when the mode ends.

## Not yet

Lines and amounts, the tax point and issue dates, the number, payments, deductions, paid advances, closing
events and rates. Each needs its own consistency checks (§2m: series gaps, VS collisions, payments that no
longer cover a tax document). The window subtitle prefix "Repair mode" and inline editing in the issued
view also wait: this part uses a Repair… sheet.
