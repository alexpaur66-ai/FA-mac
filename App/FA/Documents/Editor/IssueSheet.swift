// The review-and-issue sheet (screens-flows.md §2c, ADR 0009 and its amendments): the number the series
// would assign, what the document will say, then the problems in three severities. ↩ issues when nothing
// blocks and every ⚠ row is checked; the data layer issues in one transaction (ADR 0005).

import InvoicingCore
import InvoicingData
import SwiftUI

struct IssueSheet: View {
    let model: DraftEditorModel
    let onIssued: @MainActor (Document) -> Void

    enum Field: Hashable {
        case checkbox
        case rate
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var seriesID: String?
    @State private var checked = false
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
        // The rate field comes first when a rate is missing: it is the one thing to type here (E073).
        .defaultFocus($focus, model.rateIsMissing ? .rate : .checkbox)
        .onAppear {
            // Settings may have changed the series or the accounts, a client sheet the clients, and a rate
            // file may have been imported while the editor was open (§ 4 odst. 8 ZDPH: the tax point's rate).
            model.refreshReferenceData()
            model.refreshRate()
            if seriesID == nil || !model.series.contains(where: { $0.id == seriesID }) {
                seriesID = model.series.first?.id
            }
        }
        // A changed set of ⚠ rows is checked again.
        .onChange(of: warningKey) { _, _ in checked = false }
    }

    // MARK: Heading and summary

