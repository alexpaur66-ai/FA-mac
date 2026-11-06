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

/// Three fixed sections, one per series (set-09): the pattern and the last number issued in another tool,
/// with the live next number. One Save, because a used series cannot be changed back; it also confirms
/// the series, which Issue and Getting started wait for. Edits that are not saved are dropped.
struct NumberingPane: View {
    let stores: Stores

    /// One section's fields and its stored series.
    private struct Row: Equatable {
        var stored: StoredNumberSeries?
        var pattern: String
        var lastIssued: String

        /// The app issued a number from this series: the pattern and the counter are read-only.
        var isLocked: Bool { stored?.series.lastIssuedYear != nil }
    }

    /// What a section's fields give: the series Save would store, or why they don't parse.
    private enum Built {
        case ready(DocumentNumberSeries)
        case invalid(String)
    }

    @State private var rows: [NumberingSection: Row] = [:]
    @State private var message: LocalizedStringResource?
    @State private var isError = false
    @Environment(\.locale) private var locale

    private var today: CalendarDay { CalendarDay(Date(), in: .current) }

    var body: some View {
        Form {
            Section {
                Text(L.numberingCaption).textRole(.caption)
            }
            ForEach(NumberingSection.allCases, id: \.self) { section in
                Section {
                    sectionContent(section)
                } header: {
                    Text(Self.title(section))
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
                        .disabled(!canSave)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
    }

    @ViewBuilder
    private func sectionContent(_ section: NumberingSection) -> some View {
        if let row = rows[section] {
            if row.isLocked, let stored = row.stored {
                LabeledContent { Text(verbatim: stored.series.pattern.template).textRole(.amount) } label: { Text(L.seriesTemplate) }
                LabeledContent { Text(verbatim: stored.series.lastNumber ?? "—").textRole(.amount) } label: { Text(L.seriesLastIssued) }
            } else {
                TextField(text: binding(section, \.pattern)) { Text(L.seriesTemplate) }
                TextField(text: binding(section, \.lastIssued), prompt: Text(verbatim: samplePrompt(row))) { Text(L.seriesLastIssued) }
            }
            switch build(section, row) {
            case .ready(let series):
                Text(nextLine(section, series)).textRole(.caption)
            case .invalid(let text):
                InlineMessage(text)
            }
            if let collision = collisionMessage(for: section) {
                InlineMessage(collision, kind: .problem)
            }
        } else {
            Text(L.noSeriesForKind).textRole(.rowSecondary)
        }
    }

    private func binding(_ section: NumberingSection, _ field: WritableKeyPath<Row, String>) -> Binding<String> {
        Binding(get: { rows[section]?[keyPath: field] ?? "" }, set: { value in
            rows[section]?[keyPath: field] = value
            message = nil
        })
    }

    /// "FV 2026-0041": the pattern's number for this year with counter 41, as a hint of the form it takes.
    private func samplePrompt(_ row: Row) -> String {
        (try? DocumentNumberPattern(template: row.pattern))?.format(year: today.year, counter: 41) ?? ""
    }

    static func title(_ section: NumberingSection) -> LocalizedStringResource {
        switch section {
        case .invoices: L.numberingInvoices
        case .advances: L.numberingAdvances
        case .paymentReceipts: L.numberingReceipts
        }
    }

    /// The same names in a sentence: "Invoices and Advance invoices would …".
    static func name(_ section: NumberingSection) -> String {
        switch section {
        case .invoices: String(localized: L.numberingInvoicesName)
        case .advances: String(localized: L.numberingAdvancesName)
        case .paymentReceipts: String(localized: L.numberingReceiptsName)
        }
    }

    private func load() {
        do {
            let sections = try stores.series.sections()
            var loaded: [NumberingSection: Row] = [:]
            for section in NumberingSection.allCases {
                if let stored = sections[section] {
                    loaded[section] = Row(stored: stored, pattern: stored.series.pattern.template,
                                          lastIssued: stored.series.lastNumber ?? "")
                } else {
                    loaded[section] = Row(stored: nil, pattern: section.defaultTemplate, lastIssued: "")
                }
            }
            rows = loaded
        } catch {
            isError = true
            message = LocalizedStringResource(stringLiteral: ErrorText.message(error, locale: locale))
        }
    }

    /// The series a section's fields describe. A locked series is the stored one. Otherwise the pattern
    /// decides the yearly restart ({YYYY} or {YY} restarts the counter each year, a pattern without a year
    /// counts on), and the last issued number is read with the pattern: one from an earlier year means the
    /// counter starts again at 1 this year. Empty starts at 1.
    private func build(_ section: NumberingSection, _ row: Row) -> Built {
        if row.isLocked, let stored = row.stored { return .ready(stored.series) }
        let pattern: DocumentNumberPattern
        do {
            pattern = try DocumentNumberPattern(template: row.pattern.trimmingCharacters(in: .whitespaces))
        } catch {
            return .invalid(ErrorText.message(error, locale: locale))
        }
        var counter = 0
        let typed = row.lastIssued.trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty {
            guard let parsed = pattern.parseIssuedNumber(typed, latestYear: today.year) else {
                return .invalid(String(localized: L.lastIssuedNoMatch(pattern.format(year: today.year, counter: 41))))
            }
            if !pattern.containsYear || parsed.year == today.year {
                counter = parsed.counter
            }
        }
        do {
            let series = try DocumentNumberSeries(id: row.stored?.id ?? section.rawValue, pattern: pattern, resetsYearly: pattern.containsYear,
                                                  year: today.year, lastCounter: counter, variableSymbolPrefix: section.variableSymbolPrefix)
            return .ready(series)
        } catch {
            return .invalid(ErrorText.message(error, locale: locale))
        }
    }

    private func builtSeries(_ section: NumberingSection) -> DocumentNumberSeries? {
        guard let row = rows[section], case .ready(let series) = build(section, row) else { return nil }
        return series
    }

    /// "Next number: FV 2026-0042 · VS 120260042 – assigned when you issue"; DD carries no payment request,
    /// so its line has the number only.
    private func nextLine(_ section: NumberingSection, _ series: DocumentNumberSeries) -> LocalizedStringResource {
        guard let number = try? series.peek(on: today) else { return L.nextNumberUnknown }
        if section != .paymentReceipts,
           let symbol = PaymentSymbol.variable(fromDocumentNumber: number, prefix: series.variableSymbolPrefix) {
            return L.nextNumberLine(number, symbol.digits)
        }
        return L.nextNumberLineNoVS(number)
    }

    /// The number of 2026 with counter 42 and its variable symbol, to compare two sections' patterns.
    private func sample(_ series: DocumentNumberSeries) -> (number: String, symbol: String?) {
        let number = series.pattern.format(year: 2026, counter: 42)
        return (number, PaymentSymbol.variable(fromDocumentNumber: number, prefix: series.variableSymbolPrefix)?.digits)
    }

    /// Shown in the later of two colliding sections, naming both. Document numbers are compared across all
    /// three; variable symbols for Invoices and Advance invoices only, since DD carries none.
    private func collisionMessage(for section: NumberingSection) -> LocalizedStringResource? {
        guard let mine = builtSeries(section) else { return nil }
        let all = NumberingSection.allCases
        guard let index = all.firstIndex(of: section) else { return nil }
        for earlier in all[..<index] {
            guard let other = builtSeries(earlier) else { continue }
            if sample(mine).number == sample(other).number {
                return L.seriesSameNumbers(Self.name(earlier), Self.name(section))
            }
            if section != .paymentReceipts, earlier != .paymentReceipts,
               let symbol = sample(mine).symbol, symbol == sample(other).symbol {
                return L.seriesSameVS(Self.name(earlier), Self.name(section))
            }
        }
        return nil
    }

    private var canSave: Bool {
        guard !rows.isEmpty else { return false }
        return NumberingSection.allCases.allSatisfy { builtSeries($0) != nil && collisionMessage(for: $0) == nil }
    }

    /// Stores the unlocked series with their section's kinds, then records the confirmation. The store never
    /// moves a counter backwards; when it kept its own counter, the pane says so.
    private func save() {
        guard canSave else { return }
        do {
            var keptCounter = false
            for section in NumberingSection.allCases {
                guard let row = rows[section], !row.isLocked, let series = builtSeries(section) else { continue }
                let kinds = section.kinds.union(row.stored?.kinds ?? [])
                let name = row.stored?.name ?? section.defaultName
                try stores.series.save(StoredNumberSeries(name: name, kinds: kinds, series: series))
                if let stored = try stores.series.series(id: series.id),
                   stored.series.year != series.year || stored.series.lastCounter != series.lastCounter {
                    keptCounter = true
                }
            }
            try stores.series.confirmNumbering()
            NotificationCenter.default.post(name: .settingsDidSave, object: nil)
            isError = false
            load()
            message = keptCounter ? L.seriesStoreKeptCounter : L.saved
        } catch {
            isError = true
            message = LocalizedStringResource(stringLiteral: ErrorText.message(error, locale: locale))
        }
    }
}

extension Notification.Name {
    /// Posted after Settings wrote the company profile, a bank account, a number series or the document
    /// defaults, so an open draft editor re-reads them at once (design check E024).
    static let settingsDidSave = Notification.Name("FA.settingsDidSave")
}
