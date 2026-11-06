import GRDB

/// The database schema, one migration per released change. Migrations are never edited after they
/// ship; a change is a new migration appended to `migrator`.
///
/// Conventions (ADR 0005): ids are text (UUIDs), days are ISO "YYYY-MM-DD" text, timestamps ISO 8601
/// UTC text, amounts integer minor units next to a currency code, decimals that must stay exact are text,
/// and every record that must read back exactly as written (documents, customers, the profile) is kept
/// as a JSON snapshot next to the columns the lists and reports query.
enum Schema {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "companyProfile") { t in
                t.column("id", .integer).primaryKey().check(sql: "id = 1")
                t.column("snapshot", .text).notNull()
                t.column("updatedAt", .text).notNull()
            }

            try db.create(table: "customer") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("searchKey", .text).notNull()
                t.column("countryCode", .text).notNull()
                t.column("vatIdentifier", .text)
                t.column("identificationNumber", .text)
                t.column("currency", .text).notNull()
                t.column("snapshot", .text).notNull()
                t.column("createdAt", .text).notNull()
                t.column("updatedAt", .text).notNull()
                t.column("archivedAt", .text)
            }

            try db.create(table: "numberSeries") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("kinds", .text).notNull()
                t.column("template", .text).notNull()
                t.column("resetsYearly", .boolean).notNull()
                t.column("year", .integer).notNull()
                t.column("lastCounter", .integer).notNull()
                t.column("lastIssuedYear", .integer)
                t.column("variableSymbolPrefix", .text)
            }

            try db.create(table: "document") { t in
                t.column("id", .text).primaryKey()
                t.column("kind", .text).notNull()
                t.column("status", .text).notNull()
                t.column("number", .text)
                t.column("customerID", .text).references("customer", onDelete: .restrict)
                t.column("customerName", .text).notNull()
                t.column("issueDate", .text).notNull()
                t.column("taxPointDate", .text)
                t.column("dueDate", .text).notNull()
                t.column("currency", .text).notNull()
                t.column("totalBase", .integer)
                t.column("totalVAT", .integer)
                t.column("totalGross", .integer)
                t.column("taxableBase", .integer)
                t.column("taxableVAT", .integer)
                t.column("amountDue", .integer)
                t.column("taxableBaseCZK", .integer)
                t.column("taxableVATCZK", .integer)
                t.column("variableSymbol", .text)
                t.column("creditorReference", .text)
                t.column("relatedDocumentNumber", .text)
                t.column("snapshot", .text).notNull()
                t.column("snapshotSHA256", .text)
                t.column("createdAt", .text).notNull()
                t.column("updatedAt", .text).notNull()
                t.column("issuedAt", .text)
            }
            try db.execute(sql: "CREATE UNIQUE INDEX document_number ON document(number) WHERE number IS NOT NULL")
            try db.execute(sql: "CREATE INDEX document_customerID ON document(customerID)")
            try db.execute(sql: "CREATE INDEX document_issueDate ON document(issueDate)")
            try db.execute(sql: "CREATE INDEX document_variableSymbol ON document(variableSymbol)")
            // Issued documents are frozen (§ 35 ZDPH): no update, no delete. A correction is a new document.
            try db.execute(sql: """
                CREATE TRIGGER document_frozen_update BEFORE UPDATE ON document
                WHEN OLD.status = 'issued'
                BEGIN SELECT RAISE(ABORT, 'issued documents are frozen'); END
                """)
            try db.execute(sql: """
                CREATE TRIGGER document_frozen_delete BEFORE DELETE ON document
                WHEN OLD.status = 'issued'
                BEGIN SELECT RAISE(ABORT, 'issued documents cannot be deleted'); END
                """)
            // REPLACE removes the conflicting row without firing the delete trigger (recursive_triggers is off),
            // so an insert that would overwrite an issued row, or take its number, is aborted before it starts.
            try db.execute(sql: """
                CREATE TRIGGER document_frozen_replace BEFORE INSERT ON document
                WHEN EXISTS (SELECT 1 FROM document WHERE status = 'issued'
                             AND (id = NEW.id OR (NEW.number IS NOT NULL AND number = NEW.number)))
                BEGIN SELECT RAISE(ABORT, 'issued documents are frozen'); END
                """)

            try db.create(table: "exchangeRate") { t in
                t.column("currency", .text).notNull()
                t.column("validFor", .text).notNull()
                t.column("amount", .integer).notNull().check(sql: "amount > 0")
                t.column("czkPerAmount", .text).notNull()
                t.column("sourceKind", .text).notNull()
                t.column("sourceOrder", .integer)
                t.column("importedAt", .text).notNull()
                t.primaryKey(["currency", "validFor"])
            }

            try db.create(table: "bankStatement") { t in
                t.column("id", .text).primaryKey()
                t.column("iban", .text).notNull()
                t.column("currency", .text).notNull()
                t.column("format", .text).notNull()
                t.column("periodFrom", .text)
                t.column("periodTo", .text)
                t.column("statementNumber", .text)
                t.column("openingBalance", .integer)
                t.column("closingBalance", .integer)
                t.column("fileName", .text)
                t.column("fileSHA256", .text).unique()
                t.column("importedAt", .text).notNull()
            }

            try db.create(table: "bankTransaction") { t in
                t.column("id", .text).primaryKey()
                t.column("statementID", .text).notNull().references("bankStatement", onDelete: .cascade)
                t.column("bookedOn", .text).notNull()
                t.column("valueOn", .text)
                t.column("amount", .integer).notNull()
                t.column("currency", .text).notNull()
                t.column("counterpartyAccount", .text)
                t.column("counterpartyName", .text)
                t.column("variableSymbol", .text)
                t.column("specificSymbol", .text)
                t.column("constantSymbol", .text)
                t.column("creditorReference", .text)
                t.column("message", .text)
                t.column("bankReference", .text)
                t.column("matchedDocumentID", .text).references("document", onDelete: .setNull)
                t.column("matchState", .text).notNull().defaults(to: "unmatched")
            }
            try db.execute(sql: "CREATE INDEX bankTransaction_statementID ON bankTransaction(statementID)")
            try db.execute(sql: "CREATE INDEX bankTransaction_variableSymbol ON bankTransaction(variableSymbol)")
            try db.execute(sql: "CREATE INDEX bankTransaction_matchedDocumentID ON bankTransaction(matchedDocumentID)")
            try db.execute(sql: "CREATE UNIQUE INDEX bankTransaction_bankReference ON bankTransaction(statementID, bankReference) WHERE bankReference IS NOT NULL")

            try db.create(table: "documentPayment") { t in
                t.column("id", .text).primaryKey()
                t.column("documentID", .text).notNull().references("document", onDelete: .restrict)
                t.column("paidOn", .text).notNull()
                // Signed: money received is positive, a refund or credit moved to another document negative.
                t.column("amount", .integer).notNull()
                t.column("currency", .text).notNull()
                // received | refund | creditIn | creditOut (ADR 0007); the sign follows the kind.
                t.column("kind", .text).notNull().defaults(to: "received")
                t.column("bankTransactionID", .text).references("bankTransaction", onDelete: .setNull)
                // The payment tax document issued for this payment; a deleted draft receipt unlinks itself.
                t.column("receiptDocumentID", .text).references("document", onDelete: .setNull)
                // The other leg of an applied credit: creditOut on the overpaid document, creditIn on the paid one.
                t.column("relatedPaymentID", .text)
                t.column("note", .text)
                t.column("createdAt", .text).notNull()
                t.check(sql: "(kind IN ('received', 'creditIn') AND amount > 0) OR (kind IN ('refund', 'creditOut') AND amount < 0)")
            }
            try db.execute(sql: "CREATE INDEX documentPayment_documentID ON documentPayment(documentID)")
            // A payment tax document is the receipt of one payment only.
            try db.execute(sql: "CREATE UNIQUE INDEX documentPayment_receiptDocumentID ON documentPayment(receiptDocumentID) WHERE receiptDocumentID IS NOT NULL")
            // An issued payment tax document rests on its payment: the payment is locked while the receipt is issued.
            try db.execute(sql: """
                CREATE TRIGGER documentPayment_locked_update BEFORE UPDATE ON documentPayment
                WHEN OLD.receiptDocumentID IS NOT NULL
                    AND EXISTS (SELECT 1 FROM document WHERE id = OLD.receiptDocumentID AND status = 'issued')
                BEGIN SELECT RAISE(ABORT, 'the payment has an issued tax document'); END
                """)
            try db.execute(sql: """
                CREATE TRIGGER documentPayment_locked_delete BEFORE DELETE ON documentPayment
                WHEN OLD.receiptDocumentID IS NOT NULL
                    AND EXISTS (SELECT 1 FROM document WHERE id = OLD.receiptDocumentID AND status = 'issued')
                BEGIN SELECT RAISE(ABORT, 'the payment has an issued tax document'); END
                """)
            // REPLACE over a locked payment (same id, or same receipt through the unique index) is aborted too.
            try db.execute(sql: """
                CREATE TRIGGER documentPayment_locked_replace BEFORE INSERT ON documentPayment
                WHEN EXISTS (SELECT 1 FROM documentPayment p JOIN document d ON d.id = p.receiptDocumentID
                             WHERE d.status = 'issued'
                             AND (p.id = NEW.id OR (NEW.receiptDocumentID IS NOT NULL AND p.receiptDocumentID = NEW.receiptDocumentID)))
                BEGIN SELECT RAISE(ABORT, 'the payment has an issued tax document'); END
                """)

            // Which payment tax documents an issued final invoice deducted (§ 37a ZDPH). Written when the final
            // invoice is issued, frozen with it; a receipt is deducted by one final invoice only.
            try db.create(table: "advanceDeduction") { t in
                t.column("id", .text).primaryKey()
                t.column("finalInvoiceID", .text).notNull().references("document", onDelete: .restrict)
                t.column("finalInvoiceNumber", .text).notNull()
                t.column("receiptDocumentID", .text).notNull().unique().references("document", onDelete: .restrict)
                t.column("receiptNumber", .text).notNull()
                // The advance request the receipt's payment was received on, or the issued advance request the
                // receipt names when no payment is linked yet; nil when neither is known (DocumentStore.linkDeductions).
                t.column("advanceRequestID", .text).references("document", onDelete: .restrict)
                t.column("createdAt", .text).notNull()
            }
            try db.execute(sql: "CREATE INDEX advanceDeduction_finalInvoiceID ON advanceDeduction(finalInvoiceID)")
            try db.execute(sql: "CREATE INDEX advanceDeduction_advanceRequestID ON advanceDeduction(advanceRequestID)")
            try db.execute(sql: """
                CREATE TRIGGER advanceDeduction_frozen_update BEFORE UPDATE ON advanceDeduction
                BEGIN SELECT RAISE(ABORT, 'deductions of an issued final invoice are frozen'); END
                """)
            try db.execute(sql: """
                CREATE TRIGGER advanceDeduction_frozen_delete BEFORE DELETE ON advanceDeduction
                BEGIN SELECT RAISE(ABORT, 'deductions of an issued final invoice are frozen'); END
                """)

            // A dated closing event beside an issued document (screens-flows.md §2d): an advance closed as
            // unpaid, or a tax document marked for a credit note. One per document; reopening removes it.
            try db.create(table: "documentClosure") { t in
                t.column("documentID", .text).primaryKey().references("document", onDelete: .restrict)
                t.column("kind", .text).notNull()
                t.column("reason", .text).notNull()
                t.column("closedAt", .text).notNull()
            }

            try db.create(table: "auditEvent") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("at", .text).notNull()
                t.column("entity", .text).notNull()
                t.column("entityID", .text).notNull()
                t.column("action", .text).notNull()
                t.column("details", .text)
            }
            try db.execute(sql: "CREATE INDEX auditEvent_entity ON auditEvent(entity, entityID)")
            // The audit log is evidence: the stores only insert, and nothing may rewrite or remove an event.
            try db.execute(sql: """
                CREATE TRIGGER auditEvent_append_only_update BEFORE UPDATE ON auditEvent
                BEGIN SELECT RAISE(ABORT, 'audit events are append-only'); END
                """)
            try db.execute(sql: """
                CREATE TRIGGER auditEvent_append_only_delete BEFORE DELETE ON auditEvent
                BEGIN SELECT RAISE(ABORT, 'audit events are append-only'); END
                """)
        }

        // v2 (ADR 0010): the PDF of an issued document, rendered once at issue and kept as evidence next to
        // the frozen snapshot, plus where the app last wrote it as a file.
        migrator.registerMigration("v2") { db in
            try db.create(table: "documentPDF") { t in
                t.column("documentID", .text).primaryKey().references("document", onDelete: .restrict)
                t.column("data", .blob).notNull()
                t.column("sha256", .text).notNull()
                t.column("renderedAt", .text).notNull()
                t.column("savedPath", .text)
                t.column("savedAt", .text)
            }
            // The bytes are frozen with the document; only the file location may change.
            try db.execute(sql: """
                CREATE TRIGGER documentPDF_frozen BEFORE UPDATE OF data, sha256, renderedAt ON documentPDF
                BEGIN SELECT RAISE(ABORT, 'a stored PDF is frozen'); END
                """)
            try db.execute(sql: """
                CREATE TRIGGER documentPDF_no_delete BEFORE DELETE ON documentPDF
                BEGIN SELECT RAISE(ABORT, 'a stored PDF is frozen'); END
                """)
        }

        // v3 (ADR 0012): advances paid on § 64 goods, which have no payment tax document, settled on a final
        // invoice as paid in advance; and two document columns the lists read without decoding the snapshot.
        migrator.registerMigration("v3") { db in
            try db.alter(table: "document") { t in
                // What a final invoice lists as paid in advance, in minor units; NULL when nothing is (and on
                // every row written before v3, when nothing could be).
                t.add(column: "paidInAdvance", .integer)
                // The distinct VAT treatments of the lines (VATTreatment.groupingKey) as a JSON array, in the order
                // of the lines; NULL on rows written before v3, whose snapshot says it.
                t.add(column: "treatments", .text)
            }
            // Which payments an issued final invoice settled as paid in advance. Written when the final invoice
            // is issued, frozen with it; a payment is settled by one final invoice only.
            try db.create(table: "paidAdvance") { t in
                t.column("id", .text).primaryKey()
                t.column("finalInvoiceID", .text).notNull().references("document", onDelete: .restrict)
                t.column("finalInvoiceNumber", .text).notNull()
                t.column("paymentID", .text).notNull().unique().references("documentPayment", onDelete: .restrict)
                t.column("advanceRequestID", .text).notNull().references("document", onDelete: .restrict)
                t.column("advanceNumber", .text).notNull()
                // The part of the payment the final invoice lists, in minor units of `currency`.
                t.column("amount", .integer).notNull().check(sql: "amount > 0")
                t.column("currency", .text).notNull()
                t.column("createdAt", .text).notNull()
            }
            try db.execute(sql: "CREATE INDEX paidAdvance_finalInvoiceID ON paidAdvance(finalInvoiceID)")
            try db.execute(sql: "CREATE INDEX paidAdvance_advanceRequestID ON paidAdvance(advanceRequestID)")
            try db.execute(sql: """
                CREATE TRIGGER paidAdvance_frozen_update BEFORE UPDATE ON paidAdvance
                BEGIN SELECT RAISE(ABORT, 'advances settled by an issued final invoice are frozen'); END
                """)
            try db.execute(sql: """
                CREATE TRIGGER paidAdvance_frozen_delete BEFORE DELETE ON paidAdvance
                BEGIN SELECT RAISE(ABORT, 'advances settled by an issued final invoice are frozen'); END
                """)
            // REPLACE removes the conflicting row without firing the delete trigger (recursive_triggers is off), so
            // an insert that would overwrite a link (same id) or take its payment (unique) is aborted before it starts.
            try db.execute(sql: """
                CREATE TRIGGER paidAdvance_frozen_replace BEFORE INSERT ON paidAdvance
                WHEN EXISTS (SELECT 1 FROM paidAdvance WHERE id = NEW.id OR paymentID = NEW.paymentID)
                BEGIN SELECT RAISE(ABORT, 'advances settled by an issued final invoice are frozen'); END
                """)
            // A settled payment rests under the final invoice: its money may not change and it may not go. Its
            // links may (a draft tax document deleted, a bank line unmatched); the store refuses a tax document.
            try db.execute(sql: """
                CREATE TRIGGER documentPayment_settled_update BEFORE UPDATE OF documentID, paidOn, amount, currency, kind ON documentPayment
                WHEN EXISTS (SELECT 1 FROM paidAdvance WHERE paymentID = OLD.id)
                BEGIN SELECT RAISE(ABORT, 'the payment is settled in an issued final invoice'); END
                """)
            try db.execute(sql: """
                CREATE TRIGGER documentPayment_settled_delete BEFORE DELETE ON documentPayment
                WHEN EXISTS (SELECT 1 FROM paidAdvance WHERE paymentID = OLD.id)
                BEGIN SELECT RAISE(ABORT, 'the payment is settled in an issued final invoice'); END
                """)
            // REPLACE over a settled payment (same id) is aborted too, as for the payments of issued tax documents.
            try db.execute(sql: """
                CREATE TRIGGER documentPayment_settled_replace BEFORE INSERT ON documentPayment
                WHEN EXISTS (SELECT 1 FROM paidAdvance WHERE paymentID = NEW.id)
                BEGIN SELECT RAISE(ABORT, 'the payment is settled in an issued final invoice'); END
                """)
        }
        return migrator
    }
}
