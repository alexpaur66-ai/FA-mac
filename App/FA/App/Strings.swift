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
    static let colOverdue = r("column.overdue", "Overdue")
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
    static func tileVAT(_ month: String) -> LocalizedStringResource { r("overview.tileVAT", "VAT for \(month) (CZK)") }
    static func documentsCount(_ count: Int) -> LocalizedStringResource { r("overview.documentsCount", "\(count) documents") }
    static let documentCountOne = r("overview.documentCountOne", "1 document")
    static func oldestOverdue(_ days: Int) -> LocalizedStringResource { r("overview.oldestOverdue", "oldest \(days) days") }
    static let oldestOverdueOne = r("overview.oldestOverdueOne", "oldest 1 day")
    static let vatTileNote = r("overview.vatNote", "Tax documents by the month of their date of taxable supply. Rule for the accountant to confirm.")
    static let revenueTaxDocuments = r("overview.revenueTaxDocuments", "Revenue from tax documents")
    static let needsAttention = r("overview.needsAttention", "Needs attention")
    static func daysOverdue(_ days: Int) -> LocalizedStringResource { r("queue.daysOverdue", "\(days) days overdue") }
    static let dayOverdueOne = r("queue.dayOverdueOne", "1 day overdue")
    static let queueTaxDocumentMissing = r("queue.taxDocumentMissing", "Payment received, tax document missing")
    static let queueOldDraft = r("queue.oldDraft", "Draft waiting for more than a week")
    static let previousMonth = r("overview.previousMonth", "Previous month")
    static let nextMonth = r("overview.nextMonth", "Next month")

    static let gettingStarted = r("setup.title", "Getting started")
    static let setupIntro = r("setup.intro", "Three steps before the first document can be issued. Each opens the matching settings.")
    static let stepCompany = r("setup.company", "Company profile")
    static let stepBank = r("setup.bank", "Bank accounts")
    static let stepSeries = r("setup.series", "Continue your number series")
    static let stepRates = r("setup.rates", "ČNB rates (optional): rates are typed per document; the import fills the table")
    static let stepFirstDocuments = r("setup.firstDocuments", "First client or first invoice (optional)")
    static let noDocumentsDescription = r("empty.noDocumentsDescription", "Invoices, advance invoices and tax documents appear here. ⌘N creates a new invoice.")
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
    static let draftNote = r("document.draftNote", "Drafts open in the editor. This draft carries the client's defaults and can be deleted.")
    static func lockLine(_ issued: String) -> LocalizedStringResource {
        r("document.lockLine", "Issued \(issued) · locked. Corrections via credit note (Phase 2).")
    }
    static let paymentsSection = r("document.payments", "Payments")
    static let paid = r("document.paid", "Paid")
    static let outstanding = r("document.outstanding", "Outstanding")
    static let issuedOn = r("document.issuedOn", "Issue date")
    static let dueOn = r("document.dueOn", "Due date")
    static let variableSymbol = r("document.variableSymbol", "Variable symbol")
    static let advancesDeducted = r("document.advancesDeducted", "Advances deducted")
    /// The inline error of the document list when its live observation stopped (ADR 0008).
    static let listStopped = r("document.listStopped", "The document list stopped updating.")
    static let retry = r("action.retry", "Try again")
    static func selectedCount(_ count: Int) -> LocalizedStringResource { r("document.selectedCount", "\(count) selected") }
    static let totalsPerCurrency = r("document.totalsPerCurrency", "Totals per currency")
    static let activity = r("document.activity", "Activity")
    static let account = r("document.account", "Account")
    static let chain = r("document.chain", "Related Documents")

    // MARK: Sheets

    static let rpTitle = r("recordPayment.title", "Record payment")
    static let rpDate = r("recordPayment.date", "Payment date")
    static let rpRefundDate = r("recordPayment.refundDate", "Refund date")
    static let rpRefundTitle = r("recordPayment.refundTitle", "Record refund")
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
    static let clientDocuments = r("client.documents", "Documents")
    static let invalidICO = r("validation.ico", "IČO is not valid (8 digits with a check digit).")
    static let invalidVATID = r("validation.vatID", "VAT ID is not valid (country code and number, for example CZ12345678).")
    static let nameRequired = r("validation.nameRequired", "A name is required.")
    static let invalidIBAN = r("validation.iban", "IBAN is not valid.")
    static let invalidBIC = r("validation.bic", "BIC is not valid.")
    static let invalidCzechAccount = r("validation.czechAccount", "Czech account number is not valid (prefix-number/bank code).")
    static let invalidRegistry = r("validation.registry", "Commercial register entry needs a court, section and insert.")

    // MARK: Settings (screens-flows.md §2i)

    static let settingsGeneral = r("settings.general", "General")
    static let settingsCompany = r("settings.company", "Company")
    static let settingsBank = r("settings.bank", "Bank accounts")
    static let settingsNumbering = r("settings.numbering", "Numbering")
    static let settingsDocuments = r("settings.documents", "Documents & PDF")
    static let settingsVAT = r("settings.vat", "VAT defaults")
    static let settingsBackup = r("settings.backup", "Backup")
    static let generalLanguageNote = r("settings.languageNote", "The app is in English. Documents print in Czech, or in Czech and English for foreign clients.")
    static let generalTextSizeNote = r("settings.textSizeNote", "Text size: View ▸ Bigger Text and Smaller Text scale every screen from 100 to 200 %.")
    static let dataFolder = r("settings.dataFolder", "Data file")
    static let showInFinder = r("settings.showInFinder", "Show in Finder")
    static let companyNote = r("settings.companyNote", "Changes apply to future documents only. Issued documents keep their own copy of these details.")
    static let fieldLegalName = r("field.legalName", "Legal name")
    static let fieldRegistryCourt = r("field.registryCourt", "Register court")
    static let fieldRegistrySection = r("field.registrySection", "Section")
    static let fieldRegistryInsert = r("field.registryInsert", "Insert")
    static let noCourt = r("field.noCourt", "Not registered")
    static let fieldVATPayer = r("field.vatPayer", "VAT payer")
    static let fieldDefaultCurrency = r("field.defaultCurrency", "Default currency")
    static let fieldDefaultTerm = r("field.defaultTerm", "Default payment term (days)")
    static let fieldFooter = r("field.footer", "Footer text")
    static let bankIBAN = r("bank.iban", "IBAN")
    static let bankBIC = r("bank.bic", "BIC")
    static let bankName = r("bank.name", "Bank name")
    static let bankCurrency = r("bank.currency", "Currency")
    static let bankCurrencyAny = r("bank.currencyAny", "Any")
    static let bankCzechAccount = r("bank.czechAccount", "Czech account number (prefix-number/bank code), instead of the IBAN")
    static let bankNote = r("bank.note", "The first account in a currency is printed on documents in that currency; an account without a currency serves the rest.")
    static let companyFirst = r("bank.companyFirst", "Fill in the company profile first.")
    static let noAccounts = r("bank.noAccounts", "No bank accounts yet")
    static let seriesName = r("series.name", "Series name")
    static let seriesTemplate = r("series.template", "Pattern ({YYYY}, {YY}, {NNNN})")
    static let seriesKinds = r("series.kinds", "Numbers these types")
    static let seriesYear = r("series.year", "Year")
    static let seriesLastCounter = r("series.lastCounter", "Last issued counter")
    static let seriesLastCounterNote = r("series.lastCounterNote", "To continue a series from another tool, enter the counter of the last number issued there. The counter never goes backwards.")
    static let seriesResetsYearly = r("series.resetsYearly", "Restarts every year")
    static let seriesVSPrefix = r("series.vsPrefix", "VS prefix (1 to 3 digits, no leading zero)")
    static let seriesNext = r("series.next", "Next number")
    static let seriesVSPreview = r("series.vsPreview", "Variable symbol")
    static let seriesTitle = r("series.title", "Number Series")
    static let newSeries = r("series.new", "New Series…")
    static let createDefaultSeries = r("series.createDefaults", "Create Default Series")
    static let defaultSeriesCaption = r("series.defaultsCaption", "FV for invoices and final invoices (VS prefix 1), ZF for advance invoices (prefix 2), DD for tax documents for payments (no prefix).")
    static let noSeries = r("series.none", "No number series yet")
    static let seriesPrefixCollision = r("series.collision", "Two series with the same pattern and the same prefix would give two documents the same variable symbol.")
    static let documentsPaneNote = r("settings.documentsNote", "The QR code default per client and the payment tolerance arrive with later steps.")
    static let vatPaneNote = r("settings.vatNote", "Rates 21 / 12 / 0 %, the treatments (Czech VAT, EU goods exempt under § 64, EU services with reverse charge, services outside the EU, other exemptions) and the default treatment by client status live in InvoicingCore. A pane to edit them is not built yet.")
    static let backupPaneNote = r("settings.backupNote", "Backup folder, automatic backups and Restore arrive with the export step. Until then: quit the app and copy the data file shown under General.")

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
    static func pdfWillBeSavedTo(_ path: String) -> LocalizedStringResource { r("pdf.willBeSavedTo", "Will be saved to \(path)") }
    static let pdfNoFolder = r("pdf.noFolder", "No PDF folder chosen: the PDF stays in the app until you use Save PDF….")
    static let pdfAutoSaveOff = r("pdf.autoSaveOff", "Automatic saving is off: the PDF stays in the app until you use Save PDF….")
    static let pdfSection = r("pdf.section", "PDF")
    static let pdfFolder = r("pdf.folder", "PDF folder")
    static let pdfFolderPrompt = r("pdf.folderPrompt", "Choose the folder where issued documents are saved as PDF files.")
    static let pdfFolderNone = r("pdf.folderNone", "No folder chosen")
    static let choose = r("action.choose", "Choose")
    static let chooseFolder = r("pdf.chooseFolder", "Choose Folder…")
    static let clearFolder = r("pdf.clearFolder", "Forget Folder")
    static let pdfAutoSave = r("pdf.autoSave", "Save PDF automatically when issuing")
    static let pdfYearSubfolder = r("pdf.yearSubfolder", "Subfolder per year")
    static let pdfFileName = r("pdf.fileName", "File name")
    static let pdfFileNamePattern = r("pdf.fileNamePattern", "{number} {client}.pdf")

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
    static let readyToIssue = r("editor.ready", "Ready to issue")
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
    static func clientSuggestionLine(_ ico: String, _ country: String, _ currency: String, _ language: String, _ treatment: String) -> LocalizedStringResource {
        r("editor.clientSuggestionLine", "IČO \(ico) · \(country) · \(currency) · \(language) · \(treatment)")
    }
    static func clientSuggestionLineNoICO(_ country: String, _ currency: String, _ language: String, _ treatment: String) -> LocalizedStringResource {
        r("editor.clientSuggestionLineNoICO", "\(country) · \(currency) · \(language) · \(treatment)")
    }
    static let vatIDMissing = r("editor.vatIDMissing", "VAT ID missing")
    static let addressMissing = r("editor.addressMissing", "Address missing")
    static let fieldType = r("editor.type", "Type")
    static let fieldIssueDate = r("editor.issueDate", "Issue date")
    static let fieldTaxPoint = r("editor.taxPoint", "Date of taxable supply")
    static let sameAsIssueDate = r("editor.sameAsIssueDate", "Same as the issue date")
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
    static let defaultAccount = r("editor.defaultAccount", "Default account for the currency")
    static let fieldOrderReference = r("editor.orderReference", "Order reference")
    static let fieldRelatedDocument = r("editor.relatedDocument", "Related document number")
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
    static let treatmentDiffersFromClient = r("editor.treatmentDiffersFromClient", "The VAT treatment differs from the client's default")
    static let currencyDiffersFromClient = r("editor.currencyDiffersFromClient", "The currency differs from the client's default")

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
    static let rateReverseCharge = r("editor.rate.rc", "RC")
    static let reverseChargeItem = r("editor.reverseChargeItem", "Reverse charge")
    /// The § 64 notice in the totals bar's VAT place, until the cuts give every untaxed treatment "Total · <short form>".
    static let exemptSection64Item = r("editor.exemptSection64Item", "Exempt (§ 64)")
    static let rateExempt = r("editor.rate.exempt", "exempt")
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
    static func rateDetails(_ day: String, _ source: String) -> LocalizedStringResource { r("editor.rateDetails", "for \(day) · \(source)") }
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
    static let seriesLabel = r("issue.series", "Numbering series")
    static let noSeriesForKind = r("issue.noSeries", "No numbering series numbers this document type. Set one up in Settings ▸ Numbering.")
    static let summaryType = r("issue.type", "Type")
    static let summaryClient = r("issue.client", "Client")
    static let summaryLanguage = r("issue.language", "Language")
    static let summaryDates = r("issue.dates", "Dates")
    static let summaryTotal = r("issue.total", "Total")
    static let summaryRate = r("issue.rate", "Rate")
    static let summaryPayment = r("issue.payment", "Payment")
    static let summaryLegal = r("issue.legal", "Legal notes")
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
    static func paymentSummary(_ account: String, _ qr: String) -> LocalizedStringResource { r("issue.paymentSummary", "\(account) · \(qr)") }
    static func paymentSummaryWithVS(_ account: String, _ qr: String, _ vs: String) -> LocalizedStringResource {
        r("issue.paymentSummaryWithVS", "\(account) · \(qr) · VS \(vs)")
    }
    static let qrKindQRPlatba = r("qr.qrPlatba", "QR Platba")
    static let qrKindSEPA = r("qr.sepa", "EPC QR (SEPA)")
    static let qrKindNone = r("qr.none", "No QR code")
    static let paymentFromProfile = r("issue.paymentFromProfile", "the company's account for this currency")
    static let noPayment = r("issue.noPayment", "no bank account for this currency")
    static let blockingTitle = r("issue.blocking", "Fix before issuing")
    static let checkTitle = r("issue.check", "Check before issuing")
    static let infoTitle = r("issue.info", "Notes")
    static let checkedLabel = r("issue.checked", "Checked")
    static func issueDateNotToday(_ day: String) -> LocalizedStringResource { r("issue.dateNotToday", "The issue date \(day) is not today") }
    static let setToToday = r("issue.setToToday", "Set to today")
    static func issueFailed(_ error: String) -> LocalizedStringResource { r("issue.failed", "Issue failed: \(error)") }
    static func issuedResult(_ number: String) -> LocalizedStringResource { r("issue.result", "Issued \(number)") }
    static let draftGone = r("editor.gone", "This draft no longer exists.")
    static let taxPointOtherMonth = r("issue.taxPointOtherMonth", "DUZP is in a different month from the issue date")
    static func errorDayBeforeSeriesYear(_ year: String) -> LocalizedStringResource {
        r("error.dayBeforeSeriesYear", "The issue date is before the series year \(year). Change the issue date or pick another series.")
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
    static let lockedNumber = r("document.locked", "Issued and locked")
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
    static let fieldVATTreatment = r("field.vatTreatment", "VAT treatment")
    static let vatCzechPayer = r("vat.czechPayer", "Czech VAT payer")
    static let vatCzechNonPayer = r("vat.czechNonPayer", "Czech business, not a VAT payer")
    static let vatEUBusinessGoods = r("vat.euBusinessGoods", "EU business, goods")
    static let vatEUBusinessServices = r("vat.euBusiness", "EU business, services")
    static let vatEUConsumer = r("vat.euConsumer", "EU consumer")
    static let vatNonEUBusiness = r("vat.nonEUBusiness", "Business outside the EU, services")
    static let vatNonEUConsumer = r("vat.nonEUConsumer", "Consumer outside the EU")
    static let reverseChargeNeedsVATID = r("client.reverseChargeNeedsVATID", "EU reverse charge needs the client's VAT ID; the validator will block issuing without it.")
    static let goodsExemptionNeedsVATID = r("client.goodsNeedsVATID", "The § 64 exemption needs the client's VAT ID. Add it to issue documents for this client.")
    static func clientDocumentsCount(_ count: Int) -> LocalizedStringResource { r("client.documentsCount", "\(count) documents") }
    static let clientDocumentsCountOne = r("client.documentsCountOne", "1 document")
    static let fieldCompanyID = r("field.companyID", "Company ID (IČO)")

    // Settings
    static let seriesLockedNote = r("series.lockedNote", "Numbers were issued from this series, so its year and counter can no longer be edited here.")
    static let seriesStoreKeptCounter = r("series.storeKeptCounter", "The stored counter was ahead and was kept; a counter never goes backwards.")
    static let seriesYearInFuture = r("series.yearInFuture", "The year cannot be after this year.")
    static let seriesKindsCaption = r("series.kindsCaption", "A document type numbered by two series picks one at issue.")
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
    static let defaultSeriesInvoices = r("series.defaultInvoices", "Invoices")
    static let defaultSeriesAdvances = r("series.defaultAdvances", "Advance invoices")
    static let defaultSeriesReceipts = r("series.defaultReceipts", "Tax documents for payments")

    // Exports and the database error
    static let backUpNow = r("exports.backUpNow", "Back Up Now")
    static let restoreFromBackup = r("exports.restore", "Restore from Backup…")
    static let menuExportAccountant = r("menu.exportAccountant", "Export for Accountant…")

    // Follow-ups (PR 18): the setup card, the tiles, the detail banners, the client header, the series sheet
    static let done = r("setup.done", "Done")
    static let notDone = r("setup.notDone", "Not done")
    static func unpaidAdvancesCount(_ count: Int) -> LocalizedStringResource { r("overview.unpaidAdvancesCount", "Unpaid advances: \(count) ·") }
    static func overdueAdvancesCount(_ count: Int) -> LocalizedStringResource { r("overview.overdueAdvancesCount", "Overdue advances: \(count)") }
    static let menuKindInvoice = r("menu.kind.invoice", "Invoice")
    static let menuKindAdvance = r("menu.kind.advance", "Advance Invoice")
    static let menuKindFinal = r("menu.kind.final", "Final Invoice")
    static let menuKindPaymentTaxDocument = r("menu.kind.paymentTaxDocument", "Tax Document for Received Payment")
    static let fieldCompanyVATID = r("field.companyVATID", "VAT ID")
    static func companyIDChip(_ value: String) -> LocalizedStringResource { r("client.companyIDChip", "IČO \(value)") }
    static func vatIDChip(_ value: String) -> LocalizedStringResource { r("client.vatIDChip", "VAT ID \(value)") }
    static let countryRequired = r("validation.countryRequired", "A country is required.")
    static func seriesCollisionWith(_ name: String) -> LocalizedStringResource {
        r("series.collisionWith", "Would give the same variable symbol as the series \(name). Change the pattern or the VS prefix.")
    }
    static let bannerClosedUnpaid = r("document.bannerClosedUnpaid", "Closed as unpaid")
    static let bannerMarkedForCreditNote = r("document.bannerMarkedForCreditNote", "Marked for credit note – credit notes arrive in Phase 2")
    static func rateEqualsAmount(_ amount: Int, _ code: String, _ rate: String) -> LocalizedStringResource {
        r("rates.rateEqualsAmount", "\(amount) \(code) = \(rate) CZK")
    }
    static let documentDefaultsTitle = r("settings.documentDefaults", "Document defaults")
    static let deductedByLabel = r("document.deductedByLabel", "Deducted in")
    static let activityDraftCreated = r("activity.draftCreated", "Draft created")
    static let draftRestoredUnlinked = r(
        "result.draftRestoredUnlinked",
        "Draft restored without its payment link: the payment was deleted or already has another tax document.")
    static let paymentRestoredUnlinked = r(
        "result.paymentRestoredUnlinked",
        "Payment restored without its draft tax document: the draft was issued, changed or linked to another payment.")
    static let seriesNumbersCollide = r(
        "series.numbersCollide", "Two series would issue the same document numbers; issuing from the second one would fail. Change a pattern.")
    static func seriesNumberCollisionWith(_ name: String) -> LocalizedStringResource {
        r("series.numberCollisionWith", "Would give the same document numbers as the series \(name). Change the pattern.")
    }

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
    static let settledInLabel = r("document.settledInLabel", "Settled in")
    static func paymentSettledBy(_ number: String) -> LocalizedStringResource {
        r("payment.settledBy", "Payment is settled in \(number) and can't be deleted")
    }
    /// The lock of a settled payment row, for VoiceOver.
    static let paymentSettledLocked = r("payment.settledLocked", "A final invoice settled this payment as paid in advance; it cannot change.")
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
    static func duplicateNumberedHelp(_ number: String) -> LocalizedStringResource {
        r("help.duplicateNumbered", "Duplicate \(number) as a new draft")
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
}
