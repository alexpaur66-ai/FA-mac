# ADR 0013: Rough stock

Date: 2026-11-06 · Status: accepted, open to the adversarial review

## Context

Saša asked for rough stock keeping on 5 Nov 2026: "I cannot keep perfect track of everything that leaves
and is added to the storage/warehouse. So it will be mostly roughly so I know how much of what for ordering
etc." The design spec is screens-flows.md §2n ("Stock: a rough list for reordering"), which leaves the
model to the build. This ADR records the model. Stock ships in three parts: the Stock section (this
change), the link of invoice lines to items with the "out" movement at Issue, and the client page's Items
tab.

## Decisions

1. **Items and movements, no ledger.** A stock item has a name, a unit (free text) and an optional reorder
   level, and can be archived. A movement has a kind (`in`, `out`, `count`), a day, a quantity, an optional
   note and, for an "out" from an issued document, that document. Schema v6 adds `stockItem` and
   `stockMovement`. Quantities are decimal text, so "1.5" stays exact. Movements are never edited. Undo
   deletes the latest one, and a count fixes anything older.
2. **On hand is computed, never stored.** On hand is the latest count, plus the "in" movements after it,
   minus the "out" movements after it. Movements are ordered by day, then by the order they were recorded
   (`sequence`). With no count, on hand starts from 0, so it can go below zero. An issued document's "out"
   dated on the count's day is not after the count, because the count already saw the goods gone (§2n,
   edge cases). A count keeps the figure the app had (`previousOnHand`), so its history line explains
   itself.
3. **Stock never blocks invoicing.** Unknown or negative stock never stops a draft, a review or Issue.
4. **Issued documents stay untouched.** The link of a line to an item lives beside the document in
   `documentLineStock` (document id, line id, item id). The document's snapshot, its hash and its PDF never
   mention stock. The table is created now and used by the next part.
5. **Names are unique among listed items, ignoring case**, because the editor's suggestions match by name.
   An archived item frees its name. An item with movements is archived, not deleted. An item without
   movements is deleted together with its line links, and Undo restores both.
6. **No settings, no prices.** Nothing about stock is in Settings. An item has no stored price: a line's
   price will come from the last issued line for that item.

## Consequences

- A restore brings stock back with the rest of the data, because stock lives in the same database.
- The accountant's export gets no stock list until the accountant says it helps (ACCT, §2h).
- Later (Phase 2), a credit note may add goods back. Until then, a count or Receive… fixes the figure.
