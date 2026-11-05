// Settings (screens-flows.md §1.3, §2i): seven panes. Company, Bank accounts and Numbering edit the
// data layer's CompanyProfile and number series; the other panes name what arrives with later steps.

import AppKit
import InvoicingCore
import InvoicingData
import SwiftUI

struct SettingsRoot: View {
    let model: AppModel

    var body: some View {
        if let stores = model.stores {
            SettingsView(stores: stores)
        } else {
            DatabaseErrorView(detail: model.openError ?? "")
        }
    }
}

struct SettingsView: View {
    let stores: Stores

    var body: some View {
        TabView {
            GeneralPane(stores: stores)
                .tabItem { Label(String(localized: L.settingsGeneral), systemImage: "gearshape") }
            CompanyPane(stores: stores)
                .tabItem { Label(String(localized: L.settingsCompany), systemImage: "building.2") }
            BankAccountsPane(stores: stores)
                .tabItem { Label(String(localized: L.settingsBank), systemImage: "building.columns") }
            NumberingPane(stores: stores)
                .tabItem { Label(String(localized: L.settingsNumbering), systemImage: "number") }
            PlaceholderPane(note: L.documentsPaneNote)
                .tabItem { Label(String(localized: L.settingsDocuments), systemImage: Symbols.document) }
            PlaceholderPane(note: L.vatPaneNote)
                .tabItem { Label(String(localized: L.settingsVAT), systemImage: "percent") }
            PlaceholderPane(note: L.backupPaneNote)
                .tabItem { Label(String(localized: L.settingsBackup), systemImage: "externaldrive") }
        }
        .frame(minWidth: 620, minHeight: 440)
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
    @State private var currencyCode = "CZK"
    @State private var termDays = 14
    @State private var footer = ""
    @State private var bankConnections: [BankConnection] = []
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
                TextField(text: $countryCode) { Text(L.fieldCountry) }
                TextField(text: $ico) { Text(L.fieldICO) }
                TextField(text: $dic) { Text(L.fieldVATID) }
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
                Stepper(value: $termDays, in: 0...365) {
                    LabeledContent { Text(verbatim: String(termDays)) } label: { Text(L.fieldDefaultTerm) }
                }
                TextField(text: $footer, axis: .vertical) { Text(L.fieldFooter) }
                    .lineLimit(2...4)
            }
            Section {
                HStack {
                    if let message {
                        Text(message).textRole(.caption).foregroundStyle(isError ? Color.red : Color.secondary)
                    }
                    Spacer()
                    Button { save() } label: { Text(L.save) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
    }

    private func load() {
        guard let profile = try? stores.profile.load() else { return }
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
        termDays = profile.defaultPaymentTermDays
        footer = profile.footer ?? ""
        bankConnections = profile.bankConnections
    }

    private func save() {
        isError = true
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { message = L.nameRequired; return }
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
        let address = PostalAddress(street: street, city: city, postalCode: postalCode,
                                    countryCode: countryCode.trimmingCharacters(in: .whitespaces).uppercased())
        let supplier = Party(name: trimmedName, address: address, identificationNumber: identification, vatIdentifier: vat,
                             registryEntry: registry, email: email.isEmpty ? nil : email, phone: phone.isEmpty ? nil : phone)
        let trimmedFooter = footer.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = CompanyProfile(supplier: supplier, bankConnections: bankConnections, isVATPayer: isVATPayer,
                                     defaultCurrency: Currency.known(currencyCode), defaultPaymentTermDays: termDays,
                                     footer: trimmedFooter.isEmpty ? nil : trimmedFooter)
        do {
            try stores.profile.save(profile)
            isError = false
            message = L.saved
        } catch {
            message = LocalizedStringResource(stringLiteral: String(describing: error))
        }
    }
}

// MARK: - Bank accounts

struct BankAccountsPane: View {
    let stores: Stores

    @State private var profile: CompanyProfile?
    @State private var iban = ""
    @State private var czechAccount = ""
    @State private var bic = ""
    @State private var bankName = ""
    @State private var currencyCode = ""
    @State private var message: LocalizedStringResource?
    @State private var isError = false

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
                                Text(verbatim: connection.currency?.code ?? "—").textRole(.rowSecondary)
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
                    Text(L.bankNote).textRole(.caption)
                }
                Section {
                    TextField(text: $iban) { Text(L.bankIBAN) }
                    TextField(text: $czechAccount) { Text(L.bankCzechAccount) }
                    TextField(text: $bic) { Text(L.bankBIC) }
                    TextField(text: $bankName) { Text(L.bankName) }
                    TextField(text: $currencyCode) { Text(L.bankCurrency) }
                    HStack {
                        if let message {
                            Text(message).textRole(.caption).foregroundStyle(isError ? Color.red : Color.secondary)
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
        let currencyText = currencyCode.trimmingCharacters(in: .whitespaces).uppercased()
        let currency: Currency? = currencyText.isEmpty ? nil : Currency.known(currencyText)
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
        updated.bankConnections.remove(at: index)
        store(updated)
    }

    private func store(_ updated: CompanyProfile) {
        do {
            try stores.profile.save(updated)
            profile = updated
            isError = false
            message = L.saved
        } catch {
            isError = true
            message = LocalizedStringResource(stringLiteral: String(describing: error))
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
                if collides {
                    Label { Text(L.seriesPrefixCollision) } icon: { Image(systemName: "exclamationmark.triangle") }
                        .textRole(.caption)
                }
            } header: {
                Text(L.seriesTitle)
            }
            Section {
                HStack {
                    if let message {
                        Text(message).textRole(.caption).foregroundStyle(isError ? Color.red : Color.secondary)
                    }
                    Spacer()
                    Button { editing = SeriesDraft() } label: { Text(L.newSeries) }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
        .sheet(item: $editing) { draft in
            SeriesFormSheet(stores: stores, draft: draft) {
                load()
            }
        }
    }

    private func load() {
        do {
            series = try stores.series.all()
        } catch {
            isError = true
            message = LocalizedStringResource(stringLiteral: String(describing: error))
        }
    }

    private func nextNumber(_ stored: StoredNumberSeries) -> String {
        (try? stores.series.peekNextNumber(seriesID: stored.id, on: CalendarDay(Date(), in: .current))) ?? "—"
    }

    private func kindsText(_ stored: StoredNumberSeries) -> String {
        let kinds = DocumentKind.allCases.filter { stored.numbers($0) }
        return kinds.map { String(localized: $0.shortTitle) }.joined(separator: ", ")
    }

    /// Two series with the same template and the same prefix (or none) give two documents one variable
    /// symbol (ADR 0003 addendum).
    private var collides: Bool {
        var seen: Set<String> = []
        for stored in series {
            let key = stored.series.pattern.template + "|" + (stored.series.variableSymbolPrefix ?? "")
            if !seen.insert(key).inserted { return true }
        }
        return false
    }

    /// FV with prefix 1 for invoices and final invoices, ZF with prefix 2 for advance requests, DD without
    /// a prefix for payment tax documents (screens-flows.md §2i).
    private func createDefaults() {
        let year = CalendarDay(Date(), in: .current).year
        do {
            let defaults: [(String, String, Set<DocumentKind>, String?, String)] = [
                ("invoice", "FV {YYYY}-{NNNN}", [.invoice, .finalInvoice], "1", "Faktury"),
                ("advance", "ZF {YYYY}-{NNNN}", [.advanceRequest], "2", "Zálohové faktury"),
                ("paymentReceipt", "DD {YYYY}-{NNNN}", [.paymentTaxDocument], nil, "Daňové doklady k platbě"),
            ]
            for (id, template, kinds, prefix, name) in defaults {
                let numbering = try DocumentNumberSeries(id: id, pattern: DocumentNumberPattern(template: template),
                                                         year: year, variableSymbolPrefix: prefix)
                try stores.series.save(StoredNumberSeries(name: name, kinds: kinds, series: numbering))
            }
            isError = false
            message = L.saved
            load()
        } catch {
            isError = true
            message = LocalizedStringResource(stringLiteral: String(describing: error))
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
}

struct SeriesFormSheet: View {
    let stores: Stores
    @State var draft: SeriesDraft
    let onSave: @MainActor () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var error: LocalizedStringResource?

    init(stores: Stores, draft: SeriesDraft, onSave: @escaping @MainActor () -> Void) {
        self.stores = stores
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    private var preview: (number: String, symbol: String)? {
        guard let pattern = try? DocumentNumberPattern(template: draft.template) else { return nil }
        let number = pattern.format(year: draft.year, counter: draft.lastCounter + 1)
        let prefix = draft.prefix.trimmingCharacters(in: .whitespaces)
        let symbol = PaymentSymbol.variable(fromDocumentNumber: number, prefix: prefix.isEmpty ? nil : prefix)?.digits ?? "—"
        return (number, symbol)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(L.seriesTitle).textRole(.screenTitle)
            Form {
                TextField(text: $draft.name) { Text(L.seriesName) }
                TextField(text: $draft.template) { Text(L.seriesTemplate) }
                Section {
                    ForEach(DocumentKind.allCases, id: \.self) { kind in
                        Toggle(isOn: Binding(
                            get: { draft.kinds.contains(kind) },
                            set: { on in if on { draft.kinds.insert(kind) } else { draft.kinds.remove(kind) } })) {
                            Text(verbatim: kind.title(language: .czech))
                        }
                    }
                } header: {
                    Text(L.seriesKinds)
                }
                Stepper(value: $draft.year, in: 2000...2100) {
                    LabeledContent { Text(verbatim: String(draft.year)) } label: { Text(L.seriesYear) }
                }
                TextField(value: $draft.lastCounter, format: IntegerFormatStyle<Int>.number.grouping(.never)) {
                    Text(L.seriesLastCounter)
                }
                Text(L.seriesLastCounterNote).textRole(.caption)
                Toggle(isOn: $draft.resetsYearly) { Text(L.seriesResetsYearly) }
                TextField(text: $draft.prefix) { Text(L.seriesVSPrefix) }
                if let preview {
                    LabeledContent { Text(verbatim: preview.number).textRole(.amount) } label: { Text(L.seriesNext) }
                    LabeledContent { Text(verbatim: preview.symbol).textRole(.amount) } label: { Text(L.seriesVSPreview) }
                }
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
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty || draft.kinds.isEmpty)
            }
        }
        .padding(Spacing.xl)
        .frame(minWidth: 480, minHeight: 520)
    }

    private func save() {
        do {
            let prefix = draft.prefix.trimmingCharacters(in: .whitespaces)
            let numbering = try DocumentNumberSeries(
                id: draft.id, pattern: DocumentNumberPattern(template: draft.template), resetsYearly: draft.resetsYearly,
                year: draft.year, lastCounter: max(0, draft.lastCounter), lastIssuedYear: draft.lastIssuedYear,
                variableSymbolPrefix: prefix.isEmpty ? nil : prefix)
            try stores.series.save(StoredNumberSeries(name: draft.name.trimmingCharacters(in: .whitespaces), kinds: draft.kinds, series: numbering))
            onSave()
            dismiss()
        } catch {
            self.error = LocalizedStringResource(stringLiteral: String(describing: error))
        }
    }
}
