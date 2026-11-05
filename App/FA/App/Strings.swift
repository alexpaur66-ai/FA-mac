// The user-facing strings of the app shell. Every string is a LocalizedStringResource in the "App" table
// (App.xcstrings: English defaults in sentence case, Czech translations), the same way the design system
// keeps its status labels in the "DesignSystem" table. Legal and tax wording stays in InvoicingCore.

import Foundation

enum L {
    private static func r(_ key: StaticString, _ value: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, defaultValue: value, table: "App")
    }

    // MARK: Sidebar (screens-flows.md §1.2)

    static let overview = r("sidebar.overview", "Overview")
    static let documents = r("sidebar.documents", "Documents")
    static let clients = r("sidebar.clients", "Clients")
    static let payments = r("sidebar.payments", "Payments & Bank")
    static let rates = r("sidebar.rates", "Exchange rates")
    static let exports = r("sidebar.exports", "Exports & Backup")

    static let filterAll = r("filter.all", "All")
    static let filterDrafts = r("filter.drafts", "Drafts")
    static let filterUnpaid = r("filter.unpaid", "Unpaid")
    static let filterOverdue = r("filter.overdue", "Overdue")
    static let filterThisMonth = r("filter.thisMonth", "This month")
    static let filterOpenAdvances = r("filter.openAdvances", "Open advances")

    // MARK: Menus and commands (screens-flows.md §1.4)

    static let new = r("menu.new", "New")
    static let newInvoice = r("menu.newInvoice", "New Invoice")
    static let newAdvance = r("menu.newAdvance", "New Advance Invoice")
    static let newClient = r("menu.newClient", "New Client…")
    static let menuDocument = r("menu.document", "Document")
    static let issue = r("menu.issue", "Issue…")
    static let recordPayment = r("menu.recordPayment", "Record Payment…")
    static let closeAdvanceUnpaid = r("menu.closeAdvanceUnpaid", "Close Advance as Unpaid…")
    static let markForCreditNote = r("menu.markForCreditNote", "Mark for Credit Note…")
    static let reopen = r("menu.reopen", "Reopen")
    static let deleteDraft = r("menu.deleteDraft", "Delete Draft")
    static let mainWindow = r("menu.mainWindow", "Main Window")
    static let biggerText = r("menu.biggerText", "Bigger Text")
    static let smallerText = r("menu.smallerText", "Smaller Text")
    static let actualSize = r("menu.actualSize", "Actual Size")
    static let toggleInspector = r("menu.toggleInspector", "Show or Hide Inspector")
    static let inspector = r("toolbar.inspector", "Inspector")

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
    static let colKind = r("column.kind", "Kind")
    static let colNote = r("column.note", "Note")
    static let colName = r("column.name", "Name")
    static let colCountry = r("column.country", "Country")
    static let colVATID = r("column.vatID", "VAT ID")
    static let colOverdue = r("column.overdue", "Overdue")
    static let colLastDocument = r("column.lastDocument", "Last document")
    static let colRate = r("column.rate", "Rate (CZK)")
    static let colSource = r("column.source", "Source")
    static let colDocument = r("column.document", "Document")

    // MARK: Document types, short (screens-flows.md §5)

    static let typeInvoice = r("type.invoice", "Invoice")
    static let typeAdvance = r("type.advance", "Advance")
    static let typePaymentTaxDocument = r("type.paymentTaxDocument", "Tax doc. for payment")
    static let typeFinal = r("type.final", "Final")

    /// The overdue badge detail (design-system.md §4.3): days late and the open balance.
    static func overdueDetail(_ days: Int, _ left: String) -> LocalizedStringResource {
        r("badge.overdueDetail", "+\(days) d · \(left)")
    }

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
    static let noRates = r("empty.noRates", "No rates for this currency yet")
    static let noSelection = r("empty.noSelection", "Select a document")
    static let noClientSelected = r("empty.noClientSelected", "Select a client")
    static let allCaughtUp = r("empty.allCaughtUp", "All caught up")
    static let noClient = r("document.noClient", "(no client)")
    static let comingLater = r("placeholder.comingLater", "Arrives in a later step.")

    // MARK: Overview (screens-flows.md §2a)

    static let tileUnpaid = r("overview.tileUnpaid", "Unpaid")
    static let tileOverdue = r("overview.tileOverdue", "Overdue")
    static func tileIssued(_ month: String) -> LocalizedStringResource { r("overview.tileIssued", "Issued in \(month)") }
    static func tileVAT(_ month: String) -> LocalizedStringResource { r("overview.tileVAT", "VAT for \(month) (CZK)") }
    static let unpaidAdvances = r("overview.unpaidAdvances", "Unpaid advances")
    static let overdueAdvances = r("overview.overdueAdvances", "Overdue advances")
    static func documentsCount(_ count: Int) -> LocalizedStringResource { r("overview.documentsCount", "\(count) documents") }
    static func oldestOverdue(_ days: Int) -> LocalizedStringResource { r("overview.oldestOverdue", "oldest \(days) days") }
    static let vatTileNote = r("overview.vatNote", "Tax documents by tax point month. Rule for the accountant to confirm.")
    static let revenueTaxDocuments = r("overview.revenueTaxDocuments", "Revenue from tax documents")
    static let needsAttention = r("overview.needsAttention", "Needs attention")
    static func daysOverdue(_ days: Int) -> LocalizedStringResource { r("queue.daysOverdue", "\(days) days overdue") }
    static let queueTaxDocumentMissing = r("queue.taxDocumentMissing", "Payment received, tax document missing")
    static let queueOldDraft = r("queue.oldDraft", "Draft waiting for more than a week")
    static let previousMonth = r("overview.previousMonth", "Previous month")
    static let nextMonth = r("overview.nextMonth", "Next month")

    static let gettingStarted = r("setup.title", "Getting started")
    static let setupIntro = r("setup.intro", "Four steps before the first document can be issued. Each opens the matching settings.")
    static let stepCompany = r("setup.company", "Company profile")
    static let stepBank = r("setup.bank", "Bank accounts")
    static let stepSeries = r("setup.series", "Number series")
    static let stepRates = r("setup.rates", "ČNB rates for EUR")
    static let openSettings = r("setup.openSettings", "Open Settings…")
    static let setUpCompanyFirst = r("setup.companyFirst", "Fill in the company profile in Settings before creating documents.")

    // MARK: Document detail (screens-flows.md §2b)

    static let draftTitle = r("document.draft", "Draft")
    static let draftNote = r("document.draftNote", "The draft editor arrives in the next step. This draft carries the client's defaults and can be deleted.")
    static func lockLine(_ issued: String) -> LocalizedStringResource {
        r("document.lockLine", "Issued \(issued) · locked. Corrections via credit note (Phase 2).")
    }
    static let paymentsSection = r("document.payments", "Payments")
    static let paid = r("document.paid", "Paid")
    static let outstanding = r("document.outstanding", "Outstanding")
    static let issuedOn = r("document.issuedOn", "Issued")
    static let dueOn = r("document.dueOn", "Due")
    static let clientLabel = r("document.client", "Client")
    static let variableSymbol = r("document.variableSymbol", "Variable symbol")
    static func deductedBy(_ numbers: String) -> LocalizedStringResource { r("document.deductedBy", "Deducted in \(numbers)") }
    static let advancesDeducted = r("document.advancesDeducted", "Advances deducted")
    /// The inline error of the document list when its live observation stopped (ADR 0008).
    static let listStopped = r("document.listStopped", "The document list stopped updating.")
    static let retry = r("action.retry", "Try again")
    static let closureReason = r("document.closureReason", "Reason")
    static func selectedCount(_ count: Int) -> LocalizedStringResource { r("document.selectedCount", "\(count) selected") }
    static let totalsPerCurrency = r("document.totalsPerCurrency", "Totals per currency")
    static let activity = r("document.activity", "Activity")
    static let paymentDetails = r("document.paymentDetails", "Payment details")
    static let account = r("document.account", "Account")
    static let chain = r("document.chain", "Related documents")
    static let openPreview = r("document.openPreview", "The PDF preview arrives with the PDF step.")

    // MARK: Sheets

    static let rpTitle = r("recordPayment.title", "Record payment")
    static let rpKind = r("recordPayment.kind", "Kind")
    static let rpDate = r("recordPayment.date", "Paid on")
    static let rpAmount = r("recordPayment.amount", "Amount")
    static let rpNote = r("recordPayment.note", "Note")
    static let rpRecord = r("recordPayment.record", "Record")
    static let closeAdvanceTitle = r("closure.closeAdvanceTitle", "Close advance as unpaid")
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
    static let fieldCountry = r("field.country", "Country code")
    static let fieldICO = r("field.ico", "IČO")
    static let fieldVATID = r("field.vatID", "VAT ID (DIČ)")
    static let fieldCurrency = r("field.currency", "Currency")
    static let fieldPaymentTerm = r("field.paymentTerm", "Payment term (days)")
    static let fieldLanguage = r("field.language", "Document language")
    static let fieldNotes = r("field.notes", "Notes")
    static let fieldEmail = r("field.email", "Email")
    static let fieldPhone = r("field.phone", "Phone")
    static let languageCzech = r("language.czech", "Czech")
    static let languageEnglish = r("language.english", "English")
    static let clientOpenBalance = r("client.openBalance", "Open balance")
    static let clientInvoicedThisYear = r("client.invoicedThisYear", "Invoiced this year")
    static let clientDocuments = r("client.documents", "Documents")
    static let invalidICO = r("validation.ico", "IČO is not valid (8 digits with a check digit).")
    static let invalidVATID = r("validation.vatID", "VAT ID is not valid (country code and number, for example CZ12345678).")
    static let nameRequired = r("validation.nameRequired", "A name is required.")
    static let invalidIBAN = r("validation.iban", "IBAN is not valid.")
    static let invalidBIC = r("validation.bic", "BIC is not valid.")
    static let invalidCzechAccount = r("validation.czechAccount", "Czech account number is not valid (prefix-number/bank code).")
    static let invalidCurrency = r("validation.currency", "Currency must be a three-letter code, for example EUR, or empty.")
    static let invalidRegistry = r("validation.registry", "Commercial register entry needs a court, section and insert.")

    // MARK: Settings (screens-flows.md §2i)

    static let settingsGeneral = r("settings.general", "General")
    static let settingsCompany = r("settings.company", "Company")
    static let settingsBank = r("settings.bank", "Bank accounts")
    static let settingsNumbering = r("settings.numbering", "Numbering")
    static let settingsDocuments = r("settings.documents", "Documents & PDF")
    static let settingsVAT = r("settings.vat", "VAT defaults")
    static let settingsBackup = r("settings.backup", "Backup")
    static let generalLanguageNote = r("settings.languageNote", "The app follows the language set for it in System Settings ▸ General ▸ Language & Region ▸ Applications. Czech and English are included.")
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
    static let bankCurrency = r("bank.currency", "Currency (empty = any)")
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
    static let seriesTitle = r("series.title", "Number series")
    static let newSeries = r("series.new", "New series…")
    static let createDefaultSeries = r("series.createDefaults", "Create the default series (FV with VS prefix 1, ZF with 2, DD without)")
    static let noSeries = r("series.none", "No number series yet")
    static let seriesPrefixCollision = r("series.collision", "Two series with the same pattern and the same prefix would give two documents the same variable symbol.")
    static let documentsPaneNote = r("settings.documentsNote", "Default due days, footer texts, file-name pattern, QR defaults and payment tolerance arrive with the PDF step.")
    static let vatPaneNote = r("settings.vatNote", "Rates 21 / 12 / 0 %, the treatments (Czech, EU reverse charge, outside the EU, exempt) and the default treatment by client country live in InvoicingCore. The pane to edit them arrives with the draft editor.")
    static let backupPaneNote = r("settings.backupNote", "Backup folder, automatic backups and Restore arrive with the export step. Until then: quit the app and copy the data file shown under General.")

    // MARK: Rates (screens-flows.md §2g)

    static let importRates = r("rates.import", "Import ČNB file…")
    static func importedRates(_ count: Int) -> LocalizedStringResource { r("rates.imported", "\(count) rates imported") }
    static func latestRate(_ day: String) -> LocalizedStringResource { r("rates.latest", "Latest rate: \(day)") }
    static let rateImportFailed = r("rates.importFailed", "The file could not be read as a ČNB daily or yearly file.")
    static func rateImportFailedAtLine(_ line: Int) -> LocalizedStringResource {
        r("rates.importFailedAtLine", "The file could not be read as a ČNB rate file: parsing stopped at line \(line). Nothing was imported.")
    }
    static let rateImportBadHeader = r("rates.importBadHeader", "The first line is not the header of a ČNB daily or yearly file. Nothing was imported.")
    static let ratesCoverage = r("rates.coverage", "Coverage")
    static let ratesNote = r("rates.note", "The app makes no network calls. Download the ČNB daily or yearly text file and import it here; drag and drop arrives later.")
    static let sourceCNB = r("rates.sourceCNB", "ČNB")
    static let sourceECB = r("rates.sourceECB", "ECB")
    static let sourceManual = r("rates.sourceManual", "Manual")
    static let sourceFixed = r("rates.sourceFixed", "Fixed accounting rate")

    // MARK: Exports (screens-flows.md §2h)

    static let exportAccountant = r("exports.accountant", "Export for accountant")
    static let exportAccountantNote = r("exports.accountantNote", "CSV and PDFs per period arrive with the export step.")
    static let backupTitle = r("exports.backup", "Backup")
    static let backupNote = r("exports.backupNote", "The database is one file. A copy made while the app is closed is a complete backup; Back Up Now and Restore arrive with the export step.")
    static let showDataFolder = r("exports.showDataFolder", "Show Data Folder")

    // MARK: Errors

    static let dbCannotOpen = r("error.dbCannotOpen", "Data can't be opened")
    static let errorGeneric = r("error.generic", "That did not work. Nothing was changed.")
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
}
