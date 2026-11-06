// The detail column for one issued document (screens-flows.md §2b): the header, the closing reason, the
// chain line, the figures, the lock line, the payments, the Activity and the PDF; there is no inspector and
// no banner. Drafts never come here: they open in DraftEditorView. The window computes what the document
// offers (`DocumentActions`) once, for the toolbar here, the Document menu and the context menu, so the
// three never disagree.

import InvoicingCore
import InvoicingData
import SwiftUI

struct DocumentDetailView: View {
    let stores: Stores
    let documents: DocumentListModel
    let documentID: String
    let actions: DocumentActions
    /// Deletes a payment, with or without its draft tax document; the window registers the undo.
    let deletePayment: @MainActor (DocumentPayment, Bool) -> Void
    /// Step 3 of the advance flow: the tax document for a received payment that has none (after "Later",
    /// or after its draft was deleted).
    var createTaxDocument: (@MainActor (DocumentPayment) -> Void)? = nil
    /// The chain line's next-step button (screens-flows.md §2d).
    var chainAction: (@MainActor (ChainNextStep) -> Void)? = nil
    /// Opens a payment's draft tax document in the editor.
    var openDraft: (@MainActor (String) -> Void)? = nil
    /// Shows another issued document by id: the tax document a locked payment is the basis of, the chain.
    var openDocument: (@MainActor (String) -> Void)? = nil
    /// Bumped by whoever saves the PDF (the File menu, this view), so the row and the menu items reload.
    var pdfVersion: Binding<Int> = .constant(0)
    /// Issue could not write the PDF file (screens-flows.md §2c): the notice offers Choose Folder… and Save PDF….
    var pdfSaveFailure: Binding<PDFSaveFailure?> = .constant(nil)
    /// Set by ↩ in the Documents table: the view takes keyboard focus.
    var focusRequest: Binding<Bool> = .constant(false)

    @State private var payments: [DocumentPayment] = []
    /// A payment with a draft tax document, waiting for the answer whether the draft goes too.
    @State private var paymentPendingDeletion: DocumentPayment?
    /// The settled payments of an advance (§ 64 goods, ADR 0012), for their captions.
    @State private var paidAdvanceLinks: [PaidAdvanceLink] = []
    /// The stored document: its account, rate, language and treatments for the figures.
    @State private var document: Document?
    @State private var chain: AdvanceChain?
    /// The document's Activity, oldest first as stored.
    @State private var events: [AuditEvent] = []
    @State private var activityExpanded = false
    @State private var loadError: String?
    /// The issued document's stored PDF, rendered and stored now when it has none yet (ADR 0010).
    @State private var pdf: StoredDocumentPDF?
    @State private var pdfError: String?
    @State private var savedFileExists = false
    @FocusState private var headerFocused: Bool
    @Environment(\.locale) private var locale

    private struct LoadKey: Equatable {
        let id: String
        let states: [DocumentState]
        let pdfVersion: Int
    }

    var body: some View {
        ScrollView {
            if let state = documents.state(id: documentID) {
                content(state)
                    .padding(Spacing.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // Title only (design-system.md §8.10): a real empty state has a symbol and an action.
                ContentUnavailableView { Text(L.noSelection) }
            }
        }
        .navigationTitle(Text(verbatim: documents.state(id: documentID)?.summary.number ?? ""))
        .toolbar { toolbar }
        .task(id: LoadKey(id: documentID, states: documents.states, pdfVersion: pdfVersion.wrappedValue)) {
            load()
        }
        // The view keeps its identity across issued documents: each one opens with Activity collapsed.
        .onChange(of: documentID) {
            activityExpanded = false
        }
        .onChange(of: focusRequest.wrappedValue, initial: true) { _, requested in
            guard requested else { return }
            headerFocused = true
            focusRequest.wrappedValue = false
        }
        .paymentDeletionDialog(pending: $paymentPendingDeletion, delete: deletePayment)
    }

    /// Fixed items (design-system.md §8.11): Duplicate, and the one prominent action, text only and declared
    /// last so it is trailing: Record Payment… while something is left to pay, Record Refund… on an overpaid
    /// document. A settled document shows Duplicate only; a payment tax document shows nothing. The advance's
    /// Create Final Invoice is the chain line's button.
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if let duplicate = actions.duplicate, actions.duplicateSourceNumber != nil {
            ToolbarItem {
                Button { duplicate() } label: {
                    Label { Text(L.duplicate) } icon: { Image(systemName: "plus.square.on.square") }
                }
                .help(Text(L.duplicateHelp))
            }
        }
        if let recordPayment = actions.recordPayment {
            ToolbarItem {
                Button { recordPayment() } label: { Text(L.recordPayment) }
                    .buttonStyle(.borderedProminent)
                    .help(Text(L.recordPaymentHelp))
            }
        } else if let recordRefund = actions.recordRefund {
            ToolbarItem {
                Button { recordRefund() } label: { Text(L.recordRefund) }
                    .buttonStyle(.borderedProminent)
                    .help(Text(L.recordRefundHelp))
            }
        }
    }

