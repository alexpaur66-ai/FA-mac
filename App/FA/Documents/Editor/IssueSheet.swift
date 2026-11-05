// The review-and-issue sheet (screens-flows.md §2c, ADR 0009): the number the series would assign, what
// the document says in a few lines, then the problems in three severities. ↩ issues when nothing blocks
// and every ⚠ row is checked; the data layer issues in one transaction (ADR 0005).

import InvoicingCore
import InvoicingData
import SwiftUI

struct IssueSheet: View {
    let model: DraftEditorModel
    let onIssued: @MainActor (Document) -> Void

    private enum Field: Hashable {
        case checkbox
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var seriesID: String?
    @State private var checked = false
    @State private var error: String?
    @FocusState private var focus: Field?

    init(model: DraftEditorModel, onIssued: @escaping @MainActor (Document) -> Void) {
        self.model = model
        self.onIssued = onIssued
        _seriesID = State(initialValue: model.series.first?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            if let document = model.document, document.status == .draft {
                heading(document)
                summary(document)
                problems(document)
                if let error {
                    Text(verbatim: error).textRole(.caption).foregroundStyle(.red)
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
        .frame(minWidth: 560, maxWidth: 720)
        .defaultFocus($focus, .checkbox)
        .onAppear {
            // Settings may have gained or lost a series while the editor was open.
            model.refreshSeries()
            if seriesID == nil || !model.series.contains(where: { $0.id == seriesID }) {
                seriesID = model.series.first?.id
            }
        }
    }

    // MARK: Heading and summary

    private func heading(_ document: Document) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            let type = String(localized: document.kind.shortTitle)
            if let seriesID, let number = model.predictedNumber(seriesID: seriesID) {
                Text(L.issueTitle(type, number)).textRole(.screenTitle)
            } else {
                Text(L.issueTitleNoNumber(type)).textRole(.screenTitle)
            }
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

    private func summary(_ document: Document) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Spacing.l, verticalSpacing: Spacing.s) {
            row(L.summaryType, document.kind.title(language: document.language))
            row(L.summaryClient, clientLine(document))
            row(L.summaryDates, datesLine(document))
            row(L.summaryTotal, totalLine(document))
            if model.needsExchangeRate {
                row(L.summaryRate, rateLine(document))
            }
            if document.kind != .paymentTaxDocument {
                row(L.summaryPayment, paymentLine(document))
            }
        }
    }

    private func row(_ label: LocalizedStringResource, _ value: String) -> some View {
        GridRow {
            Text(label).textRole(.label)
            Text(verbatim: value).textRole(.body).textSelection(.enabled)
        }
    }

    private func clientLine(_ document: Document) -> String {
        var parts = [document.customer.name.isEmpty ? String(localized: L.noClient) : document.customer.name]
        if let vatID = document.customer.vatIdentifier {
            parts.append(String(localized: L.vatID(vatID.value)))
        }
        parts.append(String(localized: document.language == .czech ? L.languageCzech : L.languageEnglish))
        parts.append(String(localized: model.treatmentChoice.title))
        return parts.joined(separator: " · ")
    }

    private func datesLine(_ document: Document) -> String {
        var parts = [String(localized: L.issuedOnDay(document.issueDate.formatted(locale)))]
        if document.kind != .advanceRequest {
            parts.append(String(localized: L.taxPointOn(document.taxPoint.formatted(locale))))
        }
        parts.append(String(localized: L.dueOnDay(document.dueDate.formatted(locale))))
        return parts.joined(separator: " · ")
    }

    private func totalLine(_ document: Document) -> String {
        guard let totals = model.totals else { return String(localized: L.totalsUnavailable) }
        let code = document.currency.code
        var parts = [MoneyText.format(totals.totalGross, currency: code, locale: locale)]
        if totals.rows.contains(where: { $0.treatment.chargesVAT }) {
            parts.append(String(localized: L.vat) + " " + MoneyText.format(totals.totalVAT, currency: code, locale: locale))
            if let czk = totals.taxableVATCZK, document.currency != .czk {
                parts.append(String(localized: L.vatInCZK) + " " + MoneyText.format(czk, currency: "CZK", locale: locale))
            }
        } else {
            switch model.treatmentChoice {
            case .reverseChargeEU: parts.append(String(localized: L.noVATReverseCharge))
            case .outsideEU: parts.append(String(localized: L.noVATOutsideEU))
            case .exempt: parts.append(String(localized: L.noVATExempt))
            case .czechVAT: break
            }
        }
        if document.kind == .finalInvoice {
            parts.append(String(localized: L.amountDue) + " " + MoneyText.format(totals.amountDue, currency: code, locale: locale))
        }
        return parts.joined(separator: " · ")
    }

    private func rateLine(_ document: Document) -> String {
        guard let rate = document.exchangeRate else {
            return String(localized: L.rateMissing(document.currency.code, document.taxPoint.formatted(locale)))
        }
        return String(localized: L.rateLine(rate.czechLabel, rate.validFor.formatted(locale), RateEntryForm.sourceName(rate.source)))
    }

    /// The account the issued document will carry: the one picked in the header, else the company's
    /// account for the currency (the data layer fills it at issue), and the variable symbol the number gives.
    private func paymentLine(_ document: Document) -> String {
        let account = document.payment?.bankConnection ?? model.profile?.bankConnection(for: document.currency)
        guard let account else { return String(localized: L.noPayment) }
        var parts = [account.bankName.map { $0 + " · " + account.iban.value } ?? account.iban.value]
        if let seriesID, let stored = model.series.first(where: { $0.id == seriesID }),
           let number = model.predictedNumber(seriesID: seriesID),
           let symbol = PaymentSymbol.variable(fromDocumentNumber: number, prefix: stored.series.variableSymbolPrefix) {
            parts.append(String(localized: L.vsPredicted(symbol.digits)))
        }
        if document.payment == nil {
            parts.append(String(localized: L.paymentFromProfile))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Problems

    @ViewBuilder private func problems(_ document: Document) -> some View {
        let today = CalendarDay(Date(), in: .current)
        // The missing rate shows as the inline form, not as a second row.
        let errors = model.errors.filter { !(model.rateIsMissing && $0.code == .exchangeRateMissing) }
        let warnings = model.warnings
        let dateNotToday = document.issueDate != today
        let infos = infoLines(document)
        if !errors.isEmpty || model.rateIsMissing || model.series.isEmpty {
            section(L.blockingTitle) {
                ForEach(errors) { issue in
                    problemRow(issue.message(language: .ui(locale)), symbol: "xmark.octagon.fill", tint: .red)
                }
                if model.rateIsMissing {
                    RateEntryForm(model: model)
                }
                if model.series.isEmpty {
                    HStack(spacing: Spacing.m) {
                        problemRow(String(localized: L.noSeriesForKind), symbol: "xmark.octagon.fill", tint: .red)
                        SettingsLink { Text(L.goToSettings) }
                    }
                }
            }
        }
        if !warnings.isEmpty || dateNotToday {
            section(L.checkTitle) {
                ForEach(warnings) { issue in
                    problemRow(issue.message(language: .ui(locale)), symbol: "exclamationmark.triangle.fill", tint: .orange)
                }
                if dateNotToday {
                    HStack(spacing: Spacing.m) {
                        problemRow(String(localized: L.issueDateNotToday(document.issueDate.formatted(locale))),
                                   symbol: "exclamationmark.triangle.fill", tint: .orange)
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
                    problemRow(line, symbol: "info.circle", tint: .secondary)
                }
            }
        }
    }

    private func infoLines(_ document: Document) -> [String] {
        var lines: [String] = []
        if let from = model.rateFallbackFrom {
            lines.append(String(localized: L.rateFallback(document.taxPoint.formatted(locale), from.formatted(locale))))
        }
        if document.kind != .advanceRequest,
           (document.taxPoint.year, document.taxPoint.month) != (document.issueDate.year, document.issueDate.month) {
            lines.append(String(localized: L.taxPointOtherMonth))
        }
        return lines
    }

    private func section<Content: View>(_ title: LocalizedStringResource, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title).textRole(.sectionTitle)
            content()
        }
    }

    private func problemRow(_ text: String, symbol: String, tint: Color) -> some View {
        Label {
            Text(verbatim: text).textRole(.body).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
    }

    // MARK: Issue

    private func canIssue(_ document: Document) -> Bool {
        guard seriesID != nil, model.errors.isEmpty, !model.rateIsMissing else { return false }
        let needsCheck = !model.warnings.isEmpty || document.issueDate != CalendarDay(Date(), in: .current)
        return !needsCheck || checked
    }

    private func issue() {
        guard let seriesID else { return }
        do {
            let issued = try model.issue(seriesID: seriesID)
            dismiss()
            onIssued(issued)
        } catch {
            self.error = String(localized: L.issueFailed(ErrorText.message(error, locale: locale)))
        }
    }
}
