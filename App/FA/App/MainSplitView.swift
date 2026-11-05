// The main window: one three-column NavigationSplitView for every section (screens-flows.md §1.2),
// the document sheets, and the actions the menu bar can call.

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
    @State private var resultLine: String?

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

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: sidebarSelection, counts: documents.badgeCounts)
                .navigationSplitViewColumnWidth(
                    min: LayoutMetrics.sidebar.min, ideal: LayoutMetrics.sidebar.ideal, max: LayoutMetrics.sidebar.max)
        } content: {
            contentColumn
                .navigationSplitViewColumnWidth(
                    min: LayoutMetrics.content.min, ideal: LayoutMetrics.content.ideal, max: LayoutMetrics.content.max)
        } detail: {
            detailColumn
                .frame(minWidth: LayoutMetrics.detailMinWidth)
                .inspector(isPresented: $inspectorPresented) {
                    inspectorColumn
                        .inspectorColumnWidth(
                            min: LayoutMetrics.inspector.min, ideal: LayoutMetrics.inspector.ideal, max: LayoutMetrics.inspector.max)
                }
        }
        .frame(minWidth: LayoutMetrics.windowMin.width, minHeight: LayoutMetrics.windowMin.height)
        .focusedSceneValue(\.mainActions, mainActions)
        .sheet(item: $sheet) { sheet in
            sheetView(sheet)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            documents.restart()
        }
    }

    // MARK: Columns

    @ViewBuilder private var contentColumn: some View {
        switch sidebar.section {
        case .overview:
            OverviewView(stores: stores, documents: documents, selection: $overviewSelection, show: show, newDocument: newDraft)
        case .documents:
            DocumentsView(
                stores: stores, documents: documents, filter: sidebar.documentFilter, selection: $documentSelection,
                inspectorPresented: $inspectorPresented, resultLine: resultLine,
                newDocument: newDraft, recordPayment: { sheet = .recordPayment($0) }, deleteDraft: deleteDraft)
        case .clients:
            ClientsView(clients: clients, documents: documents, selection: $clientSelection, editClient: { sheet = .client($0) })
        case .payments:
            PaymentsView(stores: stores, documents: documents, selectedDocumentID: $paymentDocumentSelection)
        case .rates:
            RatesView(stores: stores)
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
                MultiSelectionView(rows: documents.rows(for: sidebar.documentFilter).filter { documentSelection.contains($0.id) })
            } else {
                placeholder(L.noSelection, symbol: Symbols.document)
            }
        case .clients:
            if let id = clientSelection {
                ClientDetailView(clients: clients, documents: documents, customerID: id, editClient: { sheet = .client(id) })
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
            RatesCoverageView(stores: stores)
        case .exports:
            ExportsDetailView(stores: stores)
        }
    }

    @ViewBuilder private var inspectorColumn: some View {
        if let id = selectedDocumentID {
            DocumentInspectorView(stores: stores, documents: documents, documentID: id)
        } else {
            placeholder(L.noSelection, symbol: "sidebar.right")
        }
    }

    private func documentDetail(_ id: String) -> some View {
        DocumentDetailView(
            stores: stores, documents: documents, documentID: id,
            recordPayment: { sheet = .recordPayment($0) }, deleteDraft: deleteDraft)
    }

    private func placeholder(_ title: LocalizedStringResource, symbol: String) -> some View {
        ContentUnavailableView {
            Label { Text(title) } icon: { Image(systemName: symbol) }
        }
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

    private var mainActions: MainActions {
        var actions = MainActions(
            show: show,
            newDocument: newDraft,
            newClient: { sheet = .client(nil) },
            toggleInspector: { inspectorPresented.toggle() })
        guard let id = selectedDocumentID, let state = documents.state(id: id) else { return actions }
        let summary = state.summary
        if summary.status == .draft {
            actions.deleteDraft = { deleteDraft(id) }
            return actions
        }
        if summary.kind != .paymentTaxDocument && state.closure?.kind != .closedUnpaid {
            actions.recordPayment = { sheet = .recordPayment(id) }
        }
        if state.closure != nil {
            actions.reopen = { reopen(id) }
        } else {
            if summary.kind == .advanceRequest && state.paid.isZero && !state.deductedInFinal {
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
        resultLine = nil
    }

    /// New Invoice / New Advance Invoice: a draft with the company's and the selected client's defaults.
    /// The draft editor arrives in the next step; until then the draft is shown read-only.
    private func newDraft(_ kind: DocumentKind) {
        do {
            guard let profile = try stores.profile.load() else {
                resultLine = String(localized: L.setUpCompanyFirst)
                show(.section(.overview))
                return
            }
            let selectedClient = sidebar.section == .clients ? clientSelection : nil
            let customer = try selectedClient.flatMap { try stores.customers.customer(id: $0) }
            let today = CalendarDay(Date(), in: .current)
            let customerParty = customer?.party
                ?? Party(name: "", address: PostalAddress(street: "", city: "", postalCode: "", countryCode: "CZ"))
            let document = Document(
                kind: kind, supplier: profile.supplier, customer: customerParty, customerID: customer?.id,
                language: customer?.language ?? .czech, currency: customer?.currency ?? profile.defaultCurrency,
                issueDate: today, dueDate: today.adding(days: customer?.paymentTermDays ?? profile.defaultPaymentTermDays),
                footer: profile.footer)
            try stores.documents.saveDraft(document)
            sidebar = .filter(.drafts)
            documentSelection = [document.id]
        } catch {
            resultLine = String(describing: error)
        }
    }

    private func deleteDraft(_ id: String) {
        do {
            try stores.documents.deleteDraft(id: id)
            documentSelection.remove(id)
            if overviewSelection == id { overviewSelection = nil }
        } catch {
            resultLine = String(describing: error)
        }
    }

    private func reopen(_ id: String) {
        do {
            try stores.documents.reopen(id: id)
        } catch {
            resultLine = String(describing: error)
        }
    }

    @ViewBuilder private func sheetView(_ sheet: MainSheet) -> some View {
        switch sheet {
        case .recordPayment(let id):
            if let state = documents.state(id: id) {
                RecordPaymentSheet(stores: stores, state: state)
            }
        case .closure(let id, let kind):
            if let state = documents.state(id: id) {
                ClosureSheet(stores: stores, state: state, kind: kind)
            }
        case .client(let id):
            ClientFormSheet(clients: clients, customer: id.flatMap { clients.customer(id: $0) })
        }
    }
}

enum MainSheet: Identifiable, Hashable {
    case recordPayment(String)
    case closure(String, DocumentClosureKind)
    /// nil creates a new client.
    case client(String?)

    var id: String {
        switch self {
        case .recordPayment(let id): "payment:" + id
        case .closure(let id, let kind): "closure:" + kind.rawValue + ":" + id
        case .client(let id): "client:" + (id ?? "new")
        }
    }
}

/// The detail column with several documents selected: the count and the totals per currency.
struct MultiSelectionView: View {
    let rows: [DocumentRow]
    @Environment(\.locale) private var locale

    var body: some View {
        let totals = rows.compactMap { $0.summary.totalGross }
        let open = rows.map { $0.state.outstanding }
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(L.selectedCount(rows.count)).textRole(.screenTitle)
            Grid(alignment: .leading, horizontalSpacing: Spacing.xl, verticalSpacing: Spacing.s) {
                GridRow {
                    Text(L.colTotal).textRole(.label)
                    Text(verbatim: MoneyList.text(totals, locale: locale)).textRole(.amountStrong)
                }
                GridRow {
                    Text(L.outstanding).textRole(.label)
                    Text(verbatim: MoneyList.text(open, locale: locale)).textRole(.amountStrong)
                }
            }
            Text(L.totalsPerCurrency).textRole(.caption)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
