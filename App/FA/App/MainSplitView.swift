// The main window: one three-column NavigationSplitView for every section (screens-flows.md §1.2), with
// no inspector column; the result line, the document sheets, the Exchange Rates sheet and the ČNB import,
// undo, and the actions the menu bar can call.

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
    /// The selections are kept per window (screens-flows.md §1.1, Restore); Documents as joined ids.
    @SceneStorage("documents.selection") private var documentSelectionStored = ""
    @SceneStorage("overview.selection") private var overviewSelection: String?
    @SceneStorage("clients.selection") private var clientSelection: String?
    @State private var paymentDocumentSelection: String?
    /// Restored ids whose documents are gone are dropped once, when the documents have loaded.
    @State private var restoredSelectionsChecked = false
    @State private var sheet: MainSheet?
    /// The result or error of the last action, at the top of the content column (design-system.md §8.17);
    /// cleared when the user navigates or closes it.
    @State private var result: ResultLineModel?
    /// File ▸ Import ČNB Rates… opens the file importer from any section, without switching (§2g).
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
    /// Edit ▸ Jump to Search Field presents the Documents search through this.
    @State private var documentsSearchPresented = false
    /// The Clients search; cleared when a client is opened from elsewhere, so the search cannot hide its row.
    @State private var clientsSearch = ""
    /// Each Documents filter's sort, kept with the window (`DocumentSortMemory`).
    @SceneStorage("documents.sort") private var documentsSortStored = ""
    /// ↩ on an issued document in the table: its issued view takes keyboard focus.
    @State private var detailFocusRequest = false
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

    /// The Documents selection, stored as the ids joined by commas (document ids are UUIDs).
    private var documentSelection: Set<String> {
        get { Set(documentSelectionStored.split(separator: ",").map(String.init)) }
        nonmutating set { documentSelectionStored = newValue.sorted().joined(separator: ",") }
    }

    private var documentSelectionBinding: Binding<Set<String>> {
        Binding(get: { documentSelection }, set: { documentSelection = $0 })
    }

    /// The shown filter's sort; a header click stores it for that filter.
    private var documentsSortBinding: Binding<[KeyPathComparator<DocumentRow>]> {
        let filter = sidebar.documentFilter
        return Binding(
            get: { DocumentSortMemory.sort(for: filter, in: documentsSortStored).comparators },
            set: { comparators in
                if let sort = DocumentSort(comparators) { setDocumentsSort(sort, for: filter) }
            })
    }

    private func setDocumentsSort(_ sort: DocumentSort, for filter: DocumentSmartFilter) {
        documentsSortStored = DocumentSortMemory.setting(sort, for: filter, in: documentsSortStored)
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: sidebarSelection, badges: documents.badges)
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
        }
        .frame(minWidth: LayoutMetrics.windowMin.width, minHeight: LayoutMetrics.windowMin.height)
        .focusedSceneValue(\.mainActions, mainActions)
        .onChange(of: selectedDraftID, initial: true) { _, id in
            syncEditor(id)
        }
        .onChange(of: documents.loaded, initial: true) { _, loaded in
            if loaded { dropMissingRestoredSelections() }
        }
        .fileImporter(isPresented: $ratesImporting, allowedContentTypes: RateFileTypes.allowed, allowsMultipleSelection: false) { result in
            guard let outcome = RateImport.perform(result, stores: stores, locale: locale) else { return }
            // An open draft takes the imported rate at once, as the editor's own rate form does.
            if outcome.count != nil { editor?.refreshRate() }
            report(outcome.line, kind: outcome.count == nil ? .problem : .done)
        }
        .onChange(of: documents.restoreOutcome) { _, outcome in
            guard let outcome else { return }
            if let error = outcome.error {
                report(error, kind: .problem)
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
        // A client created or edited from the sheet must reach the open editor's Client picker, and a rate
        // imported in the Exchange Rates sheet its rate form.
        .sheet(item: $sheet, onDismiss: {
            editor?.refreshReferenceData()
            editor?.refreshRate()
        }) { sheet in
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
                show: show, showOverdue: showOverdue, newDocument: newDraft, newClient: { sheet = .client(nil) }, importRates: importRates)
        case .documents:
            DocumentsView(
                stores: stores, documents: documents, filter: sidebar.documentFilter, selection: documentSelectionBinding,
                search: $documentsSearch, searchPresented: $documentsSearchPresented, sortOrder: documentsSortBinding,
                editingID: editor?.documentID,
                newDocument: newDraft, documentActions: documentActions(for:), deleteDrafts: deleteDrafts,
                open: openFromList)
        case .clients:
            ClientsView(clients: clients, documents: documents, selection: $clientSelection, search: $clientsSearch,
                        editClient: { sheet = .client($0) })
        case .payments:
            PaymentsView(stores: stores, documents: documents, selectedDocumentID: $paymentDocumentSelection,
                         deletePayment: deletePayment)
        }
    }

    @ViewBuilder private var detailColumn: some View {
        switch sidebar.section {
        case .overview:
            if let id = overviewSelection {
                documentDetail(id)
            } else {
                placeholder(L.noSelection)
            }
        case .documents:
            if documentSelection.count == 1, let id = documentSelection.first {
                documentDetail(id)
            } else if documentSelection.count > 1 {
                MultiSelectionView(rows: selectedRows)
            } else {
                placeholder(L.noSelection)
            }
        case .clients:
            if let id = clientSelection {
                let last = lastInvoice(ofClient: id)
                ClientDetailView(clients: clients, documents: documents, customerID: id,
                                 editClient: { sheet = .client(id) }, newDocument: { newDraft($0, customerID: id) },
                                 lastInvoiceNumber: last?.summary.number,
                                 duplicateLastInvoice: duplicateAction(last),
                                 openDocument: { openDocument(id: $0) })
            } else {
                placeholder(L.noClientSelected)
            }
        case .payments:
            if let id = paymentDocumentSelection {
                documentDetail(id)
            } else {
                placeholder(L.noSelection)
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
                    newClient: { sheet = .newClientForDraft($0) },
                    openChainItem: { item in
                        guard let target = item.documentID else { return }
                        if item.isDraft { openDraft(target) } else { openDocument(id: target) }
                    },
                    chainAction: performChainStep,
                    issueSheetPresented: $issueSheetPresented, previewShown: $previewShown)
            } else {
                ProgressView()
            }
        } else {
            DocumentDetailView(
                stores: stores, documents: documents, documentID: id, actions: documentActions(for: id),
                deletePayment: deletePayment,
                createTaxDocument: { createTaxDocument(advanceID: id, payment: $0) }, chainAction: performChainStep,
                openDraft: openDraft, openDocument: openDocument(id:),
                pdfVersion: $pdfVersion, pdfSaveFailure: $pdfSaveFailure, focusRequest: $detailFocusRequest)
        }
    }

    /// "Select a document": title only, no symbol (design-system.md §8.10); real empty states keep theirs.
    private func placeholder(_ title: LocalizedStringResource) -> some View {
        ContentUnavailableView { Text(title) }
    }

    // MARK: Result line

    private func report(_ text: String, kind: ResultLineModel.Kind = .done, undo: (@MainActor () -> Void)? = nil) {
        result = ResultLineModel(text, kind: kind, undo: undo)
    }

    private func report(_ resource: LocalizedStringResource, kind: ResultLineModel.Kind = .done, undo: (@MainActor () -> Void)? = nil) {
        report(String(localized: resource), kind: kind, undo: undo)
    }

    private func report(_ error: Error) {
        report(ErrorText.message(error, locale: locale), kind: .problem)
    }

    // MARK: Selection and actions

    /// The one document the detail column shows in the current section, if any.
    private var selectedDocumentID: String? {
        switch sidebar.section {
        case .overview: overviewSelection
        case .documents: documentSelection.count == 1 ? documentSelection.first : nil
        case .payments: paymentDocumentSelection
        case .clients: nil
        }
    }

    /// The selected document while it is a draft: the detail column shows its editor.
    private var selectedDraftID: String? {
        guard let id = selectedDocumentID, documents.state(id: id)?.summary.status == .draft else { return nil }
        return id
    }

    /// The client File ▸ Edit Client acts on: the one selected in Clients, else the selected document's.
    private var menuClientID: String? {
        if sidebar.section == .clients { return clientSelection }
        return selectedDocumentID.flatMap { documents.state(id: $0)?.summary.customerID }
    }

    /// One editor per selected draft; the old one writes its draft before it goes. When that save fails
    /// (the store refused it), the user is told the edits were not kept instead of losing them silently.
    private func syncEditor(_ id: String?) {
        guard editor?.documentID != id else { return }
        if let old = editor, !old.saveNow() {
            report(L.draftChangesNotSaved(old.saveError ?? ""), kind: .problem)
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
            showExchangeRates: { sheet = .exchangeRates },
            importRates: importRates,
            showGettingStarted: showGettingStarted)
        if let url = stores.databaseURL {
            actions.showDataFolder = { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        actions.currentFilter = sidebar.section == .documents ? sidebar.documentFilter : nil
        if sidebar.section == .documents {
            let filter = sidebar.documentFilter
            actions.sort = SortMenuActions(
                current: DocumentSortMemory.sort(for: filter, in: documentsSortStored),
                set: { setDocumentsSort($0, for: filter) },
                columns: DocumentSortColumn.sortMenuColumns(for: filter))
        }
        // Clients and Payments get theirs with their own searchable(isPresented:).
        if sidebar.section == .documents || sidebar.section == .overview {
            actions.jumpToSearch = jumpToDocumentsSearch
        }
        if let clientID = menuClientID, let customer = clients.customer(id: clientID) {
            actions.editClientName = customer.party.name
            actions.editClient = { sheet = .client(clientID) }
        }
        // Client context (screens-flows.md §1.4): the New items name and prefill the selected client, and
        // Duplicate copies the client's last invoice.
        if sidebar.section == .clients, let clientID = clientSelection, let customer = clients.customer(id: clientID) {
            actions.newDocumentClientName = customer.party.name
            if let last = lastInvoice(ofClient: clientID) {
                actions.document.duplicate = { duplicate(last.id) }
                actions.document.duplicateSourceNumber = last.summary.number
            }
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
            actions.related = relatedDocuments(in: try? AdvanceChain.of(id, stores: stores, states: documents.states))
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
        let chain = try? AdvanceChain.of(id, stores: stores, states: documents.states)
        actions.related = relatedDocuments(in: chain)
        // An issued advance with a payment, not closed, and not yet deducted or settled by a final invoice.
        if summary.kind == .advanceRequest && state.closure == nil && !state.deductedInFinal && state.paid.amount > 0 {
            actions.createFinalInvoice = { createFinalInvoice(from: id) }
            if case .createFinalInvoice? = chain?.nextStep { actions.finalInvoiceIsNextStep = true }
        }
        // The oldest received payment without a tax document (screens-flows.md §1.4); the payment rows offer
        // each one. An advance for § 64 goods needs none (ADR 0012).
        if summary.kind == .advanceRequest, state.taxDocumentRequired, let payments = try? stores.documents.payments(for: id) {
            let missing = TaxDocumentDraft.paymentsWithoutReceipt(payments)
            if let payment = missing.min(by: { $0.paidOn < $1.paidOn }) {
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
        // The Documents row itself is its "all" filter.
        sidebar = item == .section(.documents) ? .filter(.all) : item
        result = nil
    }

    /// Duplicate as Draft of that document, for the client page's toolbar.
    private func duplicateAction(_ state: DocumentState?) -> (@MainActor () -> Void)? {
        guard let id = state?.id else { return nil }
        return { duplicate(id) }
    }

    /// A client's last issued invoice (Faktura), which ⌘D copies in client context.
    private func lastInvoice(ofClient id: String) -> DocumentState? {
        documents.states
            .filter { $0.summary.customerID == id && $0.summary.kind == .invoice && $0.summary.status == .issued }
            .max { ($0.summary.issueDate, $0.summary.number ?? "") < ($1.summary.issueDate, $1.summary.number ?? "") }
    }

    /// Restored selections of documents that no longer exist are dropped once, after the first load; later
    /// a selected id without a state is a draft just created, which the observation has not delivered yet.
    private func dropMissingRestoredSelections() {
        guard !restoredSelectionsChecked else { return }
        restoredSelectionsChecked = true
        let known = Set(documents.states.map(\.id))
        let kept = documentSelection.filter { known.contains($0) }
        if kept != documentSelection { documentSelection = kept }
        if let id = overviewSelection, !known.contains(id) { overviewSelection = nil }
        if let id = clientSelection, clients.customer(id: id) == nil { clientSelection = nil }
    }

    /// Document ▸ Show Related Documents ▸: the chain's other documents; empty outside a chain.
    private func relatedDocuments(in chain: AdvanceChain?) -> [RelatedDocumentAction] {
        guard let chain else { return [] }
        return chain.relatedDocuments.compactMap { item in
            guard let documentID = item.documentID else { return nil }
            let isDraft = item.isDraft
            return RelatedDocumentAction(id: item.id, title: item.menuTitle) {
                if isDraft { openDraft(documentID) } else { openDocument(id: documentID) }
            }
        }
    }

    /// The chain line's next-step button (screens-flows.md §2d).
    private func performChainStep(_ step: ChainNextStep) {
        switch step {
        case .createTaxDocument(let advanceID, let payment): createTaxDocument(advanceID: advanceID, payment: payment)
        case .createFinalInvoice(let advanceID): createFinalInvoice(from: advanceID)
        }
    }

    /// ↩ or a double-click in the Documents table: a draft's editor takes the cursor at its first line, an
    /// issued document's view takes keyboard focus (screens-flows.md §2b).
    private func openFromList(_ id: String) {
        guard let state = documents.state(id: id) else { return }
        if state.summary.status == .draft {
            if let editor, editor.documentID == id { editor.requestFocus(.firstLineQuantity) }
        } else {
            detailFocusRequest = true
        }
    }

    /// Edit ▸ Jump to Search Field: from Overview it switches to Documents first.
    private func jumpToDocumentsSearch() {
        if sidebar.section != .documents { show(.filter(.all)) }
        documentsSearchPresented = true
    }

    /// The Overview's Overdue tile: Unpaid, sorted by due date with the oldest first, whatever sort Unpaid
    /// had before (screens-flows.md §2a).
    private func showOverdue() {
        setDocumentsSort(DocumentSmartFilter.unpaid.defaultSort, for: .unpaid)
        show(.filter(.unpaid))
    }

    /// Shows an issued document in Documents (the chain, a locked payment's tax document).
    private func openDocument(id: String) {
        show(.filter(.all))
        documentsSearch = ""
        documentSelection = [id]
    }

    private func showClient(ofDocument id: String) {
        guard let customerID = documents.state(id: id)?.summary.customerID else { return }
        clientsSearch = ""
        clientSelection = customerID
        show(.section(.clients))
    }

    /// File ▸ Import ČNB Rates…: the file importer over the current section; the result line reports.
    private func importRates() {
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

    /// After Issue: the document leaves Drafts, so the list switches to Documents and keeps it selected; the
    /// detail column shows the issued view (screens-flows.md §2c, "Afterwards").
    private func issued(_ document: Document) {
        issueSheetPresented = false
        previewShown = false
        if sidebar == .filter(.drafts) { sidebar = .filter(.all) }
        if sidebar.section == .documents { documentSelection = [document.id] }
        let number = document.number ?? ""
        let issuedLine = String(localized: L.issuedResult(number))
        pdfSaveFailure = nil
        // The PDF is rendered and stored now, and written to the PDF folder when one is chosen (ADR 0010).
        // One sentence, no buttons (docs-29): Record Payment… is in the toolbar, Show in Finder in the PDF row.
        do {
            if let url = try DocumentPDFService.storeAndSave(stores, document: document) {
                report(String(localized: L.issuedResultWithPDF(number, PDFSettings.displayPath(url))))
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
            report(L.draftChangesNotSaved(editor.saveError ?? ""), kind: .problem)
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
                orderReference: source.orderReference, note: source.note, footer: profile?.footer)
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
    /// be deducted and the customer would be billed for money already received. An advance for § 64 goods
    /// has no tax documents: its payments are listed as paid in advance instead (ADR 0012). An advance with a
    /// closing event, or one a final invoice already deducted or settled, gets none, however this is reached
    /// (the Document menu does not offer it, Record Payment's last step neither): it would bill the supply twice.
    private func createFinalInvoice(from advanceID: String) {
        do {
            guard let advance = try stores.documents.document(id: advanceID),
                  advance.kind == .advanceRequest, advance.status != .draft else { return }
            let advanceState = try stores.documents.state(for: advanceID, today: CalendarDay(Date(), in: .current))
            guard advanceState.closure == nil else { return }
            guard !advanceState.deductedInFinal else {
                report(L.advanceAlreadyInFinalInvoice(advanceState.deductedBy.joined(separator: ", ")), kind: .info)
                return
            }
            // A draft final invoice of this advance opens instead of a second one (the chain line offers none).
            if let draft = try AdvanceChain.finalInvoices(of: advanceState, stores: stores, states: documents.states)
                .first(where: { $0.isDraft }), let draftID = draft.documentID {
                openDraft(draftID)
                return
            }
            let goodsOnly = advance.isIntraCommunityGoodsOnly
            var pending: [DocumentPayment] = []
            if !goodsOnly {
                pending = try stores.documents.payments(for: advanceID).filter { $0.kind == .received && !$0.receiptIssued }
            }
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
            var paidAdvances: [PaidAdvance] = []
            if goodsOnly {
                paidAdvances = try stores.documents.paidAdvanceCandidates(ofAdvanceRequest: advanceID).map(\.paidAdvance)
            }
            let final = Document(
                kind: .finalInvoice, supplier: profile?.supplier ?? advance.supplier, customer: customer?.party ?? advance.customer,
                customerID: advance.customerID, language: advance.language, currency: advance.currency, pricing: advance.pricing,
                issueDate: today, taxPointDate: today, dueDate: today.adding(days: term), lines: Self.copiedLines(advance.lines),
                advanceDeductions: deductions, paidAdvances: paidAdvances.isEmpty ? nil : paidAdvances, relatedDocumentNumber: advance.number,
                orderReference: advance.orderReference, note: advance.note, footer: profile?.footer)
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

    /// Delete Payment (the payment rows of the detail, ⌫ in Payments): Undo records the payment
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
        if documentSelection.contains(id) { documentSelection.remove(id) }
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
                RecordPaymentSheet(stores: stores, state: state, mode: .payment, lastDate: $lastPaymentDate, openDraft: openDraft,
                                   createFinalInvoice: { createFinalInvoice(from: $0) }, reportRecorded: { report($0) })
            }
        case .recordRefund(let id):
            if let state = documents.state(id: id) {
                RecordPaymentSheet(stores: stores, state: state, mode: .refund, lastDate: $lastPaymentDate, openDraft: openDraft,
                                   reportRecorded: { report($0) })
            }
        case .closure(let id, let kind):
            if let state = documents.state(id: id) {
                ClosureSheet(stores: stores, state: state, kind: kind)
            }
        case .client(let id):
            // A new client is selected in Clients once saved (screens-flows.md §2e).
            ClientFormSheet(clients: clients, customer: id.flatMap { clients.customer(id: $0) }, onSaved: { saved in
                if sidebar.section == .clients {
                    clientsSearch = ""
                    clientSelection = saved
                }
            }, onOpenExisting: { existing in
                // "Possible duplicate … – open it?": the existing client is shown in Clients.
                show(.section(.clients))
                clientsSearch = ""
                clientSelection = existing
            })
        case .exchangeRates:
            ExchangeRatesSheet(stores: stores)
        case .newClientForDraft(let name):
            // New Client “X”… from the editor's client field: the saved client becomes the draft's.
            ClientFormSheet(clients: clients, customer: nil, initialName: name, onSaved: { id in
                editor?.refreshReferenceData()
                editor?.setCustomer(id)
                editor?.requestFocus(.firstLineText)
            }, onOpenExisting: { id in
                // Opened from a draft, the existing client is picked into it.
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
    /// File ▸ Exchange Rates.
    case exchangeRates

    var id: String {
        switch self {
        case .recordPayment(let id): "payment:" + id
        case .recordRefund(let id): "refund:" + id
        case .closure(let id, let kind): "closure:" + kind.rawValue + ":" + id
        case .client(let id): "client:" + (id ?? "new")
        case .newClientForDraft: "newClientForDraft"
        case .exchangeRates: "exchangeRates"
        }
    }
}

/// The detail column with several documents selected (screens-flows.md §2b): the count, then up to three
/// figures per currency under the §2a aggregation rules. Drafts count in none of them.
struct MultiSelectionView: View {
    let rows: [DocumentRow]
    @Environment(\.locale) private var locale

    var body: some View {
        let issued = rows.filter(\.isIssued)
        // Tax documents only; a final invoice net of the DDPPs it deducts, in full when it lists advances
        // as paid in advance (EU goods), the same rule as the Overview's revenue.
        let revenue = issued.compactMap { OverviewFigures.revenueAmount($0.summary) }
        let open = issued.filter { $0.state.countsAsUnpaidInvoice && $0.state.outstanding.amount > 0 }.map(\.state.outstanding)
        let advances = issued.filter { $0.state.isOpenAdvance && $0.state.outstanding.amount > 0 }.map(\.state.outstanding)
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(L.selectedCount(rows.count)).textRole(.screenTitle)
            Text(L.totalsPerCurrency).textRole(.caption)
            Grid(alignment: .leading, horizontalSpacing: Spacing.xl, verticalSpacing: Spacing.s) {
                GridRow {
                    Text(L.selectionRevenue).textRole(.label)
                    MoneyListText(monies: revenue, locale: locale, role: .amountStrong)
                }
                GridRow {
                    Text(L.openBalance).textRole(.label)
                    MoneyListText(monies: open, locale: locale, role: .amountStrong)
                }
                if !advances.isEmpty {
                    GridRow {
                        Text(L.unpaidAdvances).textRole(.label)
                        MoneyListText(monies: advances, locale: locale, role: .amountStrong)
                    }
                }
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
