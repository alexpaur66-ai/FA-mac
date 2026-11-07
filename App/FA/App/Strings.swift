// The user-facing strings of the app shell. Every string is a LocalizedStringResource in the "App" table,
// the same way the design system keeps its status labels in the "DesignSystem" table. The UI is English
// only (decision of 5 Nov 2026) and no string catalog ships, so counts with a singular are handled in
// code (`Count`); sentence case for text, title case for menus, buttons and column headings. Legal and
// tax wording stays in InvoicingCore.

import Foundation

enum L {
    private static func r(_ key: StaticString, _ value: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, defaultValue: value, table: "App")
    }

    // MARK: Sidebar (screens-flows.md §1.2)

    static let overview = r("sidebar.overview", "Overview")
    static let documents = r("sidebar.documents", "Documents")
    static let clients = r("sidebar.clients", "Clients")
    static let payments = r("sidebar.payments", "Payments")
    static let stock = r("sidebar.stock", "Stock")
    static func stockRunningLow(_ count: Int) -> LocalizedStringResource { r("sidebar.stockRunningLow", "\(count) running low") }
    static let filterDrafts = r("filter.drafts", "Drafts")
    static let filterUnpaid = r("filter.unpaid", "Unpaid")
    static let filterOpenAdvances = r("filter.openAdvances", "Open advances")
    /// View ▸ Filter ▸, in title case.
    static let filterAllDocuments = r("menu.filterAllDocuments", "All Documents")
    static let menuFilterOpenAdvances = r("menu.filterOpenAdvances", "Open Advances")
    static let menuFilter = r("menu.filter", "Filter")
    static func overdueCount(_ count: Int) -> LocalizedStringResource { r("sidebar.overdueCount", "\(count) overdue") }
    /// The Documents window subtitle: "Unpaid · 3", and "Unpaid · 7 · 3 overdue" while something is overdue.
    static func documentsSubtitle(_ filter: String, _ count: Int) -> LocalizedStringResource {
        r("documents.subtitle", "\(filter) · \(count)")
    }
    static func documentsSubtitleOverdue(_ filter: String, _ count: Int, _ overdue: Int) -> LocalizedStringResource {
        r("documents.subtitleOverdue", "\(filter) · \(count) · \(overdue) overdue")
    }

    // MARK: Menus and commands (screens-flows.md §1.4)

    static let newInvoice = r("menu.newInvoice", "New Invoice")
    static let newAdvance = r("menu.newAdvance", "New Advance Invoice")
    static let newClient = r("menu.newClient", "New Client…")
    static let menuDocument = r("menu.document", "Document")
    static let issue = r("menu.issue", "Issue…")
    static let recordPayment = r("menu.recordPayment", "Record Payment…")
    static let closeAdvanceUnpaid = r("menu.closeAdvanceUnpaid", "Close Advance as Unpaid…")
    static let markForCreditNote = r("menu.markForCreditNote", "Mark for Credit Note…")
    static let deleteDraft = r("menu.deleteDraft", "Delete Draft")
    static func deleteDraftsCount(_ count: Int) -> LocalizedStringResource { r("menu.deleteDraftsCount", "Delete \(count) Drafts") }
    static let mainWindow = r("menu.mainWindow", "Main Window")
    static let biggerText = r("menu.biggerText", "Bigger Text")
    static let smallerText = r("menu.smallerText", "Smaller Text")
    static let actualSize = r("menu.actualSize", "Actual Size")

    // MARK: Table columns

    static let colStatus = r("column.status", "Status")
    static let colNumber = r("column.number", "Number")
    static let colType = r("column.type", "Type")
    static let colClient = r("column.client", "Client")
    static let colIssued = r("column.issued", "Issued")
    static let colDue = r("column.due", "Due")
    static let colTotal = r("column.total", "Total")
    static let colOpen = r("column.open", "Open")
    static let colVS = r("column.vs", "VS")
    static let colCurrency = r("column.currency", "Currency")
    static let colDate = r("column.date", "Date")
    static let colAmount = r("column.amount", "Amount")
    static let colNote = r("column.note", "Note")
    static let colName = r("column.name", "Name")
    static let colCountry = r("column.country", "Country")
    static let colVATID = r("column.vatID", "VAT ID")
    static let colLastDocument = r("column.lastDocument", "Last document")
    static let colRate = r("column.rate", "Rate")
    static let colSource = r("column.source", "Source")
    static let colDocument = r("column.document", "Document")

    // MARK: Document types, short (screens-flows.md §5)

    static let typeInvoice = r("type.invoice", "Invoice")
    static let typeAdvance = r("type.advance", "Advance")
    static let typePaymentTaxDocument = r("type.paymentTaxDocument", "Tax doc (payment)")
    static let typeFinal = r("type.final", "Final")

    /// The badge details (design-system.md §4.3): days late and the open balance, the due date, the surplus.
    static func overdueDetail(_ days: Int, _ left: String) -> LocalizedStringResource {
        r("badge.overdueDetail", "+\(days) days · \(left) left")
    }
    static func overdueDetailOne(_ left: String) -> LocalizedStringResource { r("badge.overdueDetailOne", "+1 day · \(left) left") }
    static func dueInDays(_ days: Int) -> LocalizedStringResource { r("badge.dueInDays", "due in \(days) days") }
    static let dueTomorrow = r("badge.dueTomorrow", "due tomorrow")
    static let dueToday = r("badge.dueToday", "due today")
    static func amountLeft(_ left: String) -> LocalizedStringResource { r("badge.amountLeft", "\(left) left") }
    static func overpaidBy(_ amount: String) -> LocalizedStringResource { r("badge.overpaidBy", "\(amount) over") }

    // MARK: Payment kinds (ADR 0007)

    static let paymentReceived = r("payment.received", "Received")
    static let paymentRefund = r("payment.refund", "Refund")
    static let paymentCreditIn = r("payment.creditIn", "Credit applied")
    static let paymentCreditOut = r("payment.creditOut", "Credit moved out")
    static let paymentLocked = r("payment.locked", "A tax document rests on this payment; it cannot change.")
    static let paymentSettledLocked = r("payment.settledLocked", "A final invoice settled this payment as paid in advance; it cannot change.")

    // MARK: Empty states and placeholders

    static let noDocuments = r("empty.noDocuments", "No documents yet")
    static let noMatchingDocuments = r("empty.noMatchingDocuments", "No matching documents")
    static let nothingOverdue = r("empty.nothingOverdue", "Nothing overdue")
    static let noDrafts = r("empty.noDrafts", "No drafts")
    static let noClients = r("empty.noClients", "No clients yet")
    static let noPayments = r("empty.noPayments", "No payments yet")
    static let noRates = r("empty.noRates", "No rates yet")
    static let noSelection = r("empty.noSelection", "Select a document")
    static let noClientSelected = r("empty.noClientSelected", "Select a client")
    static let allCaughtUp = r("empty.allCaughtUp", "All caught up")
    static let noClient = r("document.noClient", "(no client)")

    // MARK: Overview (screens-flows.md §2a)

    static let tileUnpaid = r("overview.tileUnpaid", "Unpaid")
    static let tileOverdue = r("overview.tileOverdue", "Overdue")
    static func tileIssued(_ month: String) -> LocalizedStringResource { r("overview.tileIssued", "Issued in \(month)") }
    static func tileVAT(_ month: String) -> LocalizedStringResource { r("overview.tileVAT", "VAT for \(month) by DUZP (CZK)") }
    static func documentsCount(_ count: Int) -> LocalizedStringResource { r("overview.documentsCount", "\(count) documents") }
    static let documentCountOne = r("overview.documentCountOne", "1 document")
    static func oldestOverdue(_ days: Int) -> LocalizedStringResource { r("overview.oldestOverdue", "oldest \(days) days") }
    static let oldestOverdueOne = r("overview.oldestOverdueOne", "oldest 1 day")
    static let needsAttention = r("overview.needsAttention", "Needs attention")
    static func daysOverdue(_ days: Int) -> LocalizedStringResource { r("queue.daysOverdue", "\(days) days overdue") }
    static let dayOverdueOne = r("queue.dayOverdueOne", "1 day overdue")
    static let queueTaxDocumentMissing = r("queue.taxDocumentMissing", "Payment received, tax document missing")
    static let previousMonth = r("overview.previousMonth", "Previous month")
    static let nextMonth = r("overview.nextMonth", "Next month")

    static let gettingStarted = r("setup.title", "Getting started")
    static let setupIntro = r("setup.intro", "Three steps before you can issue the first document.")
    static let stepCompany = r("setup.company", "Company profile")
    static let stepBank = r("setup.bank", "Bank accounts")
    static let stepSeries = r("setup.series", "Continue your number series")
    static let noDocumentsDescription = r("empty.noDocumentsDescription", "Press ⌘N to create your first invoice.")
    static let noDraftsDescription = r("empty.noDraftsDescription", "New Invoice (⌘N) and New Advance Invoice (⇧⌘N) create drafts.")
    static let noUnpaidDescription = r("empty.noUnpaidDescription", "Every issued invoice is paid.")
    static let noOpenAdvancesDescription = r("empty.noOpenAdvancesDescription", "No advance invoice is waiting for a payment or its final invoice.")
    static let noClientsDescription = r("empty.noClientsDescription", "Clients carry the defaults of their documents: currency, payment term, VAT treatment and language.")
    static let noPaymentsDescription = r("empty.noPaymentsDescription", "Record Payment… (⌘R) on an issued document lists the payment here.")
    static let noRatesDescription = r("empty.noRatesDescription", "Rates you type on a document appear here.")
    static let openSettings = r("setup.openSettings", "Open Settings…")
    static let setUpCompanyFirst = r("setup.companyFirst", "Fill in the company profile in Settings before creating documents.")

    // MARK: Document detail (screens-flows.md §2b)

    static let draftTitle = r("document.draft", "Draft")
    static func lockLine(_ issued: String) -> LocalizedStringResource {
        r("document.lockLine", "Issued \(issued) · locked. Corrections via credit note (Phase 2).")
    }
    /// The lock line with the stored issue time (screens-flows.md §2b): "Issued 5. 11. 2026 at 19:02 · locked. …".
    static func lockLineAt(_ issued: String, _ time: String) -> LocalizedStringResource {
        r("document.lockLineAt", "Issued \(issued) at \(time) · locked. Corrections via credit note (Phase 2).")
    }
    static let paymentsSection = r("document.payments", "Payments")
    static let paid = r("document.paid", "Paid")
    static let issuedOn = r("document.issuedOn", "Issue date")
    static let dueOn = r("document.dueOn", "Due date")
    static let variableSymbol = r("document.variableSymbol", "Variable symbol")
    static let advancesDeducted = r("document.advancesDeducted", "Advances deducted")
    /// The inline error of the document list when its live observation stopped (ADR 0008).
    static let listStopped = r("document.listStopped", "The document list stopped updating.")
    static let retry = r("action.retry", "Try Again")
    static func selectedCount(_ count: Int) -> LocalizedStringResource { r("document.selectedCount", "\(count) selected") }
    static let totalsPerCurrency = r("document.totalsPerCurrency", "Totals per currency")
    static let activity = r("document.activity", "Activity")
    static let account = r("document.account", "Account")

    // MARK: Sheets

    static let rpTitle = r("recordPayment.title", "Record Payment")
    static let rpDate = r("recordPayment.date", "Payment date")
    static let rpRefundDate = r("recordPayment.refundDate", "Refund date")
    static let rpRefundTitle = r("recordPayment.refundTitle", "Record Refund")
    static let rpRecordRefund = r("recordPayment.recordRefund", "Record Refund")
    static let rpRefundNote = r("recordPayment.refundNote", "The overpaid part goes back to the client; the document keeps its payments.")
    static let rpAmount = r("recordPayment.amount", "Amount")
    static let rpNote = r("recordPayment.note", "Note")
    static let rpRecord = r("recordPayment.record", "Record")
    static let closeAdvanceTitle = r("closure.closeAdvanceTitle", "Close advance as unpaid")
    static let closeAsUnpaidButton = r("closure.closeButton", "Close as Unpaid")
    static let markForCreditNoteButton = r("closure.markButton", "Mark for Credit Note")
    static let markForCreditNoteTitle = r("closure.markForCreditNoteTitle", "Mark for credit note")
    static let closureExplanation = r("closure.explanation", "The document stays as issued. The event is recorded beside it with your reason and can be reopened.")
    static let reasonPrompt = r("closure.reasonPrompt", "Reason (required)")
    static let cancel = r("action.cancel", "Cancel")
    static let save = r("action.save", "Save")
    static let add = r("action.add", "Add")
    static let remove = r("action.remove", "Remove")
    static let delete = r("action.delete", "Delete")
    static let edit = r("action.edit", "Edit…")
    static let archive = r("action.archive", "Archive")
    static let close = r("action.close", "Close")
    static let saved = r("action.saved", "Saved.")

    // MARK: Clients (screens-flows.md §2e)

    static let newClientTitle = r("client.newTitle", "New client")
    static let editClientTitle = r("client.editTitle", "Client details")
    static let fieldName = r("field.name", "Name")
    static let fieldStreet = r("field.street", "Street")
    static let fieldCity = r("field.city", "City")
    static let fieldPostalCode = r("field.postalCode", "Postal code")
    static let fieldCountry = r("field.country", "Country")
    static let fieldICO = r("field.ico", "IČO")
    static let fieldVATID = r("field.vatID", "VAT ID (DIČ)")
    static let fieldCurrency = r("field.currency", "Currency")
    static let fieldPaymentTerm = r("field.paymentTerm", "Payment term (days)")
    static let fieldLanguage = r("field.language", "Document language")
    static let fieldNotes = r("field.notes", "Notes")
    static let fieldEmail = r("field.email", "Email")
    static let fieldPhone = r("field.phone", "Phone")
    static let languageCzech = r("language.czech", "Czech")
    static let languageEnglish = r("language.english", "Czech + English")
    static let clientOpenBalance = r("client.openBalance", "Open balance")
    static let clientInvoicedThisYear = r("client.invoicedThisYear", "Invoiced this year")
    /// The Open balance tile's second line while part of it is overdue: "1 200,00 € overdue" (lean pass shell-21).
    static func clientOverdueAmount(_ amount: String) -> LocalizedStringResource {
        r("client.overdueAmount", "\(amount) overdue")
    }
    static let clientDocuments = r("client.documents", "Documents")
    static let invalidICO = r("validation.ico", "Company ID is not valid (8 digits with a check digit).")
    static let invalidVATID = r("validation.vatID", "VAT ID is not valid (country code and number, for example CZ12345678).")
    static let nameRequired = r("validation.nameRequired", "A name is required.")
    static let invalidBIC = r("validation.bic", "BIC is not valid.")

    // MARK: Settings (screens-flows.md §2i)

    static let settingsGeneral = r("settings.general", "General")
    static let settingsCompany = r("settings.company", "Company")
    static let settingsBank = r("settings.bank", "Bank Accounts")
    static let settingsNumbering = r("settings.numbering", "Numbering")
    static let companyNote = r("settings.companyNote", "Changes apply to future documents only. Issued documents keep their own copy of these details.")
    static let fieldLegalName = r("field.legalName", "Legal name")
    static let fieldRegistryCourt = r("field.registryCourt", "Register court")
    static let noCourt = r("field.noCourt", "Not registered")
    static let fieldFooter = r("field.footer", "Footer text")
    static let footerSection = r("settings.footerSection", "Footer")
    static let fieldFileNumber = r("field.fileNumber", "File number")
    static let fileNumberPrompt = r("field.fileNumberPrompt", "C 12345")
    static let invalidFileNumber = r("validation.fileNumber", "Enter the file number as section and number, such as C 12345.")
    static let bankBIC = r("bank.bic", "BIC")
    static let bankName = r("bank.name", "Bank name")
    static let bankCurrency = r("bank.currency", "Currency")
    static let bankCurrencyAny = r("bank.currencyAny", "Any")
    static let bankAccountNumber = r("bank.accountNumber", "Account number")
    static let accountNumberPrompt = r("bank.accountNumberPrompt", "IBAN or 123456789/0800")
    static let invalidAccountNumber = r("validation.accountNumber", "Enter an IBAN or a Czech account number such as 123456789/0800.")
    static let removeBankAccount = r("action.removeBankAccount", "Remove Bank Account")
    static let bankNote = r("bank.note", "The first account in a currency is printed on documents in that currency; an account without a currency serves the rest.")
    static let companyFirst = r("bank.companyFirst", "Fill in the company profile first.")
    static let noAccounts = r("bank.noAccounts", "No bank accounts yet")
    static let seriesTemplate = r("series.template", "Pattern ({YYYY}, {YY}, {NNNN})")
    static let seriesLastIssued = r("series.lastIssued", "Last issued number")
    static let numberingCaption = r("series.numberingCaption", "Type the last number you issued in your previous tool. Leave it empty to start at 1. It can't be changed after the first document is issued.")
    static let numberingInvoices = r("series.section.invoices", "Invoices")
    static let numberingAdvances = r("series.section.advances", "Advance Invoices")
    static let numberingReceipts = r("series.section.receipts", "Tax Documents for Received Payments")
    static let numberingInvoicesName = r("series.name.invoices", "Invoices")
    static let numberingAdvancesName = r("series.name.advances", "Advance invoices")
    static let numberingReceiptsName = r("series.name.receipts", "Tax documents for received payments")
    static func lastIssuedNoMatch(_ sample: String) -> LocalizedStringResource {
        r("series.lastIssuedNoMatch", "Enter the number as the pattern writes it, such as \(sample), or leave it empty to start at 1.")
    }
    static func nextNumberLine(_ number: String, _ symbol: String) -> LocalizedStringResource {
        r("series.nextLine", "Next number: \(number) · VS \(symbol) – assigned when you issue")
    }
    static func nextNumberLineNoVS(_ number: String) -> LocalizedStringResource {
        r("series.nextLineNoVS", "Next number: \(number) – assigned when you issue")
    }
    static let nextNumberUnknown = r("series.nextUnknown", "Next number: –")
    static func seriesSameNumbers(_ first: String, _ second: String) -> LocalizedStringResource {
        r("series.sameNumbers", "\(first) and \(second) would issue the same numbers. Change one of the patterns.")
    }
    static func seriesSameVS(_ first: String, _ second: String) -> LocalizedStringResource {
        r("series.sameVS", "\(first) and \(second) would give documents the same variable symbol. Change one of the patterns.")
    }

    // MARK: Rates (screens-flows.md §2g)

    static let importRates = r("rates.import", "Import ČNB Rates…")
    static func importedRates(_ count: Int) -> LocalizedStringResource { r("rates.imported", "\(count) rates imported") }
    static let rateImportFailed = r("rates.importFailed", "The file could not be read as a ČNB daily or yearly file.")
    static func rateImportFailedAtLine(_ line: Int) -> LocalizedStringResource {
        r("rates.importFailedAtLine", "The file could not be read as a ČNB rate file: parsing stopped at line \(line). Nothing was imported.")
    }
    static let rateImportBadHeader = r("rates.importBadHeader", "The first line is not the header of a ČNB daily or yearly file. Nothing was imported.")
    static let sourceCNB = r("rates.sourceCNB", "ČNB file")
    static let sourceECB = r("rates.sourceECB", "ECB")
    static let sourceManual = r("rates.sourceManual", "Typed")
    static let sourceFixed = r("rates.sourceFixed", "Fixed accounting rate")

    // MARK: PDF (screens-flows.md §1.4, §2b, §2c, §2i; ADR 0010)

    static let savePDF = r("pdf.save", "Save PDF…")
    static let showPDFInFinder = r("pdf.showInFinder", "Show PDF in Finder")
    static let printDocument = r("pdf.print", "Print…")
    static let showPreview = r("pdf.showPreview", "Show Preview")
    static let hidePreview = r("pdf.hidePreview", "Hide Preview")
    static let pdfPreviewUnavailable = r("pdf.previewUnavailable", "Preview unavailable.")
    static func pdfPageOfPages(_ page: Int, _ count: Int) -> LocalizedStringResource { r("pdf.pageOfPages", "Page \(page) of \(count)") }
    static let pdfRow = r("pdf.row", "PDF")
    static let pdfNotSavedYet = r("pdf.notSavedYet", "Kept in the app, not saved as a file yet.")
    static let pdfFileMoved = r("pdf.fileMoved", "File moved – use Save PDF…")
    static func pdfSavedTo(_ path: String) -> LocalizedStringResource { r("pdf.savedTo", "PDF saved to \(path)") }
    static func pdfSaveFailed(_ folder: String) -> LocalizedStringResource { r("pdf.saveFailed", "PDF couldn't be saved to \(folder).") }
    static let pdfNoFolder = r("pdf.noFolderIssue", "No PDF folder: the PDF stays in the app until you use Save PDF…. Choose a folder in Settings ▸ General.")
    static func pdfFolderCaption(_ year: String) -> LocalizedStringResource {
        r("pdf.folderCaption", "Issued documents are saved as \(year)/FV \(year)-0042 Acme GmbH.pdf.")
    }
    static let pdfFolderCaptionNone = r("pdf.folderCaptionNone", "No folder: the PDF stays in the app until you use Save PDF….")
    static let pdfSection = r("pdf.section", "PDF")
    static let pdfFolder = r("pdf.folder", "PDF folder")
    static let pdfFolderPrompt = r("pdf.folderPrompt", "Choose the folder where issued documents are saved as PDF files.")
    static let pdfFolderNone = r("pdf.folderNone", "No folder chosen")
    static let choose = r("action.choose", "Choose")
    static let chooseFolder = r("pdf.chooseFolder", "Choose Folder…")
    static let clearFolder = r("pdf.clearFolder", "Forget Folder")

    // MARK: Exports (screens-flows.md §2h)

    static let showDataFolder = r("exports.showDataFolder", "Show Data Folder")

    // MARK: Errors

    static let dbCannotOpen = r("error.dbCannotOpen", "Data can't be opened")
    static let errorGeneric = r("error.generic", "That did not work. Nothing was changed.")
    static let errorReceiptMismatch = r("error.receiptMismatch", "The tax document must match its payment: the same client, currency, advance, day received and total. The change is not saved until it does.")
    static let errorNotFound = r("error.notFound", "The record no longer exists. It may have been deleted in the meantime.")
    static let errorFrozen = r("error.frozen", "The document is issued and locked. Corrections go through a credit note (Phase 2).")
    static let errorNotIssued = r("error.notIssued", "Issue the document first.")
    static let errorCustomerHasDocuments = r("error.customerHasDocuments", "Documents refer to this client, so it can only be archived.")
    static func errorValidation(_ issues: String) -> LocalizedStringResource { r("error.validation", "Check the entries: \(issues)") }
    static let errorAmountOutOfRange = r("error.amountOutOfRange", "The amount is too large.")
    static func errorCurrencyMismatch(_ code: String) -> LocalizedStringResource { r("error.currencyMismatch", "The amount must be in \(code).") }
    static let errorSeriesKind = r("error.seriesKind", "This number series does not number this document type. Choose another series in Settings ▸ Numbering.")
    static let errorAmountNotPositive = r("error.amountNotPositive", "Enter an amount greater than zero.")
    static func errorCreditAvailable(_ amount: String) -> LocalizedStringResource { r("error.creditAvailable", "At most \(amount) of credit is available.") }
    static func errorCreditOutstanding(_ amount: String) -> LocalizedStringResource { r("error.creditOutstanding", "At most \(amount) is still open on the document.") }
    static let errorHasPayments = r("error.hasPayments", "Payments are recorded on this advance, so it cannot be closed as unpaid. Delete them first.")
    static let errorDeducted = r("error.deducted", "A final invoice deducted this advance, so it cannot be closed as unpaid.")
    static let errorAlreadyClosed = r("error.alreadyClosed", "The document is closed. Reopen it first.")
    static let errorNotClosed = r("error.notClosed", "The document is not closed.")
    static let errorClosureNotApplicable = r("error.closureNotApplicable", "This closing event does not apply to this document type.")
    static let errorReasonRequired = r("error.reasonRequired", "Enter a reason.")
    static func errorRefundExceeds(_ amount: String) -> LocalizedStringResource { r("error.refundExceeds", "A refund can be at most \(amount).") }
    static let errorNotPayable = r("error.notPayable", "A tax document for a payment takes no payments. Record the payment on its advance request.")
    static let errorDuplicateStatement = r("error.duplicateStatement", "This statement was imported before.")
    static let errorCorruptRecord = r("error.corruptRecord", "A stored record cannot be read. Quit, restore a copy of the data file and try again.")
    static let errorAdvanceDeducted = r("error.advanceDeducted", "This tax document for a payment is already deducted by another final invoice.")
    static let errorCreditCustomer = r("error.creditCustomer", "Credit moves only between documents of the same client.")
    static let dbCannotOpenDetail = r("error.dbCannotOpenDetail", "The database file could not be opened or migrated. Nothing was changed. Quit, restore a copy of the file and try again.")

    // MARK: Draft editor (screens-flows.md §2c, ADR 0009)

    static let editorDraftSaved = r("editor.saved", "Draft · Saved")
    static let editorDraftSaving = r("editor.saving", "Draft · Saving…")
    static let editorDraftNotSaved = r("editor.notSaved", "Draft · Not saved")
    static let newInvoiceTitle = r("editor.newInvoiceTitle", "New Invoice")
    static let newAdvanceTitle = r("editor.newAdvanceTitle", "New Advance Invoice")
    static let newFinalInvoiceTitle = r("editor.newFinalInvoiceTitle", "New Final Invoice")
    static let newTaxDocumentTitle = r("editor.newTaxDocumentTitle", "New Tax Document")
    static let oneProblem = r("editor.oneProblem", "1 problem")
    static func problems(_ count: Int) -> LocalizedStringResource { r("editor.problems", "\(count) problems") }
    static let issueButton = r("editor.issueButton", "Issue")
    static let duplicate = r("menu.duplicate", "Duplicate")
    static let duplicateAsDraft = r("menu.duplicateAsDraft", "Duplicate as Draft")
    static func duplicateNumbered(_ number: String) -> LocalizedStringResource { r("menu.duplicateNumbered", "Duplicate \(number) as Draft") }
    static let createFinalInvoice = r("menu.createFinalInvoice", "Create Final Invoice")
    static let createTaxDocument = r("menu.createTaxDocument", "Create Tax Document")
    static let createTaxDocumentForPayment = r("menu.createTaxDocumentForPayment", "Create Tax Document for Payment")
    static let openTaxDocument = r("document.openTaxDocument", "Open Tax Document")
    static let later = r("action.later", "Later")
    static let paymentRecordedAdvance = r("rp.recordedAdvance", "Payment recorded. Create its tax document now, or later from the payment's row in the advance.")
    static let menuChangeType = r("menu.changeType", "Change Type")
    static let menuCurrency = r("menu.currency", "Currency")
    static let menuDocumentLanguage = r("menu.documentLanguage", "Document Language")
    static let menuVATTreatment = r("menu.vatTreatment", "VAT Treatment")
    static let menuTreatmentEUGoods = r("menu.treatment.euGoods", "EU Goods, Exempt (§ 64)")
    static let menuTreatmentReverseCharge = r("menu.treatment.reverseCharge", "EU Services, Reverse Charge")
    static let menuTreatmentCzechVAT = r("menu.treatment.czech", "Czech VAT")
    static let menuTreatmentOutsideEU = r("menu.treatment.outsideEU", "Outside EU, Services")
    static let menuTreatmentExempt = r("menu.treatment.exempt", "Other Exemption")
    static let menuEnterRate = r("menu.enterRate", "Enter Rate…")

    // The English names of the types with the printed Czech title (screens-flows.md §5, design-system.md §9).
    static let typeLongInvoice = r("type.long.invoice", "Invoice – tax document")
    static let typeLongAdvance = r("type.long.advance", "Advance invoice")
    static let typeLongPaymentTaxDocument = r("type.long.paymentTaxDocument", "Tax document for received payment")
    static let typeLongFinal = r("type.long.final", "Final invoice")
    static func kindWithCzechTitle(_ english: String, _ czech: String) -> LocalizedStringResource { r("type.withCzechTitle", "\(english) (\(czech))") }

    static let fieldClient = r("editor.client", "Client")
    static let clientPrompt = r("editor.clientPrompt", "Name, IČO or VAT ID")
    static func newClientNamed(_ query: String) -> LocalizedStringResource { r("editor.newClientNamed", "New Client “\(query)”…") }
    static let newClientEllipsis = r("editor.newClient", "New Client…")
    static func clientSuggestionLine(_ currency: String, _ days: String, _ treatment: String) -> LocalizedStringResource {
        r("editor.clientSuggestionLine", "\(currency) · \(days) · \(treatment)")
    }
    static let vatIDMissing = r("editor.vatIDMissing", "VAT ID missing")
    static let addressMissing = r("editor.addressMissing", "Address missing")
    static let fieldIssueDate = r("editor.issueDate", "Issue date")
    static let fieldTaxPoint = r("editor.taxPoint", "Date of taxable supply")
    static let sameAsIssueDate = r("editor.sameAsIssueDate", "Same as the issue date")
    /// The issue date's toggle: on, the date floats to the day of Issue (docs-18, docs-28).
    static let onIssue = r("editor.onIssue", "On issue")
    static let fieldDue = r("editor.due", "Due")
    static let dueDaysOne = r("editor.dueDaysOne", "1 day")
    static func dueDays(_ days: Int) -> LocalizedStringResource { r("editor.dueDays", "\(days) days") }
    static let fieldTreatment = r("editor.treatment", "VAT treatment")
    // The treatment names agreed with the design thread on 5 Nov 2026: the pop-up, the short form for the
    // client line, chips and the Issue summary, and the menu items above in title case.
    static let treatmentEUGoods = r("editor.treatment.euGoods", "EU goods, exempt (§ 64)")
    static let treatmentReverseCharge = r("editor.treatment.reverseCharge", "EU services, reverse charge")
    static let treatmentCzechVAT = r("editor.treatment.czech", "Czech VAT (rate per line)")
    static let treatmentOutsideEU = r("editor.treatment.outsideEU", "Outside EU, services")
    static let treatmentExempt = r("editor.treatment.exempt", "Other exemption")
    static let shortTreatmentEUGoods = r("editor.treatment.short.euGoods", "EU goods, exempt")
    static let shortTreatmentCzechVAT = r("editor.treatment.short.czech", "Czech VAT")
    static let exemptReference = r("editor.exemptReference", "Exemption reference (§)")
    static let fieldBankAccount = r("editor.bankAccount", "Bank account")
    static func accountIBAN(_ iban: String) -> LocalizedStringResource { r("editor.accountIBAN", "\(iban)") }
    static func accountIBANWithCurrency(_ iban: String, _ currency: String) -> LocalizedStringResource { r("editor.accountIBANWithCurrency", "\(iban) · \(currency)") }
    static func accountWithBank(_ bank: String, _ iban: String) -> LocalizedStringResource { r("editor.accountWithBank", "\(bank) · \(iban)") }
    static func accountWithBankAndCurrency(_ bank: String, _ iban: String, _ currency: String) -> LocalizedStringResource {
        r("editor.accountWithBankAndCurrency", "\(bank) · \(iban) · \(currency)")
    }
    static let fieldOrderReference = r("editor.orderReference", "Order reference")
    static let notesOnPDF = r("editor.notesOnPDF", "Notes on the PDF")
    static let fieldNote = r("editor.note", "Note above the lines")
    /// The banner on an advance (screens-flows.md §0 rule 3); the printed clause comes from InvoicingCore.
    static let notATaxDocument = r("editor.notATaxDocument", "Not a tax document")
    static let taxPointIsPaymentDate = r("editor.taxPointIsPaymentDate", "the day the payment was received")
    static func receivedAmountNote(_ amount: String, _ day: String) -> LocalizedStringResource {
        r("editor.receivedAmountNote", "For the payment of \(amount) received \(day)")
    }
    static let receiptPaymentMissing = r("editor.receiptPaymentMissing", "No payment is linked to this tax document. Delete the draft. If the payment was received, record it on the advance again and create the tax document from its row.")
    static func receiptTotalMismatch(_ amount: String) -> LocalizedStringResource {
        r("editor.receiptTotalMismatch", "The total must equal the received payment of \(amount).")
    }

    static let linesTitle = r("editor.lines", "Lines")
    static let colDescription = r("editor.col.description", "Description")
    static let colQty = r("editor.col.qty", "Qty")
    static let colUnit = r("editor.col.unit", "Unit")
    static let colUnitPrice = r("editor.col.unitPrice", "Unit price")
    static let colDiscount = r("editor.col.discount", "Discount %")
    static let colVATRate = r("editor.col.vatRate", "VAT rate")
    static let colLineTotal = r("editor.col.lineTotal", "Line total")
    static let addLine = r("editor.addLine", "Add Line Item")
    static let deleteLine = r("editor.deleteLine", "Delete Line")
    static let insertLineBelow = r("editor.insertLineBelow", "Insert Line Below")
    static let moveLineUp = r("editor.moveLineUp", "Move Line Up")
    static let moveLineDown = r("editor.moveLineDown", "Move Line Down")
    static let reverseChargeItem = r("editor.reverseChargeItem", "Reverse charge")
    /// The § 64 treatment as the totals bar's single Total names it: "Total · Exempt (§ 64)".
    static let exemptSection64Item = r("editor.exemptSection64Item", "Exempt (§ 64)")
    static let rateNotInForce = r("editor.rateNotInForce", "Not in force")
    static func vatRateFixIt(_ rates: String) -> LocalizedStringResource { r("editor.vatRateFixIt", "Enter one of the rates in force: \(rates)") }
    static func enterNumber(_ example: String) -> LocalizedStringResource { r("editor.enterNumber", "Enter a number, such as \(example)") }
    static func enterRateNumber(_ example: String) -> LocalizedStringResource { r("editor.enterRateNumber", "Enter the rate as a number, such as \(example)") }
    static func invalidCellRow(_ line: Int, _ column: String) -> LocalizedStringResource { r("editor.invalidCell", "Line \(line): \(column) is not a number") }
    static func invalidRateRow(_ line: Int) -> LocalizedStringResource { r("editor.invalidRate", "Line \(line): VAT rate must be one of the rates in force") }

    static let base = r("editor.base", "Base")
    static let vat = r("editor.vat", "VAT")
    static let total = r("editor.total", "Total")
    static let amountDue = r("editor.amountDue", "Amount due")
    static let vatInCZK = r("editor.vatInCZK", "VAT in CZK")
    static let vatAfterAdvances = r("editor.vatAfterAdvances", "VAT after advances")
    static let totalsUnavailable = r("editor.totalsUnavailable", "Totals cannot be computed yet")
    /// "VAT — (daň odvede zákazník)": the dash with the printed clause from InvoicingCore (design-system.md §9).
    static func vatDashWithClause(_ clause: String) -> LocalizedStringResource { r("editor.vatDashWithClause", "— (\(clause))") }

    static func rateMissing(_ currency: String, _ day: String) -> LocalizedStringResource { r("editor.rateMissing", "\(currency) rate for \(day) missing") }
    static func rateFieldLabel(_ currency: String) -> LocalizedStringResource { r("editor.rateField", "CZK per 1 \(currency)") }
    static let rateDateLabel = r("editor.rateDate", "Rate date")
    static let saveRate = r("editor.saveRate", "Save Rate")
    static let changeRate = r("editor.changeRate", "Change…")
    static func rateEquals(_ code: String, _ rate: String) -> LocalizedStringResource { r("editor.rateEquals", "1 \(code) = \(rate) CZK") }
    static func rateFallback(_ wanted: String, _ used: String) -> LocalizedStringResource {
        r("editor.rateFallback", "No rate is published for \(wanted) (weekend or holiday); the last published rate, for \(used), applies")
    }
    static func rateNotPublished(_ wanted: String, _ used: String) -> LocalizedStringResource {
        r("editor.rateNotPublished", "The ČNB published no rate for \(wanted); the last published rate, for \(used), applies")
    }
    static func rateAfterRateDay(_ day: String) -> LocalizedStringResource {
        r("editor.rateAfterRateDay", "The rate date cannot be after \(day), the day this document needs the rate for.")
    }
    static func rateSavedForOtherDay(_ saved: String, _ needed: String) -> LocalizedStringResource {
        r("editor.rateSavedForOtherDay", "The rate was saved for \(saved); this document needs the rate for \(needed).")
    }
    static func rateAlreadyStored(_ day: String) -> LocalizedStringResource {
        r("editor.rateAlreadyStored", "A rate for \(day) is already stored and was kept; use Change… on it to replace it.")
    }

    static let deductionsTitle = r("editor.deductions", "Advances deducted")
    static let addReceipt = r("editor.addReceipt", "Add Tax Document…")
    static let noReceiptsToDeduct = r("editor.noReceipts", "No issued tax documents of this client in this currency are open")
    static func deductionAdvanceRow(_ advance: String, _ receipts: String) -> LocalizedStringResource { r("editor.deductionAdvanceRow", "\(advance) · \(receipts)") }
    static func vatTaxedCZK(_ amount: String) -> LocalizedStringResource { r("editor.vatTaxedCZK", "VAT taxed \(amount)") }
    static func receiptMenuItem(_ number: String, _ day: String, _ amount: String) -> LocalizedStringResource {
        r("editor.receiptMenuItem", "\(number) · \(day) · \(amount)")
    }
    static func receiptAlsoInDraft(_ receipt: String) -> LocalizedStringResource {
        r("editor.receiptAlsoInDraft", "Tax document \(receipt) is also listed in another draft final invoice")
    }
    static func advanceAlreadyDeductedIn(_ receipt: String, _ finalInvoice: String) -> LocalizedStringResource {
        r("issue.advanceAlreadyDeducted", "Tax document \(receipt) is already deducted in final invoice \(finalInvoice). Remove it from Advances deducted.")
    }

    // MARK: Review-and-issue sheet (screens-flows.md §2c)

    static func issueInvoiceTitle(_ number: String) -> LocalizedStringResource { r("issue.invoiceTitle", "Issue invoice \(number)?") }
    static func issueAdvanceTitle(_ number: String) -> LocalizedStringResource { r("issue.advanceTitle", "Issue advance invoice \(number)?") }
    static func issueTaxDocumentTitle(_ number: String) -> LocalizedStringResource { r("issue.taxDocumentTitle", "Issue tax document \(number)?") }
    static func issueFinalTitle(_ number: String) -> LocalizedStringResource { r("issue.finalTitle", "Issue final invoice \(number)?") }
    static let issueInvoiceTitleNoNumber = r("issue.invoiceTitleNoNumber", "Issue the invoice?")
    static let issueAdvanceTitleNoNumber = r("issue.advanceTitleNoNumber", "Issue the advance invoice?")
    static let issueTaxDocumentTitleNoNumber = r("issue.taxDocumentTitleNoNumber", "Issue the tax document?")
    static let issueFinalTitleNoNumber = r("issue.finalTitleNoNumber", "Issue the final invoice?")
    static let issueSubtitle = r("issue.subtitle", "Once issued, the document can't be edited or deleted.")
    static let confirmNumberSeries = r("issue.confirmSeries", "Confirm your number series in Settings ▸ Numbering.")
    static let fillIn = r("issue.fillIn", "Fill in…")
    static let noSeriesForKind = r("issue.noSeries", "No numbering series numbers this document type. Set one up in Settings ▸ Numbering.")
    static let summaryType = r("issue.type", "Type")
    static let summaryClient = r("issue.client", "Client")
    static let summaryLanguage = r("issue.language", "Language")
    static let summaryDates = r("issue.dates", "Dates")
    static let summaryTotal = r("issue.total", "Total")
    static let summaryRate = r("issue.rate", "Rate")
    static let summaryPayment = r("issue.payment", "Payment")
    static func clientSummary(_ name: String, _ treatment: String) -> LocalizedStringResource { r("issue.clientSummary", "\(name) · \(treatment)") }
    static func clientSummaryWithVATID(_ name: String, _ vatID: String, _ treatment: String) -> LocalizedStringResource {
        r("issue.clientSummaryWithVATID", "\(name) · VAT ID \(vatID) · \(treatment)")
    }
    static func datesSummary(_ issued: String, _ taxPoint: String, _ due: String) -> LocalizedStringResource {
        r("issue.datesSummary", "Issued \(issued) · DUZP \(taxPoint) · Due \(due)")
    }
    static func datesSummaryNoTaxPoint(_ issued: String, _ due: String) -> LocalizedStringResource {
        r("issue.datesSummaryNoTaxPoint", "Issued \(issued) · Due \(due)")
    }
    /// "EPC QR (SEPA) · Raiffeisenbank · CZ65 … · VS 20260042": QR type, account, predicted VS (docs-27).
    static func paymentSummary(_ account: String, _ qr: String) -> LocalizedStringResource { r("issue.paymentSummary", "\(qr) · \(account)") }
    static func paymentSummaryWithVS(_ account: String, _ qr: String, _ vs: String) -> LocalizedStringResource {
        r("issue.paymentSummaryWithVS", "\(qr) · \(account) · VS \(vs)")
    }
    static let qrKindQRPlatba = r("qr.qrPlatba", "QR Platba")
    static let qrKindSEPA = r("qr.sepa", "EPC QR (SEPA)")
    static let qrKindNone = r("qr.none", "No QR code")
    static let noPayment = r("issue.noPayment", "no bank account for this currency")
    static let blockingTitle = r("issue.blocking", "Fix before issuing")
    static let checkTitle = r("issue.check", "Check before issuing")
    static let checkedLabel = r("issue.checked", "Checked")
    static func issueDateNotToday(_ day: String) -> LocalizedStringResource { r("issue.dateNotToday", "The issue date \(day) is not today") }
    /// A floating issue date moved a "Same as the issue date" DUZP out of the month the draft was started in (docs-28).
    static func floatedIntoLaterMonth(_ started: String, _ today: String) -> LocalizedStringResource {
        r("issue.floatedIntoLaterMonth", "The draft was started on \(started); issued today, its DUZP is \(today), in a later month")
    }
    static let setToToday = r("issue.setToToday", "Set to today")
    static func issueFailed(_ error: String) -> LocalizedStringResource { r("issue.failed", "Issue failed: \(error)") }
    /// Issue pressed after midnight: the floating issue date moved to the new day and nothing was issued (docs-28).
    static let issueDateMovedToToday = r("issue.dateMovedToToday", "A new day has begun: the issue date is now today. Check the sheet, then issue again.")
    static func issuedResult(_ number: String) -> LocalizedStringResource { r("issue.result", "Issued \(number)") }
    static let draftGone = r("editor.gone", "This draft no longer exists.")
    static func errorDayBeforeSeriesYear(_ year: String) -> LocalizedStringResource {
        r("error.dayBeforeSeriesYear", "The issue date is before the series year \(year). Change the issue date.")
    }
    static func finalInvoiceReceiptsPending(_ day: String) -> LocalizedStringResource {
        r("finalInvoice.receiptsPending", "Issue the tax document for the payment of \(day) first; otherwise its amount would not be deducted.")
    }
    static func finalInvoiceReceiptsPendingMany(_ days: String) -> LocalizedStringResource {
        r("finalInvoice.receiptsPendingMany", "Issue the tax documents for the payments of \(days) first; otherwise their amounts would not be deducted.")
    }
    static func draftChangesNotSaved(_ error: String) -> LocalizedStringResource {
        r("editor.changesNotSaved", "The last changes to the draft were not saved: \(error)")
    }

    // MARK: Payments with a draft tax document (ADR 0009 amendments)

    static let deletePaymentWithDraftTitle = r("payment.deleteWithDraftTitle", "Delete the payment and its draft tax document?")
    static let deletePaymentWithDraftMessage = r("payment.deleteWithDraftMessage", "A draft tax document was created for this payment. Without the payment it documents nothing.")
    static let deletePaymentAndDraft = r("payment.deleteAndDraft", "Delete Payment and Draft")
    static let deletePaymentOnly = r("payment.deleteOnly", "Delete Payment Only")

    // MARK: Follow-ups (design check of the app shell, PR 17)

    static let menuRates = r("menu.rates", "Exchange Rates")
    static let recordRefund = r("menu.recordRefund", "Record Refund…")
    static let showClient = r("menu.showClient", "Show Client")
    static let reopenAdvance = r("menu.reopenAdvance", "Reopen Advance")
    static let removeCreditNoteMark = r("menu.removeCreditNoteMark", "Remove Credit Note Mark")
        static func newInvoiceFor(_ client: String) -> LocalizedStringResource { r("menu.newInvoiceFor", "New Invoice for \(client)") }
    static func newAdvanceFor(_ client: String) -> LocalizedStringResource { r("menu.newAdvanceFor", "New Advance Invoice for \(client)") }
        static let gettingStartedMenu = r("menu.gettingStarted", "Getting Started")
    static let newInvoiceHelp = r("help.newInvoice", "Create a new invoice")
    static let recordPaymentHelp = r("help.recordPayment", "Record a payment on the selected document")
    static let newClientHelp = r("help.newClient", "Add a client")
    static let deletePayment = r("menu.deletePayment", "Delete Payment")
    static let undo = r("action.undo", "Undo")
    static let draftDeleted = r("result.draftDeleted", "Draft deleted")
    static func draftsDeleted(_ count: Int) -> LocalizedStringResource { r("result.draftsDeleted", "\(count) drafts deleted") }
    static let paymentDeleted = r("result.paymentDeleted", "Payment deleted")
    static let accountRemoved = r("result.accountRemoved", "Bank account removed")
    static let importedRatesOne = r("rates.importedOne", "1 rate imported")
    static func paymentLockedBy(_ number: String) -> LocalizedStringResource {
        r("payment.lockedBy", "Payment is the basis of \(number) and can't be deleted")
    }
    static let showDocument = r("action.showDocument", "Show Document")
    static let colOpenBalance = r("column.openBalance", "Open balance")
    static let sourceStatement = r("payment.sourceStatement", "Statement")
    static let sourceCredit = r("payment.sourceCredit", "Credit")

    // Activity (the audit log of one document, newest first)
    static func activityIssued(_ number: String) -> LocalizedStringResource { r("activity.issued", "Issued as \(number)") }
    static func activityPayment(_ kind: String, _ amount: String) -> LocalizedStringResource { r("activity.payment", "\(kind): \(amount)") }
    static func activityPaymentDeleted(_ kind: String) -> LocalizedStringResource { r("activity.paymentDeleted", "\(kind) deleted") }
    static let activityReceiptAttached = r("activity.receiptAttached", "Tax document linked to a payment")
    static func activityClosed(_ reason: String) -> LocalizedStringResource { r("activity.closed", "Closed as unpaid: \(reason)") }
    static func activityMarked(_ reason: String) -> LocalizedStringResource { r("activity.marked", "Marked for credit note: \(reason)") }
    static let activityReopened = r("activity.reopened", "Reopened")
    static let activityPDF = r("activity.pdf", "PDF rendered and stored")
    static func activityPDFSaved(_ path: String) -> LocalizedStringResource { r("activity.pdfSaved", "PDF saved to \(path)") }
    static let activityDeleted = r("activity.deleted", "Deleted")

    // Clients
    static let vatCzechPayer = r("vat.czechPayer", "Czech VAT payer")
    static let vatCzechNonPayer = r("vat.czechNonPayer", "Czech business, not a VAT payer")
    static let vatEUBusinessGoods = r("vat.euBusinessGoods", "EU business, goods")
    static let vatEUBusinessServices = r("vat.euBusiness", "EU business, services")
    static let vatEUConsumer = r("vat.euConsumer", "EU consumer")
    static let vatNonEUBusiness = r("vat.nonEUBusiness", "Business outside the EU, services")
    static let vatNonEUConsumer = r("vat.nonEUConsumer", "Consumer outside the EU")
    static let reverseChargeNeedsVATID = r("client.reverseChargeNeedsVATID", "Reverse charge needs the client's VAT ID. Add it to issue documents for this client.")
    static let goodsExemptionNeedsVATID = r("client.goodsNeedsVATID", "The § 64 exemption needs the client's VAT ID. Add it to issue documents for this client.")
    static func clientDocumentsCount(_ count: Int) -> LocalizedStringResource { r("client.documentsCount", "\(count) documents") }
    static let clientDocumentsCountOne = r("client.documentsCountOne", "1 document")
    static let fieldCompanyID = r("field.companyID", "Company ID (IČO)")

    // Settings
    static let seriesStoreKeptCounter = r("series.storeKeptCounter", "The stored counter was ahead and was kept; a counter never goes backwards.")
    static let errorPatternMissingCounter = r("error.patternMissingCounter", "The pattern needs one counter token, such as {NNNN}.")
    static let errorPatternMultipleCounters = r("error.patternMultipleCounters", "The pattern has more than one counter token.")
    static func errorPatternUnknownToken(_ token: String) -> LocalizedStringResource {
        r("error.patternUnknownToken", "Unknown token {\(token)} in the pattern; use {YYYY}, {YY} and {NNNN}.")
    }
    static let errorPatternUnterminated = r("error.patternUnterminated", "A { in the pattern has no closing }.")
    static let errorSeriesNeedsYear = r("error.seriesNeedsYear", "A series that restarts every year needs {YYYY} or {YY} in its pattern.")
    static let errorSeriesInvalidState = r("error.seriesInvalidState", "The year or the counter is not valid.")
    static func errorInvalidVSPrefix(_ prefix: String) -> LocalizedStringResource {
        r("error.invalidVSPrefix", "The VS prefix \(prefix) must be 1 to 3 digits without a leading zero.")
    }

    // Exports and the database error
    static let backUpNow = r("exports.backUpNow", "Back Up Now")
    static let restoreFromBackup = r("exports.restore", "Restore from Backup…")
    // Stock (screens-flows.md §2n)
    static let newStockItem = r("stock.newItem", "New Stock Item…")
    static let newStockItemToolbar = r("stock.newItemToolbar", "New Stock Item")
    static let newStockItemHelp = r("stock.newItemHelp", "Add a stock item")
    static let newStockItemTitle = r("stock.newItemTitle", "New Stock Item")
    static let searchStock = r("stock.search", "Search stock")
    static let noStockItems = r("stock.empty", "No stock items yet")
    static let noStockItemsDescription = r("stock.emptyDescription", "Add the things you keep on the shelf to see what's running low.")
    static let stockSelectItem = r("stock.selectItem", "Select an item")
    static let stockItemArchived = r("stock.itemArchived", "Archived: this item is no longer listed in Stock. Its history stays.")
    static let colItem = r("stock.colItem", "Item")
    // The client page's Items tab (screens-flows.md §2n "On the client page")
    static let clientTabItems = r("client.tabItems", "Items")
    static let menuClientTab = r("menu.clientTab", "Client Tab")
    static let colBoughtThisYear = r("stock.colBoughtThisYear", "Bought This Year")
    static let colBoughtInAll = r("stock.colBoughtInAll", "Bought in All")
    static let colLastBought = r("stock.colLastBought", "Last Bought")
    static let colLastPrice = r("stock.colLastPrice", "Last Price")
    static let clientNoItems = r("client.noItems", "Nothing taken from stock on this client's invoices yet.")
    static func lastBoughtLine(_ day: String, _ number: String) -> LocalizedStringResource { r("stock.lastBought", "\(day) · \(number)") }
    static let colOnHand = r("stock.colOnHand", "On Hand")
    static let colReorderAt = r("stock.colReorderAt", "Reorder At")
    static let colCounted = r("stock.colCounted", "Counted")
    static let stockLow = r("stock.low", "Low")
    static let stockNever = r("stock.never", "Never")
    static let stockNeverCounted = r("stock.neverCounted", "Never counted")
    static func stockCountedAgo(_ when: String) -> LocalizedStringResource { r("stock.countedAgo", "Counted \(when)") }
    static let stockHistory = r("stock.history", "History")
    static let stockNoHistory = r("stock.noHistory", "Nothing received, taken out or counted yet.")
    static let stockReceived = r("stock.received", "Received")
    static let stockTakenOut = r("stock.takenOut", "Taken out")
    static func stockCounted(_ figure: String) -> LocalizedStringResource { r("stock.counted", "Counted \(figure)") }
    static func stockCountedHad(_ figure: String, _ had: String) -> LocalizedStringResource {
        r("stock.countedHad", "Counted \(figure) (app had \(had))")
    }
    static let stockCount = r("stock.count", "Count…")
    static let stockReceive = r("stock.receive", "Receive…")
    static let stockTakeOut = r("stock.takeOut", "Take Out…")
    static let stockArchiveItem = r("stock.archiveItem", "Archive Item")
    static func stockCountNamed(_ name: String) -> LocalizedStringResource { r("stock.countNamed", "Count “\(name)”…") }
    static func stockReceiveNamed(_ name: String) -> LocalizedStringResource { r("stock.receiveNamed", "Receive “\(name)”…") }
    static func stockTakeOutNamed(_ name: String) -> LocalizedStringResource { r("stock.takeOutNamed", "Take Out “\(name)”…") }
    static func stockArchiveNamed(_ name: String) -> LocalizedStringResource { r("stock.archiveNamed", "Archive “\(name)”") }
    static let stockReceiveHelp = r("stock.receiveHelp", "Add goods that arrived")
    static let stockCountHelp = r("stock.countHelp", "Set the number on hand after counting the shelf")
    static let stockCountTitle = r("stock.countTitle", "Count")
    static let stockReceiveTitle = r("stock.receiveTitle", "Receive")
    static let stockTakeOutTitle = r("stock.takeOutTitle", "Take Out")
    static let stockOnHandField = r("stock.onHandField", "On hand")
    static let stockReceivedField = r("stock.receivedField", "Received")
    static let stockTakenOutField = r("stock.takenOutField", "Taken out")
    static let stockCountedOn = r("stock.countedOn", "Counted on")
    static let stockOnDay = r("stock.onDay", "On")
    static let stockNote = r("stock.note", "Note")
    static let stockSaveCount = r("stock.saveCount", "Save Count")
    static let stockReceiveButton = r("stock.receiveButton", "Receive")
    static let stockTakeOutButton = r("stock.takeOutButton", "Take Out")
    static let stockUnit = r("stock.unit", "Unit")
    static let stockReorderAt = r("stock.reorderAt", "Reorder at")
    static let stockOnHandNow = r("stock.onHandNow", "On hand now")
    static let stockAddItem = r("stock.addItem", "Add Item")
    static let stockQuantityMoreThanZero = r("stock.qtyMoreThanZero", "Enter a quantity greater than zero.")
    static let stockQuantityZeroOrMore = r("stock.qtyZeroOrMore", "Enter a quantity of 0 or more.")
    static func stockNameTaken(_ name: String) -> LocalizedStringResource {
        r("stock.nameTaken", "A stock item named “\(name)” already exists.")
    }
    static let stockDayInFuture = r("stock.dayInFuture", "A count can't be dated in the future.")
    static let stockItemMissing = r("stock.itemMissing", "This stock item no longer exists.")
    static let stockItemHasMovements = r("stock.hasMovements", "An item with history can't be deleted; archive it instead.")
    static let undoNewStockItem = r("stock.undoNew", "New Stock Item")
    static let undoChangeStockItem = r("stock.undoChange", "Change Stock Item")
    static let undoReceive = r("stock.undoReceive", "Receive")
    static let undoTakeOut = r("stock.undoTakeOut", "Take Out")
    static let undoCount = r("stock.undoCount", "Count")
    static let undoDeleteStockItem = r("stock.undoDelete", "Delete Stock Item")
    static let undoArchiveStockItem = r("stock.undoArchive", "Archive Stock Item")

    // Stock in the draft's lines (screens-flows.md §2c, §2n)
    static func stockInStock(_ figure: String) -> LocalizedStringResource { r("stock.inStock", "\(figure) in stock") }
    static func addToStockNamed(_ name: String) -> LocalizedStringResource { r("stock.addToStockNamed", "Add “\(name)” to Stock…") }
    static func takesFromStockHelp(_ name: String, _ figure: String) -> LocalizedStringResource {
        r("stock.takesFromStockHelp", "Takes from stock: \(name) (\(figure) on hand)")
    }
    static func leavesStockWithFinalHelp(_ name: String, _ figure: String) -> LocalizedStringResource {
        r("stock.leavesWithFinalHelp", "\(name) (\(figure) on hand) leaves stock with the final invoice")
    }
    static let dontTakeFromStock = r("stock.dontTake", "Don't Take from Stock")
    static let undoDontTakeFromStock = r("stock.undoDontTake", "Don't Take from Stock")
    static let issueTakesFromStock = r("issue.takesFromStock", "Takes from stock")
    static func issueStockItem(_ name: String, _ change: String, _ left: String) -> LocalizedStringResource {
        r("issue.stockItem", "\(name) \(change) (\(left) left)")
    }
    static func issueStockItemCounted(_ name: String, _ change: String, _ left: String) -> LocalizedStringResource {
        r("issue.stockItemCounted", "\(name) \(change) (\(left) left, counted after the DUZP)")
    }

    // Backups (screens-flows.md §2h, §2a, §2i)
    static let backupFolder = r("backup.folder", "Backup folder")
    static let backupFolderPrompt = r("backup.folderPrompt", "Choose the folder where backups are kept.")
    /// The General caption: "Daily and on quit; the last 30 are kept. Last backup: today 9:02."
    static func backupCaption(_ last: String) -> LocalizedStringResource {
        r("backup.caption", "Daily and on quit; the last 30 are kept. Last backup: \(last).")
    }
    static let backupCaptionNone = r("backup.captionNone", "Daily and on quit; the last 30 are kept. No backup yet.")
    static func backupCaptionFailed(_ reason: String, _ lastDay: String) -> LocalizedStringResource {
        r("backup.captionFailed", "Daily and on quit; the last 30 are kept. Last backup failed: \(reason) · last successful \(lastDay)")
    }
    static func backupCaptionFailedNever(_ reason: String) -> LocalizedStringResource {
        r("backup.captionFailedNever", "Daily and on quit; the last 30 are kept. Last backup failed: \(reason)")
    }
    /// "today 9:02"; another day reads "3. 11. 2026 9:02".
    static func backupWhen(_ day: String, _ time: String) -> LocalizedStringResource { r("backup.when", "\(day) \(time)") }
    static func backupMadeAt(_ time: String) -> LocalizedStringResource { r("backup.madeAt", "Backup made at \(time)") }
    static func backupFailed(_ reason: String) -> LocalizedStringResource { r("backup.failed", "Backup failed: \(reason)") }
    static let backupNone = r("backup.none", "No backup yet")
    static func backupDaysAgo(_ days: Int) -> LocalizedStringResource { r("backup.daysAgo", "Last backup \(days) days ago") }
    static let backupUnreadable = r("backup.unreadable", "This file isn't a backup from this app, or it is damaged.")
    static let backupFromNewerVersion = r("backup.newerVersion", "A newer version of the app made this backup. Update the app to restore it.")

    // Restore from Backup… (screens-flows.md §2h)
    static let restorePanelMessage = r("restore.panelMessage", "Choose the backup to restore.")
    static let restoreTitle = r("restore.title", "Restore from Backup")
    static let restoreFile = r("restore.file", "File")
    static let restoreMadeOn = r("restore.madeOn", "Backup from")
    static let restoreAppVersion = r("restore.appVersion", "App version")
    static let restoreNotRecorded = r("restore.notRecorded", "Not recorded")
    static let restoreButton = r("restore.button", "Restore")
    static let restoreEllipsis = r("restore.buttonEllipsis", "Restore…")
    static func restoreAlertTitle(_ day: String) -> LocalizedStringResource {
        r("restore.alertTitle", "Replace current data with the backup from \(day)?")
    }
    static let restoreAlertTitleNoDate = r("restore.alertTitleNoDate", "Replace current data with this backup?")
    static let restoreAlertMessage = r("restore.alertMessage", "Current data will be saved as a backup first.")
    static let restoreAlertMessageUnopenable = r("restore.alertMessageUnopenable", "The data file that can't be opened will be kept next to it.")
    static let restoreProblemTitle = r("restore.problemTitle", "Backup not restored")
    static func restoreNotBackedUp(_ reason: String) -> LocalizedStringResource {
        r("restore.notBackedUp", "The current data couldn't be backed up first, so nothing was restored. \(reason)")
    }
    static func restoredFrom(_ day: String) -> LocalizedStringResource { r("restore.restoredFrom", "Restored the backup from \(day)") }
    static let restoredNoDate = r("restore.restoredNoDate", "Backup restored")
    static let okButton = r("action.ok", "OK")
    static let restoreMovingFromAnotherMac = r("restore.movingFromAnotherMac", "Moving from another Mac? Restore from Backup…")
    static let menuExportAccountant = r("menu.exportAccountant", "Export for Accountant…")

    // Follow-ups (PR 18): the setup card, the tiles, the detail banners, the client header, the series sheet
    static let done = r("setup.done", "Done")
    static let notDone = r("setup.notDone", "Not done")
    /// The Unpaid tile's advances line (other-02): one sentence; the overdue part only above 0.
    static func unpaidAdvancesLine(_ count: Int, _ amounts: String) -> LocalizedStringResource {
        r("overview.unpaidAdvancesLine", "Unpaid advances: \(count) · \(amounts)")
    }
    static func unpaidAdvancesLineOverdue(_ count: Int, _ amounts: String, _ overdue: Int) -> LocalizedStringResource {
        r("overview.unpaidAdvancesLineOverdue", "Unpaid advances: \(count) · \(amounts) · \(overdue) overdue")
    }
    /// The Overdue tile's line: "3 documents · oldest 23 days".
    static func overdueTileLine(_ documents: String, _ oldest: String) -> LocalizedStringResource {
        r("overview.overdueTileLine", "\(documents) · \(oldest)")
    }
    static let menuKindInvoice = r("menu.kind.invoice", "Invoice")
    static let menuKindAdvance = r("menu.kind.advance", "Advance Invoice")
    static let menuKindFinal = r("menu.kind.final", "Final Invoice")
    static let menuKindPaymentTaxDocument = r("menu.kind.paymentTaxDocument", "Tax Document for Received Payment")
    static let fieldCompanyVATID = r("field.companyVATID", "VAT ID (DIČ)")
    static func companyIDChip(_ value: String) -> LocalizedStringResource { r("client.companyIDChip", "IČO \(value)") }
    /// The Clients list's second line under the name (other-05): "Praha · IČO 12345678".
    static func clientCityAndCompanyID(_ city: String, _ value: String) -> LocalizedStringResource {
        r("client.cityAndCompanyID", "\(city) · IČO \(value)")
    }
    static let editClientDetails = r("menu.editClientDetails", "Edit Client Details…")
    /// The client form's type pop-up (other-08).
    static let fieldClientType = r("field.clientType", "Client type")
    /// The country pop-up's empty entry for a new client (shell-23).
    static let chooseCountry = r("field.chooseCountry", "Choose…")
    static func possibleDuplicate(_ name: String) -> LocalizedStringResource {
        r("client.possibleDuplicate", "Possible duplicate: \(name) – open it?")
    }
    static let openButton = r("action.open", "Open")
    static func vatIDChip(_ value: String) -> LocalizedStringResource { r("client.vatIDChip", "VAT ID \(value)") }
    static let countryRequired = r("validation.countryRequired", "A country is required.")
    static func rateEqualsAmount(_ amount: Int, _ code: String, _ rate: String) -> LocalizedStringResource {
        r("rates.rateEqualsAmount", "\(amount) \(code) = \(rate) CZK")
    }
    static let activityDraftCreated = r("activity.draftCreated", "Draft created")
    static let draftRestoredUnlinked = r(
        "result.draftRestoredUnlinked",
        "Draft restored without its payment link: the payment was deleted or already has another tax document.")
    static let paymentRestoredUnlinked = r(
        "result.paymentRestoredUnlinked",
        "Payment restored without its draft tax document: the draft was issued, changed or linked to another payment.")

    // MARK: Advances paid on EU goods (ADR 0012, the design thread's spec of 5 Nov 2026)

    static let paidInAdvanceTitle = r("editor.paidInAdvance", "Paid in advance")
    static let addPaidAdvance = r("editor.addPaidAdvance", "Add Paid Advance…")
    static let noPaidAdvances = r("editor.noPaidAdvances", "No paid EU goods advances of this client in this currency are open")
    static func paidAdvanceRow(_ advance: String, _ day: String) -> LocalizedStringResource {
        r("editor.paidAdvanceRow", "\(advance) · paid \(day)")
    }
    static func paidAdvanceMenuItem(_ advance: String, _ day: String, _ amount: String) -> LocalizedStringResource {
        r("editor.paidAdvanceMenuItem", "\(advance) · paid \(day) · \(amount)")
    }
    static func paidAdvanceAlsoInDraft(_ advance: String) -> LocalizedStringResource {
        r("editor.paidAdvanceAlsoInDraft", "A payment of advance \(advance) is also listed in another draft final invoice")
    }
    static func paidAdvanceAlreadySettledIn(_ advance: String, _ finalInvoice: String) -> LocalizedStringResource {
        r("issue.paidAdvanceAlreadySettled",
          "A payment of advance \(advance) is already settled in final invoice \(finalInvoice). Remove it from Paid in advance.")
    }
    static let paymentRecordedGoodsAdvance = r(
        "rp.recordedGoodsAdvance",
        "Payment recorded. An advance for EU goods needs no tax document: the final invoice lists it as paid in advance.")
    static func advanceAlreadyInFinalInvoice(_ numbers: String) -> LocalizedStringResource {
        r("finalInvoice.advanceAlreadyIn", "This advance is already in final invoice \(numbers).")
    }
    static func paymentSettledBy(_ number: String) -> LocalizedStringResource {
        r("payment.settledBy", "Payment is settled in \(number) and can't be deleted")
    }
    static func errorRelatedPaymentSettled(_ number: String) -> LocalizedStringResource {
        r("error.relatedPaymentSettled",
          "Final invoice \(number) settled the other side of this credit as paid in advance, so the credit cannot be deleted.")
    }
    static func errorPaymentBacksSettlement(_ number: String) -> LocalizedStringResource {
        r("error.paymentBacksSettlement",
          "Final invoice \(number) settled this advance as paid in advance; without this payment the advance's money would no longer match it, so it cannot be deleted.")
    }
    static func errorPaymentSettled(_ number: String) -> LocalizedStringResource {
        r("error.paymentSettled", "Final invoice \(number) settled this payment as paid in advance, so it cannot change and takes no tax document.")
    }
    static let errorPaidAdvanceInvalid = r(
        "error.paidAdvanceInvalid",
        "An advance under Paid in advance no longer matches its payment: the same client, currency, advance and day paid, and at most the amount received. Remove it and add it again.")
    static func errorAdvanceSettled(_ advance: String, _ finalInvoice: String) -> LocalizedStringResource {
        r("error.advanceSettled", "A payment of advance \(advance) is already settled in final invoice \(finalInvoice).")
    }
    static func errorPaidAdvancesExceed(_ advance: String, _ amount: String) -> LocalizedStringResource {
        r("error.paidAdvancesExceed", "At most \(amount) of advance \(advance) is left to list as paid in advance.")
    }

    // MARK: Lean shell (screens-flows.md §1.4, design-system.md §8.11)

    static func editClientNamed(_ name: String) -> LocalizedStringResource { r("menu.editClientNamed", "Edit Client “\(name)”…") }
    static let editClientEmpty = r("menu.editClientEmpty", "Edit Client…")
    static let searchDocuments = r("search.documents", "Search documents")
    static let searchClients = r("search.clients", "Search clients")
    static let searchPayments = r("search.payments", "Search payments")
    static let duplicateHelp = r("help.duplicate", "Copy this document into a new draft")
    static let recordRefundHelp = r("help.recordRefund", "Record money returned to the client")
    static func newInvoiceForHelp(_ client: String) -> LocalizedStringResource {
        r("help.newInvoiceFor", "Create an invoice for \(client)")
    }
    static let editThisClientHelp = r("help.editThisClient", "Edit this client's details")
    static let previewHelp = r("help.preview", "Show or hide the PDF preview")
    /// The Exchange Rates sheet (screens-flows.md §2g): "Latest: EUR 30. 10. 2026 · USD —".
    static func ratesLatest(_ eur: String, _ usd: String) -> LocalizedStringResource {
        r("rates.latest", "Latest: EUR \(eur) · USD \(usd)")
    }
    static let unpaidAdvances = r("selection.unpaidAdvances", "Unpaid advances")
    static let selectionRevenue = r("selection.revenue", "Revenue (tax documents)")
    static let openBalance = r("selection.openBalance", "Open balance")

    // MARK: Lean documents (screens-flows.md §2b, §2d; design-system.md §4.3)

    /// The badge detail of a final invoice its advances settled.
    static let byAdvances = r("status.byAdvances", "by advances")
    static let showClientHelp = r("document.showClientHelp", "Show this client in Clients")
    static let colTaxPoint = r("column.taxPoint", "DUZP")
    static let figureTaxPoint = r("document.taxPoint", "DUZP")
    /// "1 EUR = 24,315 CZK · for 30. 10. 2026 · Typed".
    static func figureRate(_ rate: String, _ day: String, _ source: String) -> LocalizedStringResource {
        r("document.rateLine", "\(rate) · for \(day) · \(source)")
    }
    /// A weekend or holiday: the last rate published before the rate day (screens-flows.md §0 rule 6).
    static func figureRateFallback(_ rate: String, _ day: String, _ source: String) -> LocalizedStringResource {
        r("document.rateLineFallback", "\(rate) · last published rate, for \(day) · \(source)")
    }
    /// "Czech + English · EU goods, exempt".
    static func languageAndTreatments(_ language: String, _ treatments: String) -> LocalizedStringResource {
        r("document.languageAndTreatments", "\(language) · \(treatments)")
    }

    // The chain line (screens-flows.md §2d).
    static func chainAdvance(_ number: String) -> LocalizedStringResource { r("chain.advance", "Advance \(number)") }
    static func chainAdvanceState(_ number: String, _ state: String) -> LocalizedStringResource {
        r("chain.advanceState", "Advance \(number) · \(state)")
    }
    /// VoiceOver: "Advance ZF 2026-0003, paid".
    static func chainAdvanceSpoken(_ number: String, _ state: String) -> LocalizedStringResource {
        r("chain.advanceSpoken", "Advance \(number), \(state)")
    }
    static func chainPayment(_ day: String) -> LocalizedStringResource { r("chain.payment", "Payment \(day)") }
    static let chainPaymentFuture = r("chain.paymentFuture", "Payment")
    static func chainTaxDocument(_ number: String) -> LocalizedStringResource { r("chain.taxDocument", "Tax document \(number)") }
    static let chainTaxDocumentDraft = r("chain.taxDocumentDraft", "Tax document (draft)")
    static let chainTaxDocumentFuture = r("chain.taxDocumentFuture", "Tax document")
    static func chainFinal(_ number: String) -> LocalizedStringResource { r("chain.final", "Final invoice \(number)") }
    static let chainFinalDraft = r("chain.finalDraft", "Final invoice (draft)")
    static let chainFinalFuture = r("chain.finalFuture", "Final invoice")

    // Document ▸ Show Related Documents ▸ (screens-flows.md §1.4), title case.
    static let menuShowRelated = r("menu.showRelated", "Show Related Documents")
    static func relatedAdvance(_ number: String) -> LocalizedStringResource { r("menu.related.advance", "Advance \(number)") }
    static func relatedTaxDocument(_ number: String) -> LocalizedStringResource { r("menu.related.taxDocument", "Tax Document \(number)") }
    static let relatedTaxDocumentDraft = r("menu.related.taxDocumentDraft", "Tax Document (Draft)")
    static func relatedFinal(_ number: String) -> LocalizedStringResource { r("menu.related.final", "Final Invoice \(number)") }
    static let relatedFinalDraft = r("menu.related.finalDraft", "Final Invoice (Draft)")

    // View ▸ Sort By ▸ and Edit ▸ Jump to Search Field (screens-flows.md §1.4).
    static let menuSortBy = r("menu.sortBy", "Sort By")
    static let sortAscending = r("menu.sortAscending", "Ascending")
    static let sortDescending = r("menu.sortDescending", "Descending")
    /// The Drafts filter's default sort, which has no column.
    static let sortLastEdited = r("menu.sortLastEdited", "Last Edited")
    static let jumpToSearch = r("menu.jumpToSearch", "Jump to Search Field")
    /// The subtitle of the Record Payment and closing sheets: "FV 2026-0042 · Acme GmbH".
    static func numberAndClient(_ number: String, _ client: String) -> LocalizedStringResource {
        r("closure.subtitle", "\(number) · \(client)")
    }

    // MARK: Lean editor (docs-17..26)

    static func editorSubtitle(_ type: String, _ state: String) -> LocalizedStringResource { r("editor.subtitle", "\(type) · \(state)") }
    static let subtitleInvoice = r("editor.subtitle.invoice", "Invoice")
    static let subtitleAdvance = r("editor.subtitle.advance", "Advance invoice")
    static let subtitlePaymentTaxDocument = r("editor.subtitle.paymentTaxDocument", "Tax document for payment")
    static let subtitleFinal = r("editor.subtitle.final", "Final invoice")
    /// "→ Wed 19. 11. 2026" after the due days.
    static func dueOnDate(_ weekday: String, _ day: String) -> LocalizedStringResource { r("editor.dueOnDate", "→ \(weekday) \(day)") }
    /// "Total · Exempt (§ 64)": the one figure of a document without Czech VAT.
    static func totalWithTreatment(_ treatment: String) -> LocalizedStringResource { r("editor.totalWithTreatment", "Total · \(treatment)") }
    /// "· for 30. 10. 2026 · Typed" after "1 EUR = 24,315 CZK".
    static func rateLineDetails(_ day: String, _ source: String) -> LocalizedStringResource { r("editor.rateLineDetails", "· for \(day) · \(source)") }
    static let addDiscount = r("editor.addDiscount", "Add Discount")
    static let menuBankAccount = r("menu.bankAccount", "Bank Account")

    // MARK: Lean Issue sheet (docs-27..29)

    /// "today" in "Issued today · DUZP …".
    static let todayWord = r("issue.today", "today")
    static func typeNotTaxDocument(_ type: String) -> LocalizedStringResource { r("issue.typeNotTaxDocument", "\(type) · Not a tax document") }
    static func datesSummaryNoDue(_ issued: String, _ taxPoint: String) -> LocalizedStringResource {
        r("issue.datesSummaryNoDue", "Issued \(issued) · DUZP \(taxPoint)")
    }
    static func paymentReceivedAgainst(_ day: String, _ advance: String) -> LocalizedStringResource {
        r("issue.paymentReceivedAgainst", "Payment received \(day) against \(advance)")
    }
    static func paymentReceivedOn(_ day: String) -> LocalizedStringResource { r("issue.paymentReceivedOn", "Payment received \(day)") }
    static func vatAtRate(_ percent: String) -> LocalizedStringResource { r("issue.vatAtRate", "VAT \(percent)") }
    static func vatAfterAdvancesAtRate(_ percent: String) -> LocalizedStringResource { r("issue.vatAfterAdvancesAtRate", "VAT after advances \(percent)") }
    /// "DD 2026-0001 at 24,315": a deducted tax document with its advance's rate.
    static func deductionAtRate(_ number: String, _ rate: String) -> LocalizedStringResource { r("issue.deductionAtRate", "\(number) at \(rate)") }
    static func rateSummary(_ rate: String, _ day: String, _ source: String) -> LocalizedStringResource {
        r("issue.rateSummary", "\(rate) · for \(day) · \(source)")
    }
    static func rateSummaryFallback(_ rate: String, _ day: String, _ source: String) -> LocalizedStringResource {
        r("issue.rateSummaryFallback", "\(rate) · for \(day) · \(source) · last published")
    }
    static let noPaymentRequest = r("issue.noPaymentRequest", "No payment request")
    static func differsCurrencyAndTreatment(_ client: String, _ fromCurrency: String, _ toCurrency: String,
                                            _ fromTreatment: String, _ toTreatment: String) -> LocalizedStringResource {
        r("issue.differsCurrencyAndTreatment",
          "Differs from \(client)'s defaults: currency \(fromCurrency) → \(toCurrency) · VAT treatment \(fromTreatment) → \(toTreatment)")
    }
    static func differsCurrency(_ client: String, _ from: String, _ to: String) -> LocalizedStringResource {
        r("issue.differsCurrency", "Differs from \(client)'s defaults: currency \(from) → \(to)")
    }
    static func differsTreatment(_ client: String, _ from: String, _ to: String) -> LocalizedStringResource {
        r("issue.differsTreatment", "Differs from \(client)'s defaults: VAT treatment \(from) → \(to)")
    }
    static func totalChangedFromLast(_ total: String, _ last: String) -> LocalizedStringResource {
        r("issue.totalChangedFromLast", "The total \(total) differs by more than half from the client's last invoice, \(last)")
    }
    static func advanceOtherTreatment(_ number: String) -> LocalizedStringResource {
        r("issue.advanceOtherTreatment", "\(number) was taxed under another VAT treatment than this invoice")
    }
    /// The result line after Issue (docs-29): one sentence with the saved PDF's path.
    static func issuedResultWithPDF(_ number: String, _ path: String) -> LocalizedStringResource {
        r("issue.resultWithPDF", "Issued \(number) · PDF saved to \(path)")
    }

    // MARK: Lean Record Payment (docs-30)

    static let outcomePaid = r("recordPayment.outcomePaid", "Document will be: Paid")
    static func outcomePartlyPaid(_ left: String) -> LocalizedStringResource { r("recordPayment.outcomePartlyPaid", "Partly paid – \(left) left") }
    static func outcomeOverpaid(_ surplus: String) -> LocalizedStringResource {
        r("recordPayment.outcomeOverpaid", "Overpaid by \(surplus) – kept as client credit")
    }
    static func paymentBeforeIssueDate(_ day: String) -> LocalizedStringResource {
        r("recordPayment.beforeIssueDate", "The payment date is before the document's issue date, \(day)")
    }
    static let possibleDuplicatePayment = r("recordPayment.possibleDuplicate", "Possible duplicate: a payment of this amount on this day is already recorded")
    static func paymentRecordedResult(_ amount: String, _ number: String) -> LocalizedStringResource {
        r("recordPayment.result", "Payment of \(amount) recorded on \(number)")
    }
    static func refundRecordedResult(_ amount: String, _ number: String) -> LocalizedStringResource {
        r("recordPayment.refundResult", "Refund of \(amount) recorded on \(number)")
    }

    // MARK: Export for Accountant (screens-flows.md §2h)

    static let exportTitle = r("export.title", "Export for Accountant")
    static func exportButton(_ month: String) -> LocalizedStringResource { r("export.button", "Export \(month)…") }
    static func exportAgainButton(_ month: String) -> LocalizedStringResource { r("export.buttonAgain", "Export \(month) Again…") }
    static let exportNotYet = r("export.notYet", "Not exported yet")
    static func exportedOnTo(_ day: String, _ folder: String) -> LocalizedStringResource {
        r("export.exportedOnTo", "Exported on \(day) to \(folder)")
    }
    static let exportChangedOne = r("export.changedOne", "1 document changed after export")
    static func exportChangedCount(_ count: Int) -> LocalizedStringResource {
        r("export.changedCount", "\(count) documents changed after export")
    }
    /// "October 2026: 14 documents (2 advances, non-tax) · 9 payments · VAT 42 180 Kč".
    static func exportPreview(_ month: String, _ documents: String, _ payments: String, _ vat: String) -> LocalizedStringResource {
        r("export.preview", "\(month): \(documents) · \(payments) · VAT \(vat)")
    }
    static func exportDocumentsWithAdvances(_ documents: String, _ advances: Int) -> LocalizedStringResource {
        r("export.documentsWithAdvances", "\(documents) (\(advances) advances, non-tax)")
    }
    static func exportDocumentsWithAdvanceOne(_ documents: String) -> LocalizedStringResource {
        r("export.documentsWithAdvanceOne", "\(documents) (1 advance, non-tax)")
    }
    static func exportPaymentsCount(_ count: Int) -> LocalizedStringResource { r("export.paymentsCount", "\(count) payments") }
    static let exportPaymentsOne = r("export.paymentsOne", "1 payment")
    static func exportDone(_ month: String) -> LocalizedStringResource { r("export.done", "\(month) exported") }
    static func exportDoneBackup(_ month: String) -> LocalizedStringResource { r("export.doneBackup", "\(month) exported · backup made") }
    static func exportDoneBackupFailed(_ month: String, _ reason: String) -> LocalizedStringResource {
        r("export.doneBackupFailed", "\(month) exported · backup failed: \(reason)")
    }
    static func exportFailed(_ reason: String) -> LocalizedStringResource {
        r("export.failed", "The files could not be written, so the month is not marked as exported. \(reason)")
    }
    static let exportPanelPrompt = r("export.panelPrompt", "Export")
    static let exportPanelMessage = r("export.panelMessage", "The month's files are written into a new folder with this name.")
    /// The Overview queue row (§2a): "October 2026 · 1 document changed after export".
    static func exportQueueRow(_ month: String, _ changed: String) -> LocalizedStringResource {
        r("export.queueRow", "\(month) · \(changed)")
    }
    static let exportAgain = r("export.again", "Export Again…")
    /// The Issue sheet's check for a document in a month already exported (§2c).
    static func issueMonthExported(_ month: String, _ day: String) -> LocalizedStringResource {
        r("issue.monthExported", "\(month) was already exported for the accountant on \(day); this document belongs to that month")
    }

    // The client's Activity tab and notes (screens-flows.md §2e, design-system.md §8.15)
    static let clientTabActivity = r("client.tabActivity", "Activity")
    static let addNotePrompt = r("activity.addNotePrompt", "Add a note…")
    static let noteText = r("activity.noteText", "Note")
    static let noteDay = r("activity.noteDay", "Day")
    static let noteDayHelp = r("activity.noteDayHelp", "The day the note is about")
    static func menuAddNote(_ name: String) -> LocalizedStringResource { r("menu.addNoteNamed", "Add Note to “\(name)”…") }
    static let menuAddNoteEmpty = r("menu.addNoteEmpty", "Add Note…")
    static let noActivity = r("activity.empty", "No notes or document events yet")
    static let editNote = r("activity.editNote", "Edit Note…")
    static let editNoteTitle = r("activity.editNoteTitle", "Edit Note")
    static let deleteNote = r("activity.deleteNote", "Delete Note")
    static let undoAddNote = r("activity.undoAdd", "Add Note")
    static let undoEditNote = r("activity.undoEdit", "Edit Note")
    static let undoDeleteNote = r("activity.undoDelete", "Delete Note")
    /// A document event in the client's tab: "FV 2026-0042 · Received: 1 000,00 €".
    static func activityForDocument(_ number: String, _ sentence: String) -> LocalizedStringResource {
        r("activity.forDocument", "\(number) · \(sentence)")
    }
    static let noteTextRequired = r("activity.textRequired", "Type the note first.")
    static let noteMissing = r("activity.noteMissing", "This note is no longer there.")

    // Repair mode (screens-flows.md §2m, design-system.md §8.18)
    static let menuRepairMode = r("menu.repairMode", "Repair Mode…")
    static let repairEnd = r("repair.end", "End Repair Mode")
    static let repairTurnOnTitle = r("repair.turnOnTitle", "Turn On Repair Mode?")
    static let repairTurnOnText = r("repair.turnOnText", "Repair mode unlocks every record, issued documents included. Every change is written to the audit log with a reason. The audit log stays on this Mac.")
    static let repairReason = r("repair.reason", "Reason")
    static let repairReasonPrompt = r("repair.reasonPrompt", "Wrong client address on FV 2026-0042")
    static let repairUnlock = r("repair.unlock", "Unlock…")
    static let repairNotUnlocked = r("repair.notUnlocked", "Not unlocked")
    /// The system's Touch ID or password prompt: what the unlock is for, without the app's name.
    static let repairAuthPrompt = r("repair.authPrompt", "unlock every record for repair")
    static let repairBanner = r("repair.banner", "Repair mode is on. Every change to a locked record is logged.")
    static let repairEndedByTimeout = r("repair.endedByTimeout", "Repair mode ended after 10 minutes without changes")
    static func repairEnded(_ count: Int) -> LocalizedStringResource { r("repair.ended", "Repair mode ended · \(count) changes logged") }
    static let repairEndedOne = r("repair.endedOne", "Repair mode ended · 1 change logged")
    static let repairLockLine = r("repair.lockLine", "Repair mode: changes are logged")
    static let repairUnlockedLabel = r("repair.unlockedLabel", "Unlocked for repair")
    static let repairDocument = r("repair.document", "Repair…")
    static func repairDocumentTitle(_ number: String) -> LocalizedStringResource { r("repair.documentTitle", "Repair \(number)") }
    static let repairDocumentText = r("repair.documentText", "Each change is written to the audit log with the reason. The document gets a new PDF; the old one is kept. Amounts, dates of the tax point and lines can't be repaired yet.")
    static let repairClientOnDocument = r("repair.clientOnDocument", "Client on the document")
    static let repairClientNow = r("repair.clientNow", "Client now")
    static let repairUseCurrentDetails = r("repair.useCurrentDetails", "Use the client's current details")
    static let repairClientHint = r("repair.clientHint", "To fix the client's details, change the client with Edit Client… first; they can then replace the ones on this document.")
    static let repairOrderReference = r("repair.orderReference", "Order reference")
    static let repairNote = r("repair.note", "Note")
    static let repairSave = r("repair.save", "Save Repair")
    static let repairReasonRequired = r("repair.reasonRequired", "Give the reason for the change.")
    static let repairNothingChanged = r("repair.nothingChanged", "Nothing was changed.")
    static let repairModeOff = r("repair.modeOff", "Repair mode has ended. Turn it on again with File ▸ Repair Mode… to save this change.")
    static func repairDone(_ number: String, _ count: Int) -> LocalizedStringResource {
        r("repair.done", "\(number) repaired · \(count) changes logged")
    }
    static func repairDoneOne(_ number: String) -> LocalizedStringResource { r("repair.doneOne", "\(number) repaired · 1 change logged") }
    static func repairUndoReason(_ reason: String) -> LocalizedStringResource { r("repair.undoReason", "Undo: \(reason)") }
    static let undoRepair = r("repair.undoName", "Repair")
    static let repairFieldClientName = r("repair.field.clientName", "Client name")
    static let repairFieldClientAddress = r("repair.field.clientAddress", "Client address")
    static let repairFieldClientCompanyID = r("repair.field.clientCompanyID", "Client IČO")
    static let repairFieldClientVATID = r("repair.field.clientVATID", "Client DIČ")
    static let repairFieldClientRegistry = r("repair.field.clientRegistry", "Client registry entry")
    static let repairFieldClientEmail = r("repair.field.clientEmail", "Client email")
    static let repairFieldClientPhone = r("repair.field.clientPhone", "Client phone")
    /// A repair event in the Activity: "Client address: Krátká 1 → Nová 5 · Wrong address".
    static func activityRepair(_ field: String, _ old: String, _ new: String, _ reason: String) -> LocalizedStringResource {
        r("activity.repair", "\(field): \(old) → \(new) · \(reason)")
    }
    static let activityPDFReplaced = r("activity.pdfReplaced", "New PDF after a repair; the old one is kept")

    // Bank statements, PDF fallback (screens-flows.md §2f)
    static let statement = r("statement.title", "Statement")
    static let statements = r("statement.menu", "Statements")
    static let statementsHelp = r("statement.menuHelp", "Open a bank statement next to your open documents, or import one")
    static let importStatement = r("statement.import", "Import Statement…")
    static let chooseStatementAccount = r("statement.chooseAccount", "Which account is this statement for?")
    static let statementNeedsAccount = r("statement.needsAccount", "Add your bank account in Settings ▸ Bank Accounts first.")
    static func statementImported(_ name: String) -> LocalizedStringResource {
        r("statement.imported", "Statement \(name) imported. Record the payments it shows on the right.")
    }
    static let doneReading = r("statement.done", "Done")
    static let doneReadingHelp = r("statement.doneHelp", "Back to the payments")
    static let statementUnreadable = r("statement.unreadable", "The statement can't be shown")
    static let statementFileMissing = r("statement.fileMissing", "No file is stored for this statement.")
    static let searchOpenDocuments = r("statement.search", "Find by VS, number, client or amount")
    static let noOpenDocuments = r("statement.noOpen", "Nothing is waiting for a payment")
    static let noMatchingOpenDocuments = r("statement.noMatch", "No open document matches")
    static let statementHint = r("statement.hint", "Copy the date and amount from the statement.")
    static func variableSymbolShort(_ symbol: String) -> LocalizedStringResource {
        r("statement.vs", "VS \(symbol)")
    }
    static let errorNotAPDF = r("error.notAPDF", "This file is not a PDF. Import the statement as the bank's PDF.")
}