    private func load() {
        do {
            payments = try stores.documents.payments(for: documentID)
            paidAdvanceLinks = try DocumentLinks.paidAdvanceLinks(stores, state: documents.state(id: documentID))
            document = try stores.documents.document(id: documentID)
            chain = try AdvanceChain.of(documentID, stores: stores, states: documents.states)
            events = try DocumentLinks.shownEvents(stores.audit.events(entity: "document", id: documentID))
            loadError = nil
        } catch {
            payments = []
            paidAdvanceLinks = []
            document = nil
            chain = nil
            events = []
            loadError = ErrorText.message(error, locale: locale)
        }
        loadPDF()
    }

    /// The stored PDF of an issued document. A failure shows "Preview unavailable" with Try again; the
    /// document itself stays intact (screens-flows.md §2b).
    private func loadPDF() {
        guard documents.state(id: documentID)?.summary.status == .issued else {
            pdf = nil
            pdfError = nil
            savedFileExists = false
            return
        }
        do {
            let stored = try DocumentPDFService.issuedPDF(stores, documentID: documentID)
            pdf = stored
            savedFileExists = stored.savedPath.map { PDFFiles.fileExists(at: $0) } ?? false
            pdfError = nil
        } catch {
            pdf = nil
            savedFileExists = false
            pdfError = ErrorText.message(error, locale: locale)
        }
    }

