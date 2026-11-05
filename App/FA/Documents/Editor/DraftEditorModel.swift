// The draft editor's model (screens-flows.md §2c, ADR 0009): one draft, its live totals and validation
// issues, and autosave. Every edit goes through `update`, which recomputes and schedules the save; the
// data layer's observation then refreshes the lists and the badges.

import Foundation
import InvoicingCore
import InvoicingData
import Observation

/// The document-level VAT treatment the header offers. Under Czech VAT each line keeps its own rate; the
/// other treatments apply to every line (screens-flows.md §2c: mixed documents are the accountant's
/// decision and are not offered).
enum TreatmentChoice: Hashable, CaseIterable, Identifiable {
    case czechVAT, reverseChargeEU, outsideEU, exempt

    var id: Self { self }

    init(_ treatment: VATTreatment) {
        switch treatment {
        case .taxable: self = .czechVAT
        case .reverseChargeEU: self = .reverseChargeEU
        case .outsideEU: self = .outsideEU
        case .exempt: self = .exempt
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .czechVAT: L.treatmentCzechVAT
        case .reverseChargeEU: L.treatmentReverseCharge
        case .outsideEU: L.treatmentOutsideEU
        case .exempt: L.treatmentExempt
        }
    }

    /// The treatment a line takes under this choice; a Czech rate the line already had is kept.
    func apply(to existing: VATTreatment?, exemptReference: String) -> VATTreatment {
        switch self {
        case .czechVAT:
            if case .taxable(let kind)? = existing { return .taxable(kind) }
            return .taxable(.standard)
        case .reverseChargeEU:
            return .reverseChargeEU
        case .outsideEU:
            return .outsideEU
        case .exempt:
            return .exempt(reference: exemptReference)
        }
    }
}

enum DraftEditorError: Error, CustomStringConvertible {
    case saveFailed(String)

    var description: String {
        switch self {
        case .saveFailed(let detail): detail
        }
    }
}

/// Where keyboard focus should land once the editor shows its draft (screens-flows.md §2c, §4): the
/// client field of a new draft, the first line of a duplicate or a chained document, a line just added.
enum EditorFocusRequest: Hashable {
    case client
    case firstLineText
    case firstLineQuantity
    case lineText(String)
}

/// A numeric cell of the lines grid; the model counts a cell holding text that is not a number as ⛔.
struct NumberCell: Hashable {
    enum Column: Int, Hashable {
        case quantity, unitPrice, discount, vatRate

        var title: LocalizedStringResource {
            switch self {
            case .quantity: L.colQty
            case .unitPrice: L.colUnitPrice
            case .discount: L.colDiscount
            case .vatRate: L.colVATRate
            }
        }
    }

    let lineID: String
    let column: Column
}

@MainActor @Observable final class DraftEditorModel {
    enum SaveState: Equatable {
        case saved, pending, failed
    }

    let stores: Stores
    let documentID: String

    private(set) var document: Document?
    private(set) var totals: DocumentTotals?
    private(set) var totalsError: String?
    private(set) var issues: [ValidationIssue] = []
    private(set) var loadError: String?
    private(set) var saveError: String?
    private(set) var saveState: SaveState = .saved
    /// Why the last rate lookup or typed rate failed; shown under the rate form or line.
    private(set) var rateError: String?
    /// Why the last "Add Tax Document…" failed; shown in the advances section.
    private(set) var deductionError: String?
    /// Deductions of receipts that another issued final invoice already deducts (screens-flows.md §2c, ⛔).
    private(set) var deductionConflicts: [String] = []
    /// Receipts this draft lists that another draft final invoice lists too (⚠: only one can be issued).
    private(set) var deductionWarnings: [String] = []
    /// True once the user picked an explicit tax point; otherwise the tax point follows the issue date.
    private(set) var taxPointExplicit = false
    private(set) var customers: [Customer] = []
    private(set) var series: [StoredNumberSeries] = []
    private(set) var profile: CompanyProfile?
    private(set) var treatmentChoice: TreatmentChoice = .czechVAT
    /// The exemption reference typed in the header, kept while another treatment is selected.
    private(set) var exemptReference = ""
    /// How the rate for the tax point was found (§ 4 odst. 8 ZDPH); nil while no rate is needed.
    private(set) var rateResolution: ExchangeRateTable.Resolution?
    /// The payment a draft payment tax document is the receipt of; nil when no payment names it.
    private(set) var receiptPayment: DocumentPayment?
    /// Cells of the lines grid holding text that is not a number; each is a ⛔ row until fixed.
    private(set) var invalidCells: Set<NumberCell> = []
    /// The focus the view should apply; `focusRequestVersion` changes with every request.
    private(set) var focusRequest: EditorFocusRequest?
    private(set) var focusRequestVersion = 0
    /// Bumped by Document ▸ Enter Rate…: the view focuses the rate field, or opens Change… on a rate.
    private(set) var rateFocusRequest = 0
    /// The line holding keyboard focus, for the Document menu's line items.
    var focusedLineID: String?

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// Set when the draft was deleted: nothing is written any more (a pending save would re-create it).
    @ObservationIgnored private var discarded = false

