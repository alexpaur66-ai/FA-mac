// Settings (screens-flows.md §1.3, §2i): seven panes. Company, Bank accounts and Numbering edit the
// data layer's CompanyProfile and number series; Documents & PDF holds the document defaults, the PDF
// folder and its switches (ADR 0010); VAT defaults and Backup name what arrives with later steps. The
// window reopens on the pane viewed last, and the Overview's setup card opens the pane of its step.

import AppKit
import InvoicingCore
import InvoicingData
import SwiftUI

/// The panes, stored by name so the window reopens on the last one (screens-flows.md §1.3) and the
/// Getting started card can open a step's pane (§2j).
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, company, bank, numbering, documents, vat, backup

    static let storageKey = "settings.pane"

    var id: Self { self }
}

struct SettingsRoot: View {
    let model: AppModel

    var body: some View {
        if let stores = model.stores {
            SettingsView(stores: stores)
        } else {
            DatabaseErrorView(detail: model.openError ?? "", databaseURL: model.databaseURL)
        }
    }
}

struct SettingsView: View {
    let stores: Stores
    @AppStorage(SettingsPane.storageKey) private var pane: SettingsPane = .general

    var body: some View {
        TabView(selection: $pane) {
            GeneralPane(stores: stores)
                .tabItem { Label(String(localized: L.settingsGeneral), systemImage: "gearshape") }
                .tag(SettingsPane.general)
            CompanyPane(stores: stores)
                .tabItem { Label(String(localized: L.settingsCompany), systemImage: "building.2") }
                .tag(SettingsPane.company)
            BankAccountsPane(stores: stores)
                .tabItem { Label(String(localized: L.settingsBank), systemImage: "building.columns") }
                .tag(SettingsPane.bank)
            NumberingPane(stores: stores)
                .tabItem { Label(String(localized: L.settingsNumbering), systemImage: "number") }
                .tag(SettingsPane.numbering)
            DocumentsPane(stores: stores)
                .tabItem { Label(String(localized: L.settingsDocuments), systemImage: Symbols.document) }
                .tag(SettingsPane.documents)
            PlaceholderPane(note: L.vatPaneNote)
                .tabItem { Label(String(localized: L.settingsVAT), systemImage: "percent") }
                .tag(SettingsPane.vat)
            PlaceholderPane(note: L.backupPaneNote)
                .tabItem { Label(String(localized: L.settingsBackup), systemImage: "externaldrive") }
                .tag(SettingsPane.backup)
        }
        .frame(minWidth: 640, minHeight: 480)
    }
}

struct PlaceholderPane: View {
    let note: LocalizedStringResource

    var body: some View {
        Form {
            Text(note).textRole(.body)
        }
        .formStyle(.grouped)
    }
}

struct GeneralPane: View {
    let stores: Stores

