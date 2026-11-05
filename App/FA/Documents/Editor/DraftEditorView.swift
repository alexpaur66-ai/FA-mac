// The draft editor (screens-flows.md §2c, ADR 0009): the totals bar with the readiness chip, the header
// grid, the line items and, on a final invoice, the advances deducted. Every field writes through the
// model, which recomputes totals and issues and autosaves.

import InvoicingCore
import InvoicingData
import SwiftUI

struct DraftEditorView: View {
    let stores: Stores
    let documents: DocumentListModel
    let model: DraftEditorModel
    let onIssued: @MainActor (Document) -> Void
    let newClient: @MainActor () -> Void
    let deleteDraft: @MainActor (String) -> Void

    @Environment(\.locale) private var locale
    @Binding var issueSheetPresented: Bool

    private static let kinds: [DocumentKind] = [.invoice, .advanceRequest, .finalInvoice, .paymentTaxDocument]
    private static let rateKinds: [VATRateKind] = [.standard, .reduced, .zero]
    private static let units = ["hod", "h", "ks", "pcs", "den", "day", "MD", "km"]
    private static let qtyWidth: CGFloat = 72
    private static let unitWidth: CGFloat = 84
    private static let priceWidth: CGFloat = 110
    private static let discountWidth: CGFloat = 72
    private static let rateWidth: CGFloat = 90
    private static let totalWidth: CGFloat = 120

