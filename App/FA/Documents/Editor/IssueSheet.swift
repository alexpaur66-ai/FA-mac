// The review-and-issue sheet (screens-flows.md §2c, ADR 0009 and its amendments, lean pass docs-27/28): the
// number the series would assign, seven summary rows and two conditional ones, then what blocks Issue and
// what to check. ↩ issues when nothing blocks and every ⚠ row is ticked; the data layer issues in one
// transaction (ADR 0005).

import InvoicingCore
import InvoicingData
import SwiftUI

struct IssueSheet: View {
    let model: DraftEditorModel
    let onIssued: @MainActor (Document) -> Void

    enum Field: Hashable {
        /// The Checked tick of one ⚠ row, by the row's id.
        case check(String)
        case rate
    }

    /// One ⚠ row: its words, and Set to Today for the issue date.
    struct CheckRow: Identifiable {
        let id: String
        let text: String
        var setsToday = false
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var seriesID: String?
    @AppStorage(SettingsPane.storageKey) private var settingsPane: SettingsPane = .general
    @Environment(\.openSettings) private var openSettings
    /// The ⚠ rows ticked so far; a row whose words change is a new row and needs its own tick.
    @State private var checkedIDs: Set<String> = []
    @State private var issuing = false
    @State private var error: String?
    @FocusState private var focus: Field?

    init(model: DraftEditorModel, onIssued: @escaping @MainActor (Document) -> Void) {
        self.model = model
        self.onIssued = onIssued
        _seriesID = State(initialValue: model.series.first?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            if issuing {
                // Between the store's commit and the dismissal the draft is already issued; the sheet must
                // not flash "This draft no longer exists" then.
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .frame(minHeight: 160)
            } else if let document = model.document, document.status == .draft {
                heading(document)
                summary(document)
                problems(document)
                if let error {
                    InlineMessage(error)
                }
                HStack {
                    Spacer()
                    Button { dismiss() } label: { Text(L.cancel) }
                        .keyboardShortcut(.cancelAction)
                    Button { issue() } label: { Text(L.issueButton) }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canIssue(document))
                }
            } else {
                Text(L.draftGone).textRole(.body)
                HStack {
                    Spacer()
                    Button { dismiss() } label: { Text(L.cancel) }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(Spacing.xl)
        .formSheetSized()
        // The rate field comes first when a rate is missing: it is the one thing to type here (E073); else
        // the first ⚠ row's tick (docs-28).
        .defaultFocus($focus, initialFocus)
        .onAppear {
            // Settings may have changed the series or the accounts, a client sheet the clients, and a rate
            // file may have been imported while the editor was open (§ 4 odst. 8 ZDPH: the rate day's rate).
            model.refreshReferenceData()
            // A floating issue date is the day of Issue (docs-28): the sheet shows the day it will issue with.
            model.floatIssueDate()
            model.refreshRate()
            syncSeriesID()
        }
        // Settings ▸ Numbering saved while the sheet stayed open (Open Settings… on the no-series row): the
        // series read again must also be the one Issue uses.
        .onChange(of: model.series.map(\.id)) { _, _ in
            syncSeriesID()
        }
    }

    /// Keeps `seriesID` on a series the model still offers.
    private func syncSeriesID() {
        if seriesID == nil || !model.series.contains(where: { $0.id == seriesID }) {
            seriesID = model.series.first?.id
        }
    }

    private var initialFocus: Field? {
        if model.rateIsMissing { return .rate }
        guard let document = model.document, let first = checkRows(document).first else { return nil }
        return .check(first.id)
    }

    // MARK: Heading and summary

    private func heading(_ document: Document) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title(document)).textRole(.screenTitle)
            Text(L.issueSubtitle).textRole(.rowSecondary)
        }
    }

    /// "Issue invoice FV-2026-007?": the kind in the question, the number the series would assign.
    private func title(_ document: Document) -> LocalizedStringResource {
        let number = seriesID.flatMap { model.predictedNumber(seriesID: $0) }
        switch document.kind {
        case .invoice: return number.map { L.issueInvoiceTitle($0) } ?? L.issueInvoiceTitleNoNumber
        case .advanceRequest: return number.map { L.issueAdvanceTitle($0) } ?? L.issueAdvanceTitleNoNumber
        case .paymentTaxDocument: return number.map { L.issueTaxDocumentTitle($0) } ?? L.issueTaxDocumentTitleNoNumber
        case .finalInvoice: return number.map { L.issueFinalTitle($0) } ?? L.issueFinalTitleNoNumber
        }
    }