    @ViewBuilder private func content(_ state: DocumentState) -> some View {
        let summary = state.summary
        VStack(alignment: .leading, spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                header(state)
                if let closure = state.closure {
                    // The reason shows once, here (design-system.md §8.3): the badge above names the event.
                    Text(verbatim: closure.reason)
                        .textRole(.rowSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let chain {
                    ChainLine(chain: chain, open: openChainItem, perform: { chainAction?($0) })
                }
            }
            // Critical information goes at the top (screens-flows.md §0.1): a PDF that could not be written.
            if let failure = pdfSaveFailure.wrappedValue, failure.documentID == documentID {
                saveFailureNotice(failure)
            }
            VStack(alignment: .leading, spacing: Spacing.s) {
                figures(state)
                if let line = languageAndTreatmentLine {
                    Text(verbatim: line).textRole(.rowSecondary)
                }
            }
            if summary.status == .issued {
                if let repair = actions.repair {
                    // Repair mode (§2m, design-system.md §8.18): the lock is open and every change is logged.
                    HStack(spacing: Spacing.m) {
                        Label {
                            Text(L.repairLockLine)
                        } icon: {
                            Image(systemName: "lock.open.fill")
                                .help(Text(L.repairUnlockedLabel))
                                .accessibilityLabel(Text(L.repairUnlockedLabel))
                        }
                        .textRole(.legalNote)
                        Button { repair() } label: { Text(L.repairDocument) }
                    }
                } else {
                    Label {
                        Text(lockLine(summary))
                    } icon: {
                        Image(systemName: "lock.fill")
                    }
                    .textRole(.legalNote)
                }
                paymentsSection(state)
            }
            if let loadError {
                InlineMessage(loadError)
            }
            if summary.status == .issued {
                if !events.isEmpty {
                    DisclosureGroup(isExpanded: $activityExpanded) {
                        DocumentActivityList(events: events, currency: summary.currency)
                            .padding(.top, Spacing.s)
                    } label: {
                        Text(L.activity).textRole(.sectionTitle)
                    }
                }
                pdfSection
            }
        }
    }

    /// Opens a step of the chain line: a draft in the editor, an issued document in this view.
    private func openChainItem(_ item: ChainItem) {
        guard let id = item.documentID else { return }
        if item.isDraft {
            openDraft?(id)
        } else {
            openDocument?(id)
        }
    }

    /// "Issued 5. 11. 2026 at 19:02 · locked. …" with the stored issue time; the date alone when the
    /// summary has no issue stamp or it cannot be parsed.
    private func lockLine(_ summary: DocumentSummary) -> LocalizedStringResource {
        let day = summary.issueDate.formatted(locale)
        guard let stamp = summary.issuedAt, let issued = try? Date(stamp, strategy: .iso8601) else {
            return L.lockLine(day)
        }
        return L.lockLineAt(day, issued.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale)))
    }

    /// What a final invoice deducts: its gross before deductions minus its amount due, without what it lists
    /// as paid in advance (§ 64 goods, ADR 0012), which has its own row. Nil when either figure is missing.
    static func deductedAmount(_ summary: DocumentSummary) -> Money? {
        guard let total = summary.totalGross, let due = summary.amountDue, total.currency == due.currency else { return nil }
        if let paid = summary.paidInAdvance, paid.currency == due.currency {
            return total - due - paid
        }
        return total - due
    }

    /// The number; the English type with the Czech title; the client link; the status badge. A closing
    /// event's badge has no detail: its reason is the line under the header.
    private func header(_ state: DocumentState) -> some View {
        let summary = state.summary
        return HStack(alignment: .firstTextBaseline, spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verbatim: summary.number ?? "").textRole(.documentNumber)
                Text(verbatim: summary.kind.pickerTitle).textRole(.body)
                if summary.customerName.isEmpty {
                    Text(L.noClient).textRole(.rowSecondary)
                } else if let showClient = actions.showClient {
                    // The client link (screens-flows.md §2b): selects the client in Clients.
                    Button { showClient() } label: {
                        Text(verbatim: summary.customerName).textRole(.rowSecondary)
                    }
                    .buttonStyle(.link)
                    .help(Text(L.showClientHelp))
                } else {
                    Text(verbatim: summary.customerName).textRole(.rowSecondary)
                }
            }
            Spacer(minLength: Spacing.l)
            StatusBadge(DocumentStateInputs(state),
                        detail: DocumentRow(state: state, today: documents.today).badgeDetail(locale: locale, withReason: false))
        }
        // ↩ in the table lands here; Tab goes on to the links and buttons below.
        .focusable()
        .focused($headerFocused)
    }

    /// One figure: the label and its value, each only where it applies (design-system.md §8.12).
    private func figure<Value: View>(_ label: LocalizedStringResource, @ViewBuilder value: () -> Value) -> some View {
        GridRow {
            Text(label).textRole(.label)
            value()
        }
    }

    /// The frozen values in the order of screens-flows.md §2b: Total, the deduction, Paid, Open balance,
    /// Issued, DUZP, Due, VS, Account, Rate and VAT in CZK.
    private func figures(_ state: DocumentState) -> some View {
        let summary = state.summary
        let code = summary.currency.code
        let payable = summary.kind != .paymentTaxDocument
        let foreign = summary.currency != .czk
        return Grid(alignment: .leading, horizontalSpacing: Spacing.xl, verticalSpacing: Spacing.s) {
            figure(L.colTotal) {
                if let total = summary.totalGross {
                    MoneyText(amount: total.amount, currency: code, locale: locale, role: .total)
                } else {
                    Text(verbatim: "—").textRole(.total)
                }
            }
            if summary.kind == .finalInvoice, let deducted = Self.deductedAmount(summary), !deducted.isZero {
                // Total − advances = amount due (screens-flows.md §2d), so the figures reconcile.
                figure(L.advancesDeducted) {
                    MoneyText(amount: -deducted.amount, currency: code, locale: locale)
                }
            }
            if summary.kind == .finalInvoice, let paid = summary.paidInAdvance, !paid.isZero {
                // Total − paid in advance = amount due: the § 64 value itself is never reduced (ADR 0012).
                figure(L.paidInAdvanceTitle) {
                    MoneyText(amount: -paid.amount, currency: code, locale: locale)
                }
            }
            if payable && state.paid.amount > 0 {
                figure(L.paid) {
                    MoneyText(amount: state.paid.amount, currency: code, locale: locale)
                }
            }
            if payable {
                figure(L.openBalance) {
                    MoneyText(amount: state.outstanding.amount, currency: code, locale: locale, role: .amountStrong)
                }
            }
            figure(L.issuedOn) { DayText(summary.issueDate) }
            if summary.kind.isTaxDocument {
                figure(L.figureTaxPoint) { DayText(summary.taxPointDate ?? summary.issueDate) }
            }
            if payable {
                figure(L.dueOn) { DayText(summary.dueDate) }
            }
            if let symbol = summary.variableSymbol {
                figure(L.variableSymbol) {
                    Text(verbatim: symbol).textRole(.amount).textSelection(.enabled)
                }
            }
            if let account = document?.payment?.bankConnection.iban.formatted {
                figure(L.account) {
                    Text(verbatim: account).textRole(.amount).textSelection(.enabled)
                }
            }
            if foreign, summary.kind.isTaxDocument, let line = rateLine {
                figure(L.colRate) {
                    Text(verbatim: line).textRole(.amount).textSelection(.enabled)
                }
            }
            if foreign, let vat = summary.taxableVATCZK, !vat.isZero {
                // Czech VAT charged on a EUR or USD document, in CZK (screens-flows.md §0 rule 5).
                figure(L.vatInCZK) {
                    MoneyText(amount: vat.amount, currency: vat.currency.code, locale: locale)
                }
            }
        }
    }

    /// "1 EUR = 24,315 CZK · for 30. 10. 2026 · Typed": the rate, its own day and its source. A rate for an
    /// earlier day than the rate day (a weekend or holiday) is named the last published rate (§0 rule 6).
    private var rateLine: String? {
        guard let document, let rate = document.exchangeRate else { return nil }
        let row = RateRow(rate: rate)
        let value = row.rateText(locale: locale)
        let day = rate.validFor.formatted(locale)
        return rate.validFor == document.exchangeRateDay
            ? String(localized: L.figureRate(value, day, row.sourceName))
            : String(localized: L.figureRateFallback(value, day, row.sourceName))
    }

    /// "Czech + English · EU goods, exempt": the document language and its VAT treatments in short form.
    private var languageAndTreatmentLine: String? {
        guard let document else { return nil }
        let language = String(localized: document.language == .english ? L.languageEnglish : L.languageCzech)
        var seen: Set<TreatmentChoice> = []
        let treatments = document.treatments.map { TreatmentChoice($0) }.filter { seen.insert($0).inserted }
            .map { String(localized: $0.shortTitle) }
        guard !treatments.isEmpty else { return language }
        return String(localized: L.languageAndTreatments(language, treatments.joined(separator: ", ")))
    }

    private func paymentsSection(_ state: DocumentState) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(L.paymentsSection).textRole(.sectionTitle)
            if payments.isEmpty {
                Text(L.noPayments).textRole(.rowSecondary)
            }
            ForEach(payments) { payment in
                paymentRow(payment, state: state)
            }
        }
    }

    /// Date · kind · source (bank imports only) · note, the amount trailing, with no lock glyph (screens-flows.md
    /// §2f). A payment an issued tax document rests on, or one a final invoice settled, says so in its
    /// caption. Open Tax Document, Create Tax Document and Delete Payment are in the row's context menu.
    @ViewBuilder private func paymentRow(_ payment: DocumentPayment, state: DocumentState) -> some View {
        // An advance for § 64 goods takes no tax document; its payments are settled in the final invoice (ADR 0012).
        let isAdvanceReceipt = state.summary.kind == .advanceRequest && payment.kind == .received && state.taxDocumentRequired
        let settledIn = paidAdvanceLinks.first { $0.paymentID == payment.id }
        let draftReceiptID = payment.receiptIssued ? nil : payment.receiptDocumentID
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(spacing: Spacing.m) {
                DayText(payment.paidOn)
                Text(payment.kind.title).textRole(.rowSecondary)
                if payment.isFromBankImport {
                    Text(payment.sourceTitle).textRole(.rowSecondary)
                }
                if let note = payment.note, !note.isEmpty {
                    Text(verbatim: note).textRole(.rowSecondary).lineLimit(1)
                }
                Spacer()
                MoneyText(amount: payment.amount.amount, currency: payment.amount.currency.code, locale: locale)
            }
            // The basis of an issued tax document: the row names it and opens it (screens-flows.md §2f).
            if payment.receiptIssued, let receiptID = payment.receiptDocumentID {
                HStack(spacing: Spacing.m) {
                    Text(L.paymentLockedBy(documents.state(id: receiptID)?.summary.number ?? "")).textRole(.caption)
                    if let openDocument {
                        Button { openDocument(receiptID) } label: { Text(L.showDocument) }
                            .buttonStyle(.link)
                    }
                }
            } else if let settledIn {
                HStack(spacing: Spacing.m) {
                    Text(L.paymentSettledBy(settledIn.finalInvoiceNumber)).textRole(.caption)
                    if let openDocument {
                        Button { openDocument(settledIn.finalInvoiceID) } label: { Text(L.showDocument) }
                            .buttonStyle(.link)
                    }
                }
            }
        }
        .contextMenu {
            if isAdvanceReceipt, let draftReceiptID, let openDraft {
                Button { openDraft(draftReceiptID) } label: { Text(L.openTaxDocument) }
            } else if isAdvanceReceipt, payment.receiptDocumentID == nil, let createTaxDocument {
                Button { createTaxDocument(payment) } label: { Text(L.createTaxDocument) }
            }
            if payment.canBeDeleted && settledIn == nil {
                Button(role: .destructive) {
                    // A draft tax document of the payment documents nothing without it: ask (ADR 0009 amendments).
                    if payment.deletionNeedsConfirmation {
                        paymentPendingDeletion = payment
                    } else {
                        deletePayment(payment, false)
                    }
                } label: {
                    Text(L.deletePayment)
                }
            }
        }
    }


    // MARK: PDF (screens-flows.md §2b, ADR 0010)

    /// The saved file line, the PDF actions and the pages. Show PDF in Finder is disabled while the file is
    /// missing: the app keeps its own frozen copy of the bytes from issue time.
    @ViewBuilder private var pdfSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(L.pdfSection).textRole(.sectionTitle)
            if let path = pdf?.savedPath {
                Text(verbatim: savedFileExists ? PDFSettings.displayPath(URL(fileURLWithPath: path)) : String(localized: L.pdfFileMoved))
                    .textRole(.rowSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            } else if pdf != nil {
                Text(L.pdfNotSavedYet).textRole(.rowSecondary)
            }
            HStack(spacing: Spacing.m) {
                Button { savePDF() } label: { Text(L.savePDF) }
                    .disabled(pdf == nil)
                Button { if let path = pdf?.savedPath { PDFFiles.reveal(path: path) } } label: { Text(L.showPDFInFinder) }
                    .disabled(!savedFileExists)
                Button { printPDF() } label: { Text(L.printDocument) }
                    .disabled(pdf == nil)
            }
            if let pdfError {
                HStack(spacing: Spacing.m) {
                    InlineMessage(L.pdfPreviewUnavailable, detail: pdfError)
                    Button { loadPDF() } label: { Text(L.retry) }
                }
            }
        }
        if let pdf {
            PDFPagesView(data: pdf.data)
        }
    }

    /// "PDF couldn't be saved to …" with Choose Folder… and Save PDF… (screens-flows.md §2c).
    private func saveFailureNotice(_ failure: PDFSaveFailure) -> some View {
        // A problem-kind message, the system text as its detail line (design-system.md §8.3).
        VStack(alignment: .leading, spacing: Spacing.s) {
            InlineMessage(L.pdfSaveFailed(failure.folder), detail: failure.detail)
            HStack(spacing: Spacing.m) {
                Button { chooseFolderAndSave() } label: { Text(L.chooseFolder) }
                Button { savePDF() } label: { Text(L.savePDF) }
            }
        }
    }

    private func savePDF() {
        do {
            guard try PDFActions.save(stores, documentID: documentID) != nil else { return }
            pdfSaveFailure.wrappedValue = nil
            loadPDF()
            pdfVersion.wrappedValue += 1
        } catch {
            loadError = ErrorText.message(error, locale: locale)
        }
    }

    private func chooseFolderAndSave() {
        do {
            guard let folder = try PDFFiles.chooseFolder() else { return }
            _ = try PDFActions.save(stores, documentID: documentID, into: folder)
            pdfSaveFailure.wrappedValue = nil
            loadPDF()
            pdfVersion.wrappedValue += 1
        } catch {
            loadError = ErrorText.message(error, locale: locale)
        }
    }

    private func printPDF() {
        do {
            try PDFActions.printPDF(stores, documentID: documentID, draft: nil)
        } catch {
            loadError = ErrorText.message(error, locale: locale)
        }
    }
}