    var body: some View {
        Group {
            if let document = model.document {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        totalsBar(document)
                        if document.kind == .advanceRequest {
                            Text(L.notATaxDocument).textRole(.legalNote)
                        }
                        header(document)
                        lines(document)
                        if document.kind == .finalInvoice {
                            deductions(document)
                        }
                        notes(document)
                    }
                    .padding(Spacing.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if let error = model.loadError {
                ContentUnavailableView {
                    Label { Text(verbatim: error) } icon: { Image(systemName: "exclamationmark.triangle") }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(Text(verbatim: title))
        .navigationSubtitle(Text(saveLine))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(role: .destructive) { deleteDraft(model.documentID) } label: {
                    Label { Text(L.deleteDraft) } icon: { Image(systemName: "trash") }
                }
                Button { openIssueSheet() } label: { Text(L.issue) }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.document == nil)
            }
        }
        .sheet(isPresented: $issueSheetPresented) {
            IssueSheet(model: model, onIssued: onIssued)
        }
        .onDisappear { model.saveNow() }
    }

    func openIssueSheet() {
        model.saveNow()
        issueSheetPresented = true
    }

    private var title: String {
        guard let document = model.document else { return String(localized: L.draftTitle) }
        return String(localized: document.kind.shortTitle) + " · " + String(localized: L.draftTitle)
    }

    private var saveLine: LocalizedStringResource {
        switch model.saveState {
        case .saved: L.editorDraftSaved
        case .pending: L.editorDraftSaving
        case .failed: L.editorDraftNotSaved(model.saveError ?? "")
        }
    }

    // MARK: Totals bar

    private func totalsBar(_ document: Document) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xl) {
                if let totals = model.totals {
                    figure(L.base, totals.totalBase, document.currency)
                    if totals.rows.contains(where: { $0.treatment.chargesVAT }) {
                        figure(L.vat, totals.totalVAT, document.currency)
                    }
                    figure(L.total, totals.totalGross, document.currency)
                    if document.kind == .finalInvoice {
                        figure(L.amountDue, totals.amountDue, document.currency)
                    }
                    if let vatCZK = totals.taxableVATCZK, document.currency != .czk {
                        figure(L.vatInCZK, vatCZK, .czk)
                    }
                } else {
                    Text(L.totalsUnavailable).textRole(.rowSecondary)
                }
                Spacer()
                readinessChip
            }
            if model.rateIsMissing {
                RateEntryForm(model: model)
            } else if model.needsExchangeRate, let rate = document.exchangeRate {
                rateLine(rate, document: document)
            }
        }
        .padding(Spacing.l)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: Radius.l))
    }

    private func figure(_ label: LocalizedStringResource, _ amount: Decimal, _ currency: Currency) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(label).textRole(.caption)
            MoneyText(amount: amount, currency: currency.code, locale: locale, role: .amountStrong)
        }
    }

    private var readinessChip: some View {
        let count = model.errors.count
        return Button { openIssueSheet() } label: {
            if count == 0 {
                Label { Text(L.readyToIssue) } icon: { Image(systemName: "checkmark.circle.fill") }
            } else {
                Label { Text(count == 1 ? L.oneProblem : L.problems(count)) } icon: { Image(systemName: "exclamationmark.circle.fill") }
            }
        }
        .buttonStyle(.bordered)
        .tint(count == 0 ? .green : .orange)
    }

    private func rateLine(_ rate: ExchangeRate, document: Document) -> some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
            Text(L.rateLine(rate.czechLabel, rate.validFor.formatted(locale), RateEntryForm.sourceName(rate.source)))
                .textRole(.rowSecondary)
            if let from = model.rateFallbackFrom {
                Text(L.rateFallback(document.taxPoint.formatted(locale), from.formatted(locale))).textRole(.rowSecondary)
            }
        }
    }

    // MARK: Header

    private func header(_ document: Document) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Spacing.l, verticalSpacing: Spacing.m) {
            GridRow {
                Text(L.fieldClient).textRole(.label)
                HStack(spacing: Spacing.s) {
                    Picker(selection: Binding(get: { document.customerID }, set: { model.setCustomer($0) })) {
                        Text(L.noClient).tag(String?.none)
                        ForEach(model.customers, id: \.id) { customer in
                            Text(verbatim: customer.party.name).tag(Optional(customer.id))
                        }
                    } label: {
                        Text(L.fieldClient)
                    }
                    .labelsHidden()
                    .frame(maxWidth: 320)
                    Button { newClient() } label: { Text(L.newClientEllipsis) }
                    if document.customerID != nil {
                        if document.customer.vatIdentifier == nil, document.hasReverseCharge {
                            chip(L.vatIDMissing)
                        }
                        if document.customer.address.street.isEmpty || document.customer.address.city.isEmpty {
                            chip(L.addressMissing)
                        }
                    }
                }
            }
            GridRow {
                Text(L.fieldType).textRole(.label)
                Picker(selection: Binding(get: { document.kind }, set: { model.setKind($0) })) {
                    ForEach(Self.kinds, id: \.self) { kind in
                        Text(kind.shortTitle).tag(kind)
                    }
                } label: {
                    Text(L.fieldType)
                }
                .labelsHidden()
                .frame(maxWidth: 320)
            }
            GridRow {
                Text(L.fieldIssueDate).textRole(.label)
                DatePicker(selection: dayBinding(document.issueDate) { model.setIssueDate($0) }, displayedComponents: .date) {
                    Text(L.fieldIssueDate)
                }
                .labelsHidden()
            }
            if document.kind != .advanceRequest {
                GridRow {
                    Text(L.fieldTaxPoint).textRole(.label)
                    HStack(spacing: Spacing.m) {
                        Toggle(isOn: Binding(get: { document.taxPointDate == nil },
                                             set: { same in model.setTaxPointDate(same ? nil : document.issueDate) })) {
                            Text(L.sameAsIssueDate)
                        }
                        if let taxPoint = document.taxPointDate {
                            DatePicker(selection: dayBinding(taxPoint) { model.setTaxPointDate($0) }, displayedComponents: .date) {
                                Text(L.fieldTaxPoint)
                            }
                            .labelsHidden()
                        }
                    }
                }
            }
            GridRow {
                Text(L.fieldDue).textRole(.label)
                HStack(spacing: Spacing.m) {
                    Stepper(value: Binding(get: { model.dueDays }, set: { model.setDueDays($0) }), in: 0...365) {
                        Text(L.dueDays(model.dueDays))
                    }
                    DayText(document.dueDate).textRole(.rowSecondary)
                }
            }
            GridRow {
                Text(L.fieldCurrency).textRole(.label)
                Picker(selection: Binding(get: { document.currency }, set: { model.setCurrency($0) })) {
                    ForEach(currencies(document), id: \.code) { currency in
                        Text(verbatim: currency.code).tag(currency)
                    }
                } label: {
                    Text(L.fieldCurrency)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 240)
            }
            GridRow {
                Text(L.fieldLanguage).textRole(.label)
                Picker(selection: Binding(get: { document.language }, set: { model.setLanguage($0) })) {
                    Text(L.languageCzech).tag(DocumentLanguage.czech)
                    Text(L.languageEnglish).tag(DocumentLanguage.english)
                } label: {
                    Text(L.fieldLanguage)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 240)
            }
            GridRow {
                Text(L.fieldTreatment).textRole(.label)
                HStack(spacing: Spacing.m) {
                    Picker(selection: Binding(get: { model.treatmentChoice }, set: { model.setTreatment($0) })) {
                        ForEach(TreatmentChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    } label: {
                        Text(L.fieldTreatment)
                    }
                    .labelsHidden()
                    .frame(maxWidth: 360)
                    if model.treatmentChoice == .exempt {
                        TextField(text: Binding(get: { model.exemptReference }, set: { model.setExemptReference($0) })) {
                            Text(L.exemptReference)
                        }
                        .frame(width: 220)
                    }
                }
            }
            if document.kind != .paymentTaxDocument {
                GridRow {
                    Text(L.fieldBankAccount).textRole(.label)
                    Picker(selection: Binding(get: { document.payment?.bankConnection }, set: { model.setBankAccount($0) })) {
                        Text(L.defaultAccount).tag(BankConnection?.none)
                        ForEach(model.bankAccounts, id: \.self) { account in
                            Text(verbatim: accountLabel(account)).tag(Optional(account))
                        }
                    } label: {
                        Text(L.fieldBankAccount)
                    }
                    .labelsHidden()
                    .frame(maxWidth: 360)
                }
            }
            GridRow {
                Text(L.fieldOrderReference).textRole(.label)
                TextField(text: Binding(get: { document.orderReference ?? "" }, set: { model.setOrderReference($0) })) {
                    Text(L.fieldOrderReference)
                }
                .labelsHidden()
                .frame(maxWidth: 360)
            }
            if document.kind == .finalInvoice || document.kind == .paymentTaxDocument {
                GridRow {
                    Text(L.fieldRelatedDocument).textRole(.label)
                    TextField(text: Binding(get: { document.relatedDocumentNumber ?? "" }, set: { model.setRelatedDocumentNumber($0) })) {
                        Text(L.fieldRelatedDocument)
                    }
                    .labelsHidden()
                    .frame(maxWidth: 360)
                }
            }
        }
    }

    private func chip(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .textRole(.badge)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xxs)
            .background(Color.orange.opacity(0.2), in: Capsule())
    }

    private func currencies(_ document: Document) -> [Currency] {
        var list: [Currency] = [.czk, .eur, .usd]
        if !list.contains(document.currency) { list.append(document.currency) }
        return list
    }

    private func accountLabel(_ account: BankConnection) -> String {
        var parts: [String] = []
        if let bankName = account.bankName, !bankName.isEmpty { parts.append(bankName) }
        parts.append(account.iban.value)
        if let currency = account.currency { parts.append(currency.code) }
        return parts.joined(separator: " · ")
    }

    private func dayBinding(_ day: CalendarDay, set: @escaping @MainActor (CalendarDay) -> Void) -> Binding<Date> {
        Binding(get: { day.midnight(in: .current) }, set: { set(CalendarDay($0, in: .current)) })
    }

    // MARK: Lines

    private func lines(_ document: Document) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(L.linesTitle).textRole(.sectionTitle)
            lineHeader
            ForEach(Array(document.lines.enumerated()), id: \.element.id) { index, line in
                lineRow(line, index: index, document: document)
            }
            Button { model.addLine() } label: {
                Label { Text(L.addLine) } icon: { Image(systemName: "plus") }
            }
            .keyboardShortcut("l", modifiers: .command)
        }
    }

    private var lineHeader: some View {
        HStack(spacing: Spacing.s) {
            Text(L.colDescription).frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
            Text(L.colQty).frame(width: Self.qtyWidth, alignment: .trailing)
            Text(L.colUnit).frame(width: Self.unitWidth, alignment: .leading)
            Text(L.colUnitPrice).frame(width: Self.priceWidth, alignment: .trailing)
            Text(L.colDiscount).frame(width: Self.discountWidth, alignment: .trailing)
            Text(L.colVATRate).frame(width: Self.rateWidth, alignment: .leading)
            Text(L.colLineTotal).frame(width: Self.totalWidth, alignment: .trailing)
        }
        .textRole(.caption)
    }

    private func lineRow(_ line: DocumentLine, index: Int, document: Document) -> some View {
        HStack(spacing: Spacing.s) {
            TextField(text: lineText(line.id)) { Text(L.colDescription) }
                .labelsHidden()
                .frame(minWidth: 200, maxWidth: .infinity)
            TextField(value: lineDecimal(line.id, \.quantity), format: Decimal.FormatStyle.number.precision(.fractionLength(0...3))) {
                Text(L.colQty)
            }
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .frame(width: Self.qtyWidth)
            HStack(spacing: 0) {
                TextField(text: lineUnit(line.id)) { Text(L.colUnit) }
                    .labelsHidden()
                Menu {
                    ForEach(Self.units, id: \.self) { unit in
                        Button(unit) { model.setLine(line.id) { $0.unit = unit } }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .frame(width: 20)
                .accessibilityLabel(Text(L.colUnit))
            }
            .frame(width: Self.unitWidth)
            TextField(value: lineDecimal(line.id, \.unitPrice), format: Decimal.FormatStyle.number.precision(.fractionLength(0...2))) {
                Text(L.colUnitPrice)
            }
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .frame(width: Self.priceWidth)
            TextField(value: lineDecimal(line.id, \.discountPercent), format: Decimal.FormatStyle.number.precision(.fractionLength(0...2))) {
                Text(L.colDiscount)
            }
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .frame(width: Self.discountWidth)
            rateCell(line, document: document)
                .frame(width: Self.rateWidth, alignment: .leading)
            Group {
                if let amounts = model.lineAmounts(at: index) {
                    MoneyText(amount: amounts.gross, currency: document.currency.code, locale: locale)
                } else {
                    Text(verbatim: "—").textRole(.rowSecondary)
                }
            }
            .frame(width: Self.totalWidth, alignment: .trailing)
        }
        .contextMenu {
            Button { model.insertLine(after: line.id) } label: { Text(L.insertLineBelow) }
            Button { model.moveLine(line.id, by: -1) } label: { Text(L.moveLineUp) }
                .disabled(index == 0)
            Button { model.moveLine(line.id, by: 1) } label: { Text(L.moveLineDown) }
                .disabled(index == document.lines.count - 1)
            Divider()
            Button(role: .destructive) { model.removeLine(line.id) } label: { Text(L.deleteLine) }
        }
    }

    @ViewBuilder private func rateCell(_ line: DocumentLine, document: Document) -> some View {
        switch line.treatment {
        case .taxable(let kind):
            Picker(selection: Binding(get: { kind }, set: { newKind in model.setLine(line.id) { $0.treatment = .taxable(newKind) } })) {
                ForEach(Self.rateKinds, id: \.self) { rateKind in
                    Text(verbatim: Self.ratePercentLabel(rateKind, on: document.taxPoint)).tag(rateKind)
                }
            } label: {
                Text(L.colVATRate)
            }
            .labelsHidden()
        case .reverseChargeEU:
            Text(L.rateReverseCharge).textRole(.rowSecondary)
        case .outsideEU:
            Text(L.rateOutsideEU).textRole(.rowSecondary)
        case .exempt:
            Text(L.rateExempt).textRole(.rowSecondary)
        }
    }

    private static func ratePercentLabel(_ kind: VATRateKind, on day: CalendarDay) -> String {
        if let rate = CzechVATRates.rate(kind, on: day) {
            return rate.percent.plainString + " %"
        }
        return kind.rawValue
    }

    private func lineText(_ id: String) -> Binding<String> {
        Binding(
            get: { model.document?.lines.first(where: { $0.id == id })?.text ?? "" },
            set: { value in model.setLine(id) { $0.text = value } })
    }

    private func lineUnit(_ id: String) -> Binding<String> {
        Binding(
            get: { model.document?.lines.first(where: { $0.id == id })?.unit ?? "" },
            set: { value in model.setLine(id) { $0.unit = value.isEmpty ? nil : value } })
    }

    private func lineDecimal(_ id: String, _ keyPath: WritableKeyPath<DocumentLine, Decimal>) -> Binding<Decimal> {
        Binding(
            get: { model.document?.lines.first(where: { $0.id == id })?[keyPath: keyPath] ?? 0 },
            set: { value in model.setLine(id) { $0[keyPath: keyPath] = value } })
    }

    // MARK: Advances deducted

    private func deductions(_ document: Document) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(L.deductionsTitle).textRole(.sectionTitle)
            let numbers = Self.orderedNumbers(document.advanceDeductions)
            ForEach(numbers, id: \.self) { number in
                let rows = document.advanceDeductions.filter { $0.documentNumber == number }
                HStack(spacing: Spacing.l) {
                    Text(verbatim: number).textRole(.documentNumber)
                    if let day = rows.first?.paymentDate {
                        DayText(day).textRole(.rowSecondary)
                    }
                    Spacer()
                    MoneyText(amount: rows.reduce(Decimal(0)) { $0 + $1.gross }, currency: document.currency.code, locale: locale)
                    Button(role: .destructive) { model.removeDeductions(ofDocumentNumber: number) } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text(L.remove))
                }
            }
            let candidates = model.receiptCandidates(in: documents.states)
            Menu {
                ForEach(candidates) { candidate in
                    Button { model.addDeduction(receiptID: candidate.id) } label: {
                        Text(verbatim: candidate.number + " · " + candidate.paymentDate.formatted(locale) + " · " + candidate.gross.description)
                    }
                }
            } label: {
                Label { Text(L.addReceipt) } icon: { Image(systemName: "plus") }
            }
            .disabled(candidates.isEmpty)
            if candidates.isEmpty && document.advanceDeductions.isEmpty {
                Text(L.noReceiptsToDeduct).textRole(.rowSecondary)
            }
        }
    }

    private static func orderedNumbers(_ deductions: [AdvanceDeduction]) -> [String] {
        var seen: Set<String> = []
        return deductions.compactMap { seen.insert($0.documentNumber).inserted ? $0.documentNumber : nil }
    }

    // MARK: Notes

    private func notes(_ document: Document) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: Spacing.m) {
                TextField(text: Binding(get: { document.note ?? "" }, set: { model.setNote($0) }), axis: .vertical) {
                    Text(L.fieldNote)
                }
                TextField(text: Binding(get: { document.footer ?? "" }, set: { model.setFooter($0) }), axis: .vertical) {
                    Text(L.fieldFooter)
                }
            }
            .padding(.top, Spacing.s)
        } label: {
            Text(L.notesOnPDF).textRole(.sectionTitle)
        }
    }
}

