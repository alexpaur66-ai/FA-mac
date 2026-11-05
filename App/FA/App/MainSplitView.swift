// The main window: one three-column NavigationSplitView for every section (screens-flows.md §1.2),
// the result line, the document sheets, undo, and the actions the menu bar can call.

import AppKit
import Combine
import InvoicingCore
import InvoicingData
import SwiftUI

struct MainSplitView: View {
    let stores: Stores

    @SceneStorage("sidebar") private var sidebar: SidebarItem = .section(.overview)
    @State private var documents: DocumentListModel
    @State private var clients: ClientsModel
    @State private var documentSelection: Set<String> = []
    @State private var overviewSelection: String?
    @State private var clientSelection: String?
    @State private var paymentDocumentSelection: String?
    @State private var inspectorPresented = false
    @State private var sheet: MainSheet?
    /// The result or error of the last action, at the top of the content column (design-system.md §8.17);
    /// cleared when the user navigates or closes it.
    @State private var result: ResultLineModel?
    /// Bumped after every rate import, so the coverage column reloads beside the rates table.
    @State private var ratesVersion = 0
    /// File ▸ Import ČNB Rates… opens the file importer of the Exchange rates section.
    @State private var ratesImporting = false
    /// The editor of the selected draft; replaced when another draft is selected (ADR 0009).
    @State private var editor: DraftEditorModel?
    @State private var issueSheetPresented = false
    /// View ▸ Show Preview: the selected draft's detail shows its live PDF preview instead of the editor.
    @State private var previewShown = false
    /// Bumped after a menu action changed a stored PDF's saved path, so the detail reloads its PDF row.
    @State private var pdfVersion = 0
    /// Issue stored the PDF but could not write the file; the detail shows the banner (screens-flows.md §2c).
    @State private var pdfSaveFailure: PDFSaveFailure?
    /// The Documents search; cleared when a draft is opened, so the search cannot hide the row of the
    /// draft being edited.
    @State private var documentsSearch = ""
    /// Where the editor of the draft being opened puts the cursor: the client of a new draft without one,
    /// else its first line. Consumed by the editor of that draft only.
    @State private var pendingEditorFocus: PendingEditorFocus?
    /// The payment date last recorded, proposed by the next Record Payment sheet (screens-flows.md §2f).
    @State private var lastPaymentDate: Date?
    /// Help ▸ Getting Started shows the setup card again once it has hidden itself.
    @AppStorage(SetupStatus.forcedKey) private var gettingStartedForced = false
    @Environment(\.locale) private var locale
    @Environment(\.undoManager) private var undoManager

    struct PendingEditorFocus: Equatable {
        let documentID: String
        let focus: EditorFocusRequest
    }

    init(stores: Stores) {
        self.stores = stores
        _documents = State(initialValue: DocumentListModel(stores: stores))
        _clients = State(initialValue: ClientsModel(stores: stores))
    }

    private var sidebarSelection: Binding<SidebarItem?> {
        Binding(
            get: { sidebar },
            set: { newValue in
                if let newValue { show(newValue) }
            })
    }