/// The links of the advance chain and the Activity events of a document, loaded for the issued view.
enum DocumentLinks {
    /// The numbers in their order, without repeats (they are the ids of a ForEach).
    static func unique(_ numbers: [String]) -> [String] {
        var seen: Set<String> = []
        return numbers.filter { seen.insert($0).inserted }
    }

    /// The events the Activity list shows. The store records "create" and "update" for every draft save:
    /// the autosaves are noise, and a draft written back by Undo records a second "create", so only the
    /// first one stays ("Draft created").
    static func shownEvents(_ events: [AuditEvent]) -> [AuditEvent] {
        var sawCreate = false
        return events.filter { event in
            if event.action == "update" { return false }
            if event.action == "create" {
                if sawCreate { return false }
                sawCreate = true
            }
            return true
        }
    }

    /// The paid-in-advance links of an issued final invoice, or the settled payments of an issued advance
    /// request (§ 64 goods, ADR 0012); empty for every other document.
    static func paidAdvanceLinks(_ stores: Stores, state: DocumentState?) throws -> [PaidAdvanceLink] {
        guard let state, state.summary.status == .issued else { return [] }
        switch state.summary.kind {
        case .finalInvoice: return try stores.documents.paidAdvances(ofFinalInvoice: state.id)
        case .advanceRequest: return try stores.documents.paidAdvances(ofAdvanceRequest: state.id)
        default: return []
        }
    }
}

