// Clients (screens-flows.md §2e): the table, the client page with the client's details, defaults and
// documents (there is no inspector), and the client form.

import InvoicingCore
import InvoicingData
import Observation
import SwiftUI

/// The customers of the database; reloaded after every save, archive or import.
@MainActor @Observable
final class ClientsModel {
    private(set) var customers: [Customer] = []
    private(set) var error: String?
    /// False until a load succeeded, so a failed first load is not shown as "no clients yet".
    private(set) var loaded = false
    let stores: Stores

    init(stores: Stores) {
        self.stores = stores
        reload()
    }

    func reload() {
        do {
            customers = try stores.customers.all()
            error = nil
            loaded = true
        } catch {
            self.error = ErrorText.message(error)
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
    let documentCount: Int

    init(customer: Customer, states: [DocumentState]) {
        self.customer = customer
        let own = states.filter { $0.summary.customerID == customer.id }
        // The same rule as the Unpaid and Overdue filters (screens-flows.md §2a).
        let unpaid = own.filter(\.countsAsUnpaidInvoice)
        open = MoneyList.sums(unpaid.map(\.outstanding))
        overdue = MoneyList.sums(unpaid.filter(\.isOverdue).map(\.outstanding))
        lastDocument = own.filter { $0.summary.status == .issued }.map(\.summary.issueDate).max()
        documentCount = own.count
    }

    var id: String { customer.id }
    var name: String { customer.party.name }
    var country: String { customer.party.address.countryCode }
    var vatID: String { customer.party.vatIdentifier?.value ?? "" }
    var companyID: String { customer.party.identificationNumber?.digits ?? "" }
    var city: String { customer.party.address.city.trimmingCharacters(in: .whitespaces) }
    var lastDocumentText: String { lastDocument?.isoString ?? "" }

    /// Search (other-05): the name, the IČO and the VAT ID.
    func matches(search: String) -> Bool {
        let needle = search.folded
        guard !needle.isEmpty else { return true }
        return [name, companyID, vatID].contains { $0.folded.contains(needle) }
    }
}

struct ClientsView: View {
    let clients: ClientsModel
    let documents: DocumentListModel
    @Binding var selection: String?
    /// The Clients search, kept by the window so that opening a client from elsewhere can clear it.
    @Binding var search: String
    let editClient: @MainActor (String?) -> Void

    @State private var sortOrder = [KeyPathComparator(\ClientRow.name, comparator: .localizedStandard)]
    @Environment(\.locale) private var locale

    private var rows: [ClientRow] {
        clients.customers
            .map { ClientRow(customer: $0, states: documents.states) }
            .filter { $0.matches(search: search) }
            .sorted(using: sortOrder)
    }

    var body: some View {
        let rows = self.rows
        VStack(spacing: 0) {
            if let error = clients.error {
                HStack(spacing: Spacing.m) {
                    InlineMessage(error)
                    Spacer()
                    Button { clients.reload() } label: { Text(L.retry) }
                }
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s)
                Divider()
            }
            if rows.isEmpty && search.isEmpty {
                // After a failed first load the error line and Retry are the content: no "no clients" claim.
                if clients.loaded {
                    ContentUnavailableView {
                        Label { Text(L.noClients) } icon: { Image(systemName: "person.2") }
                    } description: {
                        Text(L.noClientsDescription)
                    } actions: {
                        Button { editClient(nil) } label: { Text(L.newClient) }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    Spacer()
                }
            } else if rows.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                table(rows)
            }
        }
        .navigationTitle(Text(L.clients))
        .navigationSubtitle(Text(verbatim: String(rows.count)))
        .searchable(text: $search, placement: .toolbar, prompt: Text(L.searchClients))
        .toolbar {
            ToolbarItem {
                Button { editClient(nil) } label: {
                    Label { Text(L.newClient) } icon: { Image(systemName: "person.badge.plus") }
                }
                .help(Text(L.newClientHelp))
            }
        }
    }

    // Name · Country · VAT ID · Open balance · Last document (other-05, shell-21).
    private func table(_ rows: [ClientRow]) -> some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn(Text(L.colName), value: \.name) { row in
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(verbatim: row.name).textRole(.body)
                    if let second = secondLine(row) {
                        Text(verbatim: second).textRole(.rowSecondary)
                    }
                }
            }
            TableColumn(Text(L.colCountry), value: \.country) { row in
                Text(verbatim: row.country).textRole(.body)
            }
            .width(min: 50, ideal: 60)
            TableColumn(Text(L.colVATID), value: \.vatID) { row in
                Text(verbatim: row.vatID).textRole(.amount)
            }
            .width(min: 90, ideal: 120)
            TableColumn(Text(L.colOpenBalance)) { row in
                VStack(alignment: .trailing, spacing: Spacing.xxs) {
                    MoneyListText(monies: row.open, locale: locale)
                    // The overdue part in words, not a colour or a column.
                    if !row.overdue.isEmpty {
                        Text(L.clientOverdueAmount(Self.amounts(row.overdue, locale: locale))).textRole(.rowSecondary)
                    }
                }
            }
            .width(min: 110, ideal: 160)
            .alignment(.trailing)
            TableColumn(Text(L.colLastDocument), value: \.lastDocumentText) { row in
                if let day = row.lastDocument { DayText(day) } else { Text(verbatim: "—").textRole(.body) }
            }
            .alignment(.trailing)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if ids.count == 1, let id = ids.first {
                Button { editClient(id) } label: { Text(L.editClientDetails) }
            }
        }
    }

    /// "Praha · IČO 12345678": the city and, when present, the IČO.
    private func secondLine(_ row: ClientRow) -> String? {
        switch (row.city.isEmpty, row.companyID.isEmpty) {
        case (false, false): return String(localized: L.clientCityAndCompanyID(row.city, row.companyID))
        case (false, true): return row.city
        case (true, false): return String(localized: L.companyIDChip(row.companyID))
        case (true, true): return nil
        }
    }

    /// Amounts per currency, never summed: "1 200,00 € + 3 000 Kč".
    static func amounts(_ monies: [Money], locale: Locale) -> String {
        MoneyList.sums(monies)
            .map { MoneyText.format($0.amount, currency: $0.currency.code, locale: locale) }
            .joined(separator: " + ")
    }
}

