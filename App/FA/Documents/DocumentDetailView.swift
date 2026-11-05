// The detail column for one issued document: the header, a closing banner, the figures, the lock line,
// the payments and the PDF (screens-flows.md §2b). Drafts open in DraftEditorView. The window computes
// what the document offers (`DocumentActions`) once, for the toolbar here, the Document menu and the
// context menu, so the three never disagree.

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
    /// Opens a payment's draft tax document in the editor.
    var openDraft: (@MainActor (String) -> Void)? = nil
    /// Shows another issued document by id: the tax document a locked payment is the basis of, the chain.
    var openDocument: (@MainActor (String) -> Void)? = nil
    /// Bumped by whoever saves the PDF (the File menu, this view), so the row and the menu items reload.
    var pdfVersion: Binding<Int> = .constant(0)
    /// Issue could not write the PDF file (screens-flows.md §2c): the banner offers Choose Folder… and Save PDF….
    var pdfSaveFailure: Binding<PDFSaveFailure?> = .constant(nil)

    @State private var payments: [DocumentPayment] = []
    /// A payment with a draft tax document, waiting for the answer whether the draft goes too.
    @State private var paymentPendingDeletion: DocumentPayment?
    /// A final invoice's deduction links: the payment tax documents of the advances it deducts.
    @State private var deductions: [AdvanceDeductionLink] = []
    @State private var loadError: String?
    /// The issued document's stored PDF, rendered and stored now when it has none yet (ADR 0010).
    @State private var pdf: StoredDocumentPDF?
    @State private var pdfError: String?
    @State private var savedFileExists = false
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
                ContentUnavailableView {
                    Label { Text(L.noSelection) } icon: { Image(systemName: Symbols.document) }
                }
            }
        }
        .navigationTitle(Text(verbatim: documents.state(id: documentID)?.summary.number ?? String(localized: L.draftTitle)))
        .toolbar { toolbar }
        .task(id: LoadKey(id: documentID, states: documents.states, pdfVersion: pdfVersion.wrappedValue)) {
            load()
        }
        .paymentDeletionDialog(pending: $paymentPendingDeletion, delete: deletePayment)
    }

    /// The one prominent action of the issued view, trailing (screens-flows.md §2b): Record Payment while
    /// something is left to pay, Record Refund on an overpaid document; then the chain's next step.
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            if let recordPayment = actions.recordPayment {
                Button { recordPayment() } label: {
                    Label { Text(L.recordPayment) } icon: { Image(systemName: "banknote") }
                }
                .buttonStyle(.borderedProminent)
                .help(Text(L.recordPaymentHelp))
            } else if let recordRefund = actions.recordRefund {
                Button { recordRefund() } label: {
                    Label { Text(L.recordRefund) } icon: { Image(systemName: "arrow.uturn.backward") }
                }
                .buttonStyle(.borderedProminent)
            }
            if let createFinalInvoice = actions.createFinalInvoice {
                Button { createFinalInvoice() } label: {
                    Label { Text(L.createFinalInvoice) } icon: { Image(systemName: Symbols.finalInvoice) }
                }
            }
            if let duplicate = actions.duplicate, let source = actions.duplicateSourceNumber {
                Button { duplicate() } label: {
                    Label { Text(L.duplicate) } icon: { Image(systemName: "plus.square.on.square") }
                }
                .help(Text(L.duplicateNumbered(source)))
            }
        }
    }

    private func load() {
        do {
            payments = try stores.documents.payments(for: documentID)
            deductions = try DocumentInspectorView.deductions(stores, state: documents.state(id: documentID))
            loadError = nil
        } catch {
            payments = []
            deductions = []
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
            header(state)
            // Critical information goes at the top (screens-flows.md §0.1): a closing event, a PDF that
            // could not be written.
            if let closure = state.closure {
                closureBanner(closure)
            }
            if let failure = pdfSaveFailure.wrappedValue, failure.documentID == documentID {
                saveFailureBanner(failure)
            }
            figures(state)
            if summary.status == .issued {
                Label {
                    Text(L.lockLine(summary.issueDate.formatted(locale)))
                } icon: {
                    Image(systemName: "lock.fill")
                }
                .textRole(.legalNote)
                paymentsSection(state)
            } else {
                Text(L.draftNote).textRole(.body)
                if let deleteDraft = actions.deleteDraft {
                    Button(role: .destructive) { deleteDraft() } label: { Text(L.deleteDraft) }
                }
            }
            if let loadError {
                InlineMessage(loadError)
            }
            if summary.status == .issued {
                pdfSection
            }
        }
    }

    /// What a final invoice deducts: its gross before deductions minus its amount due. Nil when either
    /// figure is missing.
    static func deductedAmount(_ summary: DocumentSummary) -> Money? {
        guard let total = summary.totalGross, let due = summary.amountDue, total.currency == due.currency else { return nil }
        return total - due
    }

    private func header(_ state: DocumentState) -> some View {
        let summary = state.summary
        return HStack(alignment: .firstTextBaseline, spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verbatim: summary.number ?? String(localized: L.draftTitle)).textRole(.documentNumber)
                Text(summary.kind.longTitle).textRole(.body)
                if summary.customerName.isEmpty {
                    Text(L.noClient).textRole(.rowSecondary)
                } else if let showClient = actions.showClient {
                    // The client link (screens-flows.md §2b): selects the client in Clients.
                    Button { showClient() } label: {
                        Text(verbatim: summary.customerName).textRole(.rowSecondary)
                    }
                    .buttonStyle(.link)
                    .help(Text(L.showClient))
                } else {
                    Text(verbatim: summary.customerName).textRole(.rowSecondary)
                }
            }
            Spacer(minLength: Spacing.l)
            StatusBadge(DocumentStateInputs(state), detail: DocumentRow(state: state, today: documents.today).badgeDetail(locale: locale))
        }
    }

    /// A closing event as a banner under the header (screens-flows.md §2d): the kind, and the reason.
    private func closureBanner(_ closure: DocumentClosure) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label {
                Text(closure.kind == .closedUnpaid ? L.bannerClosedUnpaid : L.bannerMarkedForCreditNote)
                    .textRole(.body)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: closure.kind == .closedUnpaid ? "xmark.circle" : "flag")
                    .foregroundStyle(.secondary)
            }
            Text(verbatim: closure.reason)
                .textRole(.rowSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileSurface(radius: Radius.m)
    }

    private func figures(_ state: DocumentState) -> some View {
        let summary = state.summary
        return Grid(alignment: .leading, horizontalSpacing: Spacing.xl, verticalSpacing: Spacing.s) {
            GridRow {
                Text(L.colTotal).textRole(.label)
                if let total = summary.totalGross {
                    MoneyText(amount: total.amount, currency: summary.currency.code, locale: locale, role: .total)
                } else {
                    // A draft whose totals cannot be computed yet (for example a missing rate).
                    Text(verbatim: "—").textRole(.total)
                }
            }
            if summary.kind == .finalInvoice, let deducted = Self.deductedAmount(summary), !deducted.isZero {
                // Total − advances = amount due (screens-flows.md §2d), so the figures reconcile.
                GridRow {
                    Text(L.advancesDeducted).textRole(.label)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        MoneyText(amount: -deducted.amount, currency: summary.currency.code, locale: locale)
                        if !deductions.isEmpty {
                            chainLinks(deductions.map(\.receiptNumber))
                        }
                    }
                }
            }
            if summary.status == .issued && summary.kind != .paymentTaxDocument {
                GridRow {
                    Text(L.paid).textRole(.label)
                    MoneyText(amount: state.paid.amount, currency: summary.currency.code, locale: locale)
                }
                GridRow {
                    Text(L.outstanding).textRole(.label)
                    MoneyText(amount: state.outstanding.amount, currency: summary.currency.code, locale: locale, role: .amountStrong)
                }
            }
            GridRow {
                Text(L.issuedOn).textRole(.label)
                DayText(summary.issueDate)
            }
            GridRow {
                Text(L.dueOn).textRole(.label)
                DayText(summary.dueDate)
            }
            if let symbol = summary.variableSymbol {
                GridRow {
                    Text(L.variableSymbol).textRole(.label)
                    Text(verbatim: symbol).textRole(.amount).textSelection(.enabled)
                }
            }
            if let related = summary.relatedDocumentNumber {
                GridRow {
                    Text(L.chain).textRole(.label)
                    chainLinks([related])
                }
            }
            if !state.deductedBy.isEmpty {
                GridRow {
                    Text(L.deductedByLabel).textRole(.label)
                    chainLinks(state.deductingFinalInvoices)
                }
            }
        }
    }

    /// Document numbers of the chain, each a link to that document when the list knows it.
    private func chainLinks(_ numbers: [String]) -> some View {
        HStack(spacing: Spacing.s) {
            ForEach(numbers, id: \.self) { number in
                if let openDocument, let id = documents.states.first(where: { $0.summary.number == number })?.id {
                    Button { openDocument(id) } label: { Text(verbatim: number).textRole(.body) }
                        .buttonStyle(.link)
                } else {
                    Text(verbatim: number).textRole(.body)
                }
            }
        }
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

    @ViewBuilder private func paymentRow(_ payment: DocumentPayment, state: DocumentState) -> some View {
        let isAdvanceReceipt = state.summary.kind == .advanceRequest && payment.kind == .received
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
                if payment.receiptIssued {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text(L.paymentLocked))
                } else if isAdvanceReceipt {
                    if let receiptID = payment.receiptDocumentID {
                        if let openDraft {
                            Button { openDraft(receiptID) } label: { Text(L.openTaxDocument) }
                        }
                    } else if let createTaxDocument {
                        Button { createTaxDocument(payment) } label: { Text(L.createTaxDocument) }
                    }
                }
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
            }
        }
        .contextMenu {
            if isAdvanceReceipt, payment.receiptDocumentID == nil, let createTaxDocument {
                Button { createTaxDocument(payment) } label: { Text(L.createTaxDocument) }
            }
            if payment.canBeDeleted {
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
                    InlineMessage(String(localized: L.pdfPreviewUnavailable) + " " + pdfError, kind: .warning)
                    Button { loadPDF() } label: { Text(L.retry) }
                }
            }
        }
        if let pdf {
            PDFPagesView(data: pdf.data)
        }
    }

    /// "PDF couldn't be saved to …" with Choose Folder… and Save PDF… (screens-flows.md §2c).
    private func saveFailureBanner(_ failure: PDFSaveFailure) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label {
                Text(L.pdfSaveFailed(failure.folder))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            .textRole(.body)
            Text(verbatim: failure.detail).textRole(.caption)
            HStack(spacing: Spacing.m) {
                Button { chooseFolderAndSave() } label: { Text(L.chooseFolder) }
                Button { savePDF() } label: { Text(L.savePDF) }
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileSurface(radius: Radius.m)
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

/// The inspector: derived information only (design-system.md §8.12): payment details, payments,
/// the document chain and the activity log, newest first.
struct DocumentInspectorView: View {
    let stores: Stores
    let documents: DocumentListModel
    let documentID: String
    /// Shows the document with that number (the chain knows numbers only).
    var openDocument: (@MainActor (String) -> Void)? = nil

    @State private var document: Document?
    @State private var payments: [DocumentPayment] = []
    @State private var deductions: [AdvanceDeductionLink] = []
    @State private var events: [AuditEvent] = []
    @Environment(\.locale) private var locale

    private struct LoadKey: Equatable {
        let id: String
        let states: [DocumentState]
    }

    var body: some View {
        let state = documents.state(id: documentID)
        let isIssued = state?.summary.status == .issued
        List {
            if let payment = document?.payment {
                Section {
                    LabeledContent {
                        Text(verbatim: payment.bankConnection.iban.formatted).textRole(.amount).textSelection(.enabled)
                    } label: {
                        Text(L.account).textRole(.body)
                    }
                    if let symbol = payment.variableSymbol {
                        LabeledContent {
                            Text(verbatim: symbol.digits).textRole(.amount).textSelection(.enabled)
                        } label: {
                            Text(L.variableSymbol).textRole(.body)
                        }
                    }
                } header: {
                    Text(L.paymentDetails)
                }
            }
            if isIssued {
                Section {
                    if payments.isEmpty {
                        Text(L.noPayments).textRole(.rowSecondary)
                    }
                    ForEach(payments) { payment in
                        LabeledContent {
                            MoneyText(amount: payment.amount.amount, currency: payment.amount.currency.code, locale: locale)
                        } label: {
                            HStack(spacing: Spacing.xs) {
                                DayText(payment.paidOn)
                                Text(payment.kind.title).textRole(.rowSecondary)
                                if payment.receiptIssued {
                                    Image(systemName: "lock.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .accessibilityLabel(Text(L.paymentLocked))
                                }
                            }
                        }
                    }
                } header: {
                    Text(L.paymentsSection)
                }
            }
            // The advance of a tax document or a final invoice, the final invoices that deducted an advance,
            // the payment tax documents a final invoice deducts: each a link to that document.
            let chain = chainNumbers(state)
            if !chain.isEmpty {
                Section {
                    ForEach(chain, id: \.self) { number in
                        if let openDocument {
                            Button { openDocument(number) } label: { Text(verbatim: number).textRole(.amount) }
                                .buttonStyle(.link)
                        } else {
                            Text(verbatim: number).textRole(.amount)
                        }
                    }
                } header: {
                    Text(L.chain)
                }
            }
            Section {
                ForEach(events.reversed()) { event in
                    let line = activity(event, currency: document?.currency ?? state?.summary.currency ?? .czk)
                    Label {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(verbatim: line.text).textRole(.body).textSelection(.enabled)
                            Text(verbatim: Self.timestamp(event.at, locale: locale)).textRole(.caption)
                        }
                    } icon: {
                        Image(systemName: line.symbol)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .help(Text(verbatim: Self.timestamp(event.at, locale: locale, full: true)))
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text(L.activity)
            }
        }
        .task(id: LoadKey(id: documentID, states: documents.states)) {
            document = try? stores.documents.document(id: documentID)
            payments = (try? stores.documents.payments(for: documentID)) ?? []
            deductions = (try? Self.deductions(stores, state: documents.state(id: documentID))) ?? []
            events = Self.shownEvents((try? stores.audit.events(entity: "document", id: documentID)) ?? [])
        }
    }

    /// Each number once: an advance deducted through two receipts names its final invoice twice.
    private func chainNumbers(_ state: DocumentState?) -> [String] {
        var numbers: [String] = []
        if let related = state?.summary.relatedDocumentNumber { numbers.append(related) }
        numbers += state?.deductingFinalInvoices ?? []
        numbers += deductions.map(\.receiptNumber)
        return Self.unique(numbers)
    }

    /// The numbers in their order, without repeats (they are the ids of the chain's ForEach).
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

    /// The deduction links of an issued final invoice; empty for every other document.
    static func deductions(_ stores: Stores, state: DocumentState?) throws -> [AdvanceDeductionLink] {
        guard let state, state.summary.kind == .finalInvoice, state.summary.status == .issued else { return [] }
        return try stores.documents.deductions(ofFinalInvoice: state.id)
    }

    /// One audit event as a sentence with its kind symbol (design-system.md §8.15). An action the shell
    /// does not know shows its key.
    private func activity(_ event: AuditEvent, currency: Currency) -> (symbol: String, text: String) {
        let details = event.details ?? [:]
        func paymentKind() -> String {
            let raw = details["kind"] ?? ""
            return DocumentPaymentKind(rawValue: raw).map { String(localized: $0.title) } ?? raw
        }
        switch event.action {
        case "issue":
            return ("lock.fill", String(localized: L.activityIssued(details["number"] ?? "")))
        case "payment":
            let raw = details["amount"] ?? ""
            let amount = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))
                .map { MoneyText.format($0, currency: currency.code, locale: locale) } ?? raw
            return ("banknote", String(localized: L.activityPayment(paymentKind(), amount)))
        case "paymentDeleted":
            return ("banknote", String(localized: L.activityPaymentDeleted(paymentKind())))
        case "receiptAttached":
            return (Symbols.receipt, String(localized: L.activityReceiptAttached))
        case "close":
            let reason = details["reason"] ?? ""
            if details["kind"] == DocumentClosureKind.markedForCreditNote.rawValue {
                return ("flag", String(localized: L.activityMarked(reason)))
            }
            return ("xmark.circle", String(localized: L.activityClosed(reason)))
        case "reopen":
            return ("arrow.uturn.backward", String(localized: L.activityReopened))
        case "pdf":
            return ("doc.richtext", String(localized: L.activityPDF))
        case "pdfSaved":
            return ("folder", String(localized: L.activityPDFSaved(details["path"] ?? "")))
        case "delete":
            return ("trash", String(localized: L.activityDeleted))
        case "create":
            return ("square.and.pencil", String(localized: L.activityDraftCreated))
        default:
            return ("circle", event.action)
        }
    }

    /// The stored ISO 8601 timestamp in the UI locale (with seconds in the tooltip); the raw text when it
    /// cannot be parsed.
    private static func timestamp(_ iso: String, locale: Locale, full: Bool = false) -> String {
        guard let date = try? Date(iso, strategy: .iso8601) else { return iso }
        return date.formatted(Date.FormatStyle(date: .numeric, time: full ? .standard : .shortened, locale: locale))
    }
}
