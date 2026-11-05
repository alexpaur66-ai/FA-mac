// Clients (screens-flows.md §2e): the table, the client detail with their documents, and the client form.

import InvoicingCore
import InvoicingData
import Observation
import SwiftUI

/// The customers of the database; reloaded after every save, archive or import.
@MainActor @Observable
final class ClientsModel {
    private(set) var customers: [Customer] = []
    private(set) var error: String?
    let stores: Stores

    init(stores: Stores) {
        self.stores = stores
        reload()
    }

    func reload() {
        do {
            customers = try stores.customers.all()
            error = nil
        } catch {
            self.error = String(describing: error)
        }
    }

    func customer(id: String) -> Customer? {
        customers.first { $0.id == id }
    }
}

struct ClientRow: Identifiable, Hashable {
    let customer: Customer
    let open: [Money]
    let overdue: [Money]
    let lastDocument: CalendarDay?

    init(customer: Customer, states: [DocumentState]) {
        self.customer = customer
        let own = states.filter { $0.summary.customerID == customer.id }
        let unpaid = own.filter {
            $0.summary.status == .issued && ($0.summary.kind == .invoice || $0.summary.kind == .finalInvoice)
                && ($0.settlement == .open || $0.settlement == .partlyPaid) && !$0.markedForCreditNote
        }
        open = MoneyList.sums(unpaid.map { $0.outstanding })
        overdue = MoneyList.sums(unpaid.filter { $0.isOverdue }.map { $0.outstanding })
        lastDocument = own.filter { $0.summary.status == .issued }.map { $0.summary.issueDate }.max()
    }

    var id: String { customer.id }
    var name: String { customer.party.name }
    var country: String { customer.party.address.countryCode }
    var vatID: String { customer.party.vatIdentifier?.value ?? "" }
    var currencyCode: String { customer.currency.code }
    var lastDocumentText: String { lastDocument?.isoString ?? "" }
}

struct ClientsView: View {
    let clients: ClientsModel
    let documents: DocumentListModel
    @Binding var selection: String?
    let editClient: @MainActor (String?) -> Void

    @State private var search = ""
    @State private var sortOrder = [KeyPathComparator(\ClientRow.name, comparator: .localizedStandard)]
    @Environment(\.locale) private var locale

    private var rows: [ClientRow] {
        clients.customers
            .map { ClientRow(customer: $0, states: documents.states) }
            .filter { search.isEmpty || $0.name.folded.contains(search.folded) || $0.vatID.folded.contains(search.folded) }
            .sorted(using: sortOrder)
    }

    var body: some View {
        let rows = self.rows
        Group {
            if rows.isEmpty && search.isEmpty {
                ContentUnavailableView {
                    Label { Text(L.noClients) } icon: { Image(systemName: "person.2") }
                } description: {
                    EmptyView()
                } actions: {
                    Button { editClient(nil) } label: { Text(L.newClient) }
                }
            } else if rows.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                Table(rows, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn(Text(L.colName), value: \.name) { row in
                        Text(verbatim: row.name).textRole(.body)
                    }
                    TableColumn(Text(L.colCountry), value: \.country).width(min: 50, ideal: 60)
                    TableColumn(Text(L.colVATID), value: \.vatID).width(min: 90, ideal: 120)
                    TableColumn(Text(L.colCurrency), value: \.currencyCode).width(min: 50, ideal: 60)
                    TableColumn(Text(L.colOpen)) { row in
                        Text(verbatim: MoneyList.text(row.open, locale: locale)).textRole(.amount)
                    }
                    .alignment(.trailing)
                    TableColumn(Text(L.colOverdue)) { row in
                        Text(verbatim: MoneyList.text(row.overdue, locale: locale)).textRole(.amount)
                    }
                    .alignment(.trailing)
                    TableColumn(Text(L.colLastDocument), value: \.lastDocumentText) { row in
                        if let day = row.lastDocument { DayText(day) } else { Text(verbatim: "—") }
                    }
                    .alignment(.trailing)
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    if ids.count == 1, let id = ids.first {
                        Button { editClient(id) } label: { Text(L.edit) }
                    }
                }
            }
        }
        .navigationTitle(Text(L.clients))
        .navigationSubtitle(Text(verbatim: String(rows.count)))
        .searchable(text: $search, placement: .toolbar)
        .toolbar {
            ToolbarItem {
                Button { editClient(nil) } label: {
                    Label { Text(L.newClient) } icon: { Image(systemName: "person.badge.plus") }
                }
                .help(Text(L.newClient))
            }
        }
    }
}

