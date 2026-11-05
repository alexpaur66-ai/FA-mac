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
    /// Why the last rate lookup or typed rate failed; shown beside the rate line.
    private(set) var rateError: String?
    /// Why the last "Add tax document…" failed; shown in the advances section.
    private(set) var deductionError: String?
    /// Deductions of receipts that another issued final invoice already deducts (screens-flows.md §2c, ⛔).
    private(set) var deductionConflicts: [String] = []
    /// True once the user picked an explicit tax point; otherwise the tax point follows the issue date.
    private(set) var taxPointExplicit = false
    private(set) var customers: [Customer] = []
    private(set) var series: [StoredNumberSeries] = []
    private(set) var profile: CompanyProfile?
    private(set) var treatmentChoice: TreatmentChoice = .czechVAT
    /// The exemption reference typed in the header, kept while another treatment is selected.
    private(set) var exemptReference = ""
    /// The day the document's rate was published for, when that is earlier than its tax point (rule 6).
    private(set) var rateFallbackFrom: CalendarDay?

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// Set when the draft was deleted: nothing is written any more (a pending save would re-create it).
    @ObservationIgnored private var discarded = false

    init(stores: Stores, documentID: String) {
        self.stores = stores
        self.documentID = documentID
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
            recompute()
            // A draft saved without its tax point (an older draft) gets the issue date, which the validator needs.
            if document.kind.isTaxDocument && document.taxPointDate == nil {
                update { Self.followIssueDate(&$0, explicitTaxPoint: false) }
            }
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
            totalsError = ErrorText.message(error)
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

    /// Writes the draft now; the editor calls it when it goes away and before Issue. False when the
    /// save failed (`saveError` says why), so the caller can tell the user before the edits are dropped.
    @discardableResult
    func saveNow() -> Bool {
        saveTask?.cancel()
        saveTask = nil
        guard !discarded, saveState != .saved, let document, document.status == .draft else { return true }
        do {
            try stores.documents.saveDraft(Self.strippingBlankTrailingLine(document))
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

    nonisolated static func strippingBlankTrailingLine(_ document: Document) -> Document {
        var copy = document
        if let last = copy.lines.last, isBlankLine(last) { copy.lines.removeLast() }
        return copy
    }

    /// What the validator sees: the draft without its blank trailing line and, when no account is
    /// picked, with the company's account for the currency that `DocumentStore.issue` will fill in.
    nonisolated static func validationPreview(of document: Document, profile: CompanyProfile?) -> Document {
        var preview = strippingBlankTrailingLine(document)
        if preview.payment == nil, let account = profile?.bankConnection(for: preview.currency) {
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

    // MARK: Header fields

    var customer: Customer? {
        customers.first { $0.id == document?.customerID }
    }

    /// A new client brings its defaults: currency, language, due days, VAT treatment (screens-flows.md §2c).
    func setCustomer(_ id: String?) {
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
        refreshDeductionConflicts()
        refreshRate()
    }

    /// Re-reads the clients, the company profile and the series that number the draft's kind: a client
    /// sheet or Settings may have changed them while the editor is open.
    func refreshReferenceData() {
        guard !discarded, let document else { return }
        if let fresh = try? stores.customers.all() { customers = fresh }
        if let fresh = try? stores.profile.load() { profile = fresh }
        series = (try? stores.series.series(for: document.kind)) ?? []
        refreshDeductionConflicts()
        recompute()
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

    /// Prices are not converted (screens-flows.md §2c); the account and the rate are re-picked.
    func setCurrency(_ currency: Currency) {
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
        refreshRate()
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

    func setRelatedDocumentNumber(_ text: String) {
        update { $0.relatedDocumentNumber = text.isEmpty ? nil : text }
    }

    func setNote(_ text: String) {
        update { $0.note = text.isEmpty ? nil : text }
    }

    func setFooter(_ text: String) {
        update { $0.footer = text.isEmpty ? nil : text }
    }

    // MARK: Lines

    private var newLineTreatment: VATTreatment {
        if treatmentChoice == .czechVAT, case .taxable(let kind)? = document?.lines.last?.treatment {
            return .taxable(kind)
        }
        return treatmentChoice.apply(to: nil, exemptReference: exemptReference)
    }

    @discardableResult
    func addLine() -> String {
        let line = DocumentLine(text: "", quantity: 1, unit: nil, unitPrice: 0, treatment: newLineTreatment)
        update { doc in doc.lines.append(line) }
        return line.id
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

    func removeLine(_ id: String) {
        update { doc in doc.lines.removeAll { $0.id == id } }
    }

    func moveLine(_ id: String, by offset: Int) {
        update { doc in
            guard let index = doc.lines.firstIndex(where: { $0.id == id }) else { return }
            let target = index + offset
            guard doc.lines.indices.contains(target) else { return }
            doc.lines.swapAt(index, target)
        }
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

    // MARK: Exchange rate

    /// A tax document in a foreign currency needs the rate of its tax point (§ 4 odst. 8 ZDPH). The data
    /// layer gives the last rate published on or before that day (rule 6), or nothing when the table ends
    /// earlier; then the user types the rate.
    var needsExchangeRate: Bool {
        guard let document else { return false }
        return document.kind.isTaxDocument && document.currency != .czk
    }

    var rateIsMissing: Bool {
        needsExchangeRate && document?.exchangeRate == nil
    }

    func refreshRate() {
        guard !discarded, let document else { return }
        rateError = nil
        guard needsExchangeRate else {
            rateFallbackFrom = nil
            if document.exchangeRate != nil { update { $0.exchangeRate = nil } }
            return
        }
        do {
            let rate = try stores.rates.rate(for: document.currency, on: document.taxPoint)
            rateFallbackFrom = rate.flatMap { $0.validFor != document.taxPoint ? $0.validFor : nil }
            if rate != document.exchangeRate { update { $0.exchangeRate = rate } }
        } catch {
            rateError = ErrorText.message(error)
        }
    }

    /// Saves a typed rate for the tax point (source "typed in") and puts it on the document. A rate
    /// already stored for that day (imported meanwhile) is never overwritten: the document takes it.
    func saveManualRate(_ czkPerUnit: Decimal) {
        guard let document, czkPerUnit > 0 else { return }
        rateError = nil
        let rate = ExchangeRate(currency: document.currency, amount: 1, czkPerAmount: czkPerUnit,
                                validFor: document.taxPoint, source: .manual)
        do {
            if let stored = try stores.rates.rate(for: document.currency, on: document.taxPoint),
               stored.validFor == document.taxPoint {
                refreshRate()
                return
            }
            try stores.rates.save(rate)
            rateFallbackFrom = nil
            update { $0.exchangeRate = rate }
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
    /// receipt, `linkDeductions`): a ⛔ row naming that invoice instead of a refusal after the click.
    private func refreshDeductionConflicts() {
        guard let document, document.kind == .finalInvoice, !document.advanceDeductions.isEmpty else {
            deductionConflicts = []
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
        } catch {
            deductionConflicts = []
            deductionError = ErrorText.message(error)
        }
    }

    // MARK: Issue

    var errors: [ValidationIssue] {
        issues.filter(\.isError)
    }

    var warnings: [ValidationIssue] {
        issues.filter { !$0.isError }
    }

    /// The validator's errors that block Issue; a missing rate counts once, as the inline form.
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
            + (numberingProblem(seriesID: seriesID) == nil ? 0 : 1)
    }

    func predictedNumber(seriesID: String) -> String? {
        guard let document else { return nil }
        return try? stores.series.peekNextNumber(seriesID: seriesID, on: document.issueDate)
    }

    /// Writes the draft, then issues it in the data layer's one transaction (ADR 0005): number, symbol,
    /// validation, totals, hash, audit. The rate of the tax point is read again first (§ 4 odst. 8 ZDPH),
    /// a day's file may have been imported since the editor opened. The returned document carries its number.
    func issue(seriesID: String) throws -> Document {
        refreshRate()
        // A draft stored before blank trailing lines were dropped is written again without it.
        if let last = document?.lines.last, Self.isBlankLine(last), saveState == .saved { saveState = .pending }
        saveNow()
        if saveState == .failed { throw DraftEditorError.saveFailed(saveError ?? "") }
        let issued = try stores.documents.issue(id: documentID, seriesID: seriesID)
        document = issued
        return issued
    }
}