/// The issued view's Activity (design-system.md §8.15, screens-flows.md §2b): one sentence per event,
/// newest first, with its time, text only; shown in a collapsed disclosure between the payments and the PDF.
struct DocumentActivityList: View {
    let events: [AuditEvent]
    let currency: Currency
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            ForEach(events.reversed()) { event in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    // The only Activity symbol: a Repair mode change (design-system.md §8.15).
                    if event.action == "repair" {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(verbatim: Self.sentence(event, currency: currency, locale: locale)).textRole(.body).textSelection(.enabled)
                        Text(verbatim: Self.timestamp(event.at, locale: locale)).textRole(.caption)
                    }
                }
                .help(Text(verbatim: Self.timestamp(event.at, locale: locale, full: true)))
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One audit event as a sentence, with no kind symbol (design-system.md §8.15). An action the shell
    /// does not know shows its key. The client's Activity tab uses the same sentences (§2e).
    static func sentence(_ event: AuditEvent, currency: Currency, locale: Locale) -> String {
        let details = event.details ?? [:]
        func paymentKind() -> String {
            let raw = details["kind"] ?? ""
            return DocumentPaymentKind(rawValue: raw).map { String(localized: $0.title) } ?? raw
        }
        switch event.action {
        case "issue":
            return String(localized: L.activityIssued(details["number"] ?? ""))
        case "payment":
            let raw = details["amount"] ?? ""
            let amount = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))
                .map { MoneyText.format($0, currency: currency.code, locale: locale) } ?? raw
            return String(localized: L.activityPayment(paymentKind(), amount))
        case "paymentDeleted":
            return String(localized: L.activityPaymentDeleted(paymentKind()))
        case "receiptAttached":
            return String(localized: L.activityReceiptAttached)
        case "close":
            let reason = details["reason"] ?? ""
            if details["kind"] == DocumentClosureKind.markedForCreditNote.rawValue {
                return String(localized: L.activityMarked(reason))
            }
            return String(localized: L.activityClosed(reason))
        case "reopen":
            return String(localized: L.activityReopened)
        case "pdf":
            return String(localized: L.activityPDF)
        case "pdfSaved":
            return String(localized: L.activityPDFSaved(details["path"] ?? ""))
        case "delete":
            return String(localized: L.activityDeleted)
        case "create":
            return String(localized: L.activityDraftCreated)
        case "repair":
            return repairSentence(details, locale: locale)
        case "pdfReplaced":
            return String(localized: L.activityPDFReplaced)
        default:
            return event.action
        }
    }

    /// "Client address: Krátká 1 → Nová 5 · Wrong address"; a date in the UI's format, a missing value as "—".
    private static func repairSentence(_ details: [String: String], locale: Locale) -> String {
        let raw = details["field"] ?? ""
        let field = RepairField(rawValue: raw)
        func value(_ text: String?) -> String {
            guard let text, !text.isEmpty else { return "—" }
            if field == .dueDate, let day = CalendarDay(iso: text) { return day.formatted(locale) }
            return text
        }
        let name = field.map { String(localized: $0.title) } ?? raw
        return String(localized: L.activityRepair(name, value(details["old"]), value(details["new"]), details["reason"] ?? ""))
    }

    /// The stored ISO 8601 timestamp in the UI locale (with seconds in the tooltip); the raw text when it
    /// cannot be parsed.
    static func timestamp(_ iso: String, locale: Locale, full: Bool = false) -> String {
        guard let date = try? Date(iso, strategy: .iso8601) else { return iso }
        return date.formatted(Date.FormatStyle(date: .numeric, time: full ? .standard : .shortened, locale: locale))
    }
}