    init(stores: Stores, documentID: String, initialFocus: EditorFocusRequest? = nil) {
        self.stores = stores
        self.documentID = documentID
        if let initialFocus { requestFocus(initialFocus) }
        load()
    }

    deinit {
        saveTask?.cancel()
    }

    // MARK: Loading and saving

    func load() {
        do {
            guard let document = try stores.documents.document(id: documentID), document.status == .draft else {
                loadError = String(localized: L.draftGone)
                return
            }
            self.document = document
            customers = try stores.customers.all()
            profile = try stores.profile.load()
            series = try stores.series.series(for: document.kind)
            if let first = document.lines.first?.treatment {
                treatmentChoice = TreatmentChoice(first)
                if case .exempt(let reference) = first { exemptReference = reference }
            } else if let customer = customers.first(where: { $0.id == document.customerID }) {
                treatmentChoice = TreatmentChoice(customer.vatStatus.defaultServiceTreatment)
            }
            // A payment tax document's tax point is the day of its payment and never follows the issue date.
            taxPointExplicit = document.kind == .paymentTaxDocument || document.taxPointDate.map { $0 != document.issueDate } ?? false
            // One blank row to type into (design-system.md §8.5); it is never saved or validated.
            if document.lines.isEmpty { appendBlankLine() }
            recompute()
            // A draft saved without its tax point (an older draft) gets the issue date, which the validator needs.
            if document.kind.isTaxDocument && document.taxPointDate == nil {
                update { Self.followIssueDate(&$0, explicitTaxPoint: false) }
            }
            refreshSnapshots()
            refreshReceiptPayment()
            refreshDeductionConflicts()
            refreshRate()
        } catch {
            loadError = ErrorText.message(error)
        }
    }

    /// Applies one change to the draft, recomputes totals and issues, and schedules the save.
    func update(_ change: (inout Document) -> Void) {
        guard !discarded, var document else { return }
        change(&document)
        self.document = document
        recompute()
        scheduleSave()
    }

    private func recompute() {
        guard let document else { return }
        // The number is assigned and checked by `DocumentStore.issue`; a draft never has one.
        issues = DocumentValidator.validate(Self.validationPreview(of: document, profile: profile), forIssue: false)
        do {
            totals = try DocumentTotals.compute(for: document)
            totalsError = nil
        } catch {
            totals = nil
            // The edit was kept; the totals wait for the fix the validator names (a negative quantity, a
            // discount out of range, a rate not in force). Without one, the view says the totals wait.
            let causes: Set<ValidationIssue.Code> = [.lineQuantityNegative, .lineDiscountOutOfRange, .rateNotInForce]
            totalsError = issues.first { causes.contains($0.code) }?.message(language: .english)
        }
    }

