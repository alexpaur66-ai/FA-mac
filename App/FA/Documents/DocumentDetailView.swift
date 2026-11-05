// The detail column for one issued document: read-only header, lock line, payments, the prominent
// Record Payment and the next step of the chain (screens-flows.md §2b). Drafts open in DraftEditorView.

import InvoicingCore
import InvoicingData
import SwiftUI

struct DocumentDetailView: View {
    let stores: Stores
    let documents: DocumentListModel
    let documentID: String
    let recordPayment: @MainActor (String) -> Void
    let deleteDraft: @MainActor (String) -> Void
    /// Step 4 of the advance flow (screens-flows.md §2d): a final invoice draft that deducts this advance.
    var createFinalInvoice: (@MainActor (String) -> Void)? = nil
    /// Step 3 of the advance flow: the tax document for a received payment that has none (after "Later",
    /// or after its draft was deleted).
    var createTaxDocument: (@MainActor (DocumentPayment) -> Void)? = nil
    /// Opens a payment's draft tax document in the editor.
    var openDraft: (@MainActor (String) -> Void)? = nil
    /// Bumped by the window after a menu action changed the stored PDF's saved path, so the PDF row reloads.
    /// Bumped by whoever saves the PDF (the File menu, this view), so the row and the menu items reload.
    var pdfVersion: Binding<Int> = .constant(0)
    /// Issue could not write the PDF file (screens-flows.md §2c): the banner offers Choose Folder… and Save PDF….
    var pdfSaveFailure: Binding<PDFSaveFailure?> = .constant(nil)