    var body: some View {
        Form {
            Section {
                Text(L.generalLanguageNote).textRole(.body)
                Text(L.generalTextSizeNote).textRole(.body)
            }
            Section {
                LabeledContent {
                    VStack(alignment: .trailing, spacing: Spacing.xs) {
                        Text(verbatim: stores.databaseURL?.path ?? "—").textRole(.caption).textSelection(.enabled)
                        if let url = stores.databaseURL {
                            Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Text(L.showInFinder) }
                        }
                    }
                } label: {
                    Text(L.dataFolder)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Company

/// The supplier's details and the VAT status. The payment term and the footer live in Documents & PDF
/// (screens-flows.md §1.3); the bank accounts in their own pane. Save keeps what this pane does not show.
struct CompanyPane: View {
    let stores: Stores

    @State private var name = ""
    @State private var street = ""
    @State private var city = ""
    @State private var postalCode = ""
    @State private var countryCode = "CZ"
    @State private var ico = ""
    @State private var dic = ""
    @State private var court: RegistryCourt?
    @State private var registrySection = ""
    @State private var registryInsert = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var isVATPayer = true
    @State private var currencyCode = "EUR"
    /// The stored profile, so Save keeps the bank accounts, the term and the footer.
    @State private var loaded: CompanyProfile?
    /// The profile exists but could not be read: Save would overwrite it with an empty one, so it is off.
    @State private var loadFailed = false
    @State private var message: LocalizedStringResource?
    @State private var isError = false

    var body: some View {
        Form {
            Section {
                Text(L.companyNote).textRole(.caption)
            }
            Section {
                TextField(text: $name) { Text(L.fieldLegalName) }
                TextField(text: $street) { Text(L.fieldStreet) }
                TextField(text: $city) { Text(L.fieldCity) }
                TextField(text: $postalCode) { Text(L.fieldPostalCode) }
                CountryPicker(code: $countryCode)
                TextField(text: $ico) { Text(L.fieldCompanyID) }
                TextField(text: $dic) { Text(L.fieldCompanyVATID) }
                Picker(selection: $court) {
                    Text(L.noCourt).tag(RegistryCourt?.none)
                    ForEach(RegistryCourt.allCases, id: \.self) { court in
                        Text(verbatim: court.czechNominative).tag(RegistryCourt?.some(court))
                    }
                } label: {
                    Text(L.fieldRegistryCourt)
                }
                if court != nil {
                    TextField(text: $registrySection) { Text(L.fieldRegistrySection) }
                    TextField(text: $registryInsert) { Text(L.fieldRegistryInsert) }
                }
                TextField(text: $email) { Text(L.fieldEmail) }
                TextField(text: $phone) { Text(L.fieldPhone) }
            }
            Section {
                Toggle(isOn: $isVATPayer) { Text(L.fieldVATPayer) }
                Picker(selection: $currencyCode) {
                    ForEach(ClientFormSheet.currencies, id: \.code) { currency in
                        Text(verbatim: currency.code).tag(currency.code)
                    }
                } label: {
                    Text(L.fieldDefaultCurrency)
                }
            }
            Section {
                HStack {
                    if let message {
                        if isError {
                            InlineMessage(message)
                        } else {
                            Text(message).textRole(.caption)
                        }
                    }
                    Spacer()
                    Button { save() } label: { Text(L.save) }
                        .buttonStyle(.borderedProminent)
                        .disabled(loadFailed)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
    }

    private func load() {
        do {
            loaded = try stores.profile.load()
            loadFailed = false
        } catch {
            loadFailed = true
            isError = true
            message = LocalizedStringResource(stringLiteral: ErrorText.message(error))
            return
        }
        guard let profile = loaded else { return }
        let supplier = profile.supplier
        name = supplier.name
        street = supplier.address.street
        city = supplier.address.city
        postalCode = supplier.address.postalCode
        countryCode = supplier.address.countryCode
        ico = supplier.identificationNumber?.digits ?? ""
        dic = supplier.vatIdentifier?.value ?? ""
        court = supplier.registryEntry?.court
        registrySection = supplier.registryEntry?.section ?? ""
        registryInsert = supplier.registryEntry?.insert ?? ""
        email = supplier.email ?? ""
        phone = supplier.phone ?? ""
        isVATPayer = profile.isVATPayer
        currencyCode = profile.defaultCurrency.code
    }

    private func save() {
        isError = true
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { message = L.nameRequired; return }
        let country = countryCode.trimmingCharacters(in: .whitespaces).uppercased()
        guard !country.isEmpty else { message = L.countryRequired; return }
        var identification: IdentificationNumber?
        let icoText = ico.trimmingCharacters(in: .whitespaces)
        if !icoText.isEmpty {
            guard let parsed = IdentificationNumber(icoText) else { message = L.invalidICO; return }
            identification = parsed
        }
        var vat: VATIdentifier?
        let dicText = dic.trimmingCharacters(in: .whitespaces)
        if !dicText.isEmpty {
            guard let parsed = VATIdentifier(dicText) else { message = L.invalidVATID; return }
            vat = parsed
        }
        var registry: RegistryEntry?
        if let court {
            guard let entry = RegistryEntry(court: court, section: registrySection, insert: registryInsert) else {
                message = L.invalidRegistry
                return
            }
            registry = entry
        }
        let address = PostalAddress(street: street, city: city, postalCode: postalCode, countryCode: country)
        let supplier = Party(name: trimmedName, address: address, identificationNumber: identification, vatIdentifier: vat,
                             registryEntry: registry, email: email.isEmpty ? nil : email, phone: phone.isEmpty ? nil : phone)
        let profile = CompanyProfile(supplier: supplier, bankConnections: loaded?.bankConnections ?? [], isVATPayer: isVATPayer,
                                     defaultCurrency: Currency.known(currencyCode),
                                     defaultPaymentTermDays: loaded?.defaultPaymentTermDays ?? 14, footer: loaded?.footer)
        do {
            try stores.profile.save(profile)
            loaded = profile
            NotificationCenter.default.post(name: .settingsDidSave, object: nil)
            isError = false
            message = L.saved
        } catch {
            message = LocalizedStringResource(stringLiteral: ErrorText.message(error))
        }
    }
}

// MARK: - Bank accounts

struct BankAccountsPane: View {
    let stores: Stores

    /// A removed account, kept until the next change so Undo can put it back where it was.
    private struct RemovedAccount {
        let connection: BankConnection
        let index: Int
    }

    @State private var profile: CompanyProfile?
    @State private var iban = ""
    @State private var czechAccount = ""
    @State private var bic = ""
    @State private var bankName = ""
    /// Empty means any currency (the account serves every currency without its own account).
    @State private var currencyCode = ""
    @State private var removed: RemovedAccount?
    @State private var message: LocalizedStringResource?
    @State private var isError = false

    /// Any, then the currencies Saša invoices in (decision of 5 Nov 2026).
    private static let currencyCodes = [""] + ClientFormSheet.currencies.map(\.code)

    var body: some View {
        Form {
            if let profile {
                Section {
                    if profile.bankConnections.isEmpty {
                        Text(L.noAccounts).textRole(.rowSecondary)
                    }
                    ForEach(Array(profile.bankConnections.enumerated()), id: \.offset) { index, connection in
                        LabeledContent {
                            HStack {
                                Text(verbatim: connection.currency?.code ?? String(localized: L.bankCurrencyAny)).textRole(.rowSecondary)
                                Button { remove(at: index) } label: { Text(L.remove) }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(verbatim: connection.domesticLabel).textRole(.body)
                                Text(verbatim: [connection.iban.formatted, connection.bic?.value, connection.bankName]
                                    .compactMap { $0 }.joined(separator: " · "))
                                    .textRole(.caption)
                            }
                        }
                    }
                    // Remove has no confirmation: Undo puts the account back (design-system.md §10).
                    if removed != nil {
                        HStack(spacing: Spacing.m) {
                            Label { Text(L.accountRemoved) } icon: { Image(systemName: MessageKind.done.symbol).foregroundStyle(MessageKind.done.tint) }
                                .textRole(.caption)
                            Button { undoRemove() } label: { Text(L.undo) }
                        }
                    }
                    Text(L.bankNote).textRole(.caption)
                }
                Section {
                    TextField(text: $iban) { Text(L.bankIBAN) }
                    TextField(text: $czechAccount) { Text(L.bankCzechAccount) }
                    TextField(text: $bic) { Text(L.bankBIC) }
                    TextField(text: $bankName) { Text(L.bankName) }
                    Picker(selection: $currencyCode) {
                        ForEach(Self.currencyCodes, id: \.self) { code in
                            Text(code.isEmpty ? L.bankCurrencyAny : LocalizedStringResource(stringLiteral: code)).tag(code)
                        }
                    } label: {
                        Text(L.bankCurrency)
                    }
                    HStack {
                        if let message {
                            if isError {
                                InlineMessage(message)
                            } else {
                                Text(message).textRole(.caption)
                            }
                        }
                        Spacer()
                        Button { add() } label: { Text(L.add) }
                            .disabled(iban.trimmingCharacters(in: .whitespaces).isEmpty
                                      && czechAccount.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            } else {
                Text(L.companyFirst).textRole(.body)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
    }

    private func load() {
        profile = try? stores.profile.load()
    }

    private func add() {
        isError = true
        guard var updated = profile else { return }
        var parsedBIC: BIC?
        let bicText = bic.trimmingCharacters(in: .whitespaces)
        if !bicText.isEmpty {
            guard let parsed = BIC(bicText) else { message = L.invalidBIC; return }
            parsedBIC = parsed
        }
        let currency: Currency? = currencyCode.isEmpty ? nil : Currency.known(currencyCode)
        let name = bankName.trimmingCharacters(in: .whitespaces)
        let connection: BankConnection
        let ibanText = iban.trimmingCharacters(in: .whitespaces)
        if !ibanText.isEmpty {
            guard let parsedIBAN = IBAN(ibanText) else { message = L.invalidIBAN; return }
            connection = BankConnection(iban: parsedIBAN, bic: parsedBIC, bankName: name.isEmpty ? nil : name, currency: currency)
        } else {
            guard let account = CzechBankAccount(parsing: czechAccount.trimmingCharacters(in: .whitespaces)),
                  let fromAccount = BankConnection(czech: account, bic: parsedBIC, bankName: name.isEmpty ? nil : name, currency: currency)
            else { message = L.invalidCzechAccount; return }
            connection = fromAccount
        }
        updated.bankConnections.append(connection)
        removed = nil
        store(updated)
        if !isError {
            iban = ""
            czechAccount = ""
            bic = ""
            bankName = ""
            currencyCode = ""
        }
    }

    private func remove(at index: Int) {
        guard var updated = profile, updated.bankConnections.indices.contains(index) else { return }
        let connection = updated.bankConnections.remove(at: index)
        store(updated)
        if !isError {
            removed = RemovedAccount(connection: connection, index: index)
            message = nil
        }
    }

    private func undoRemove() {
        guard var updated = profile, let removed else { return }
        updated.bankConnections.insert(removed.connection, at: min(removed.index, updated.bankConnections.count))
        store(updated)
        if !isError {
            self.removed = nil
        }
    }

    private func store(_ updated: CompanyProfile) {
        do {
            try stores.profile.save(updated)
            profile = updated
            NotificationCenter.default.post(name: .settingsDidSave, object: nil)
            isError = false
            message = L.saved
        } catch {
            isError = true
            message = LocalizedStringResource(stringLiteral: ErrorText.message(error))
        }
    }
}

// MARK: - Numbering

struct NumberingPane: View {
    let stores: Stores

    @State private var series: [StoredNumberSeries] = []
    @State private var editing: SeriesDraft?
    @State private var message: LocalizedStringResource?
    @State private var isError = false

    var body: some View {
        Form {
            Section {
                if series.isEmpty {
                    Text(L.noSeries).textRole(.rowSecondary)
                    Button { createDefaults() } label: { Text(L.createDefaultSeries) }
                    Text(L.defaultSeriesCaption).textRole(.caption)
                }
                ForEach(series) { stored in
                    LabeledContent {
                        HStack(spacing: Spacing.m) {
                            Text(verbatim: nextNumber(stored)).textRole(.amount)
                            Button { editing = SeriesDraft(stored) } label: { Text(L.edit) }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(verbatim: stored.name).textRole(.body)
                            Text(verbatim: stored.series.pattern.template + " · "
                                 + kindsText(stored) + (stored.series.variableSymbolPrefix.map { " · VS " + $0 + "…" } ?? ""))
                                .textRole(.caption)
                        }
                    }
                }
                if numbersCollide {
                    InlineMessage(L.seriesNumbersCollide, kind: .problem)
                }
                if collides {
                    InlineMessage(L.seriesPrefixCollision, kind: .problem)
                }
            } header: {
                Text(L.seriesTitle)
            }
            Section {
                HStack {
                    if let message {
                        if isError {
                            InlineMessage(message)
                        } else {
                            Text(message).textRole(.caption)
                        }
                    }
                    Spacer()
                    Button { editing = SeriesDraft() } label: { Text(L.newSeries) }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
        .sheet(item: $editing) { draft in
            SeriesFormSheet(stores: stores, draft: draft, others: series.filter { $0.id != draft.id }) {
                load()
            }
        }
    }

    private func load() {
        do {
            series = try stores.series.all()
        } catch {
            isError = true
            message = LocalizedStringResource(stringLiteral: ErrorText.message(error))
        }
    }

    private func nextNumber(_ stored: StoredNumberSeries) -> String {
        (try? stores.series.peekNextNumber(seriesID: stored.id, on: CalendarDay(Date(), in: .current))) ?? "—"
    }

    private func kindsText(_ stored: StoredNumberSeries) -> String {
        let kinds = DocumentKind.allCases.filter { stored.numbers($0) }
        return kinds.map { String(localized: $0.shortTitle) }.joined(separator: ", ")
    }

    /// Two series whose numbers give one variable symbol (ADR 0003 addendum): "FV 2026-0042" and
    /// "ZF 2026-0042" both become 20260042, so the check compares the symbols of a sample number.
    private var collides: Bool {
        var seen: Set<String> = []
        for stored in series {
            guard let symbol = SeriesFormSheet.sampleVariableSymbol(template: stored.series.pattern.template,
                                                                     prefix: stored.series.variableSymbolPrefix) else { continue }
            if !seen.insert(symbol).inserted { return true }
        }
        return false
    }

    /// Two series that issue the same document numbers ("FV {YYYY}-{NNNN}" twice, with other VS prefixes):
    /// the second one's first number already exists, so issuing from it would fail.
    private var numbersCollide: Bool {
        var seen: Set<String> = []
        for stored in series {
            guard let number = SeriesFormSheet.sampleNumber(template: stored.series.pattern.template) else { continue }
            if !seen.insert(number).inserted { return true }
        }
        return false
    }

    /// FV with prefix 1 for invoices and final invoices, ZF with prefix 2 for advance requests, DD without
    /// a prefix for payment tax documents (screens-flows.md §2i; decision of 5 Nov 2026). English names:
    /// the UI is English, the Czech titles stay on the PDF.
    private func createDefaults() {
        let year = CalendarDay(Date(), in: .current).year
        do {
            let defaults: [(String, String, Set<DocumentKind>, String?, LocalizedStringResource)] = [
                ("invoice", "FV {YYYY}-{NNNN}", [.invoice, .finalInvoice], "1", L.defaultSeriesInvoices),
                ("advance", "ZF {YYYY}-{NNNN}", [.advanceRequest], "2", L.defaultSeriesAdvances),
                ("paymentReceipt", "DD {YYYY}-{NNNN}", [.paymentTaxDocument], nil, L.defaultSeriesReceipts),
            ]
            for (id, template, kinds, prefix, name) in defaults {
                let numbering = try DocumentNumberSeries(id: id, pattern: DocumentNumberPattern(template: template),
                                                         year: year, variableSymbolPrefix: prefix)
                try stores.series.save(StoredNumberSeries(name: String(localized: name), kinds: kinds, series: numbering))
            }
            NotificationCenter.default.post(name: .settingsDidSave, object: nil)
            isError = false
            message = L.saved
            load()
        } catch {
            isError = true
            message = LocalizedStringResource(stringLiteral: ErrorText.message(error))
        }
    }
}

/// The editable fields of one series.
struct SeriesDraft: Identifiable, Hashable {
    var id: String
    var isNew: Bool
    var name = ""
    var template = "FV {YYYY}-{NNNN}"
    var kinds: Set<DocumentKind> = [.invoice, .finalInvoice]
    var year: Int
    var lastCounter = 0
    var lastIssuedYear: Int?
    var resetsYearly = true
    var prefix = ""

    init() {
        id = UUID().uuidString
        isNew = true
        year = CalendarDay(Date(), in: .current).year
    }

    init(_ stored: StoredNumberSeries) {
        id = stored.id
        isNew = false
        name = stored.name
        template = stored.series.pattern.template
        kinds = stored.kinds
        year = stored.series.year
        lastCounter = stored.series.lastCounter
        lastIssuedYear = stored.series.lastIssuedYear
        resetsYearly = stored.series.resetsYearly
        prefix = stored.series.variableSymbolPrefix ?? ""
    }

    /// The app issued a number from this series: its year and counter are no longer edited here
    /// (screens-flows.md §2i).
    var isLocked: Bool { lastIssuedYear != nil }
}

struct SeriesFormSheet: View {
    let stores: Stores
    @State var draft: SeriesDraft
    /// The other stored series, for the variable-symbol collision check.
    let others: [StoredNumberSeries]
    let onSave: @MainActor () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var error: LocalizedStringResource?

    private let currentYear = CalendarDay(Date(), in: .current).year

    init(stores: Stores, draft: SeriesDraft, others: [StoredNumberSeries], onSave: @escaping @MainActor () -> Void) {
        self.stores = stores
        _draft = State(initialValue: draft)
        self.others = others
        self.onSave = onSave
    }

    private enum Preview {
        case ready(number: String, symbol: String)
        case invalid(String)
    }

    /// The next number as the store would assign it today (the same rule as the list), with its variable
    /// symbol; or why the series is not valid yet.
    private func preview() -> Preview {
        do {
            let series = try buildSeries()
            let number = try series.peek(on: CalendarDay(Date(), in: .current))
            let symbol = PaymentSymbol.variable(fromDocumentNumber: number, prefix: series.variableSymbolPrefix)?.digits ?? "—"
            return .ready(number: number, symbol: symbol)
        } catch {
            return .invalid(ErrorText.message(error))
        }
    }

    /// The variable symbol a series gives the sample number of 2026 with counter 42; two series with the
    /// same digits would give two documents one symbol (ADR 0003 addendum, screens-flows.md §2i).
    static func sampleVariableSymbol(template: String, prefix: String?) -> String? {
        guard let pattern = try? DocumentNumberPattern(template: template) else { return nil }
        let number = pattern.format(year: 2026, counter: 42)
        return PaymentSymbol.variable(fromDocumentNumber: number, prefix: prefix)?.digits
    }

    /// The sample number of 2026 with counter 42; two series with the same one issue the same document
    /// numbers. Nil while the template is not valid.
    static func sampleNumber(template: String) -> String? {
        guard let pattern = try? DocumentNumberPattern(template: template) else { return nil }
        return pattern.format(year: 2026, counter: 42)
    }

    /// The stored series whose document numbers this draft would repeat, if any.
    private var numberCollidingSeries: StoredNumberSeries? {
        guard let mine = Self.sampleNumber(template: draft.template) else { return nil }
        return others.first { other in Self.sampleNumber(template: other.series.pattern.template) == mine }
    }

    /// The stored series this draft would collide with, if any.
    private var collidingSeries: StoredNumberSeries? {
        let prefix = draft.prefix.trimmingCharacters(in: .whitespaces)
        guard let mine = Self.sampleVariableSymbol(template: draft.template, prefix: prefix.isEmpty ? nil : prefix) else { return nil }
        return others.first { other in
            Self.sampleVariableSymbol(template: other.series.pattern.template, prefix: other.series.variableSymbolPrefix) == mine
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(L.seriesTitle).textRole(.screenTitle)
            Form {
                TextField(text: $draft.name) { Text(L.seriesName) }
                TextField(text: $draft.template) { Text(L.seriesTemplate) }
                if let patternError {
                    InlineMessage(patternError)
                }
                Section {
                    ForEach(DocumentKind.allCases, id: \.self) { kind in
                        Toggle(isOn: Binding(
                            get: { draft.kinds.contains(kind) },
                            set: { on in if on { draft.kinds.insert(kind) } else { draft.kinds.remove(kind) } })) {
                            Text(verbatim: kind.pickerTitle)
                        }
                    }
                    Text(L.seriesKindsCaption).textRole(.caption)
                } header: {
                    Text(L.seriesKinds)
                }
                if draft.isLocked {
                    // Numbers were issued: the year and the counter are read-only (screens-flows.md §2i).
                    LabeledContent { Text(verbatim: String(draft.year)).textRole(.amount) } label: { Text(L.seriesYear) }
                    LabeledContent { Text(verbatim: String(draft.lastCounter)).textRole(.amount) } label: { Text(L.seriesLastCounter) }
                    Text(L.seriesLockedNote).textRole(.caption)
                } else {
                    Stepper(value: $draft.year, in: 2000...max(2000, currentYear)) {
                        LabeledContent { Text(verbatim: String(draft.year)) } label: { Text(L.seriesYear) }
                    }
                    if draft.year > currentYear {
                        InlineMessage(L.seriesYearInFuture)
                    }
                    TextField(value: $draft.lastCounter, format: IntegerFormatStyle<Int>.number.grouping(.never)) {
                        Text(L.seriesLastCounter)
                    }
                    Text(L.seriesLastCounterNote).textRole(.caption)
                }
                Toggle(isOn: $draft.resetsYearly) { Text(L.seriesResetsYearly) }
                TextField(text: $draft.prefix) { Text(L.seriesVSPrefix) }
                switch preview() {
                case .ready(let number, let symbol):
                    LabeledContent { Text(verbatim: number).textRole(.amount) } label: { Text(L.seriesNext) }
                    LabeledContent { Text(verbatim: symbol).textRole(.amount) } label: { Text(L.seriesVSPreview) }
                case .invalid(let text):
                    if patternError == nil {
                        InlineMessage(text)
                    }
                }
                if let other = numberCollidingSeries {
                    InlineMessage(L.seriesNumberCollisionWith(other.name), kind: .problem)
                } else if let other = collidingSeries {
                    InlineMessage(L.seriesCollisionWith(other.name), kind: .problem)
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
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty || draft.kinds.isEmpty)
            }
        }
        .padding(Spacing.xl)
        .frame(minHeight: 600)
        .formSheetSized(minWidth: 520, maxWidth: 640)
    }

    /// The pattern's own problem, under the template field, where the preview would just disappear.
    private var patternError: String? {
        do {
            _ = try DocumentNumberPattern(template: draft.template)
            return nil
        } catch {
            return ErrorText.message(error)
        }
    }

    private func buildSeries() throws -> DocumentNumberSeries {
        let prefix = draft.prefix.trimmingCharacters(in: .whitespaces)
        return try DocumentNumberSeries(
            id: draft.id, pattern: DocumentNumberPattern(template: draft.template), resetsYearly: draft.resetsYearly,
            year: draft.year, lastCounter: max(0, draft.lastCounter), lastIssuedYear: draft.lastIssuedYear,
            variableSymbolPrefix: prefix.isEmpty ? nil : prefix)
    }

    private func save() {
        do {
            let numbering = try buildSeries()
            let name = draft.name.trimmingCharacters(in: .whitespaces)
            try stores.series.save(StoredNumberSeries(name: name, kinds: draft.kinds, series: numbering))
            onSave()
            NotificationCenter.default.post(name: .settingsDidSave, object: nil)
            // A counter never goes backwards: when the store kept its own year or counter, say so and stay open.
            if let stored = try stores.series.series(id: draft.id),
               stored.series.year != numbering.year || stored.series.lastCounter != numbering.lastCounter {
                draft = SeriesDraft(stored)
                error = L.seriesStoreKeptCounter
                return
            }
            dismiss()
        } catch {
            self.error = LocalizedStringResource(stringLiteral: ErrorText.message(error))
        }
    }
}

extension Notification.Name {
    /// Posted after Settings wrote the company profile, a bank account, a number series or the document
    /// defaults, so an open draft editor re-reads them at once (design check E024).
    static let settingsDidSave = Notification.Name("FA.settingsDidSave")
}