    private func scheduleSave() {
        saveState = .pending
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            self.saveNow()
        }
    }

    /// Writes the draft now; the editor calls it when it goes away, before Issue and when the app quits.
    /// False when the save failed (`saveError` says why), so the caller can tell the user before the
    /// edits are dropped.
    @discardableResult
    func saveNow() -> Bool {
        saveTask?.cancel()
        saveTask = nil
        guard !discarded, saveState != .saved, let document, document.status == .draft else { return true }
        do {
            try stores.documents.saveDraft(Self.strippingBlankTrailingLines(document))
            saveState = .saved
            saveError = nil
            return true
        } catch {
            saveState = .failed
            saveError = ErrorText.message(error)
            return false
        }
    }

    /// The draft was deleted: drop the pending save and never write again, or the upsert of `saveDraft`
    /// would bring the deleted draft back.
    func discard() {
        saveTask?.cancel()
        saveTask = nil
        discarded = true
        saveState = .saved
    }

    // MARK: Pure helpers (testable without SwiftUI)

    /// A fully empty trailing line (Add Line left untouched) is dropped on save and at issue and never
    /// counts as invalid (screens-flows.md §2c).
    nonisolated static func isBlankLine(_ line: DocumentLine) -> Bool {
        line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (line.quantity == 1 || line.quantity == 0) && line.unitPrice == 0 && line.discountPercent == 0
            && (line.unit ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Every blank line at the end goes, not only the last one (⌘L twice leaves two).
    nonisolated static func strippingBlankTrailingLines(_ document: Document) -> Document {
        var copy = document
        while let last = copy.lines.last, isBlankLine(last) { copy.lines.removeLast() }
        return copy
    }

    /// What the validator sees: the draft without its blank trailing lines and, when no account is
    /// picked, with the company's account for the currency that `DocumentStore.issue` will fill in. A
    /// payment tax document carries no payment instructions (nothing is due on it), so it is checked
    /// without any.
    nonisolated static func validationPreview(of document: Document, profile: CompanyProfile?) -> Document {
        var preview = strippingBlankTrailingLines(document)
        if preview.kind == .paymentTaxDocument {
            preview.payment = nil
        } else if preview.payment == nil, let account = profile?.bankConnection(for: preview.currency) {
            preview.payment = PaymentInstructions.standard(for: "", bankConnection: account, currency: preview.currency)
        }
        return preview
    }

    /// "Same as the issue date" stores the issue date as the tax point, because a tax document needs a
    /// stored one (§ 29 odst. 1 písm. h) ZDPH, `taxPointDateMissing`); an advance has none.
    nonisolated static func followIssueDate(_ document: inout Document, explicitTaxPoint: Bool) {
        guard document.kind.isTaxDocument else {
            document.taxPointDate = nil
            return
        }
        // A payment tax document states the day the payment was received (§ 29 odst. 1 písm. h) ZDPH); the
        // store checks that day against the payment, so the editor never moves it.
        if document.kind == .paymentTaxDocument { return }
        if !explicitTaxPoint || document.taxPointDate == nil { document.taxPointDate = document.issueDate }
    }

    /// The types the header offers: a payment tax document comes only from a payment on an advance
    /// (screens-flows.md §1.4, §2d), so it is listed only for such a draft, which cannot change type.
    nonisolated static func kindOptions(for current: DocumentKind) -> [DocumentKind] {
        current == .paymentTaxDocument ? [.paymentTaxDocument] : [.invoice, .advanceRequest, .finalInvoice]
    }

    /// Validator warnings the editor treats as blocking (ADR 0009 amendments): the company's IČO belongs
    /// on every document (§ 29 odst. 1 písm. a) ZDPH), and an account in the document's currency must
    /// exist before Issue would freeze another currency's account onto it.
    nonisolated static func isPromoted(_ issue: ValidationIssue, kind: DocumentKind) -> Bool {
        switch issue.code {
        case .supplierIdentificationNumberMissing: true
        case .paymentInstructionsMissing, .bankAccountCurrencyDiffers: kind != .paymentTaxDocument
        default: false
        }
    }

    /// Issues that do not apply to the kind: a payment tax document carries no payment instructions.
    nonisolated static func isExcluded(_ issue: ValidationIssue, kind: DocumentKind) -> Bool {
        kind == .paymentTaxDocument && (issue.code == .paymentInstructionsMissing || issue.code == .bankAccountCurrencyDiffers)
    }

    // MARK: Focus

    func requestFocus(_ request: EditorFocusRequest) {
        focusRequest = request
        focusRequestVersion += 1
    }

    /// The pending request, cleared; the view applies it once the fields exist.
    func takeFocusRequest() -> EditorFocusRequest? {
        defer { focusRequest = nil }
        return focusRequest
    }

    /// Document ▸ Enter Rate…: the rate field takes focus, or Change… opens on a resolved rate.
    func requestRateFocus() {
        rateFocusRequest += 1
    }

    // MARK: Header fields

    var customer: Customer? {
        customers.first { $0.id == document?.customerID }
    }

    /// Clients whose name, IČO or VAT ID contains `query` (case- and diacritic-insensitive), at most six;
    /// the first six by name while nothing is typed.
    func matchingCustomers(_ query: String) -> [Customer] {
        let needle = query.trimmingCharacters(in: .whitespaces).folded
        let sorted = customers.sorted { $0.party.name.folded < $1.party.name.folded }
        guard !needle.isEmpty else { return Array(sorted.prefix(6)) }
        return Array(sorted.filter { customer in
            customer.party.name.folded.contains(needle)
                || (customer.party.identificationNumber?.digits.contains(needle) ?? false)
                || (customer.party.vatIdentifier?.value.folded.contains(needle) ?? false)
        }.prefix(6))
    }

    /// A new client brings its defaults: currency, language, due days, VAT treatment (screens-flows.md §2c).
    /// A payment tax document keeps the client of its advance. Picking the client already set changes
    /// nothing, so the currency, due date, account and treatment the user chose stay.
    func setCustomer(_ id: String?) {
        guard document?.kind != .paymentTaxDocument else { return }
        if id != nil, id == document?.customerID { return }
        let chosen = customers.first { $0.id == id }
        update { doc in
            // Deductions belong to the previous client's receipts; the store would refuse them at issue.
            if chosen?.id != doc.customerID { doc.advanceDeductions = [] }
            doc.customerID = chosen?.id
            doc.customer = chosen?.party
                ?? Party(name: "", address: PostalAddress(street: "", city: "", postalCode: "", countryCode: "CZ"))
            guard let chosen else { return }
            doc.currency = chosen.currency
            doc.language = chosen.language
            doc.dueDate = doc.issueDate.adding(days: chosen.paymentTermDays)
            doc.payment = nil
            doc.exchangeRate = nil
            treatmentChoice = TreatmentChoice(chosen.vatStatus.defaultServiceTreatment)
            for index in doc.lines.indices {
                doc.lines[index].treatment = treatmentChoice.apply(to: doc.lines[index].treatment, exemptReference: exemptReference)
            }
        }
        dropRateCellsOfUntaxedLines()
        refreshDeductionConflicts()
        refreshRate()
    }

    /// Re-reads the clients, the company profile and the series that number the draft's kind: a client
    /// sheet or Settings may have changed them while the editor is open. The draft's copies of the
    /// supplier and the client follow, so the issued document carries the corrected details.
    func refreshReferenceData() {
        guard !discarded, let document else { return }
        if let fresh = try? stores.customers.all() { customers = fresh }
        if let fresh = try? stores.profile.load() { profile = fresh }
        series = (try? stores.series.series(for: document.kind)) ?? []
        refreshSnapshots()
        refreshReceiptPayment()
        refreshDeductionConflicts()
        recompute()
    }

    /// The supplier and the client are copied onto the draft and frozen at issue. Until then the copies
    /// follow the company profile and the client card. An account picked explicitly that Settings no
    /// longer lists (removed, or replaced with another IBAN or BIC) falls back to the default account for
    /// the currency, so the issued document never prints an account the company no longer has.
    func refreshSnapshots() {
        guard !discarded, let document else { return }
        let supplier = profile?.supplier
        let party = customer?.party
        let supplierChanged = supplier.map { $0 != document.supplier } ?? false
        let customerChanged = party.map { $0 != document.customer } ?? false
        let accountGone = profile.map { profile in
            document.payment.map { !profile.bankConnections.contains($0.bankConnection) } ?? false
        } ?? false
        guard supplierChanged || customerChanged || accountGone else { return }
        update { doc in
            if let supplier { doc.supplier = supplier }
            if let party { doc.customer = party }
            if accountGone { doc.payment = nil }
        }
    }

    func setKind(_ kind: DocumentKind) {
        guard let current = document?.kind, Self.kindOptions(for: current).contains(kind) else { return }
        update { doc in
            doc.kind = kind
            Self.followIssueDate(&doc, explicitTaxPoint: taxPointExplicit)
            if kind != .finalInvoice { doc.advanceDeductions = [] }
        }
        series = (try? stores.series.series(for: kind)) ?? []
        refreshDeductionConflicts()
        refreshRate()
    }

    /// Moving the issue date keeps the due days, so the due date moves with it, and so does a tax point
    /// that is "same as the issue date".
    func setIssueDate(_ day: CalendarDay) {
        update { doc in
            let term = doc.dueDate.days(since: doc.issueDate)
            doc.issueDate = day
            doc.dueDate = day.adding(days: max(term, 0))
            Self.followIssueDate(&doc, explicitTaxPoint: taxPointExplicit)
        }
        refreshRate()
    }

    /// An explicit tax point picked in the header.
    func setTaxPointDate(_ day: CalendarDay) {
        guard document?.kind != .paymentTaxDocument else { return }
        taxPointExplicit = true
        update { $0.taxPointDate = day }
        refreshRate()
    }

    var taxPointSameAsIssue: Bool { !taxPointExplicit }

    /// On: the tax point is the issue date and follows it. Off: the current day stays as an explicit date.
    func setTaxPointSameAsIssue(_ same: Bool) {
        guard document?.kind != .paymentTaxDocument else { return }
        taxPointExplicit = !same
        update { Self.followIssueDate(&$0, explicitTaxPoint: !same) }
        refreshRate()
    }

    var dueDays: Int {
        document.map { $0.dueDate.days(since: $0.issueDate) } ?? 0
    }

    func setDueDays(_ days: Int) {
        update { doc in doc.dueDate = doc.issueDate.adding(days: max(days, 0)) }
    }

    /// The due date picked directly; the days follow (screens-flows.md §2c: "30 days" and a date, linked).
    func setDueDate(_ day: CalendarDay) {
        update { doc in doc.dueDate = day }
    }

    /// Prices are not converted (screens-flows.md §2c); the account and the rate are re-picked. A payment
    /// tax document stays in the currency of its payment.
    func setCurrency(_ currency: Currency) {
        guard document?.kind != .paymentTaxDocument else { return }
        update { doc in
            doc.currency = currency
            doc.payment = nil
            doc.exchangeRate = nil
        }
        refreshRate()
    }

    func setLanguage(_ language: DocumentLanguage) {
        update { $0.language = language }
    }

    func setTreatment(_ choice: TreatmentChoice) {
        treatmentChoice = choice
        update { doc in
            for index in doc.lines.indices {
                doc.lines[index].treatment = choice.apply(to: doc.lines[index].treatment, exemptReference: exemptReference)
            }
        }
        dropRateCellsOfUntaxedLines()
        refreshRate()
    }

    /// A line under reverse charge, outside EU or exempt has no VAT rate cell, so typed text that was not
    /// a rate in force no longer blocks Issue.
    private func dropRateCellsOfUntaxedLines() {
        guard let document else { return }
        let taxable = Set(document.lines.compactMap { line -> String? in
            if case .taxable = line.treatment { return line.id }
            return nil
        })
        let kept = invalidCells.filter { $0.column != .vatRate || taxable.contains($0.lineID) }
        if kept != invalidCells { invalidCells = kept }
    }

    func setExemptReference(_ text: String) {
        exemptReference = text
        guard treatmentChoice == .exempt else { return }
        update { doc in
            for index in doc.lines.indices { doc.lines[index].treatment = .exempt(reference: text) }
        }
    }

    /// The company's accounts that fit the document's currency (an account without a currency fits all).
    var bankAccounts: [BankConnection] {
        guard let profile, let document else { return [] }
        return profile.bankConnections.filter { $0.currency == nil || $0.currency == document.currency }
    }

    /// nil means the company's default account for the currency, chosen by the data layer at issue.
    func setBankAccount(_ account: BankConnection?) {
        update { doc in
            guard let account else {
                doc.payment = nil
                return
            }
            var payment = PaymentInstructions.standard(for: "", bankConnection: account, currency: doc.currency)
            payment.variableSymbol = nil
            payment.creditorReference = nil
            doc.payment = payment
        }
    }

    func setOrderReference(_ text: String) {
        update { $0.orderReference = text.isEmpty ? nil : text }
    }

    /// A payment tax document names its advance; that reference is not edited by hand.
    func setRelatedDocumentNumber(_ text: String) {
        guard document?.kind != .paymentTaxDocument else { return }
        update { $0.relatedDocumentNumber = text.isEmpty ? nil : text }
    }

    func setNote(_ text: String) {
        update { $0.note = text.isEmpty ? nil : text }
    }

    func setFooter(_ text: String) {
        update { $0.footer = text.isEmpty ? nil : text }
    }

    // MARK: Payment tax document

    /// True on a draft payment tax document that no payment names any more: it would document a payment
    /// that does not exist, so Issue is blocked (ADR 0009 amendments).
    var receiptPaymentMissing: Bool {
        document?.kind == .paymentTaxDocument && receiptPayment == nil
    }

    private func refreshReceiptPayment() {
        guard let document, document.kind == .paymentTaxDocument else {
            receiptPayment = nil
            return
        }
        do {
            receiptPayment = try stores.documents.payment(ofReceipt: documentID)
        } catch {
            // On a read error the last known payment stands; a false "no payment" row would mislead.
        }
    }

    // MARK: Lines

    private var newLineTreatment: VATTreatment {
        if treatmentChoice == .czechVAT, case .taxable(let kind)? = document?.lines.last?.treatment {
            return .taxable(kind)
        }
        return treatmentChoice.apply(to: nil, exemptReference: exemptReference)
    }

    /// A blank row to type into; `strippingBlankTrailingLines` keeps it out of the saved draft and the
    /// validator, so adding it does not change the draft and schedules no save.
    private func appendBlankLine() {
        document?.lines.append(DocumentLine(text: "", quantity: 1, unit: nil, unitPrice: 0, treatment: newLineTreatment))
        recompute()
    }

    @discardableResult
    func addLine() -> String {
        let line = DocumentLine(text: "", quantity: 1, unit: nil, unitPrice: 0, treatment: newLineTreatment)
        update { doc in doc.lines.append(line) }
        return line.id
    }

    /// Add Line Item (⌘L): the new line's Description takes focus.
    func addLineAndFocus() {
        let id = addLine()
        requestFocus(.lineText(id))
    }

    func insertLine(after id: String) {
        let line = DocumentLine(text: "", quantity: 1, unit: nil, unitPrice: 0, treatment: newLineTreatment)
        update { doc in
            if let index = doc.lines.firstIndex(where: { $0.id == id }) {
                doc.lines.insert(line, at: index + 1)
            } else {
                doc.lines.append(line)
            }
        }
    }

    /// Deleting the last line leaves one blank row (design-system.md §8.5).
    func removeLine(_ id: String) {
        update { doc in doc.lines.removeAll { $0.id == id } }
        invalidCells = invalidCells.filter { $0.lineID != id }
        if focusedLineID == id { focusedLineID = nil }
        if document?.lines.isEmpty == true { appendBlankLine() }
    }

    func moveLine(_ id: String, by offset: Int) {
        update { doc in
            guard let index = doc.lines.firstIndex(where: { $0.id == id }) else { return }
            let target = index + offset
            guard doc.lines.indices.contains(target) else { return }
            doc.lines.swapAt(index, target)
        }
    }

    func deleteFocusedLine() {
        guard let id = focusedLineID else { return }
        removeLine(id)
    }

    func moveFocusedLine(by offset: Int) {
        guard let id = focusedLineID else { return }
        moveLine(id, by: offset)
    }

    func setLine(_ id: String, _ change: (inout DocumentLine) -> Void) {
        update { doc in
            guard let index = doc.lines.firstIndex(where: { $0.id == id }) else { return }
            change(&doc.lines[index])
        }
    }

    /// The computed amounts of the line at `index`, when the totals are available.
    func lineAmounts(at index: Int) -> LineAmounts? {
        guard let totals, totals.lines.indices.contains(index) else { return nil }
        return totals.lines[index]
    }

    /// The validator's first message about a line, for the trailing marker of its row.
    func lineProblem(_ id: String, locale: Locale) -> String? {
        guard let kind = document?.kind else { return nil }
        return issues.first { $0.lineID == id && !Self.isExcluded($0, kind: kind) }?.message(language: .english)
    }

    /// A cell holds text that is not a number (or has been fixed). Each invalid cell is a ⛔ row.
    func setCell(_ cell: NumberCell, invalid: Bool) {
        guard invalidCells.contains(cell) != invalid else { return }
        if invalid {
            invalidCells.insert(cell)
        } else {
            invalidCells.remove(cell)
        }
    }

    /// One ⛔ row per invalid cell, in line order.
    var invalidCellMessages: [String] {
        guard let document else { return [] }
        let order = Dictionary(document.lines.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return invalidCells
            .compactMap { cell in order[cell.lineID].map { (index: $0, cell: cell) } }
            .sorted { ($0.index, $0.cell.column.rawValue) < ($1.index, $1.cell.column.rawValue) }
            .map { entry in
                entry.cell.column == .vatRate
                    ? String(localized: L.invalidRateRow(entry.index + 1))
                    : String(localized: L.invalidCellRow(entry.index + 1, String(localized: entry.cell.column.title)))
            }
    }

    // MARK: Exchange rate

    /// A tax document in a foreign currency needs the rate of its tax point (§ 4 odst. 8 ZDPH):
    /// `ExchangeRateTable.resolve` gives the day's rate, or on a weekend or holiday the last working
    /// day's, and nothing otherwise; then the user types the rate or imports the ČNB file.
    var needsExchangeRate: Bool {
        guard let document else { return false }
        return document.kind.isTaxDocument && document.currency != .czk
    }

    var rateIsMissing: Bool {
        needsExchangeRate && document?.exchangeRate == nil
    }

    /// The day whose rate stands in for the tax point, when it is not the tax point itself.
    var rateFallbackFrom: CalendarDay? { rateResolution?.fallbackFrom }

    /// The day whose published rate the document needs: the tax point, or the last working day before it.
    var neededRateDay: CalendarDay {
        if let rateResolution { return rateResolution.publicationDay }
        if let document { return CzechHolidays.lastWorkingDay(onOrBefore: document.taxPoint) }
        return CalendarDay(Date(), in: .current)
    }

    func refreshRate() {
        guard !discarded, let document else { return }
        rateError = nil
        guard needsExchangeRate else {
            rateResolution = nil
            if document.exchangeRate != nil { update { $0.exchangeRate = nil } }
            return
        }
        do {
            let resolution = try stores.rates.table(for: document.currency).resolve(document.currency, on: document.taxPoint)
            rateResolution = resolution
            if resolution.rate != document.exchangeRate { update { $0.exchangeRate = resolution.rate } }
        } catch {
            rateError = ErrorText.message(error)
        }
    }

    /// Saves a typed rate for `day` (the needed publication day when nil) with the source "Typed", and
    /// applies whatever the tax point then resolves to. Without `replace`, a rate already stored for that
    /// day (an import meanwhile) is kept and taken; Change… replaces it, which is how a typo is fixed.
    func saveManualRate(_ czkPerUnit: Decimal, validFor day: CalendarDay? = nil, replace: Bool = false) {
        guard let document, czkPerUnit > 0 else { return }
        rateError = nil
        let day = day ?? neededRateDay
        guard day <= document.taxPoint else {
            rateError = String(localized: L.rateAfterTaxPoint)
            return
        }
        do {
            let existing = try stores.rates.rate(for: document.currency, on: day, lookup: .exactDay)
            let saved = replace || existing == nil
            if saved {
                try stores.rates.save(ExchangeRate(currency: document.currency, amount: 1, czkPerAmount: czkPerUnit, validFor: day, source: .manual))
            }
            refreshRate()
            if rateIsMissing, rateError == nil {
                rateError = saved
                    ? String(localized: L.rateSavedForOtherDay(day.formatted(.current), neededRateDay.formatted(.current)))
                    : String(localized: L.rateAlreadyStored(day.formatted(.current)))
            }
        } catch {
            rateError = ErrorText.message(error)
        }
    }

    // MARK: Advances deducted (final invoice)

    struct ReceiptCandidate: Identifiable, Hashable {
        let id: String
        let number: String
        let paymentDate: CalendarDay
        let gross: Money
    }

    /// Issued payment tax documents of the same client in the same currency that no issued final invoice
    /// deducts yet (`deduction(ofReceipt:)`) and this draft does not list (screens-flows.md §2d, step 4).
    func receiptCandidates(in states: [DocumentState]) -> [ReceiptCandidate] {
        guard let document, document.kind == .finalInvoice, document.customerID != nil else { return [] }
        let listed = Set(document.advanceDeductions.map(\.documentNumber))
        return states.compactMap { state in
            let summary = state.summary
            guard summary.kind == .paymentTaxDocument, summary.status != .draft,
                  summary.currency == document.currency, summary.customerID == document.customerID,
                  let number = summary.number, !listed.contains(number), let gross = summary.totalGross,
                  (try? stores.documents.deduction(ofReceipt: summary.id)) == nil
            else { return nil }
            return ReceiptCandidate(id: summary.id, number: number, paymentDate: summary.taxPointDate ?? summary.issueDate, gross: gross)
        }
    }

    /// The number of the advance a listed receipt was issued for, from the lists' states.
    func advanceNumber(ofReceipt number: String, in states: [DocumentState]) -> String? {
        states.first { $0.summary.number == number && $0.summary.kind == .paymentTaxDocument }?.summary.relatedDocumentNumber
    }

    /// Adds the deductions the receipt carries: one per VAT summary row, with the rate and the exchange
    /// rate the advance was taxed at (§ 37a odst. 2 písm. b) ZDPH, InvoicingCore).
    func addDeduction(receiptID: String) {
        deductionError = nil
        do {
            guard let receipt = try stores.documents.document(id: receiptID), receipt.status != .draft else {
                deductionError = String(localized: L.errorNotFound)
                return
            }
            let receiptTotals = try DocumentTotals.compute(for: receipt)
            let deductions = receipt.advanceDeductions(totals: receiptTotals)
            update { doc in doc.advanceDeductions.append(contentsOf: deductions) }
        } catch {
            deductionError = ErrorText.message(error)
        }
        refreshDeductionConflicts()
    }

    func removeDeductions(ofDocumentNumber number: String) {
        deductionError = nil
        update { doc in doc.advanceDeductions.removeAll { $0.documentNumber == number } }
        refreshDeductionConflicts()
    }

    /// The listed receipts that another issued final invoice already deducts (one final invoice per
    /// receipt, `linkDeductions`) are ⛔ rows naming that invoice instead of a refusal after the click;
    /// receipts another draft final invoice lists too are ⚠ rows.
    private func refreshDeductionConflicts() {
        guard let document, document.kind == .finalInvoice, !document.advanceDeductions.isEmpty else {
            deductionConflicts = []
            deductionWarnings = []
            return
        }
        let numbers = Set(document.advanceDeductions.map(\.documentNumber))
        do {
            var conflicts: [String] = []
            let receipts = try stores.documents.summaries(DocumentFilter(kinds: [.paymentTaxDocument], status: .issued))
            for receipt in receipts {
                guard let number = receipt.number, numbers.contains(number),
                      let link = try stores.documents.deduction(ofReceipt: receipt.id), link.finalInvoiceID != documentID
                else { continue }
                conflicts.append(String(localized: L.advanceAlreadyDeductedIn(number, link.finalInvoiceNumber)))
            }
            deductionConflicts = conflicts
            var warnings: [String] = []
            for other in try stores.documents.summaries(DocumentFilter(kinds: [.finalInvoice], status: .draft)) where other.id != documentID {
                guard let draft = try stores.documents.document(id: other.id) else { continue }
                for number in Set(draft.advanceDeductions.map(\.documentNumber)).intersection(numbers).sorted() {
                    warnings.append(String(localized: L.receiptAlsoInDraft(number)))
                }
            }
            deductionWarnings = warnings
        } catch {
            deductionConflicts = []
            deductionWarnings = []
            deductionError = ErrorText.message(error)
        }
    }

    // MARK: Issue

    /// The validator's errors plus the warnings the editor promotes (`isPromoted`).
    var errors: [ValidationIssue] {
        guard let kind = document?.kind else { return [] }
        return issues.filter { ($0.isError || Self.isPromoted($0, kind: kind)) && !Self.isExcluded($0, kind: kind) }
    }

    /// The ⚠ rows from the validator; a missing rate shows as the inline form, not as a warning too.
    var warnings: [ValidationIssue] {
        guard let kind = document?.kind else { return [] }
        return issues.filter {
            !$0.isError && !Self.isPromoted($0, kind: kind) && !Self.isExcluded($0, kind: kind)
                && !(rateIsMissing && $0.code == .exchangeRateMissing)
        }
    }

    /// ⚠ rows the validator cannot know: a receipt listed in another draft, defaults that differ from
    /// the client's card.
    var extraWarnings: [String] {
        var result = deductionWarnings
        if let document, let customer, document.kind != .paymentTaxDocument {
            if document.currency != customer.currency { result.append(String(localized: L.currencyDiffersFromClient)) }
            if TreatmentChoice(customer.vatStatus.defaultServiceTreatment) != treatmentChoice {
                result.append(String(localized: L.treatmentDiffersFromClient))
            }
        }
        return result
    }

    /// The errors that block Issue; a missing rate counts once, as the inline form.
    var blockingErrors: [ValidationIssue] {
        errors.filter { !(rateIsMissing && $0.code == .exchangeRateMissing) }
    }

    /// Why the series cannot number the draft on its issue date (an issue date before the series year).
    func numberingProblem(seriesID: String?) -> String? {
        guard let document, let seriesID else { return nil }
        do {
            _ = try stores.series.peekNextNumber(seriesID: seriesID, on: document.issueDate)
            return nil
        } catch let error as DocumentNumberSeries.NumberingError {
            return ErrorText.message(error)
        } catch {
            // A series that disappeared is caught by the sheet's own list and by the store.
            return nil
        }
    }

    /// Every ⛔ row the review sheet shows for `seriesID`; the readiness chip shows the same count.
    func blockingCount(seriesID: String?) -> Int {
        blockingErrors.count + (rateIsMissing ? 1 : 0) + (series.isEmpty ? 1 : 0) + deductionConflicts.count
            + (numberingProblem(seriesID: seriesID) == nil ? 0 : 1) + invalidCellMessages.count + (receiptPaymentMissing ? 1 : 0)
    }

    func predictedNumber(seriesID: String) -> String? {
        guard let document else { return nil }
        return try? stores.series.peekNextNumber(seriesID: seriesID, on: document.issueDate)
    }

    /// Writes the draft, then issues it in the data layer's one transaction (ADR 0005): number, symbol,
    /// validation, totals, hash, audit. The supplier and client copies and the rate of the tax point are
    /// refreshed first (§ 4 odst. 8 ZDPH: a day's file may have been imported since the editor opened).
    /// The returned document carries its number.
    func issue(seriesID: String) throws -> Document {
        refreshSnapshots()
        refreshRate()
        // A draft stored before blank trailing lines were dropped is written again without them.
        if let last = document?.lines.last, Self.isBlankLine(last), saveState == .saved { saveState = .pending }
        saveNow()
        if saveState == .failed { throw DraftEditorError.saveFailed(saveError ?? "") }
        let issued = try stores.documents.issue(id: documentID, seriesID: seriesID)
        document = issued
        return issued
    }
}