    @State private var payments: [DocumentPayment] = []
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
        .task(id: LoadKey(id: documentID, states: documents.states, pdfVersion: pdfVersion.wrappedValue)) {
            load()
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
            Grid(alignment: .leading, horizontalSpacing: Spacing.xl, verticalSpacing: Spacing.s) {
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
                                Text(verbatim: deductions.map(\.receiptNumber).joined(separator: ", ")).textRole(.rowSecondary)
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
                if !state.deductedBy.isEmpty {
                    GridRow {
                        Text(L.chain).textRole(.label)
                        Text(L.deductedBy(state.deductedBy.joined(separator: ", "))).textRole(.body)
                    }
                }
            }
            if summary.status == .issued {
                Label {
                    Text(L.lockLine(summary.issueDate.formatted(locale)))
                } icon: {
                    Image(systemName: "lock.fill")
                }
                .textRole(.legalNote)
            } else {
                Text(L.draftNote).textRole(.body)
            }
            if let closure = state.closure {
                closureLine(closure)
            }
            if summary.status == .issued {
                paymentsSection(state)
            }
            actions(state)
            if let loadError {
                Text(verbatim: loadError).textRole(.caption).foregroundStyle(.red)
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
                Text(verbatim: summary.kind.title(language: .ui(locale))).textRole(.body)
                Text(verbatim: summary.customerName.isEmpty ? String(localized: L.noClient) : summary.customerName)
                    .textRole(.rowSecondary)
            }
            Spacer(minLength: Spacing.l)
            StatusBadge(DocumentStateInputs(state), detail: DocumentRow(state: state).badgeDetail(locale: locale))
        }
    }

    private func closureLine(_ closure: DocumentClosure) -> some View {
        Label {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                StatusBadge(closure.kind == .closedUnpaid ? DocumentStateLabel.closedUnpaid : DocumentStateLabel.markedForCreditNote)
                Text(verbatim: String(localized: L.closureReason) + ": " + closure.reason).textRole(.rowSecondary)
            }
        } icon: {
            Image(systemName: closure.kind == .closedUnpaid ? "xmark.circle" : "flag")
        }
    }

    private func paymentsSection(_ state: DocumentState) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(L.paymentsSection).textRole(.sectionTitle)
            if payments.isEmpty {
                Text(L.noPayments).textRole(.rowSecondary)
            }
            ForEach(payments) { payment in
                HStack(spacing: Spacing.m) {
                    DayText(payment.paidOn)
                    Text(payment.kind.title).textRole(.rowSecondary)
                    if let note = payment.note, !note.isEmpty {
                        Text(verbatim: note).textRole(.rowSecondary).lineLimit(1)
                    }
                    Spacer()
                    MoneyText(amount: payment.amount.amount, currency: payment.amount.currency.code, locale: locale)
                    if payment.receiptIssued {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.secondary)
                            .help(Text(L.paymentLocked))
                    } else if state.summary.kind == .advanceRequest, payment.kind == .received {
                        if let receiptID = payment.receiptDocumentID {
                            if let openDraft {
                                Button { openDraft(receiptID) } label: { Text(L.openTaxDocument) }
                            }
                        } else if let createTaxDocument {
                            Button { createTaxDocument(payment) } label: { Text(L.createTaxDocument) }
                        }
                    }
                }
                .contextMenu {
                    if state.summary.kind == .advanceRequest, payment.kind == .received, payment.receiptDocumentID == nil,
                       let createTaxDocument {
                        Button { createTaxDocument(payment) } label: { Text(L.createTaxDocument) }
                    }
                    if !payment.receiptIssued {
                        Button(role: .destructive) { deletePayment(payment.id) } label: { Text(L.delete) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func actions(_ state: DocumentState) -> some View {
        HStack(spacing: Spacing.m) {
            if state.summary.status == .draft {
                Button(role: .destructive) { deleteDraft(documentID) } label: { Text(L.deleteDraft) }
            } else if state.summary.kind != .paymentTaxDocument && state.closure?.kind != .closedUnpaid {
                Button { recordPayment(documentID) } label: {
                    Label { Text(L.recordPayment) } icon: { Image(systemName: "banknote") }
                }
                .buttonStyle(.borderedProminent)
                if state.summary.kind == .advanceRequest, !state.deductedInFinal, let createFinalInvoice {
                    Button { createFinalInvoice(documentID) } label: {
                        Label { Text(L.createFinalInvoice) } icon: { Image(systemName: Symbols.finalInvoice) }
                    }
                }
            }
        }
    }

    private func deletePayment(_ id: String) {
        do {
            try stores.documents.deletePayment(id: id)
            load()
        } catch {
            loadError = ErrorText.message(error, locale: locale)
        }
    }

    // MARK: PDF (screens-flows.md §2b, ADR 0010)

    /// The saved file line, the PDF actions and the pages. Show PDF in Finder is disabled while the file is
    /// missing: the app keeps its own frozen copy of the bytes from issue time.
    @ViewBuilder private var pdfSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(L.pdfSection).textRole(.sectionTitle)
            if let failure = pdfSaveFailure.wrappedValue, failure.documentID == documentID {
                saveFailureBanner(failure)
            }
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
                    Text(L.pdfPreviewUnavailable).textRole(.body)
                    Button { loadPDF() } label: { Text(L.retry) }
                }
                Text(verbatim: pdfError).textRole(.caption).foregroundStyle(.red)
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
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: Radius.m))
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
/// the document chain and the activity log.
struct DocumentInspectorView: View {
    let stores: Stores
    let documents: DocumentListModel
    let documentID: String

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
        List {
            if let payment = document?.payment {
                Section {
                    LabeledContent { Text(verbatim: payment.bankConnection.iban.formatted).textSelection(.enabled) } label: { Text(L.account) }
                    if let symbol = payment.variableSymbol {
                        LabeledContent { Text(verbatim: symbol.digits).textSelection(.enabled) } label: { Text(L.variableSymbol) }
                    }
                } header: {
                    Text(L.paymentDetails)
                }
            }
            Section {
                if payments.isEmpty {
                    Text(L.noPayments).textRole(.rowSecondary)
                }
                ForEach(payments) { payment in
                    LabeledContent {
                        Text(verbatim: MoneyText.format(payment.amount.amount, currency: payment.amount.currency.code, locale: locale))
                    } label: {
                        Text(verbatim: payment.paidOn.formatted(locale) + " · " + String(localized: payment.kind.title))
                    }
                }
            } header: {
                Text(L.paymentsSection)
            }
            // An advance lists the final invoices that deducted it, a final invoice the payment tax
            // documents it deducts.
            let chain = (documents.state(id: documentID)?.deductedBy ?? []) + deductions.map(\.receiptNumber)
            if !chain.isEmpty {
                Section {
                    ForEach(chain, id: \.self) { number in
                        Text(verbatim: number)
                    }
                } header: {
                    Text(L.chain)
                }
            }
            Section {
                ForEach(events) { event in
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(verbatim: event.action).textRole(.body)
                        Text(verbatim: Self.timestamp(event.at, locale: locale)).textRole(.caption)
                    }
                }
            } header: {
                Text(L.activity)
            }
        }
        .task(id: LoadKey(id: documentID, states: documents.states)) {
            document = try? stores.documents.document(id: documentID)
            payments = (try? stores.documents.payments(for: documentID)) ?? []
            deductions = (try? Self.deductions(stores, state: documents.state(id: documentID))) ?? []
            events = (try? stores.audit.events(entity: "document", id: documentID)) ?? []
        }
    }

    /// The deduction links of an issued final invoice; empty for every other document.
    static func deductions(_ stores: Stores, state: DocumentState?) throws -> [AdvanceDeductionLink] {
        guard let state, state.summary.kind == .finalInvoice, state.summary.status == .issued else { return [] }
        return try stores.documents.deductions(ofFinalInvoice: state.id)
    }

    /// The stored ISO 8601 timestamp in the UI locale; the raw text when it cannot be parsed.
    private static func timestamp(_ iso: String, locale: Locale) -> String {
        guard let date = try? Date(iso, strategy: .iso8601) else { return iso }
        return date.formatted(Date.FormatStyle(date: .numeric, time: .shortened, locale: locale))
    }
}
