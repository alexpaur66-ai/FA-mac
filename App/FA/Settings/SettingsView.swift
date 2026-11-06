// Settings (screens-flows.md §1.3, §2i; lean pass set-01): four panes. General holds the PDF folder;
// Company, Bank Accounts and Numbering edit the data layer's CompanyProfile and number series. The VAT
// rules, the document defaults and the PDF switches are fixed rules (set-02, set-04, set-07). Every pane
// but Numbering applies a field as soon as it is committed (settlement 9). The window reopens on the pane
// viewed last, and the Overview's setup card opens the pane of its step.

import AppKit
import Combine
import InvoicingCore
import InvoicingData
import SwiftUI

/// The panes, stored by name so the window reopens on the last one (screens-flows.md §1.3) and the
/// Getting started card can open a step's pane (§2j). A stored name of a removed pane ("documents", "vat",
/// "backup") is no case, so @AppStorage falls back to General.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, company, bank, numbering

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
            GeneralPane()
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
        }
        .frame(minWidth: 640, minHeight: 480)
    }
}

// MARK: - General

/// The PDF folder (set-03, set-04): a chosen folder means each issued document's PDF is saved there at
/// Issue, as ‹folder›/‹year›/‹number› ‹client›.pdf; without one the PDF stays in the app until Save PDF….
/// The folder is a security-scoped bookmark the user grants through the open panel (ADR 0010). The backup
/// folder joins this pane with the backup step.
struct GeneralPane: View {
    @State private var folderURL: URL?
    @State private var message: String?
    @Environment(\.locale) private var locale

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    VStack(alignment: .trailing, spacing: Spacing.xs) {
                        if let folderURL {
                            Text(verbatim: PDFSettings.displayPath(folderURL)).textRole(.caption).textSelection(.enabled)
                        }
                        HStack(spacing: Spacing.s) {
                            if folderURL != nil {
                                Button { forgetFolder() } label: { Text(L.clearFolder) }
                            }
                            Button { chooseFolder() } label: { Text(L.chooseFolder) }
                        }
                    }
                } label: {
                    Text(L.pdfFolder)
                }
                Text(caption).textRole(.caption)
                if let message {
                    InlineMessage(message)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { folderURL = PDFSettings.folderURL() }
    }

    /// "Issued documents are saved as 2026/FV 2026-0042 Acme GmbH.pdf." with the current year, or the line
    /// that says where the PDF stays without a folder.
    private var caption: LocalizedStringResource {
        guard folderURL != nil else { return L.pdfFolderCaptionNone }
        return L.pdfFolderCaption(String(CalendarDay(Date(), in: .current).year))
    }

    private func chooseFolder() {
        do {
            if let url = try PDFFiles.chooseFolder() {
                folderURL = url
                message = nil
            }
        } catch {
            message = ErrorText.message(error, locale: locale)
        }
    }

    private func forgetFolder() {
        do {
            try PDFSettings.setFolder(nil)
            folderURL = nil
            message = nil
        } catch {
            message = ErrorText.message(error, locale: locale)
        }
    }
}

// MARK: - Company

/// The supplier's details and the footer, as one form without a Save button (set-06, settlement 9): each
/// field is stored when it is committed (↩, focus moving on, a pop-up choice, the pane closing). A value
/// that is not valid shows its message under the field and stays in the field; the stored profile keeps
/// its previous value for that field. The VAT payer status is fixed (always a payer) and a draft without a
/// client starts in EUR (set-07); the bank accounts live in their own pane.
struct CompanyPane: View {
    let stores: Stores

    private enum Field: Hashable {
        case name, street, city, postalCode, ico, dic, fileNumber, email, phone, footer
    }