struct ClientDetailView: View {
    let clients: ClientsModel
    let documents: DocumentListModel
    let customerID: String
    let editClient: @MainActor () -> Void

    @State private var documentSelection: Set<String> = []
    @Environment(\.locale) private var locale

    var body: some View {
        if let customer = clients.customer(id: customerID) {
            let row = ClientRow(customer: customer, states: documents.states)
            let own = documents.states.filter { $0.summary.customerID == customerID }.map { DocumentRow(state: $0) }
                .sorted(using: [KeyPathComparator(\DocumentRow.issueDate, order: .reverse)])
            VStack(alignment: .leading, spacing: Spacing.l) {
                header(customer)
                HStack(spacing: Spacing.l) {
                    figure(L.clientOpenBalance, MoneyList.text(row.open, locale: locale))
                    figure(L.colOverdue, MoneyList.text(row.overdue, locale: locale))
                    figure(L.clientInvoicedThisYear, MoneyList.text(invoicedThisYear(own), locale: locale))
                }
                Text(L.clientDocuments).textRole(.sectionTitle)
                Table(own, selection: $documentSelection) {
                    TableColumn(Text(L.colStatus)) { row in
                        StatusBadge(row.badgeInputs, detail: row.badgeDetail(locale: locale))
                    }
                    .width(min: 110, ideal: 180)
                    TableColumn(Text(L.colNumber)) { row in Text(verbatim: row.number.isEmpty ? "—" : row.number) }
                    TableColumn(Text(L.colType)) { row in Text(verbatim: row.typeName) }
                    TableColumn(Text(L.colIssued)) { row in DayText(row.issueDate) }.alignment(.trailing)
                    TableColumn(Text(L.colDue)) { row in DayText(row.dueDate) }.alignment(.trailing)
                    TableColumn(Text(L.colTotal)) { row in
                        MoneyText(amount: row.total, currency: row.currencyCode, locale: locale)
                    }
                    .alignment(.trailing)
                    TableColumn(Text(L.colOpen)) { row in
                        MoneyText(amount: row.outstanding, currency: row.currencyCode, locale: locale)
                    }
                    .alignment(.trailing)
                }
            }
            .padding(Spacing.xl)
            .navigationTitle(Text(verbatim: customer.party.name))
            .toolbar {
                ToolbarItem {
                    Button { editClient() } label: {
                        Label { Text(L.edit) } icon: { Image(systemName: "pencil") }
                    }
                }
            }
        } else {
            ContentUnavailableView {
                Label { Text(L.noClientSelected) } icon: { Image(systemName: "person.2") }
            }
        }
    }

    private func header(_ customer: Customer) -> some View {
        let party = customer.party
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: party.name).textRole(.screenTitle)
            ForEach(Array(party.address.lines().enumerated()), id: \.offset) { _, line in
                Text(verbatim: line).textRole(.body)
            }
            HStack(spacing: Spacing.l) {
                if let ico = party.identificationNumber {
                    Text(verbatim: "IČO " + ico.digits).textRole(.rowSecondary).textSelection(.enabled)
                }
                if let vat = party.vatIdentifier {
                    Text(verbatim: "DIČ " + vat.value).textRole(.rowSecondary).textSelection(.enabled)
                }
            }
            Text(verbatim: [customer.currency.code, String(localized: customer.language == .czech ? L.languageCzech : L.languageEnglish),
                            String(customer.paymentTermDays) + " d"].joined(separator: " · "))
                .textRole(.rowSecondary)
        }
    }

    private func figure(_ title: LocalizedStringResource, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title).textRole(.label)
            Text(verbatim: value).textRole(.amountStrong)
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: Radius.m))
    }

    private func invoicedThisYear(_ rows: [DocumentRow]) -> [Money] {
        let year = documents.today.year
        return rows.filter { !$0.isDraft && $0.kind.isTaxDocument && $0.issueDate.year == year }
            .compactMap { $0.summary.totalGross }
    }
}