/// The inline rate form (screens-flows.md §2c, edge cases): the tax point's rate is missing, so the
/// user types it; ↩ saves it with the source "typed in" and the document takes it at once.
struct RateEntryForm: View {
    let model: DraftEditorModel

    @Environment(\.locale) private var locale
    @State private var manualRate: Decimal = 0

    var body: some View {
        if let document = model.document {
            HStack(spacing: Spacing.m) {
                Label {
                    Text(L.rateMissing(document.currency.code, document.taxPoint.formatted(locale)))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.orange)
                TextField(value: $manualRate, format: Decimal.FormatStyle.number.precision(.fractionLength(0...3))) {
                    Text(L.rateFieldLabel(document.currency.code))
                }
                .frame(width: 150)
                .onSubmit { save() }
                Button { save() } label: { Text(L.saveRate) }
                    .disabled(manualRate <= 0)
            }
        }
    }

    private func save() {
        guard manualRate > 0 else { return }
        model.saveManualRate(manualRate)
    }

    static func sourceName(_ source: ExchangeRateSource) -> String {
        switch source {
        case .cnb: String(localized: L.sourceCNB)
        case .ecb: String(localized: L.sourceECB)
        case .manual: String(localized: L.sourceManual)
        case .fixedAccounting: String(localized: L.sourceFixed)
        }
    }
}