    @State private var name = ""
    @State private var street = ""
    @State private var city = ""
    @State private var postalCode = ""
    @State private var countryCode = "CZ"
    @State private var ico = ""
    @State private var dic = ""
    @State private var court: RegistryCourt?
    @State private var fileNumber = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var footer = ""
    /// The profile as last read or stored; a commit that changes nothing writes nothing.
    @State private var loaded: CompanyProfile?
    /// The pane has read the profile; commits before that would store the empty fields.
    @State private var isLoaded = false
    /// The profile exists but could not be read: storing would overwrite it, so nothing is stored.
    @State private var loadFailed = false
    @State private var problems: [Field: LocalizedStringResource] = [:]
    @State private var failure: String?
    @FocusState private var focus: Field?
    @Environment(\.locale) private var locale
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        Form {
            Section {
                Text(L.companyNote).textRole(.caption)
            }
            Section {
                field(.name, $name, L.fieldLegalName)
                field(.street, $street, L.fieldStreet)
                field(.city, $city, L.fieldCity)
                field(.postalCode, $postalCode, L.fieldPostalCode)
                CountryPicker(code: $countryCode)
                field(.ico, $ico, L.fieldCompanyID)
                field(.dic, $dic, L.fieldCompanyVATID)
                Picker(selection: $court) {
                    Text(L.noCourt).tag(RegistryCourt?.none)
                    ForEach(RegistryCourt.allCases, id: \.self) { court in
                        Text(verbatim: court.czechNominative).tag(RegistryCourt?.some(court))
                    }
                } label: {
                    Text(L.fieldRegistryCourt)
                }
                if court != nil {
                    field(.fileNumber, $fileNumber, L.fieldFileNumber, prompt: L.fileNumberPrompt)
                }
                field(.email, $email, L.fieldEmail)
                field(.phone, $phone, L.fieldPhone)
            }
            Section {
                TextField(text: $footer, axis: .vertical) { Text(L.fieldFooter) }
                    .lineLimit(2...5)
                    .focused($focus, equals: .footer)
            } header: {
                Text(L.footerSection)
            }
            if let failure {
                Section {
                    InlineMessage(failure)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(loadFailed)
        .onAppear(perform: load)
        .onDisappear(perform: commit)
        .onSubmit(commit)
        .onChange(of: focus) { old, _ in
            if old != nil { commit() }
        }
        .onChange(of: countryCode) { commit() }
        .onChange(of: court) { commit() }
        // Leaving the Settings window keeps the field's focus, so the window resigning key commits too, before
        // the main window uses the profile; Quit runs no onDisappear (AppKit posts on the main thread).
        .onChange(of: activeState) { _, state in
            if state != .key { commit() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            commit()
        }
    }

    @ViewBuilder
    private func field(_ field: Field, _ text: Binding<String>, _ label: LocalizedStringResource,
                       prompt: LocalizedStringResource? = nil) -> some View {
        TextField(text: text, prompt: prompt.map { Text($0) }) { Text(label) }
            .focused($focus, equals: field)
        if let problem = problems[field] {
            InlineMessage(problem)
        }
    }

    private func load() {
        isLoaded = false
        do {
            loaded = try stores.profile.load()
            loadFailed = false
        } catch {
            loadFailed = true
            failure = ErrorText.message(error, locale: locale)
            return
        }
        problems = [:]
        failure = nil
        if let profile = loaded {
            let supplier = profile.supplier
            name = supplier.name
            street = supplier.address.street
            city = supplier.address.city
            postalCode = supplier.address.postalCode
            countryCode = supplier.address.countryCode
            ico = supplier.identificationNumber?.digits ?? ""
            dic = supplier.vatIdentifier?.value ?? ""
            court = supplier.registryEntry?.court
            fileNumber = supplier.registryEntry?.fileNumber ?? ""
            email = supplier.email ?? ""
            phone = supplier.phone ?? ""
            footer = profile.footer ?? ""
        }
        isLoaded = true
    }

    /// Stores what the fields hold. A field that is not valid keeps the stored value and shows why; a
    /// company without a name is not stored yet, because every document needs the supplier's name.
    private func commit() {
        guard isLoaded, !loadFailed else { return }
        var problems: [Field: LocalizedStringResource] = [:]
        let previous = loaded?.supplier
        func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

        var legalName = trimmed(name)
        if legalName.isEmpty {
            problems[.name] = L.nameRequired
            legalName = previous?.name ?? ""
        }
        var identification = previous?.identificationNumber
        if trimmed(ico).isEmpty {
            identification = nil
        } else if let parsed = IdentificationNumber(trimmed(ico)) {
            identification = parsed
        } else {
            problems[.ico] = L.invalidICO
        }
        var vat = previous?.vatIdentifier
        if trimmed(dic).isEmpty {
            vat = nil
        } else if let parsed = VATIdentifier(trimmed(dic)) {
            vat = parsed
        } else {
            problems[.dic] = L.invalidVATID
        }
        // A court without a file number yet stores no entry and asks for nothing until a number is typed.
        var registry: RegistryEntry?
        if let court, !trimmed(fileNumber).isEmpty {
            if var stored = previous?.registryEntry, trimmed(fileNumber) == stored.fileNumber {
                // The stored entry as the pane shows it: kept even when an older form stored an insert this
                // field would not take, such as "12345/A".
                stored.court = court
                registry = stored
            } else if let parsed = RegistryEntry(court: court, fileNumber: fileNumber) {
                registry = parsed
            } else {
                problems[.fileNumber] = L.invalidFileNumber
                registry = previous?.registryEntry
            }
        }
        self.problems = problems
        guard !legalName.isEmpty else { return }

        do {
            // Read again, so the accounts the Bank Accounts pane changed meanwhile are kept.
            let current = try stores.profile.load()
            let country = countryCode.trimmingCharacters(in: .whitespaces).uppercased()
            let address = PostalAddress(street: trimmed(street), city: trimmed(city), postalCode: trimmed(postalCode),
                                        countryCode: country.isEmpty ? (previous?.address.countryCode ?? "CZ") : country)
            let supplier = Party(name: legalName, address: address, identificationNumber: identification, vatIdentifier: vat,
                                 registryEntry: registry, email: trimmed(email).isEmpty ? nil : trimmed(email),
                                 phone: trimmed(phone).isEmpty ? nil : trimmed(phone))
            let footerText = trimmed(footer)
            let profile = CompanyProfile(supplier: supplier, bankConnections: current?.bankConnections ?? [], isVATPayer: true,
                                         defaultCurrency: current?.defaultCurrency ?? .eur,
                                         defaultPaymentTermDays: current?.defaultPaymentTermDays ?? 14,
                                         footer: footerText.isEmpty ? nil : footerText)
            guard profile != current else {
                loaded = current
                failure = nil
                return
            }
            try stores.profile.save(profile)
            loaded = profile
            failure = nil
            NotificationCenter.default.post(name: .settingsDidSave, object: nil)
        } catch {
            failure = ErrorText.message(error, locale: locale)
        }
    }
}

// MARK: - Bank accounts

/// One Edit ▸ Undo registration of a removed account; the line under the list runs the same action, and
/// whichever comes first spends it. The UndoManager does not keep its targets alive, so `registered` does,
/// for as long as the window's undo stack may still reach them.
@MainActor final class BankAccountUndo {
    static var registered: [BankAccountUndo] = []

    var run: (@MainActor () -> Void)?

    static func make() -> BankAccountUndo {
        let action = BankAccountUndo()
        registered.append(action)
        return action
    }
}

/// The accounts printed on documents (set-08): one row per account, Remove without a question, undoable
/// from the line under the list and from Edit ▸ Undo; the form takes the account number (an IBAN or a
/// Czech number), the BIC, the bank name and the currency.
struct BankAccountsPane: View {
    let stores: Stores

    /// A removed account and the place it had, so Undo puts it back where it was.
    private struct RemovedAccount {
        let connection: BankConnection
        let index: Int
    }

    @State private var profile: CompanyProfile?
    @State private var accountNumber = ""
    @State private var bic = ""
    @State private var bankName = ""
    /// Empty means any currency (the account serves every currency without its own account).
    @State private var currencyCode = ""
    /// The undo of the last removal, while the line under the list offers it.
    @State private var pendingUndo: BankAccountUndo?
    @State private var message: LocalizedStringResource?
    @State private var isError = false
    @Environment(\.undoManager) private var undoManager
    @Environment(\.locale) private var locale

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
                    if let pendingUndo {
                        HStack(spacing: Spacing.m) {
                            Label { Text(L.accountRemoved) } icon: { Image(systemName: MessageKind.done.symbol).foregroundStyle(MessageKind.done.tint) }
                                .textRole(.caption)
                            Button { pendingUndo.run?() } label: { Text(L.undo) }
                        }
                    }
                    Text(L.bankNote).textRole(.caption)
                }
                Section {
                    TextField(text: $accountNumber, prompt: Text(L.accountNumberPrompt)) { Text(L.bankAccountNumber) }
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
                            .disabled(accountNumber.trimmingCharacters(in: .whitespaces).isEmpty)
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
        let number = accountNumber.trimmingCharacters(in: .whitespaces)
        let connection: BankConnection
        if let iban = IBAN(number) {
            connection = BankConnection(iban: iban, bic: parsedBIC, bankName: name.isEmpty ? nil : name, currency: currency)
        } else if let account = CzechBankAccount(parsing: number),
                  let fromAccount = BankConnection(czech: account, bic: parsedBIC, bankName: name.isEmpty ? nil : name, currency: currency) {
            connection = fromAccount
        } else {
            message = L.invalidAccountNumber
            return
        }
        updated.bankConnections.append(connection)
        guard store(updated) else { return }
        message = nil
        accountNumber = ""
        bic = ""
        bankName = ""
        currencyCode = ""
    }

    private func remove(at index: Int) {
        guard var updated = profile, updated.bankConnections.indices.contains(index) else { return }
        let removed = RemovedAccount(connection: updated.bankConnections.remove(at: index), index: index)
        guard store(updated) else { return }
        message = nil
        // A new removal replaces the line's offer; the older one stays on the Edit ▸ Undo stack.
        let action = BankAccountUndo.make()
        action.run = { [weak action] in
            guard let action else { return }
            restore(removed, action: action)
        }
        if let undoManager {
            undoManager.registerUndo(withTarget: action) { registered in
                MainActor.assumeIsolated { registered.run?() }
            }
            undoManager.setActionName(String(localized: L.removeBankAccount))
        }
        pendingUndo = action
    }

    /// Puts the account back at its old place in the stored list, read again so later changes are kept.
    /// Runs once: the line's Undo also takes the registration off the window's stack.
    private func restore(_ removed: RemovedAccount, action: BankAccountUndo) {
        action.run = nil
        if pendingUndo === action { pendingUndo = nil }
        do {
            guard var updated = try stores.profile.load() else { return }
            updated.bankConnections.insert(removed.connection, at: min(removed.index, updated.bankConnections.count))
            _ = store(updated)
        } catch {
            isError = true
            message = LocalizedStringResource(stringLiteral: ErrorText.message(error, locale: locale))
        }
        if undoManager?.isUndoing == false {
            undoManager?.removeAllActions(withTarget: action)
            BankAccountUndo.registered.removeAll { $0 === action }
        }
    }

    @discardableResult
    private func store(_ updated: CompanyProfile) -> Bool {
        do {
            try stores.profile.save(updated)
            profile = updated
            NotificationCenter.default.post(name: .settingsDidSave, object: nil)
            isError = false
            return true
        } catch {
            isError = true
            message = LocalizedStringResource(stringLiteral: ErrorText.message(error, locale: locale))
            return false
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