struct ClientDetailView: View {
    let clients: ClientsModel
    let documents: DocumentListModel
    let customerID: String
    let editClient: @MainActor () -> Void
    /// New Invoice for this client (screens-flows.md §2e); ⇧⌘N makes an advance for it.
    let newDocument: @MainActor (DocumentKind) -> Void
    /// The number of the client's last invoice, which Duplicate copies; nil when it has none.
    var lastInvoiceNumber: String? = nil
    var duplicateLastInvoice: (@MainActor () -> Void)? = nil
    /// ↩ or a double-click on a document row shows it in Documents ▸ All (other-07).
    var openDocument: (@MainActor (String) -> Void)? = nil

    @State private var documentSelection: Set<String> = []
    @Environment(\.locale) private var locale

    var body: some View {
        if let customer = clients.customer(id: customerID) {
            let row = ClientRow(customer: customer, states: documents.states)
            let own = documents.states.filter { $0.summary.customerID == customerID }
                .map { DocumentRow(state: $0, today: documents.today) }
                .sorted(using: [KeyPathComparator(\DocumentRow.issueDate, order: .reverse)])
            VStack(alignment: .leading, spacing: Spacing.l) {
                header(customer)
                HStack(spacing: Spacing.l) {
                    // Two figures, no Overdue tile: the open balance says in words what of it is overdue.
                    figure(L.clientOpenBalance, row.open, overdue: row.overdue)
                    figure(L.clientInvoicedThisYear, invoicedThisYear(own))
                }
                Text(L.clientDocuments).textRole(.sectionTitle)
                Table(own, selection: $documentSelection) {
                    TableColumn(Text(L.colStatus)) { row in
                        StatusBadge(row.badgeInputs, detail: row.badgeDetail(locale: locale))
                    }
                    .width(min: 110, ideal: 180)
                    TableColumn(Text(L.colNumber)) { row in DocumentNumberText(row: row) }
                    TableColumn(Text(L.colType)) { row in Text(verbatim: row.typeName).textRole(.body) }
                    TableColumn(Text(L.colIssued)) { row in DayText(row.issueDate) }.alignment(.trailing)
                    TableColumn(Text(L.colDue)) { row in DayText(row.dueDate) }.alignment(.trailing)
                    TableColumn(Text(L.colTotal)) { row in
                        if let total = row.totalOrNil {
                            MoneyText(amount: total, currency: row.currencyCode, locale: locale)
                        } else {
                            Text(verbatim: "—").textRole(.amountSecondary)
                        }
                    }
                    .alignment(.trailing)
                    TableColumn(Text(L.colOpen)) { row in
                        MoneyText(amount: row.outstanding, currency: row.currencyCode, locale: locale,
                                  role: row.outstanding > 0 ? .amountStrong : .amount)
                    }
                    .alignment(.trailing)
                }
                .contextMenu(forSelectionType: String.self) { _ in
                    EmptyView()
                } primaryAction: { ids in
                    if ids.count == 1, let id = ids.first { openDocument?(id) }
                }
            }
            .padding(Spacing.xl)
            .navigationTitle(Text(verbatim: customer.party.name))
            // Fixed items (other-06): the New Invoice split button and Edit; no buttons in the content.
            .toolbar {
                ToolbarItem {
                    // A click makes an invoice for this client; the menu adds an advance and a copy of the
                    // client's last invoice (File ▸ New Invoice / New Advance Invoice / Duplicate in client context).
                    Menu {
                        Button { newDocument(.invoice) } label: { Text(L.newInvoice) }
                        Button { newDocument(.advanceRequest) } label: { Text(L.newAdvance) }
                        Button { duplicateLastInvoice?() } label: {
                            Text(lastInvoiceNumber.map { L.duplicateNumbered($0) } ?? L.duplicateAsDraft)
                        }
                        .disabled(duplicateLastInvoice == nil)
                    } label: {
                        Label { Text(L.newInvoice) } icon: { Image(systemName: "plus") }
                    } primaryAction: {
                        newDocument(.invoice)
                    }
                    .help(Text(L.newInvoiceForHelp(customer.party.name)))
                }
                ToolbarItem {
                    Button { editClient() } label: {
                        Label { Text(L.edit) } icon: { Image(systemName: "pencil") }
                    }
                    .help(Text(L.editThisClientHelp))
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
                    Text(L.companyIDChip(ico.digits)).textRole(.rowSecondary).textSelection(.enabled)
                }
                if let vat = party.vatIdentifier {
                    Text(L.vatIDChip(vat.value)).textRole(.rowSecondary).textSelection(.enabled)
                }
            }
            ClientDefaultsChips(customer: customer)
            // The contacts and the note, which the inspector used to show (screens-flows.md §2e).
            if party.email != nil || party.phone != nil {
                HStack(spacing: Spacing.l) {
                    if let email = party.email {
                        Text(verbatim: email).textRole(.rowSecondary).textSelection(.enabled)
                    }
                    if let phone = party.phone {
                        Text(verbatim: phone).textRole(.rowSecondary).textSelection(.enabled)
                    }
                }
            }
            if !customer.notes.isEmpty {
                Text(verbatim: customer.notes)
                    .textRole(.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func figure(_ title: LocalizedStringResource, _ monies: [Money], overdue: [Money] = []) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title).textRole(.label)
            MoneyListText(monies: monies, locale: locale, role: .amountStrong)
            let overdueSums = MoneyList.sums(overdue)
            if !overdueSums.isEmpty {
                let amounts = overdueSums
                    .map { MoneyText.format($0.amount, currency: $0.currency.code, locale: locale) }
                    .joined(separator: " + ")
                Text(L.clientOverdueAmount(amounts)).textRole(.rowSecondary)
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileSurface(radius: Radius.m)
    }

    /// The Overview's revenue rule (screens-flows.md §2a): invoices, payment tax documents, and a final
    /// invoice net of the advances its tax documents already taxed, so the two screens agree.
    private func invoicedThisYear(_ rows: [DocumentRow]) -> [Money] {
        let year = documents.today.year
        return rows.filter { $0.isIssued && $0.issueDate.year == year }
            .compactMap { OverviewFigures.revenueAmount($0.summary) }
    }
}

/// "EUR · Czech + English · EU services, reverse charge · 30 days" (other-06): the client's defaults once,
/// with the treatment in the editor's short form.
struct ClientDefaultsChips: View {
    let customer: Customer

    var body: some View {
        HStack(spacing: Spacing.s) {
            Text(verbatim: customer.currency.code).textRole(.rowSecondary)
            dot
            Text(customer.language.title).textRole(.rowSecondary)
            dot
            Text(TreatmentChoice(customer.vatStatus.defaultTreatment).shortTitle).textRole(.rowSecondary)
            dot
            Text(customer.paymentTermDays == 1 ? L.dueDaysOne : L.dueDays(customer.paymentTermDays)).textRole(.rowSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var dot: some View {
        Text(verbatim: "·").textRole(.rowSecondary).accessibilityHidden(true)
    }
}

extension CustomerVATStatus {
    var title: LocalizedStringResource {
        switch self {
        case .czechVATPayer: L.vatCzechPayer
        case .czechNonPayer: L.vatCzechNonPayer
        case .euBusinessGoods: L.vatEUBusinessGoods
        case .euBusinessServices: L.vatEUBusinessServices
        case .euConsumer: L.vatEUConsumer
        case .nonEUBusiness: L.vatNonEUBusiness
        case .nonEUConsumer: L.vatNonEUConsumer
        }
    }
}

extension DocumentLanguage {
    /// "Czech" or "Czech + English": the bilingual document, not an English one (design-system.md §9).
    var title: LocalizedStringResource {
        self == .czech ? L.languageCzech : L.languageEnglish
    }
}

/// New Client / Client details (screens-flows.md §2e, other-08, shell-23). IČO and VAT ID are checked by the
/// core's parsers; there is no online check. A new client starts with no country; until each is picked by
/// hand, the client type, the currency and the document language follow the VAT ID and the country as they
/// are typed. The Edit sheet never re-infers.
struct ClientFormSheet: View {
    let clients: ClientsModel
    let customer: Customer?
    /// The name typed into the editor's client field, prefilled for a new client.
    var initialName: String? = nil
    /// Called with the saved client's id before the sheet closes (the editor picks it into the draft).
    var onSaved: (@MainActor (String) -> Void)? = nil
    /// "Possible duplicate: … – open it?": called with the existing client's id after the sheet closes
    /// without saving.
    var onOpenExisting: (@MainActor (String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var street = ""
    @State private var city = ""
    @State private var postalCode = ""
    @State private var countryCode = ""
    @State private var ico = ""
    @State private var vatID = ""
    @State private var vatStatus: CustomerVATStatus = .euBusinessGoods
    /// False until the client type or the currency was picked by hand (other-08).
    @State private var vatStatusPicked = false
    @State private var currencyPicked = false
    @State private var email = ""
    @State private var phone = ""
    @State private var currencyCode = "EUR"
    @State private var paymentTermDays = 14
    @State private var language: DocumentLanguage = .czech
    /// False until the language was picked by hand: a new client's language follows the country, as the
    /// core's rule has it (Czech for a Czech address, Czech + English otherwise).
    @State private var languagePicked = false
    @State private var notes = ""
    @State private var error: LocalizedStringResource?

    /// The currencies Saša invoices in (decision of 5 Nov 2026).
    static let currencies: [Currency] = [.eur, .czk, .usd]

    struct CountryOption: Identifiable {
        let code: String
        let name: String
        var id: String { code }
    }

    /// Every ISO 3166 country with its English name, A to Z; the pop-up of the country field.
    static let countries: [CountryOption] = {
        let english = Locale(identifier: "en_US")
        return Locale.Region.isoRegions
            .map(\.identifier)
            .filter { $0.count == 2 }
            .compactMap { code in english.localizedString(forRegionCode: code).map { CountryOption(code: code, name: $0) } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }()

    private var currencyOptions: [Currency] {
        var list = Self.currencies
        let current = Currency.known(currencyCode)
        if !list.contains(current) { list.append(current) }
        return list
    }

    private var languageBinding: Binding<DocumentLanguage> {
        Binding(
            get: { language },
            set: { newValue in
                language = newValue
                languagePicked = true
            })
    }

    private var vatStatusBinding: Binding<CustomerVATStatus> {
        Binding(
            get: { vatStatus },
            set: { newValue in
                vatStatus = newValue
                vatStatusPicked = true
            })
    }

    private var currencyBinding: Binding<String> {
        Binding(
            get: { currencyCode },
            set: { newValue in
                currencyCode = newValue
                currencyPicked = true
            })
    }

    /// The client types in the pop-up's order (other-08): the EU business pair, a divider, the rest.
    static let euBusinessTypes: [CustomerVATStatus] = [.euBusinessGoods, .euBusinessServices]
    static let otherTypes: [CustomerVATStatus] = [.czechVATPayer, .czechNonPayer, .euConsumer, .nonEUBusiness, .nonEUConsumer]

    /// The client type a VAT ID and a country imply (other-08, shell-23): with no country yet, an EU
    /// business buying goods; otherwise the core's country rule (CustomerVATStatus.inferred), except that an
    /// EU client without a VAT ID yet is taken as an EU business buying goods, with the warning below.
    static func inferredStatus(vatID: String, countryCode: String) -> CustomerVATStatus {
        let country = countryCode.trimmingCharacters(in: .whitespaces).uppercased()
        let parsed = VATIdentifier(vatID.trimmingCharacters(in: .whitespaces))
        guard parsed != nil || !country.isEmpty else { return .euBusinessGoods }
        let status = CustomerVATStatus.inferred(vatIdentifier: parsed, countryCode: country)
        return status == .euConsumer ? .euBusinessGoods : status
    }

    /// CZK for a Czech client, EUR otherwise and while no country is set; USD only by hand.
    static func inferredCurrency(countryCode: String) -> String {
        countryCode.uppercased() == "CZ" ? Currency.czk.code : Currency.eur.code
    }

    /// True for an EU member state's ISO country code other than CZ. The VAT prefixes name Greece "EL",
    /// so "GR" is mapped as the core's CustomerVATStatus.inferred does.
    static func isEUCountryOtherThanCZ(_ countryCode: String) -> Bool {
        let country = countryCode.trimmingCharacters(in: .whitespaces).uppercased()
        guard country != "CZ" else { return false }
        return VATIdentifier.euPrefixes.contains(country == "GR" ? "EL" : country)
    }

    /// The new client's derived values, for each not yet picked by hand; the Edit sheet never re-infers.
    private func reinfer() {
        guard customer == nil else { return }
        if !vatStatusPicked { vatStatus = Self.inferredStatus(vatID: vatID, countryCode: countryCode) }
        if !currencyPicked { currencyCode = Self.inferredCurrency(countryCode: countryCode) }
        if !languagePicked { language = countryCode.uppercased() == "CZ" ? .czech : .english }
    }

    private var trimmedICO: String { ico.trimmingCharacters(in: .whitespaces) }
    private var trimmedVATID: String { vatID.trimmingCharacters(in: .whitespaces) }

    /// Another client with the same IČO or VAT ID (other-08: "Possible duplicate: Acme GmbH – open it?").
    private var possibleDuplicate: Customer? {
        let icoDigits = IdentificationNumber(trimmedICO)?.digits
        let vat = VATIdentifier(trimmedVATID)?.value
        guard icoDigits != nil || vat != nil else { return nil }
        return clients.customers.first { other in
            guard other.id != customer?.id else { return false }
            if let icoDigits, other.party.identificationNumber?.digits == icoDigits { return true }
            if let vat, other.party.vatIdentifier?.value == vat { return true }
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(customer == nil ? L.newClientTitle : L.editClientTitle).textRole(.screenTitle)
            Form {
                Section {
                    TextField(text: $name) { Text(L.fieldName) }
                    CountryPicker(code: $countryCode)
                    TextField(text: $street) { Text(L.fieldStreet) }
                    TextField(text: $city) { Text(L.fieldCity) }
                    TextField(text: $postalCode) { Text(L.fieldPostalCode) }
                }
                Section {
                    TextField(text: $ico) { Text(L.fieldICO) }
                    if !trimmedICO.isEmpty && IdentificationNumber(trimmedICO) == nil {
                        InlineMessage(L.invalidICO, kind: .problem)
                    }
                    TextField(text: $vatID) { Text(L.fieldVATID) }
                    if !trimmedVATID.isEmpty && VATIdentifier(trimmedVATID) == nil {
                        InlineMessage(L.invalidVATID, kind: .problem)
                    }
                    if let duplicate = possibleDuplicate {
                        HStack(spacing: Spacing.m) {
                            InlineMessage(L.possibleDuplicate(duplicate.party.name), kind: .problem)
                            if let onOpenExisting {
                                Button {
                                    let id = duplicate.id
                                    dismiss()
                                    onOpenExisting(id)
                                } label: { Text(L.openButton) }
                            }
                        }
                    }
                    Picker(selection: vatStatusBinding) {
                        ForEach(Self.euBusinessTypes, id: \.self) { status in
                            Text(status.title).tag(status)
                        }
                        Divider()
                        ForEach(Self.otherTypes, id: \.self) { status in
                            Text(status.title).tag(status)
                        }
                    } label: {
                        Text(L.fieldClientType)
                    }
                    // For an EU country other than CZ while the VAT ID is empty, not on the status alone
                    // (other-08, shell-23).
                    if vatStatus.isEUBusiness && Self.isEUCountryOtherThanCZ(countryCode) && trimmedVATID.isEmpty {
                        InlineMessage(vatStatus == .euBusinessGoods ? L.goodsExemptionNeedsVATID : L.reverseChargeNeedsVATID, kind: .problem)
                    }
                }
                Section {
                    TextField(text: $email) { Text(L.fieldEmail) }
                    TextField(text: $phone) { Text(L.fieldPhone) }
                }
                Section {
                    Picker(selection: currencyBinding) {
                        ForEach(currencyOptions, id: \.code) { currency in
                            Text(verbatim: currency.code).tag(currency.code)
                        }
                    } label: {
                        Text(L.fieldCurrency)
                    }
                    Stepper(value: $paymentTermDays, in: 0...365) {
                        LabeledContent { Text(verbatim: String(paymentTermDays)) } label: { Text(L.fieldPaymentTerm) }
                    }
                    Picker(selection: languageBinding) {
                        Text(L.languageCzech).tag(DocumentLanguage.czech)
                        Text(L.languageEnglish).tag(DocumentLanguage.english)
                    } label: {
                        Text(L.fieldLanguage)
                    }
                    TextField(text: $notes, axis: .vertical) { Text(L.fieldNotes) }
                        .lineLimit(2...5)
                }
                if let error {
                    InlineMessage(error)
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
        .frame(minHeight: 640)
        .formSheetSized(minWidth: 520, maxWidth: 640)
        .onAppear(perform: fill)
        .onChange(of: countryCode) { reinfer() }
        .onChange(of: vatID) { reinfer() }
    }

    private func fill() {
        guard let customer else {
            if let initialName { name = initialName }
            reinfer()
            return
        }
        let party = customer.party
        name = party.name
        street = party.address.street
        city = party.address.city
        postalCode = party.address.postalCode
        countryCode = party.address.countryCode
        ico = party.identificationNumber?.digits ?? ""
        vatID = party.vatIdentifier?.value ?? ""
        vatStatus = customer.vatStatus
        email = party.email ?? ""
        phone = party.phone ?? ""
        currencyCode = customer.currency.code
        paymentTermDays = customer.paymentTermDays
        language = customer.language
        languagePicked = true
        vatStatusPicked = true
        currencyPicked = true
        notes = customer.notes
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { error = L.nameRequired; return }
        let country = countryCode.trimmingCharacters(in: .whitespaces).uppercased()
        guard !country.isEmpty else { error = L.countryRequired; return }
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
        let address = PostalAddress(street: street, city: city, postalCode: postalCode, countryCode: country)
        // The register entry has no field here; an existing one is kept.
        let party = Party(name: trimmedName, address: address, identificationNumber: identification, vatIdentifier: vat,
                          registryEntry: customer?.party.registryEntry,
                          email: email.isEmpty ? nil : email, phone: phone.isEmpty ? nil : phone)
        let saved = Customer(id: customer?.id ?? UUID().uuidString, party: party, vatStatus: vatStatus,
                             currency: Currency.known(currencyCode), paymentTermDays: paymentTermDays,
                             language: language, notes: notes)
        do {
            try clients.stores.customers.save(saved)
            clients.reload()
            onSaved?(saved.id)
            dismiss()
        } catch {
            self.error = LocalizedStringResource(stringLiteral: ErrorText.message(error))
        }
    }
}

/// The country pop-up of the client form and the Company pane (screens-flows.md §2e): every ISO 3166
/// country by its English name. A stored code the list does not know (an old free-text entry) is added,
/// so the picker always shows the saved value.
struct CountryPicker: View {
    @Binding var code: String

    private var options: [ClientFormSheet.CountryOption] {
        var options = ClientFormSheet.countries
        if !options.contains(where: { $0.code == code }) {
            // A new client starts with no country: the explicit empty entry reads "Choose…" (shell-23).
            let name = code.isEmpty ? String(localized: L.chooseCountry) : code
            options.insert(ClientFormSheet.CountryOption(code: code, name: name), at: 0)
        }
        return options
    }

    var body: some View {
        Picker(selection: $code) {
            ForEach(options) { option in
                Text(verbatim: option.name).tag(option.code)
            }
        } label: {
            Text(L.fieldCountry)
        }
    }
}