/// New Client / Client details. IČO and VAT ID are checked by the core's parsers; there is no online check.
struct ClientFormSheet: View {
    let clients: ClientsModel
    let customer: Customer?

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var street = ""
    @State private var city = ""
    @State private var postalCode = ""
    @State private var countryCode = "CZ"
    @State private var ico = ""
    @State private var vatID = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var currencyCode = "CZK"
    @State private var paymentTermDays = 14
    @State private var language: DocumentLanguage = .czech
    @State private var notes = ""
    @State private var error: LocalizedStringResource?

    static let currencies: [Currency] = [.czk, .eur, .usd, .gbp, .chf, .pln]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(customer == nil ? L.newClientTitle : L.editClientTitle).textRole(.screenTitle)
            Form {
                TextField(text: $name) { Text(L.fieldName) }
                TextField(text: $countryCode) { Text(L.fieldCountry) }
                TextField(text: $street) { Text(L.fieldStreet) }
                TextField(text: $city) { Text(L.fieldCity) }
                TextField(text: $postalCode) { Text(L.fieldPostalCode) }
                TextField(text: $ico) { Text(L.fieldICO) }
                TextField(text: $vatID) { Text(L.fieldVATID) }
                TextField(text: $email) { Text(L.fieldEmail) }
                TextField(text: $phone) { Text(L.fieldPhone) }
                Picker(selection: $currencyCode) {
                    ForEach(Self.currencies, id: \.code) { currency in
                        Text(verbatim: currency.code).tag(currency.code)
                    }
                } label: {
                    Text(L.fieldCurrency)
                }
                Stepper(value: $paymentTermDays, in: 0...365) {
                    LabeledContent { Text(verbatim: String(paymentTermDays)) } label: { Text(L.fieldPaymentTerm) }
                }
                Picker(selection: $language) {
                    Text(L.languageCzech).tag(DocumentLanguage.czech)
                    Text(L.languageEnglish).tag(DocumentLanguage.english)
                } label: {
                    Text(L.fieldLanguage)
                }
                TextField(text: $notes, axis: .vertical) { Text(L.fieldNotes) }
                    .lineLimit(2...5)
                if let error {
                    Text(error).textRole(.caption).foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button { dismiss() } label: { Text(L.cancel) }
                    .keyboardShortcut(.cancelAction)
                Button { save() } label: { Text(L.save) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(Spacing.xl)
        .frame(minWidth: 480, minHeight: 560)
        .onAppear(perform: fill)
    }

    private func fill() {
        guard let customer else { return }
        let party = customer.party
        name = party.name
        street = party.address.street
        city = party.address.city
        postalCode = party.address.postalCode
        countryCode = party.address.countryCode
        ico = party.identificationNumber?.digits ?? ""
        vatID = party.vatIdentifier?.value ?? ""
        email = party.email ?? ""
        phone = party.phone ?? ""
        currencyCode = customer.currency.code
        paymentTermDays = customer.paymentTermDays
        language = customer.language
        notes = customer.notes
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { error = L.nameRequired; return }
        let icoText = ico.trimmingCharacters(in: .whitespaces)
        var identification: IdentificationNumber?
        if !icoText.isEmpty {
            guard let parsed = IdentificationNumber(icoText) else { error = L.invalidICO; return }
            identification = parsed
        }
        let vatText = vatID.trimmingCharacters(in: .whitespaces)
        var vat: VATIdentifier?
        if !vatText.isEmpty {
            guard let parsed = VATIdentifier(vatText) else { error = L.invalidVATID; return }
            vat = parsed
        }
        let address = PostalAddress(street: street, city: city, postalCode: postalCode,
                                    countryCode: countryCode.trimmingCharacters(in: .whitespaces).uppercased())
        let party = Party(name: trimmedName, address: address, identificationNumber: identification, vatIdentifier: vat,
                          email: email.isEmpty ? nil : email, phone: phone.isEmpty ? nil : phone)
        let saved = Customer(id: customer?.id ?? UUID().uuidString, party: party, vatStatus: nil,
                             currency: Currency.known(currencyCode), paymentTermDays: paymentTermDays,
                             language: language, notes: notes)
        do {
            try clients.stores.customers.save(saved)
            clients.reload()
            dismiss()
        } catch {
            self.error = LocalizedStringResource(stringLiteral: String(describing: error))
        }
    }
}