    /// The inspector is a column of the sections that have one; elsewhere it stays closed.
    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: { inspectorPresented && sidebar.section.hasInspector },
            set: { inspectorPresented = $0 })
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: sidebarSelection, counts: documents.badgeCounts)
                .navigationSplitViewColumnWidth(
                    min: LayoutMetrics.sidebar.min, ideal: LayoutMetrics.sidebar.ideal, max: LayoutMetrics.sidebar.max)
        } content: {
            contentColumn
                .safeAreaInset(edge: .top, spacing: 0) {
                    if let result {
                        ResultLine(model: result) { self.result = nil }
                    }
                }
                .navigationSplitViewColumnWidth(
                    min: LayoutMetrics.content.min, ideal: LayoutMetrics.content.ideal, max: LayoutMetrics.content.max)
        } detail: {
            detailColumn
                .frame(minWidth: LayoutMetrics.detailMinWidth)
                .inspector(isPresented: inspectorBinding) {
                    inspectorColumn
                        .inspectorColumnWidth(
                            min: LayoutMetrics.inspector.min, ideal: LayoutMetrics.inspector.ideal, max: LayoutMetrics.inspector.max)
                }
        }
        .frame(minWidth: LayoutMetrics.windowMin.width, minHeight: LayoutMetrics.windowMin.height)
        .focusedSceneValue(\.mainActions, mainActions)
        .onChange(of: selectedDraftID, initial: true) { _, id in
            syncEditor(id)
        }
        .onChange(of: documents.restoreOutcome) { _, outcome in
            guard let outcome else { return }
            if let error = outcome.error {
                report(error, kind: .error)
            } else if let note = outcome.note {
                report(note, kind: .info)
            } else if result?.undo != nil {
                // Undone from Edit ▸ Undo (only the latest deletion can be): the line's Undo is spent.
                result = nil
            }
            if let id = outcome.draftID, sidebar.section == .documents {
                documentSelection = [id]
            }
        }
        // A client created or edited from the sheet must reach the open editor's Client picker.
        .sheet(item: $sheet, onDismiss: { editor?.refreshReferenceData() }) { sheet in
            sheetView(sheet)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            documents.restart()
        }
        // A Settings save (company, accounts, series, document defaults) reaches the open editor at once.
        .onReceive(NotificationCenter.default.publisher(for: .settingsDidSave).receive(on: RunLoop.main)) { _ in
            editor?.refreshReferenceData()
        }
        // Quit writes the open draft at once: autosave's delay must not lose the last edits. AppKit posts
        // the notification on the main thread, synchronously, just before the process exits.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            _ = editor?.saveNow()
        }
    }

    // MARK: Columns

    @ViewBuilder private var contentColumn: some View {
        switch sidebar.section {
        case .overview:
            OverviewView(
                stores: stores, documents: documents, selection: $overviewSelection, forced: $gettingStartedForced,
                show: show, newDocument: newDraft, newClient: { sheet = .client(nil) }, importRates: importRates)
        case .documents:
            DocumentsView(
                stores: stores, documents: documents, filter: sidebar.documentFilter, selection: $documentSelection,
                inspectorPresented: $inspectorPresented, search: $documentsSearch, editingID: editor?.documentID,
                newDocument: newDraft, documentActions: documentActions(for:), deleteDrafts: deleteDrafts)
        case .clients:
            ClientsView(clients: clients, documents: documents, selection: $clientSelection, editClient: { sheet = .client($0) })
        case .payments:
            PaymentsView(stores: stores, documents: documents, selectedDocumentID: $paymentDocumentSelection,
                         deletePayment: deletePayment)
        case .rates:
            RatesView(stores: stores, version: $ratesVersion, importing: $ratesImporting, report: { text, isError in
                report(text, kind: isError ? .error : .success)
            })
        case .exports:
            ExportsView(stores: stores)
        }
    }

    @ViewBuilder private var detailColumn: some View {
        switch sidebar.section {
        case .overview:
            if let id = overviewSelection {
                documentDetail(id)
            } else {
                placeholder(L.noSelection, symbol: "square.grid.2x2")
            }
        case .documents:
            if documentSelection.count == 1, let id = documentSelection.first {
                documentDetail(id)
            } else if documentSelection.count > 1 {
                MultiSelectionView(rows: selectedRows)
            } else {
                placeholder(L.noSelection, symbol: Symbols.document)
            }
        case .clients:
            if let id = clientSelection {
                ClientDetailView(clients: clients, documents: documents, customerID: id,
                                 editClient: { sheet = .client(id) }, newDocument: { newDraft($0, customerID: id) })
            } else {
                placeholder(L.noClientSelected, symbol: "person.2")
            }
        case .payments:
            if let id = paymentDocumentSelection {
                documentDetail(id)
            } else {
                placeholder(L.noSelection, symbol: "banknote")
            }
        case .rates:
            RatesCoverageView(stores: stores, version: ratesVersion)
        case .exports:
            ExportsDetailView(stores: stores)
        }
    }

    @ViewBuilder private var inspectorColumn: some View {
        switch sidebar.section {
        case .clients:
            if let id = clientSelection {
                ClientInspectorView(clients: clients, documents: documents, customerID: id)
            } else {
                placeholder(L.noClientSelected, symbol: "person.2")
            }
        case .documents where documentSelection.count > 1:
            MultiSelectionView(rows: selectedRows)
        default:
            if let id = selectedDocumentID {
                DocumentInspectorView(stores: stores, documents: documents, documentID: id, openDocument: openDocument(number:))
            } else {
                placeholder(L.noSelection, symbol: "sidebar.right")
            }
        }
    }

    /// The rows selected in Documents, in the current filter.
    private var selectedRows: [DocumentRow] {
        documents.rows(for: sidebar.documentFilter).filter { documentSelection.contains($0.id) }
    }

    @ViewBuilder private func documentDetail(_ id: String) -> some View {
        if documents.state(id: id)?.summary.status == .draft {
            if let editor, editor.documentID == id {
                DraftEditorView(
                    stores: stores, documents: documents, model: editor, onIssued: issued,
                    newClient: { sheet = .newClientForDraft($0) }, duplicate: duplicate,
                    issueSheetPresented: $issueSheetPresented, previewShown: $previewShown)
            } else {
                ProgressView()
            }
        } else {
            DocumentDetailView(
                stores: stores, documents: documents, documentID: id, actions: documentActions(for: id),
                deletePayment: deletePayment,
                createTaxDocument: { createTaxDocument(advanceID: id, payment: $0) }, openDraft: openDraft,
                openDocument: openDocument(id:),
                pdfVersion: $pdfVersion, pdfSaveFailure: $pdfSaveFailure)
        }
    }

    private func placeholder(_ title: LocalizedStringResource, symbol: String) -> some View {
        ContentUnavailableView {
            Label { Text(title) } icon: { Image(systemName: symbol) }
        }
    }

    // MARK: Result line

    private func report(_ text: String, kind: ResultLineModel.Kind = .success, undo: (@MainActor () -> Void)? = nil) {
        result = ResultLineModel(text, kind: kind, undo: undo)
    }

    private func report(_ resource: LocalizedStringResource, kind: ResultLineModel.Kind = .success, undo: (@MainActor () -> Void)? = nil) {
        report(String(localized: resource), kind: kind, undo: undo)
    }

    private func report(_ error: Error) {
        report(ErrorText.message(error, locale: locale), kind: .error)
    }

    // MARK: Selection and actions

    /// The one document the detail column shows in the current section, if any.
    private var selectedDocumentID: String? {
        switch sidebar.section {
        case .overview: overviewSelection
        case .documents: documentSelection.count == 1 ? documentSelection.first : nil
        case .payments: paymentDocumentSelection
        case .clients, .rates, .exports: nil
        }
    }

    /// The selected document while it is a draft: the detail column shows its editor.
    private var selectedDraftID: String? {
        guard let id = selectedDocumentID, documents.state(id: id)?.summary.status == .draft else { return nil }
        return id
    }

    /// The client the Client menu acts on: the one selected in Clients, else the selected document's.
    private var menuClientID: String? {
        if sidebar.section == .clients { return clientSelection }
        return selectedDocumentID.flatMap { documents.state(id: $0)?.summary.customerID }
    }

    /// One editor per selected draft; the old one writes its draft before it goes. When that save fails
    /// (the store refused it), the user is told the edits were not kept instead of losing them silently.
    private func syncEditor(_ id: String?) {
        guard editor?.documentID != id else { return }
        if let old = editor, !old.saveNow() {
            report(L.draftChangesNotSaved(old.saveError ?? ""), kind: .error)
        }
        issueSheetPresented = false
        previewShown = false
        let focus = pendingEditorFocus?.documentID == id ? pendingEditorFocus?.focus : nil
        editor = id.map { DraftEditorModel(stores: stores, documentID: $0, initialFocus: focus) }
        if let id, pendingEditorFocus?.documentID == id { pendingEditorFocus = nil }
    }

    private var mainActions: MainActions {
        var actions = MainActions(
            show: show,
            newDocument: newDraft,
            newClient: { sheet = .client(nil) },
            importRates: importRates,
            showGettingStarted: showGettingStarted)
        if let url = stores.databaseURL {
            actions.showDataFolder = { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        if sidebar.section.hasInspector {
            actions.toggleInspector = { inspectorPresented.toggle() }
            actions.inspectorShown = inspectorPresented
        }
        if let clientID = menuClientID, let customer = clients.customer(id: clientID) {
            actions.clientName = customer.party.name
            actions.newDocumentForClient = { newDraft($0, customerID: clientID) }
            actions.editClient = { sheet = .client(clientID) }
        }
        if let id = selectedDocumentID {
            actions.document = documentActions(for: id)
            if let editor, editor.documentID == id {
                actions.editor = editor
                actions.togglePreview = { previewShown.toggle() }
                actions.previewShown = previewShown
            }
        }
        return actions
    }

    /// What one document offers, for the Document menu of the selected one and the context menu of any row.
    private func documentActions(for id: String) -> DocumentActions {
        var actions = DocumentActions()
        guard let state = documents.state(id: id) else { return actions }
        let summary = state.summary
        if summary.customerID != nil {
            actions.showClient = { showClient(ofDocument: id) }
        }
        if summary.status == .draft {
            actions.deleteDraft = { deleteDrafts([id]) }
            if let editor, editor.documentID == id {
                actions.issue = { requestIssue(id) }
                // A draft prints as its watermarked preview (screens-flows.md §1.4).
                actions.printDocument = { printDocument(id, draft: editor.document) }
            }
            if summary.kind != .paymentTaxDocument {
                actions.duplicate = { duplicate(id) }
            }
            return actions
        }
        if summary.kind != .paymentTaxDocument {
            actions.duplicate = { duplicate(id) }
            actions.duplicateSourceNumber = summary.number
        }
        actions.savePDF = { savePDF(id) }
        actions.printDocument = { printDocument(id, draft: nil) }
        if let path = PDFActions.existingFile(stores, documentID: id) {
            actions.showPDFInFinder = { PDFFiles.reveal(path: path) }
        }
        if summary.kind == .advanceRequest && state.closure == nil && !state.deductedInFinal {
            actions.createFinalInvoice = { createFinalInvoice(from: id) }
        }
        // One received payment without a tax document: the menu creates it; with several, the payment rows do.
        if summary.kind == .advanceRequest, let payments = try? stores.documents.payments(for: id) {
            let missing = TaxDocumentDraft.paymentsWithoutReceipt(payments)
            if missing.count == 1, let payment = missing.first {
                actions.createTaxDocument = { createTaxDocument(advanceID: id, payment: payment) }
            }
        }
        if state.acceptsPayment {
            actions.recordPayment = { sheet = .recordPayment(id) }
        }
        if state.acceptsRefund {
            actions.recordRefund = { sheet = .recordRefund(id) }
        }
        if let closure = state.closure {
            actions.reopen = { reopen(id) }
            actions.reopenKind = closure.kind
        } else {
            // The store refuses while any payment row exists, even a payment and its refund that net to zero.
            if summary.kind == .advanceRequest && state.paid.isZero && !state.deductedInFinal
                && (try? stores.documents.payments(for: id).isEmpty) == true {
                actions.closeAdvanceUnpaid = { sheet = .closure(id, .closedUnpaid) }
            }
            if summary.kind.isTaxDocument {
                actions.markForCreditNote = { sheet = .closure(id, .markedForCreditNote) }
            }
        }
        return actions
    }

    private func show(_ item: SidebarItem) {
        // The Documents section itself is its "All" filter.
        sidebar = item == .section(.documents) ? .filter(.all) : item
        result = nil
    }

    /// Shows an issued document in Documents ▸ All (the chain, a locked payment's tax document).
    private func openDocument(id: String) {
        show(.filter(.all))
        documentsSearch = ""
        documentSelection = [id]
    }

    /// The same by number, for the inspector's chain, which knows numbers only.
    private func openDocument(number: String) {
        guard let state = documents.states.first(where: { $0.summary.number == number }) else { return }
        openDocument(id: state.id)
    }

    private func showClient(ofDocument id: String) {
        guard let customerID = documents.state(id: id)?.summary.customerID else { return }
        clientSelection = customerID
        show(.section(.clients))
    }

    /// File ▸ Import ČNB Rates…: Exchange rates with its file importer open.
    private func importRates() {
        show(.section(.rates))
        ratesImporting = true
    }

    private func showGettingStarted() {
        gettingStartedForced = true
        show(.section(.overview))
    }

    /// New Invoice / New Advance Invoice: a draft with the company's and the selected client's defaults,
    /// opened in the editor. In Clients the selected client is the draft's.
    private func newDraft(_ kind: DocumentKind) {
        newDraft(kind, customerID: sidebar.section == .clients ? clientSelection : nil)
    }

    private func newDraft(_ kind: DocumentKind, customerID: String?) {
        do {
            guard let profile = try stores.profile.load() else {
                // show() clears the line, so it comes first; the Overview carries the setup card.
                show(.section(.overview))
                report(L.setUpCompanyFirst, kind: .info)
                return
            }
            let customer = try customerID.flatMap { try stores.customers.customer(id: $0) }
            let today = CalendarDay(Date(), in: .current)
            let customerParty = customer?.party
                ?? Party(name: "", address: PostalAddress(street: "", city: "", postalCode: "", countryCode: "CZ"))
            let document = Document(
                kind: kind, supplier: profile.supplier, customer: customerParty, customerID: customer?.id,
                language: customer?.language ?? .czech, currency: customer?.currency ?? profile.defaultCurrency,
                issueDate: today, taxPointDate: kind.isTaxDocument ? today : nil, dueDate: today.adding(days: customer?.paymentTermDays ?? profile.defaultPaymentTermDays),
                footer: profile.footer)
            try stores.documents.saveDraft(document)
            openDraft(document.id, focus: customer == nil ? .client : .firstLineText)
        } catch {
            report(error)
        }
    }

    /// Shows a draft in Documents ▸ Drafts, where its editor opens with the cursor at `focus`. The search
    /// is cleared first: a search that hides the row would leave the detail column without the editor.
    private func openDraft(_ id: String, focus: EditorFocusRequest) {
        documentsSearch = ""
        if let editor, editor.documentID == id {
            editor.requestFocus(focus)
        } else {
            pendingEditorFocus = PendingEditorFocus(documentID: id, focus: focus)
        }
        sidebar = .filter(.drafts)
        documentSelection = [id]
        result = nil
    }

    /// An existing draft opened from a list, a payment row or a chain: the cursor goes to the first line.
    private func openDraft(_ id: String) {
        openDraft(id, focus: .firstLineQuantity)
    }

    /// Document ▸ Issue… (⌘↩): writes the draft and opens the review sheet over its editor.
    private func requestIssue(_ id: String) {
        guard let editor, editor.documentID == id else { return }
        editor.saveNow()
        issueSheetPresented = true
    }

    /// After Issue: the document leaves Drafts, so the list switches to All and keeps it selected; the
    /// detail column shows the issued view (screens-flows.md §2c, "Afterwards").
    private func issued(_ document: Document) {
        issueSheetPresented = false
        previewShown = false
        if sidebar == .filter(.drafts) { sidebar = .filter(.all) }
        if sidebar.section == .documents { documentSelection = [document.id] }
        let issuedLine = String(localized: L.issuedResult(document.number ?? ""))
        pdfSaveFailure = nil
        // The PDF is rendered and stored now, and written to the PDF folder when one is chosen (ADR 0010).
        do {
            if let url = try DocumentPDFService.storeAndSave(stores, document: document) {
                report(issuedLine + " · " + String(localized: L.pdfSavedTo(PDFSettings.displayPath(url))))
            } else {
                report(issuedLine)
            }
        } catch {
            // The document is issued either way: the database is the source of truth (screens-flows.md §2c).
            report(issuedLine)
            let folder = PDFSettings.folderURL().map(PDFSettings.displayPath) ?? String(localized: L.pdfFolderNone)
            pdfSaveFailure = PDFSaveFailure(documentID: document.id, folder: folder, detail: ErrorText.message(error))
        }
    }

    /// File ▸ Save PDF…: the issued document's stored PDF through a save panel (screens-flows.md §1.4).
    private func savePDF(_ id: String) {
        do {
            guard let url = try PDFActions.save(stores, documentID: id) else { return }
            pdfSaveFailure = nil
            pdfVersion += 1
            report(L.pdfSavedTo(PDFSettings.displayPath(url)))
        } catch {
            report(error)
        }
    }

    /// File ▸ Print… (⌘P): the stored PDF of an issued document, or the draft's watermarked preview.
    private func printDocument(_ id: String, draft: Document?) {
        do {
            try PDFActions.printPDF(stores, documentID: id, draft: draft)
        } catch {
            report(error)
        }
    }

    /// Duplicate as Draft (⌘D): the lines, client, currency, language and notes of any invoice, advance or
    /// final invoice, with today's dates, the client's current term and address, and no number, rate,
    /// payment or deductions; those belong to the new document.
    private func duplicate(_ id: String) {
        // The open draft's last edits are still waiting for autosave: the copy is made of what the editor shows.
        if let editor, editor.documentID == id, !editor.saveNow() {
            report(L.draftChangesNotSaved(editor.saveError ?? ""), kind: .error)
            return
        }
        do {
            guard let source = try stores.documents.document(id: id), source.kind != .paymentTaxDocument else { return }
            let profile = try stores.profile.load()
            let customer = try source.customerID.flatMap { try stores.customers.customer(id: $0) }
            let today = CalendarDay(Date(), in: .current)
            let term = customer?.paymentTermDays ?? max(source.dueDate.days(since: source.issueDate), 0)
            let copy = Document(
                kind: source.kind, supplier: profile?.supplier ?? source.supplier, customer: customer?.party ?? source.customer,
                customerID: source.customerID, language: source.language, currency: source.currency, pricing: source.pricing,
                issueDate: today, taxPointDate: source.kind.isTaxDocument ? today : nil, dueDate: today.adding(days: term),
                lines: Self.copiedLines(source.lines),
                orderReference: source.orderReference, note: source.note, footer: source.footer)
            try stores.documents.saveDraft(copy)
            openDraft(copy.id, focus: .firstLineQuantity)
        } catch {
            report(error)
        }
    }

    /// Create Final Invoice… on an issued advance (screens-flows.md §2d, step 4): a final invoice draft
    /// with the advance's lines and client, deducting every issued tax document of its payments that no
    /// other final invoice deducts (§ 37a ZDPH; the deductions carry the advance's rate and exchange rate).
    /// Refused with the reason while a received payment has no issued tax document: its amount would not
    /// be deducted and the customer would be billed for money already received.
    private func createFinalInvoice(from advanceID: String) {
        do {
            guard let advance = try stores.documents.document(id: advanceID),
                  advance.kind == .advanceRequest, advance.status != .draft else { return }
            let pending = try stores.documents.payments(for: advanceID).filter { $0.kind == .received && !$0.receiptIssued }
            guard pending.isEmpty else {
                let days = pending.map { $0.paidOn.formatted(locale) }
                let text = days.count == 1
                    ? String(localized: L.finalInvoiceReceiptsPending(days[0]))
                    : String(localized: L.finalInvoiceReceiptsPendingMany(days.formatted(.list(type: .and).locale(locale))))
                report(text, kind: .info)
                return
            }
            let profile = try stores.profile.load()
            let customer = try advance.customerID.flatMap { try stores.customers.customer(id: $0) }
            let today = CalendarDay(Date(), in: .current)
            let term = customer?.paymentTermDays ?? profile?.defaultPaymentTermDays ?? 14
            var deductions: [AdvanceDeduction] = []
            for payment in try stores.documents.payments(for: advanceID) where payment.isIncoming && payment.receiptIssued {
                guard let receiptID = payment.receiptDocumentID,
                      try stores.documents.deduction(ofReceipt: receiptID) == nil,
                      let receipt = try stores.documents.document(id: receiptID) else { continue }
                let totals = try DocumentTotals.compute(for: receipt)
                deductions += receipt.advanceDeductions(totals: totals)
            }
            let final = Document(
                kind: .finalInvoice, supplier: profile?.supplier ?? advance.supplier, customer: customer?.party ?? advance.customer,
                customerID: advance.customerID, language: advance.language, currency: advance.currency, pricing: advance.pricing,
                issueDate: today, taxPointDate: today, dueDate: today.adding(days: term), lines: Self.copiedLines(advance.lines),
                advanceDeductions: deductions, relatedDocumentNumber: advance.number,
                orderReference: advance.orderReference, note: advance.note, footer: advance.footer)
            try stores.documents.saveDraft(final)
            openDraft(final.id, focus: .firstLineQuantity)
        } catch {
            report(error)
        }
    }

    private static func copiedLines(_ lines: [DocumentLine]) -> [DocumentLine] {
        lines.map { line in
            DocumentLine(text: line.text, quantity: line.quantity, unit: line.unit, unitPrice: line.unitPrice,
                         discountPercent: line.discountPercent, treatment: line.treatment)
        }
    }

    /// Delete Draft (⌫, the context menu, the detail, the menu bar): no confirmation, an Undo instead
    /// (screens-flows.md §4). Undo writes the draft back under its id and relinks a payment tax document
    /// to its payment. A pending or failed autosave of the deleted draft must not write it back
    /// (`saveDraft` inserts a missing id): the editor is discarded before the selection change runs `syncEditor`.
    private func deleteDrafts(_ ids: [String]) {
        var deleted: [DocumentListModel.DeletedDraft] = []
        var failure: Error?
        for id in ids {
            do {
                guard let document = try stores.documents.document(id: id), document.status == .draft else { continue }
                let receiptOf = try stores.documents.payment(ofReceipt: id)
                try stores.documents.deleteDraft(id: id)
                deleted.append(DocumentListModel.DeletedDraft(document: document, receiptOf: receiptOf))
                forgetDeletedDraft(id)
            } catch {
                failure = error
            }
        }
        if let failure {
            report(failure)
        }
        guard !deleted.isEmpty else { return }
        var undo: (@MainActor () -> Void)?
        if let undoManager {
            let restore = deleted
            let model = documents
            let ticket = model.makeUndoTicket()
            undoManager.registerUndo(withTarget: ticket) { registered in
                MainActor.assumeIsolated { model.restoreDrafts(restore, ticket: registered) }
            }
            undoManager.setActionName(String(localized: L.deleteDraft))
            // The line restores what it announced, not whatever is on top of the window's stack, and takes
            // its registration off the stack; after Edit ▸ Undo the shared ticket makes it do nothing.
            undo = {
                model.restoreDrafts(restore, ticket: ticket)
                undoManager.removeAllActions(withTarget: ticket)
            }
        }
        if failure == nil {
            let text = deleted.count == 1 ? String(localized: L.draftDeleted) : String(localized: L.draftsDeleted(deleted.count))
            report(text, undo: undo)
        }
    }

    /// Delete Payment (the payment rows of the detail, ⌫ in Payments & Bank): Undo records the payment
    /// again and relinks a draft tax document that was kept, except for credit legs and a payment deleted
    /// together with its draft tax document.
    private func deletePayment(_ payment: DocumentPayment, deletingDraftReceipt: Bool) {
        do {
            try stores.documents.deletePayment(id: payment.id, deletingDraftReceipt: deletingDraftReceipt)
            if deletingDraftReceipt, let receiptID = payment.receiptDocumentID {
                forgetDeletedDraft(receiptID)
            }
            var undo: (@MainActor () -> Void)?
            let restorable = (payment.kind == .received || payment.kind == .refund)
                && !(deletingDraftReceipt && payment.receiptDocumentID != nil)
            if restorable, let undoManager {
                let model = documents
                let ticket = model.makeUndoTicket()
                undoManager.registerUndo(withTarget: ticket) { registered in
                    MainActor.assumeIsolated { model.restorePayment(payment, ticket: registered) }
                }
                undoManager.setActionName(String(localized: L.deletePayment))
                // As for Delete Draft: the line undoes this deletion only.
                undo = {
                    model.restorePayment(payment, ticket: ticket)
                    undoManager.removeAllActions(withTarget: ticket)
                }
            }
            report(L.paymentDeleted, undo: undo)
        } catch {
            report(error)
        }
    }

    /// A deleted draft leaves the window: its editor is discarded first (a pending autosave must not write
    /// it back; `saveDraft` inserts a missing id), then it leaves every selection.
    private func forgetDeletedDraft(_ id: String) {
        if let open = editor, open.documentID == id {
            open.discard()
            editor = nil
            issueSheetPresented = false
        }
        documentSelection.remove(id)
        if overviewSelection == id { overviewSelection = nil }
        if paymentDocumentSelection == id { paymentDocumentSelection = nil }
    }

    /// Create Tax Document for a received payment on an advance that has none (screens-flows.md §2d,
    /// step 3): the draft opens in the editor.
    private func createTaxDocument(advanceID: String, payment: DocumentPayment) {
        do {
            guard let id = try TaxDocumentDraft.create(stores: stores, advanceID: advanceID, payment: payment) else { return }
            openDraft(id)
        } catch {
            report(error)
        }
    }

    private func reopen(_ id: String) {
        do {
            try stores.documents.reopen(id: id)
        } catch {
            report(error)
        }
    }

    @ViewBuilder private func sheetView(_ sheet: MainSheet) -> some View {
        switch sheet {
        case .recordPayment(let id):
            if let state = documents.state(id: id) {
                RecordPaymentSheet(stores: stores, state: state, mode: .payment, lastDate: $lastPaymentDate, openDraft: openDraft)
            }
        case .recordRefund(let id):
            if let state = documents.state(id: id) {
                RecordPaymentSheet(stores: stores, state: state, mode: .refund, lastDate: $lastPaymentDate, openDraft: openDraft)
            }
        case .closure(let id, let kind):
            if let state = documents.state(id: id) {
                ClosureSheet(stores: stores, state: state, kind: kind)
            }
        case .client(let id):
            // A new client is selected in Clients once saved (screens-flows.md §2e).
            ClientFormSheet(clients: clients, customer: id.flatMap { clients.customer(id: $0) }, onSaved: { saved in
                if sidebar.section == .clients { clientSelection = saved }
            })
        case .newClientForDraft(let name):
            // New Client “X”… from the editor's client field: the saved client becomes the draft's.
            ClientFormSheet(clients: clients, customer: nil, initialName: name, onSaved: { id in
                editor?.refreshReferenceData()
                editor?.setCustomer(id)
                editor?.requestFocus(.firstLineText)
            })
        }
    }
}

enum MainSheet: Identifiable, Hashable {
    case recordPayment(String)
    case recordRefund(String)
    case closure(String, DocumentClosureKind)
    /// nil creates a new client.
    case client(String?)
    /// A new client typed into the editor's client field, picked into the draft when saved.
    case newClientForDraft(String)

    var id: String {
        switch self {
        case .recordPayment(let id): "payment:" + id
        case .recordRefund(let id): "refund:" + id
        case .closure(let id, let kind): "closure:" + kind.rawValue + ":" + id
        case .client(let id): "client:" + (id ?? "new")
        case .newClientForDraft: "newClientForDraft"
        }
    }
}

/// The detail column and the inspector with several documents selected: the count and the totals per
/// currency (screens-flows.md §2b). The open balance counts issued documents with something left to pay.
struct MultiSelectionView: View {
    let rows: [DocumentRow]
    @Environment(\.locale) private var locale

    var body: some View {
        let totals = rows.compactMap { $0.summary.totalGross }
        let open = rows.filter { $0.isIssued && $0.state.outstanding.amount > 0 }.map { $0.state.outstanding }
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(L.selectedCount(rows.count)).textRole(.screenTitle)
            Grid(alignment: .leading, horizontalSpacing: Spacing.xl, verticalSpacing: Spacing.s) {
                GridRow {
                    Text(L.colTotal).textRole(.label)
                    MoneyListText(monies: totals, locale: locale, role: .amountStrong)
                }
                GridRow {
                    Text(L.outstanding).textRole(.label)
                    MoneyListText(monies: open, locale: locale, role: .amountStrong)
                }
            }
            Text(L.totalsPerCurrency).textRole(.caption)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