    /// Type, Client, Language, Dates, Total, Rate (EUR and USD tax documents) and Payment; the PDF row only
    /// when the PDF won't be written (docs-27). Every printed clause sits in the row it belongs to.
    private func summary(_ document: Document) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Spacing.l, verticalSpacing: Spacing.s) {
            row(L.summaryType) {
                if document.kind == .advanceRequest {
                    Text(L.typeNotTaxDocument(document.kind.pickerTitle)).textRole(.body)
                } else {
                    Text(verbatim: document.kind.pickerTitle).textRole(.body)
                }
            }
            row(L.summaryClient) {
                Text(clientLine(document)).textRole(.body)
            }
            row(L.summaryLanguage) {
                Text(document.language == .czech ? L.languageCzech : L.languageEnglish).textRole(.body)
            }
            row(L.summaryDates) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(datesLine(document)).textRole(.body)
                    if document.kind == .paymentTaxDocument, let day = document.taxPointDate {
                        Text(receivedLine(day, advance: document.relatedDocumentNumber)).textRole(.rowSecondary)
                    }
                }
            }
            row(L.summaryTotal) {
                totalsGrid(document)
            }
            if model.needsExchangeRate {
                row(L.summaryRate) {
                    rateLine(document)
                }
            }
            row(L.summaryPayment) {
                paymentLine(document)
            }
            if let notice = pdfNotice {
                row(L.pdfRow) {
                    Text(notice).textRole(.body).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func row<Content: View>(_ label: LocalizedStringResource, @ViewBuilder _ content: () -> Content) -> some View {
        GridRow {
            Text(label).textRole(.label)
            content()
                .textSelection(.enabled)
                .gridColumnAlignment(.leading)
        }
    }

    /// The PDF row appears only when no PDF folder is chosen (set-04): it says where the PDF stays and where
    /// to choose a folder. With a folder, the result line names the file after Issue.
    private var pdfNotice: LocalizedStringResource? {
        PDFSettings.folderURL() == nil ? L.pdfNoFolder : nil
    }

    private func clientLine(_ document: Document) -> LocalizedStringResource {
        let name = document.customer.name.isEmpty ? String(localized: L.noClient) : document.customer.name
        let treatment = String(localized: model.treatmentChoice.shortTitle)
        if let vatID = document.customer.vatIdentifier {
            return L.clientSummaryWithVATID(name, vatID.value, treatment)
        }
        return L.clientSummary(name, treatment)
    }

    /// "Issued today · DUZP 31. 10. 2026 · Due 14. 11. 2026"; no DUZP on an advance, no due date on a
    /// payment tax document, which asks for no payment.
    private func datesLine(_ document: Document) -> LocalizedStringResource {
        let issued = document.issueDate == CalendarDay(Date(), in: .current)
            ? String(localized: L.todayWord) : document.issueDate.formatted(locale)
        let due = document.dueDate.formatted(locale)
        switch document.kind {
        case .advanceRequest: return L.datesSummaryNoTaxPoint(issued, due)
        case .paymentTaxDocument: return L.datesSummaryNoDue(issued, document.taxPoint.formatted(locale))
        case .invoice, .finalInvoice: return L.datesSummary(issued, document.taxPoint.formatted(locale), due)
        }
    }

    /// "Payment received 12. 11. 2026 against ZF 2026-0003": the payment clause of a payment tax document.
    private func receivedLine(_ day: CalendarDay, advance: String?) -> LocalizedStringResource {
        if let advance { return L.paymentReceivedAgainst(day.formatted(locale), advance) }
        return L.paymentReceivedOn(day.formatted(locale))
    }

    /// Total, then one VAT row per rate under Czech VAT, or the VAT row with the printed clause under the
    /// other treatments (docs-27); the VAT in CZK on EUR and USD; on a final invoice the advances deducted
    /// with their tax documents (and rates), the advances paid and the amount due.
    @ViewBuilder private func totalsGrid(_ document: Document) -> some View {
        if let totals = model.totals {
            let code = document.currency.code
            let chargesVAT = totals.rows.contains(where: { $0.treatment.chargesVAT })
            let isFinal = document.kind == .finalInvoice
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Spacing.m, verticalSpacing: Spacing.xxs) {
                moneyRow(L.total, totals.totalGross, code, role: isFinal ? .amount : .amountStrong)
                if chargesVAT {
                    ForEach(Array(totals.rows.enumerated()), id: \.offset) { _, vatRow in
                        if vatRow.treatment.chargesVAT {
                            moneyRow(vatLabel(vatRow, afterAdvances: isFinal), isFinal ? vatRow.taxableVAT : vatRow.vat, code)
                        }
                    }
                    // Lines without Czech VAT beside a Czech-VAT deduction (a final invoice deducting an advance
                    // taxed under another treatment): the PDF still prints their clause.
                    ForEach(Array(document.treatments.filter { !$0.chargesVAT }.enumerated()), id: \.offset) { _, treatment in
                        dashRow(L.vat, clause: clause(for: treatment, language: document.language))
                    }
                    if document.currency != .czk, model.needsExchangeRate {
                        if let czk = totals.taxableVATCZK {
                            moneyRow(L.vatInCZK, czk, "CZK")
                        } else {
                            dashRow(L.vatInCZK, clause: nil)
                        }
                    }
                } else {
                    dashRow(L.vat, clause: untaxedClause(document))
                }
                if isFinal {
                    let deducted = totals.totalGross - totals.dueBeforePaidInAdvance
                    if deducted != 0 {
                        GridRow {
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(L.advancesDeducted).textRole(.body)
                                Text(verbatim: deductedNumbers(document)).textRole(.rowSecondary)
                            }
                            MoneyText(amount: -deducted, currency: code, locale: locale, role: .amount)
                                .gridColumnAlignment(.trailing)
                        }
                    }
                    // Advances paid on § 64 goods reduce only what is left to pay (ADR 0012).
                    if totals.paidInAdvance != 0 {
                        moneyRow(L.paidInAdvanceTitle, -totals.paidInAdvance, code)
                    }
                    moneyRow(L.amountDue, totals.amountDue, code, role: .amountStrong)
                }
            }
        } else {
            InlineMessage(model.totalsError ?? String(localized: L.totalsUnavailable), kind: .problem)
        }
    }

    /// "VAT 21 %", or "VAT after advances 21 %" on a final invoice.
    private func vatLabel(_ vatRow: VATSummaryRow, afterAdvances: Bool) -> LocalizedStringResource {
        guard let percent = vatRow.appliedRatePercent else { return afterAdvances ? L.vatAfterAdvances : L.vat }
        let text = VATRateField<EditorFocus>.percentText(percent, locale: locale)
        return afterAdvances ? L.vatAfterAdvancesAtRate(text) : L.vatAtRate(text)
    }

    /// The clause the PDF prints in the VAT's place: the reverse-charge words, or the treatment's clause in
    /// the document's language (DocumentClause).
    private func untaxedClause(_ document: Document) -> String? {
        switch model.treatmentChoice {
        case .czechVAT: return nil
        case .reverseChargeEU: return DocumentClause.reverseChargeNotice
        case .intraCommunityGoods: return DocumentClause.intraCommunitySupply.text(language: document.language)
        case .outsideEU: return DocumentClause.outsideScope.text(language: document.language)
        case .exempt: return DocumentClause.exempt(reference: model.exemptReference).text(language: document.language)
        }
    }

    /// The clause one line treatment prints (DocumentClause.clauses), nil under Czech VAT.
    private func clause(for treatment: VATTreatment, language: DocumentLanguage) -> String? {
        switch treatment {
        case .taxable: return nil
        case .reverseChargeEU: return DocumentClause.reverseChargeNotice
        case .intraCommunityGoods: return DocumentClause.intraCommunitySupply.text(language: language)
        case .outsideEU: return DocumentClause.outsideScope.text(language: language)
        case .exempt(let reference): return DocumentClause.exempt(reference: reference).text(language: language)
        }
    }

    /// "DD 2026-0001, DD 2026-0002", each with the advance's rate on a EUR or USD document.
    private func deductedNumbers(_ document: Document) -> String {
        var seen: Set<String> = []
        var items: [String] = []
        for deduction in document.advanceDeductions where seen.insert(deduction.documentNumber).inserted {
            if document.currency != .czk, let rate = deduction.exchangeRate {
                items.append(String(localized: L.deductionAtRate(deduction.documentNumber, DraftEditorView.rateText(rate, locale: locale))))
            } else {
                items.append(deduction.documentNumber)
            }
        }
        return items.joined(separator: ", ")
    }

    private func moneyRow(_ label: LocalizedStringResource, _ amount: Decimal, _ code: String, role: TextRole = .amount) -> some View {
        GridRow {
            Text(label).textRole(.body)
            MoneyText(amount: amount, currency: code, locale: locale, role: role)
                .gridColumnAlignment(.trailing)
        }
    }

    private func dashRow(_ label: LocalizedStringResource, clause: String?) -> some View {
        GridRow {
            Text(label).textRole(.body)
            if let clause {
                Text(L.vatDashWithClause(clause)).textRole(.amount).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(verbatim: "—").textRole(.amount).gridColumnAlignment(.trailing)
            }
        }
    }

    /// "24,315 · for 30. 10. 2026 · Typed", or "… · last published" for a rule-6 fallback; the inline form
    /// shows here while the rate is missing (docs-27 row 6), and "Fix before issuing" names the missing rate.
    @ViewBuilder private func rateLine(_ document: Document) -> some View {
        if let rate = document.exchangeRate {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                let value = DraftEditorView.rateText(rate, locale: locale)
                let day = rate.validFor.formatted(locale)
                let source = RateSourceName.text(rate.source)
                Text(model.rateFallbackFrom == nil ? L.rateSummary(value, day, source) : L.rateSummaryFallback(value, day, source))
                    .textRole(.amount)
                // A refresh that failed (the rates could not be read again) shows here as in the editor.
                if let rateError = model.rateError {
                    InlineMessage(rateError)
                }
            }
        } else {
            // The form names the day whose rate is needed (the last working day on a weekend or holiday).
            RateEntryForm(model: model, stores: model.stores, focus: $focus, focusValue: .rate)
        }
    }

    /// A payment tax document asks for nothing (its payment has been received), nor does a final invoice
    /// whose advances cover the supply: the Payment row says there is no payment request.
    private func showsPayment(_ document: Document) -> Bool {
        if document.kind == .paymentTaxDocument { return false }
        if document.kind == .finalInvoice, let totals = model.totals, totals.amountDue <= 0 { return false }
        return true
    }

    /// The account the issued document will carry: the one picked in the header, else the company's
    /// account for the currency (the data layer fills it at issue), the QR code it gets and the variable
    /// symbol the number gives.
    @ViewBuilder private func paymentLine(_ document: Document) -> some View {
        let account = document.payment?.bankConnection ?? model.profile?.bankConnection(for: document.currency)
        if !showsPayment(document) {
            Text(L.noPaymentRequest).textRole(.body)
        } else if let account {
            let accountText = String(localized: DraftEditorView.accountLabel(account))
            let qrKind = document.payment?.qrCode
                ?? PaymentInstructions.standard(for: "", bankConnection: account, currency: document.currency).qrCode
            let qrText = String(localized: Self.qrKindTitle(qrKind))
            if let symbol = predictedVariableSymbol() {
                Text(L.paymentSummaryWithVS(accountText, qrText, symbol)).textRole(.body)
            } else {
                Text(L.paymentSummary(accountText, qrText)).textRole(.body)
            }
        } else {
            Text(L.noPayment).textRole(.body)
        }
    }

    static func qrKindTitle(_ kind: PaymentQRKind) -> LocalizedStringResource {
        switch kind {
        case .qrPlatba: L.qrKindQRPlatba
        case .sepa: L.qrKindSEPA
        case .none: L.qrKindNone
        }
    }

    private func predictedVariableSymbol() -> String? {
        guard let seriesID, let stored = model.series.first(where: { $0.id == seriesID }),
              let number = model.predictedNumber(seriesID: seriesID),
              let symbol = PaymentSymbol.variable(fromDocumentNumber: number, prefix: stored.series.variableSymbolPrefix)
        else { return nil }
        return symbol.digits
    }

    // MARK: Problems

    @ViewBuilder private func problems(_ document: Document) -> some View {
        let today = CalendarDay(Date(), in: .current)
        // The missing rate is typed in the Rate row's inline form; this section only names it.
        let errors = model.blockingErrors
        let numberingProblem = model.numberingProblem(seriesID: seriesID)
        let rows = checkRows(document)
        if model.blockingCount(seriesID: seriesID) > 0 {
            section(L.blockingTitle) {
                ForEach(errors) { issue in
                    InlineMessage(issue.message(language: .english))
                }
                ForEach(model.deductionConflicts, id: \.self) { conflict in
                    InlineMessage(conflict)
                }
                if let numberingProblem {
                    InlineMessage(numberingProblem)
                }
                ForEach(model.invalidCellMessages, id: \.self) { message in
                    InlineMessage(message)
                }
                if model.receiptPaymentMissing {
                    InlineMessage(L.receiptPaymentMissing)
                }
                if model.receiptTotalDiffers, let payment = model.receiptPayment {
                    InlineMessage(L.receiptTotalMismatch(MoneyText.format(payment.amount.amount, currency: payment.amount.currency.code, locale: locale)))
                }
                if model.rateIsMissing {
                    InlineMessage(L.rateMissing(document.currency.code, model.neededRateDay.formatted(locale)))
                }
                if model.series.isEmpty {
                    HStack(spacing: Spacing.m) {
                        InlineMessage(L.noSeriesForKind)
                        Button { openNumbering() } label: { Text(L.openSettings) }
                    }
                } else if model.numberingUnconfirmed {
                    HStack(spacing: Spacing.m) {
                        InlineMessage(L.confirmNumberSeries)
                        Button { openNumbering() } label: { Text(L.fillIn) }
                    }
                }
            }
        }
        if !rows.isEmpty {
            section(L.checkTitle) {
                ForEach(rows) { checkRow in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
                        InlineMessage(checkRow.text, kind: .problem)
                        if checkRow.setsToday {
                            Button { model.setIssueDate(today) } label: { Text(L.setToToday) }
                        }
                        Spacer(minLength: Spacing.s)
                        Toggle(isOn: checkedBinding(checkRow.id)) { Text(L.checkedLabel) }
                            .toggleStyle(.checkbox)
                            .focused($focus, equals: .check(checkRow.id))
                    }
                }
            }
        }
    }

    /// The validator's warnings, the editor's own checks (one defaults row, the 50 % total change, an
    /// advance under another treatment, a receipt in another draft), then the issue date: one set by hand that
    /// is not today, or a floating one that moves a "Same as the issue date" DUZP into a later month (docs-28).
    private func checkRows(_ document: Document) -> [CheckRow] {
        var rows: [CheckRow] = []
        for issue in model.warnings {
            let text = issue.message(language: .english)
            rows.append(CheckRow(id: "validator|\(issue.code)|\(text)", text: text))
        }
        for warning in model.extraWarnings {
            rows.append(CheckRow(id: "editor|\(warning)", text: warning))
        }
        let today = CalendarDay(Date(), in: .current)
        if model.issueDateSetByHand {
            if document.issueDate != today {
                rows.append(CheckRow(id: "issueDate|\(document.issueDate)",
                                     text: String(localized: L.issueDateNotToday(document.issueDate.formatted(locale))), setsToday: true))
            }
        } else if document.kind.isTaxDocument, document.kind != .paymentTaxDocument, model.taxPointSameAsIssue,
                  let started = model.startedOn, started.startOfMonth < document.issueDate.startOfMonth {
            rows.append(CheckRow(id: "floatedMonth|\(started)|\(document.issueDate)",
                                 text: String(localized: L.floatedIntoLaterMonth(started.formatted(locale), document.issueDate.formatted(locale)))))
        }
        return rows
    }

    /// Fill in… and Open Settings… open Settings on the Numbering pane (set-09); the sheet stays, and its
    /// rows are read again when it next appears.
    private func openNumbering() {
        settingsPane = .numbering
        openSettings()
    }

    private func checkedBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { checkedIDs.contains(id) }, set: { on in
            if on { checkedIDs.insert(id) } else { checkedIDs.remove(id) }
        })
    }

    private func section<Content: View>(_ title: LocalizedStringResource, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title).textRole(.sectionTitle)
            content()
        }
    }

    // MARK: Issue

    private func canIssue(_ document: Document) -> Bool {
        // The same count as the ⛔ section and the editor's readiness chip.
        guard seriesID != nil, model.blockingCount(seriesID: seriesID) == 0 else { return false }
        return checkRows(document).allSatisfy { checkedIDs.contains($0.id) }
    }

    private func issue() {
        guard let seriesID else { return }
        issuing = true
        do {
            let issued = try model.issue(seriesID: seriesID)
            dismiss()
            onIssued(issued)
        } catch DraftEditorError.issueDateMoved {
            // Nothing was issued: the sheet shows the new day's date, number and checks before Issue again.
            issuing = false
            error = String(localized: L.issueDateMovedToToday)
        } catch DraftEditorError.saveFailed(let detail) {
            issuing = false
            error = String(localized: L.issueFailed(detail))
        } catch {
            issuing = false
            self.error = String(localized: L.issueFailed(ErrorText.message(error, locale: locale)))
        }
    }
}