    private func heading(_ document: Document) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title(document)).textRole(.screenTitle)
            Text(L.issueSubtitle).textRole(.rowSecondary)
            if model.series.count > 1 {
                Picker(selection: $seriesID) {
                    ForEach(model.series) { stored in
                        Text(verbatim: stored.name).tag(Optional(stored.id))
                    }
                } label: {
                    Text(L.seriesLabel)
                }
                .frame(maxWidth: 360)
            }
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

    private func summary(_ document: Document) -> some View {
        let clauses = DocumentClause.clauses(for: document, totals: model.totals).map { $0.text(language: .english) }
        return Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Spacing.l, verticalSpacing: Spacing.s) {
            row(L.summaryType) {
                Text(verbatim: document.kind.pickerTitle).textRole(.body)
            }
            row(L.summaryClient) {
                Text(clientLine(document)).textRole(.body)
            }
            row(L.summaryLanguage) {
                Text(document.language == .czech ? L.languageCzech : L.languageEnglish).textRole(.body)
            }
            row(L.summaryDates) {
                Text(datesLine(document)).textRole(.body)
            }
            row(L.summaryTotal) {
                totalsGrid(document)
            }
            if model.needsExchangeRate {
                row(L.summaryRate) {
                    rateLine(document)
                }
            }
            if showsPayment(document) {
                row(L.summaryPayment) {
                    paymentLine(document)
                }
            }
            if !clauses.isEmpty {
                row(L.summaryLegal) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        ForEach(clauses, id: \.self) { clause in
                            Text(verbatim: clause).textRole(.legalNote).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            row(L.pdfRow) {
                Text(verbatim: pdfLine(document)).textRole(.body).fixedSize(horizontal: false, vertical: true)
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

    /// Where Issue writes the PDF (screens-flows.md §2c), named with the predicted number, or that it stays
    /// in the app until Save PDF….
    private func pdfLine(_ document: Document) -> String {
        guard PDFSettings.autoSaveOnIssue else { return String(localized: L.pdfAutoSaveOff) }
        guard let folder = PDFSettings.folderURL() else { return String(localized: L.pdfNoFolder) }
        var predicted = document
        predicted.number = seriesID.flatMap { model.predictedNumber(seriesID: $0) }
        return String(localized: L.pdfWillBeSavedTo(PDFSettings.displayPath(PDFSettings.plannedURL(for: predicted, in: folder))))
    }

    private func clientLine(_ document: Document) -> LocalizedStringResource {
        let name = document.customer.name.isEmpty ? String(localized: L.noClient) : document.customer.name
        let treatment = String(localized: model.treatmentChoice.title)
        if let vatID = document.customer.vatIdentifier {
            return L.clientSummaryWithVATID(name, vatID.value, treatment)
        }
        return L.clientSummary(name, treatment)
    }

    private func datesLine(_ document: Document) -> LocalizedStringResource {
        let issued = document.issueDate.formatted(locale)
        let due = document.dueDate.formatted(locale)
        if document.kind == .advanceRequest {
            return L.datesSummaryNoTaxPoint(issued, due)
        }
        return L.datesSummary(issued, document.taxPoint.formatted(locale), due)
    }

    /// The same figures as the editor's totals bar, one per line: Total, the VAT (or why there is none),
    /// the VAT in CZK, and on a final invoice the advances deducted and the amount due.
    @ViewBuilder private func totalsGrid(_ document: Document) -> some View {
        if let totals = model.totals {
            let code = document.currency.code
            let chargesVAT = totals.rows.contains(where: { $0.treatment.chargesVAT })
            let isFinal = document.kind == .finalInvoice
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Spacing.m, verticalSpacing: Spacing.xxs) {
                moneyRow(L.total, totals.totalGross, code, role: isFinal ? .amount : .amountStrong)
                if chargesVAT {
                    if isFinal {
                        moneyRow(L.vatAfterAdvances, totals.taxableVAT, code)
                    } else {
                        moneyRow(L.vat, totals.totalVAT, code)
                    }
                    if document.currency != .czk, model.needsExchangeRate {
                        if let czk = totals.taxableVATCZK {
                            moneyRow(L.vatInCZK, czk, "CZK")
                        } else {
                            dashRow(L.vatInCZK, clause: nil)
                        }
                    }
                } else {
                    // Reverse charge: the dash carries the notice the PDF prints (§ 29 odst. 2 písm. c) ZDPH).
                    dashRow(L.vat, clause: document.hasReverseCharge ? DocumentClause.reverseChargeNotice : nil)
                }
                if isFinal {
                    let deducted = totals.totalGross - totals.amountDue
                    if deducted != 0 {
                        moneyRow(L.advancesDeducted, -deducted, code)
                    }
                    moneyRow(L.amountDue, totals.amountDue, code, role: .amountStrong)
                }
            }
        } else {
            InlineMessage(model.totalsError ?? String(localized: L.totalsUnavailable), kind: .warning)
        }
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
                Text(L.vatDashWithClause(clause)).textRole(.amount).gridColumnAlignment(.trailing)
            } else {
                Text(verbatim: "—").textRole(.amount).gridColumnAlignment(.trailing)
            }
        }
    }

    @ViewBuilder private func rateLine(_ document: Document) -> some View {
        if let rate = document.exchangeRate {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(L.rateEquals(document.currency.code, DraftEditorView.rateText(rate, locale: locale))).textRole(.amount)
                Text(L.rateDetails(rate.validFor.formatted(locale), RateSourceName.text(rate.source))).textRole(.rowSecondary)
                // A refresh that failed (the rates could not be read again) shows here as in the editor.
                if let rateError = model.rateError {
                    InlineMessage(rateError)
                }
            }
        } else {
            // The day whose rate is needed (the last working day on a weekend or holiday), as the form prefills it.
            Text(L.rateMissing(document.currency.code, model.neededRateDay.formatted(locale))).textRole(.body)
        }
    }

    /// A payment tax document asks for nothing (its payment has been received), nor does a final invoice
    /// whose advances cover the supply.
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
        if let account {
            let accountText = String(localized: DraftEditorView.accountLabel(account))
            let qrKind = document.payment?.qrCode
                ?? PaymentInstructions.standard(for: "", bankConnection: account, currency: document.currency).qrCode
            let qrText = String(localized: Self.qrKindTitle(qrKind))
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                if let symbol = predictedVariableSymbol() {
                    Text(L.paymentSummaryWithVS(accountText, qrText, symbol)).textRole(.body)
                } else {
                    Text(L.paymentSummary(accountText, qrText)).textRole(.body)
                }
                if document.payment == nil {
                    Text(L.paymentFromProfile).textRole(.rowSecondary)
                }
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
        // The missing rate shows as the inline form, not as a second row.
        let errors = model.blockingErrors
        let numberingProblem = model.numberingProblem(seriesID: seriesID)
        let warnings = model.warnings
        let extraWarnings = model.extraWarnings
        let dateNotToday = document.issueDate != today
        let infos = infoLines(document)
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
                    RateEntryForm(model: model, stores: model.stores, focus: $focus, focusValue: .rate)
                }
                if model.series.isEmpty {
                    HStack(spacing: Spacing.m) {
                        InlineMessage(L.noSeriesForKind)
                        SettingsLink { Text(L.openSettings) }
                    }
                }
            }
        }
        if !warnings.isEmpty || !extraWarnings.isEmpty || dateNotToday {
            section(L.checkTitle) {
                ForEach(warnings) { issue in
                    InlineMessage(issue.message(language: .english), kind: .warning)
                }
                ForEach(extraWarnings, id: \.self) { warning in
                    InlineMessage(warning, kind: .warning)
                }
                if dateNotToday {
                    HStack(spacing: Spacing.m) {
                        InlineMessage(L.issueDateNotToday(document.issueDate.formatted(locale)), kind: .warning)
                        Button { model.setIssueDate(today) } label: { Text(L.setToToday) }
                    }
                }
                Toggle(isOn: $checked) { Text(L.checkedLabel) }
                    .toggleStyle(.checkbox)
                    .focused($focus, equals: .checkbox)
            }
        }
        if !infos.isEmpty {
            section(L.infoTitle) {
                ForEach(infos, id: \.self) { line in
                    InlineMessage(line, kind: .info)
                }
            }
        }
    }

    private func infoLines(_ document: Document) -> [String] {
        var lines: [String] = []
        if let from = model.rateFallbackFrom {
            let used = from.formatted(locale)
            let resource: LocalizedStringResource
            if let resolution = model.rateResolution, resolution.rule == .noPublicationThatDay {
                resource = L.rateNotPublished(resolution.publicationDay.formatted(locale), used)
            } else {
                resource = L.rateFallback(document.taxPoint.formatted(locale), used)
            }
            lines.append(String(localized: resource))
        }
        if document.kind != .advanceRequest,
           (document.taxPoint.year, document.taxPoint.month) != (document.issueDate.year, document.issueDate.month) {
            lines.append(String(localized: L.taxPointOtherMonth))
        }
        return lines
    }

    /// What the Checked box vouches for; when it changes, the box is cleared.
    private var warningKey: [String] {
        var key = model.warnings.map { String(describing: $0.code) }
        key.append(contentsOf: model.extraWarnings)
        if let document = model.document, document.issueDate != CalendarDay(Date(), in: .current) {
            key.append(document.issueDate.formatted(locale))
        }
        return key
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
        let needsCheck = !model.warnings.isEmpty || !model.extraWarnings.isEmpty
            || document.issueDate != CalendarDay(Date(), in: .current)
        return !needsCheck || checked
    }

    private func issue() {
        guard let seriesID else { return }
        issuing = true
        do {
            let issued = try model.issue(seriesID: seriesID)
            dismiss()
            onIssued(issued)
        } catch DraftEditorError.saveFailed(let detail) {
            issuing = false
            error = String(localized: L.issueFailed(detail))
        } catch {
            issuing = false
            self.error = String(localized: L.issueFailed(ErrorText.message(error, locale: locale)))
        }
    }
}
