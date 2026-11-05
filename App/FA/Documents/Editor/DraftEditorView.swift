// The draft editor (screens-flows.md §2c, ADR 0009): the pinned totals bar with the readiness chip, the
// header grid, the line items and, on a final invoice, the advances deducted. Every field writes through
// the model, which recomputes totals and issues and autosaves. One focus model covers the header and the
// lines, so ↩ moves down a column, Esc reverts a field and the menu bar reaches the focused line.

import InvoicingCore
import InvoicingData
import SwiftUI
import UniformTypeIdentifiers

/// The fields of the editor that take keyboard focus.
enum EditorFocus: Hashable {
    case client
    case rate
    case text(String), quantity(String), unit(String), price(String), discount(String), vatRate(String)

    var lineID: String? {
        switch self {
        case .client, .rate: nil
        case .text(let id), .quantity(let id), .unit(let id), .price(let id), .discount(let id), .vatRate(let id): id
        }
    }

    /// The same column on another line.
    func onLine(_ id: String) -> EditorFocus {
        switch self {
        case .client, .rate: self
        case .text: .text(id)
        case .quantity: .quantity(id)
        case .unit: .unit(id)
        case .price: .price(id)
        case .discount: .discount(id)
        case .vatRate: .vatRate(id)
        }
    }
}

/// The examples in the fix-it messages, formatted for the UI locale (design-system.md §8.3).
enum FixIt {
    private static let amount = Decimal(string: "1234.5", locale: Locale(identifier: "en_US_POSIX")) ?? 1234
    private static let rate = Decimal(string: "24.315", locale: Locale(identifier: "en_US_POSIX")) ?? 24

    static func numberExample(_ locale: Locale) -> String { DecimalInput.example(amount, locale: locale, fractionLength: 2) }
    static func rateExample(_ locale: Locale) -> String { DecimalInput.example(rate, locale: locale, fractionLength: 3) }
}

struct DraftEditorView: View {
    let stores: Stores
    let documents: DocumentListModel
    let model: DraftEditorModel
    let onIssued: @MainActor (Document) -> Void
    /// New Client “X”… from the client field: the New Client sheet opens with the typed name.
    let newClient: @MainActor (String) -> Void
    /// Duplicate (toolbar, File ▸ New): a draft copy of this draft.
    let duplicate: @MainActor (String) -> Void

    @Environment(\.locale) private var locale
    @Environment(\.textScale) private var textScale
    @Binding var issueSheetPresented: Bool
    /// View ▸ Show Preview: the live PDF preview takes the editor's place; the toolbar and Issue stay.
    @Binding var previewShown: Bool
    @FocusState private var focus: EditorFocus?
    @State private var changingRate = false

    private static let units = ["hod", "h", "ks", "pcs", "den", "day", "MD", "km"]
    private static let markerWidth: CGFloat = 20

    // The fixed columns at the system text size; View ▸ Bigger scales them with the text, so the cells keep
    // holding their numbers and the grid scrolls sideways instead (ADR 0009).
    private var qtyWidth: CGFloat { 72 * textScale }
    private var unitWidth: CGFloat { 84 * textScale }
    private var priceWidth: CGFloat { 110 * textScale }
    private var discountWidth: CGFloat { 72 * textScale }
    private var rateWidth: CGFloat { 90 * textScale }
    private var totalWidth: CGFloat { 120 * textScale }

    var body: some View {
        Group {
            if model.document != nil, previewShown {
                DraftPreviewView(model: model)
            } else if let document = model.document {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.section) {
                        if model.saveState == .failed, let saveError = model.saveError {
                            InlineMessage(saveError)
                        }
                        if document.kind == .advanceRequest {
                            // The banner (screens-flows.md §0 rule 3); the printed clause is InvoicingCore's.
                            Label {
                                Text(L.notATaxDocument).textRole(.legalNote)
                            } icon: {
                                Image(systemName: "info.circle").accessibilityHidden(true)
                            }
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
                // The totals bar stays visible while the content scrolls (design-system.md §8.6).
                .modifier(TotalsBarAttachment(bar: totalsBar(document)))
                .onAppear {
                    applyFocusRequest()
                    // Enter Rate… chosen while the preview was shown: the editor is back and takes it.
                    if model.takeRateFocusRequest() { focusRate() }
                }
                .onChange(of: model.focusRequestVersion) { _, _ in applyFocusRequest() }
                .onChange(of: model.rateFocusRequest) { _, _ in
                    if model.takeRateFocusRequest() { focusRate() }
                }
                .onChange(of: focus) { _, newValue in model.focusedLineID = newValue?.lineID }
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
            // Centre: Preview toggle · Duplicate; the one prominent action, Issue…, last (design-system.md §8.11).
            ToolbarItem(placement: .automatic) {
                Button { previewShown.toggle() } label: {
                    Label { Text(previewShown ? L.hidePreview : L.showPreview) } icon: {
                        Image(systemName: previewShown ? "square.and.pencil" : "doc.text.magnifyingglass")
                    }
                }
                .disabled(model.document == nil)
                .help(Text(previewShown ? L.hidePreview : L.showPreview))
            }
            ToolbarItem(placement: .automatic) {
                Button { duplicate(model.documentID) } label: {
                    Label { Text(L.duplicate) } icon: { Image(systemName: "plus.square.on.square") }
                }
                // A payment tax document belongs to its payment; it is never duplicated.
                .disabled(model.document == nil || model.document?.kind == .paymentTaxDocument)
                .help(Text(L.duplicate))
            }
            ToolbarItem(placement: .automatic) {
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

    /// The client's name, or what the draft will be while it has none.
    private var title: String {
        guard let document = model.document else { return String(localized: L.draftTitle) }
        if !document.customer.name.isEmpty { return document.customer.name }
        switch document.kind {
        case .invoice: return String(localized: L.newInvoiceTitle)
        case .advanceRequest: return String(localized: L.newAdvanceTitle)
        case .paymentTaxDocument: return String(localized: L.newTaxDocumentTitle)
        case .finalInvoice: return String(localized: L.newFinalInvoiceTitle)
        }
    }

    private var saveLine: LocalizedStringResource {
        switch model.saveState {
        case .saved: L.editorDraftSaved
        case .pending: L.editorDraftSaving
        case .failed: L.editorDraftNotSaved
        }
    }

    // MARK: Focus

    /// The fields exist only once the body has rendered, so focus moves on the next turn of the run loop.
    private func applyFocusRequest() {
        guard let request = model.takeFocusRequest(), let document = model.document else { return }
        let target: EditorFocus?
        switch request {
        case .client: target = .client
        case .firstLineText: target = document.lines.first.map { .text($0.id) }
        case .firstLineQuantity: target = document.lines.first.map { .quantity($0.id) }
        case .lineText(let id): target = .text(id)
        }
        guard let target else { return }
        Task { @MainActor in focus = target }
    }

    /// Document ▸ Enter Rate…: the rate field while the rate is missing, otherwise Change… on the rate line.
    private func focusRate() {
        guard model.needsExchangeRate else { return }
        if model.rateIsMissing {
            Task { @MainActor in focus = .rate }
        } else {
            changingRate = true
        }
    }

    private func focusFirstLine() {
        guard let first = model.document?.lines.first else { return }
        Task { @MainActor in focus = .text(first.id) }
    }

    /// ↩ in a cell: the same column one row down; on the last row a new line whose Description takes focus
    /// (screens-flows.md §2c, design-system.md §8.5).
    private func moveDown(from current: EditorFocus) {
        guard let id = current.lineID, let lines = model.document?.lines,
              let index = lines.firstIndex(where: { $0.id == id }) else { return }
        if index + 1 < lines.count {
            let next = lines[index + 1].id
            Task { @MainActor in focus = current.onLine(next) }
        } else {
            let newID = model.addLine()
            Task { @MainActor in focus = .text(newID) }
        }
    }

    // MARK: Totals bar

    /// One row when the detail column is wide enough; at the minimum width the chip moves below the
    /// figures, and the figures wrap.
    private func totalsBar(_ document: Document) -> some View {
        // The same count as the sheet's ⛔ section, so the chip never says ready while Issue is blocked.
        let blocking = model.blockingCount(seriesID: model.series.first?.id)
        return VStack(alignment: .leading, spacing: Spacing.s) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xl) {
                    figures(document)
                    Spacer(minLength: Spacing.l)
                    readinessChip(blocking)
                }
                VStack(alignment: .leading, spacing: Spacing.m) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xl) {
                        figures(document)
                    }
                    readinessChip(blocking)
                }
                VStack(alignment: .leading, spacing: Spacing.m) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: Spacing.l, alignment: .leading)],
                              alignment: .leading, spacing: Spacing.s) {
                        figures(document)
                    }
                    readinessChip(blocking)
                }
            }
            if model.rateIsMissing {
                RateEntryForm(model: model, stores: stores, focus: $focus, focusValue: .rate)
            } else if model.needsExchangeRate, let rate = document.exchangeRate {
                rateLine(rate, document: document)
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.m)
    }

    /// Base and Total are the lines before any deduction; a final invoice then shows the advances
    /// deducted, the amount due and the VAT after the deduction, the base of the VAT in CZK
    /// (screens-flows.md §2d, step 4: Total → − advances → Amount due). Under reverse charge the VAT
    /// figure's place says so; the VAT in CZK appears only when Czech VAT is charged in a foreign currency.
    @ViewBuilder private func figures(_ document: Document) -> some View {
        if let totals = model.totals {
            let chargesVAT = totals.rows.contains(where: { $0.treatment.chargesVAT })
            let isFinal = document.kind == .finalInvoice
            let isReceipt = document.kind == .paymentTaxDocument
            figure(L.base, totals.totalBase, document.currency)
            if document.hasReverseCharge && !chargesVAT {
                dashFigure(L.reverseChargeItem)
            }
            if chargesVAT && !isFinal {
                figure(L.vat, totals.totalVAT, document.currency)
            }
            figure(L.total, totals.totalGross, document.currency, role: isFinal || isReceipt ? .amountStrong : .total)
            if isFinal {
                let deducted = totals.totalGross - totals.amountDue
                if deducted != 0 {
                    figure(L.advancesDeducted, -deducted, document.currency)
                }
                figure(L.amountDue, totals.amountDue, document.currency, role: .total)
                if chargesVAT {
                    figure(L.vatAfterAdvances, totals.taxableVAT, document.currency)
                }
            }
            if chargesVAT, document.currency != .czk, model.needsExchangeRate {
                if let vatCZK = totals.taxableVATCZK {
                    figure(L.vatInCZK, vatCZK, .czk)
                } else {
                    dashFigure(L.vatInCZK)
                }
            }
        } else {
            InlineMessage(model.totalsError ?? String(localized: L.totalsUnavailable), kind: .warning)
        }
    }

    private func figure(_ label: LocalizedStringResource, _ amount: Decimal, _ currency: Currency, role: TextRole = .amountStrong) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(label).textRole(.caption)
            MoneyText(amount: amount, currency: currency.code, locale: locale, role: role)
        }
    }

    private func dashFigure(_ label: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(label).textRole(.caption)
            Text(verbatim: "—").textRole(.amountStrong)
        }
    }

    private func readinessChip(_ count: Int) -> some View {
        Button { openIssueSheet() } label: {
            if count == 0 {
                Label { Text(L.readyToIssue) } icon: { Image(systemName: "checkmark.circle.fill") }
            } else {
                Label { Text(count == 1 ? L.oneProblem : L.problems(count)) } icon: { Image(systemName: "exclamationmark.circle.fill") }
            }
        }
        .buttonStyle(.bordered)
        .tint(count == 0 ? .green : .orange)
    }

    /// "1 EUR = 24,315 CZK · for 4. 11. 2026 · ČNB file" with Change…, the fallback note, a stale-rate
    /// warning and the last rate error (design-system.md §8.9).
    private func rateLine(_ rate: ExchangeRate, document: Document) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.s) {
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(L.rateEquals(document.currency.code, Self.rateText(rate, locale: locale))).textRole(.amount)
                Text(L.rateDetails(rate.validFor.formatted(locale), RateSourceName.text(rate.source))).textRole(.rowSecondary)
                Button { changingRate = true } label: { Text(L.changeRate) }
                    .buttonStyle(.link)
                    .popover(isPresented: $changingRate, arrowEdge: .bottom) {
                        RateChangePopover(model: model, rate: rate)
                    }
            }
            if let from = model.rateFallbackFrom {
                Label {
                    Text(fallbackText(from, document: document)).textRole(.rowSecondary)
                } icon: {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            if let stale = model.warnings.first(where: { $0.code == .exchangeRateStale }) {
                InlineMessage(stale.message(language: .english), kind: .warning)
            }
            if let rateError = model.rateError {
                InlineMessage(rateError)
            }
        }
    }

    private func fallbackText(_ from: CalendarDay, document: Document) -> LocalizedStringResource {
        let used = from.formatted(locale)
        if let resolution = model.rateResolution, resolution.rule == .noPublicationThatDay {
            // The day the ČNB skipped: the tax point itself, or the last working day before a weekend tax point.
            return L.rateNotPublished(resolution.publicationDay.formatted(locale), used)
        }
        return L.rateFallback(document.taxPoint.formatted(locale), used)
    }

    /// "24,315": the rate for one unit in the UI locale; `czechLabel` stays on the PDF.
    static func rateText(_ rate: ExchangeRate, locale: Locale) -> String {
        rate.czkPerUnit.formatted(Decimal.FormatStyle(locale: locale).precision(.fractionLength(3)))
    }

    // MARK: Header

    private func header(_ document: Document) -> some View {
        let isReceipt = document.kind == .paymentTaxDocument
        return Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Spacing.l, verticalSpacing: Spacing.m) {
            GridRow {
                Text(L.fieldClient).textRole(.label)
                if isReceipt {
                    // The client, currency and advance of a payment tax document are those of its payment.
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(verbatim: document.customer.name.isEmpty ? String(localized: L.noClient) : document.customer.name).textRole(.body)
                        if let payment = model.receiptPayment {
                            Text(L.receivedAmountNote(MoneyText.format(payment.amount.amount, currency: payment.amount.currency.code, locale: locale),
                                                      payment.paidOn.formatted(locale)))
                                .textRole(.rowSecondary)
                        } else {
                            InlineMessage(L.receiptPaymentMissing)
                        }
                    }
                } else {
                    ClientField(model: model, focus: $focus, focusValue: .client, newClient: newClient, picked: focusFirstLine)
                }
            }
            GridRow {
                Text(L.fieldType).textRole(.label)
                Picker(selection: Binding(get: { document.kind }, set: { model.setKind($0) })) {
                    ForEach(DraftEditorModel.kindOptions(for: document.kind), id: \.self) { kind in
                        Text(verbatim: kind.pickerTitle).tag(kind)
                    }
                } label: {
                    Text(L.fieldType)
                }
                .labelsHidden()
                .frame(maxWidth: 360)
                // A payment tax document belongs to its payment; another type would orphan the link.
                .disabled(isReceipt)
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
                    if isReceipt {
                        // The day the payment was received; the store refuses any other day (checkReceipt).
                        HStack(spacing: Spacing.m) {
                            DayText(document.taxPointDate ?? document.issueDate)
                            Text(L.taxPointIsPaymentDate).textRole(.rowSecondary)
                        }
                    } else {
                        HStack(spacing: Spacing.m) {
                            Toggle(isOn: Binding(get: { model.taxPointSameAsIssue },
                                                 set: { same in model.setTaxPointSameAsIssue(same) })) {
                                Text(L.sameAsIssueDate)
                            }
                            if !model.taxPointSameAsIssue {
                                DatePicker(selection: dayBinding(document.taxPointDate ?? document.issueDate) { model.setTaxPointDate($0) },
                                           displayedComponents: .date) {
                                    Text(L.fieldTaxPoint)
                                }
                                .labelsHidden()
                            }
                        }
                    }
                }
            }
            GridRow {
                Text(L.fieldDue).textRole(.label)
                // "30 days" and the date, linked: each updates the other (screens-flows.md §2c).
                HStack(spacing: Spacing.m) {
                    DueDaysField(model: model)
                        .frame(width: 56 * textScale)
                    Text(model.dueDays == 1 ? L.dueDaysOne : L.dueDays(model.dueDays)).textRole(.body)
                    DatePicker(selection: dayBinding(document.dueDate) { model.setDueDate($0) }, displayedComponents: .date) {
                        Text(L.fieldDue)
                    }
                    .labelsHidden()
                }
            }
            GridRow {
                Text(L.fieldCurrency).textRole(.label)
                if isReceipt {
                    Text(verbatim: document.currency.code).textRole(.body)
                } else {
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
                .frame(maxWidth: 280)
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
                        .textRole(.body)
                        .frame(width: 220)
                    }
                }
            }
            if !isReceipt {
                GridRow {
                    Text(L.fieldBankAccount).textRole(.label)
                    Picker(selection: Binding(get: { document.payment?.bankConnection }, set: { model.setBankAccount($0) })) {
                        Text(L.defaultAccount).tag(BankConnection?.none)
                        ForEach(model.bankAccounts, id: \.self) { account in
                            Text(Self.accountLabel(account)).tag(Optional(account))
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
                .textRole(.body)
                .frame(maxWidth: 360)
            }
            if document.kind == .finalInvoice {
                GridRow {
                    Text(L.fieldRelatedDocument).textRole(.label)
                    TextField(text: Binding(get: { document.relatedDocumentNumber ?? "" }, set: { model.setRelatedDocumentNumber($0) })) {
                        Text(L.fieldRelatedDocument)
                    }
                    .labelsHidden()
                    .textRole(.body)
                    .frame(maxWidth: 360)
                }
            } else if isReceipt, let related = document.relatedDocumentNumber {
                GridRow {
                    Text(L.fieldRelatedDocument).textRole(.label)
                    Text(verbatim: related).textRole(.body)
                }
            }
        }
    }

    /// EUR | CZK | USD (screens-flows.md §5), plus the draft's own currency when it is another one.
    private func currencies(_ document: Document) -> [Currency] {
        var list: [Currency] = [.eur, .czk, .usd]
        if !list.contains(document.currency) { list.append(document.currency) }
        return list
    }

    /// "Raiffeisenbank · CZ65 0800 … · EUR": the account as the header picker and the Issue sheet name it.
    static func accountLabel(_ account: BankConnection) -> LocalizedStringResource {
        let bank = account.bankName ?? ""
        return switch (bank.isEmpty, account.currency) {
        case (true, nil): L.accountIBAN(account.iban.value)
        case (true, let currency?): L.accountIBANWithCurrency(account.iban.value, currency.code)
        case (false, nil): L.accountWithBank(bank, account.iban.value)
        case (false, let currency?): L.accountWithBankAndCurrency(bank, account.iban.value, currency.code)
        }
    }

    private func dayBinding(_ day: CalendarDay, set: @escaping @MainActor (CalendarDay) -> Void) -> Binding<Date> {
        Binding(get: { day.midnight(in: .current) }, set: { set(CalendarDay($0, in: .current)) })
    }

    // MARK: Lines

    private func lines(_ document: Document) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(L.linesTitle).textRole(.sectionTitle)
            // The columns need about 800 pt; a narrower detail column scrolls the grid sideways instead of
            // clipping the rate and the line total.
            ViewThatFits(in: .horizontal) {
                lineGrid(document)
                ScrollView(.horizontal) {
                    lineGrid(document)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            // ⌘L lives in the Document menu, which reaches the editor through the focused scene.
            Button { model.addLineAndFocus() } label: {
                Label { Text(L.addLine) } icon: { Image(systemName: "plus") }
            }
        }
    }

    private func lineGrid(_ document: Document) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            lineHeader
            ForEach(Array(document.lines.enumerated()), id: \.element.id) { index, line in
                lineRow(line, index: index, document: document)
            }
        }
    }

    private var lineHeader: some View {
        HStack(spacing: Spacing.s) {
            Text(L.colDescription).frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
            Text(L.colQty).frame(width: qtyWidth, alignment: .trailing)
            Text(L.colUnit).frame(width: unitWidth, alignment: .leading)
            Text(L.colUnitPrice).frame(width: priceWidth, alignment: .trailing)
            Text(L.colDiscount).frame(width: discountWidth, alignment: .trailing)
            Text(L.colVATRate).frame(width: rateWidth, alignment: .leading)
            Text(L.colLineTotal).frame(width: totalWidth, alignment: .trailing)
            Color.clear.frame(width: Self.markerWidth, height: 1)
        }
        .textRole(.caption)
    }

    private func lineRow(_ line: DocumentLine, index: Int, document: Document) -> some View {
        HStack(spacing: Spacing.s) {
            LineTextCell(label: L.colDescription, value: line.text, focus: $focus, focusValue: .text(line.id),
                         commit: { value in model.setLine(line.id) { $0.text = value } },
                         onSubmit: { moveDown(from: .text(line.id)) })
                .frame(minWidth: 200, maxWidth: .infinity)
            AmountField(cell: NumberCell(lineID: line.id, column: .quantity), label: L.colQty, value: line.quantity, fractionLength: 0...3,
                        model: model, focus: $focus, focusValue: .quantity(line.id),
                        commit: { value in model.setLine(line.id) { $0.quantity = value } },
                        onSubmit: { moveDown(from: .quantity(line.id)) })
                .frame(width: qtyWidth)
            HStack(spacing: 0) {
                LineTextCell(label: L.colUnit, value: line.unit ?? "", focus: $focus, focusValue: .unit(line.id),
                             commit: { value in model.setLine(line.id) { $0.unit = value.isEmpty ? nil : value } },
                             onSubmit: { moveDown(from: .unit(line.id)) })
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
            .frame(width: unitWidth)
            AmountField(cell: NumberCell(lineID: line.id, column: .unitPrice), label: L.colUnitPrice, value: line.unitPrice, fractionLength: 2...2,
                        model: model, focus: $focus, focusValue: .price(line.id),
                        // Stored as shown and printed: the price is rounded to the currency's minor units, so
                        // the grid, the PDF and the line total use the same number.
                        commit: { value in
                            let scale = document.currency.minorUnits
                            model.setLine(line.id) { $0.unitPrice = value.rounded(scale: scale) }
                        },
                        onSubmit: { moveDown(from: .price(line.id)) })
                .frame(width: priceWidth)
            AmountField(cell: NumberCell(lineID: line.id, column: .discount), label: L.colDiscount, value: line.discountPercent, fractionLength: 0...2,
                        model: model, focus: $focus, focusValue: .discount(line.id),
                        commit: { value in model.setLine(line.id) { $0.discountPercent = value } },
                        onSubmit: { moveDown(from: .discount(line.id)) })
                .frame(width: discountWidth)
            rateCell(line, document: document)
                .frame(width: rateWidth, alignment: .leading)
            Group {
                if let amounts = model.lineAmounts(at: index) {
                    MoneyText(amount: amounts.gross, currency: document.currency.code, locale: locale)
                } else {
                    Text(verbatim: "—").textRole(.amountSecondary)
                }
            }
            .frame(width: totalWidth, alignment: .trailing)
            // The row's problem from the validator (design-system.md §8.5 "row invalid").
            Group {
                if let problem = model.lineProblem(line.id, locale: locale) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(Text(verbatim: problem))
                        .accessibilityLabel(Text(verbatim: problem))
                }
            }
            .frame(width: Self.markerWidth)
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
            VATRateField(line: line, kind: kind, day: document.taxPoint, model: model, focus: $focus, focusValue: .vatRate(line.id),
                         commit: { newKind in model.setLine(line.id) { $0.treatment = .taxable(newKind) } },
                         onSubmit: { moveDown(from: .vatRate(line.id)) })
        case .reverseChargeEU:
            Text(L.rateReverseCharge)
                .textRole(.rowSecondary)
                .help(Text(L.treatmentReverseCharge))
                .accessibilityLabel(Text(L.treatmentReverseCharge))
        case .outsideEU:
            Text(verbatim: "—")
                .textRole(.rowSecondary)
                .help(Text(L.treatmentOutsideEU))
                .accessibilityLabel(Text(L.treatmentOutsideEU))
        case .exempt:
            Text(L.rateExempt).textRole(.rowSecondary)
        }
    }

    // MARK: Advances deducted

    private func deductions(_ document: Document) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(L.deductionsTitle).textRole(.sectionTitle)
            // One row per advance (design check E068): its number with the tax documents deducted, the days
            // the payments were received, the VAT taxed in CZK and the summed gross; the button drops them all.
            ForEach(deductionGroups(document)) { group in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.l) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        let receipts = group.receiptNumbers.joined(separator: ", ")
                        if let advance = group.advanceNumber {
                            Text(L.deductionAdvanceRow(advance, receipts)).textRole(.documentNumber)
                        } else {
                            Text(verbatim: receipts).textRole(.documentNumber)
                        }
                        HStack(spacing: Spacing.s) {
                            Text(verbatim: group.paymentDays.map { $0.formatted(locale) }.joined(separator: ", ")).textRole(.rowSecondary)
                            if let vatCZK = Self.vatTaxedCZK(group.rows) {
                                Text(L.vatTaxedCZK(MoneyText.format(vatCZK, currency: "CZK", locale: locale))).textRole(.amountSecondary)
                            }
                        }
                    }
                    Spacer()
                    MoneyText(amount: group.rows.reduce(Decimal(0)) { $0 + $1.gross }, currency: document.currency.code, locale: locale)
                    Button(role: .destructive) { model.removeDeductions(ofDocumentNumbers: group.receiptNumbers) } label: {
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
                        Text(L.receiptMenuItem(candidate.number, candidate.paymentDate.formatted(locale),
                                               MoneyText.format(candidate.gross.amount, currency: candidate.gross.currency.code, locale: locale)))
                    }
                }
            } label: {
                Label { Text(L.addReceipt) } icon: { Image(systemName: "plus") }
            }
            .disabled(candidates.isEmpty)
            if candidates.isEmpty && document.advanceDeductions.isEmpty {
                Text(L.noReceiptsToDeduct).textRole(.rowSecondary)
            }
            ForEach(model.deductionConflicts, id: \.self) { conflict in
                InlineMessage(conflict)
            }
            ForEach(model.deductionWarnings, id: \.self) { warning in
                InlineMessage(warning, kind: .warning)
            }
            if let deductionError = model.deductionError {
                InlineMessage(deductionError)
            }
        }
    }

    private static func orderedNumbers(_ deductions: [AdvanceDeduction]) -> [String] {
        var seen: Set<String> = []
        return deductions.compactMap { seen.insert($0.documentNumber).inserted ? $0.documentNumber : nil }
    }

    /// The deductions of one advance: its number (when the lists know the receipts' advance), the tax
    /// documents deducted and their rows.
    private struct DeductionGroup: Identifiable {
        let id: String
        let advanceNumber: String?
        var receiptNumbers: [String]
        var rows: [AdvanceDeduction]

        /// The days the payments were received, each once, in row order.
        var paymentDays: [CalendarDay] {
            var seen: Set<CalendarDay> = []
            return rows.compactMap { seen.insert($0.paymentDate).inserted ? $0.paymentDate : nil }
        }
    }

    /// Receipts grouped by their advance, in the order they were listed; a receipt whose advance the lists
    /// do not know stands on its own.
    private func deductionGroups(_ document: Document) -> [DeductionGroup] {
        var groups: [DeductionGroup] = []
        for number in Self.orderedNumbers(document.advanceDeductions) {
            let rows = document.advanceDeductions.filter { $0.documentNumber == number }
            let advance = model.advanceNumber(ofReceipt: number, in: documents.states)
            let key = advance ?? number
            if let index = groups.firstIndex(where: { $0.id == key }) {
                groups[index].receiptNumbers.append(number)
                groups[index].rows.append(contentsOf: rows)
            } else {
                groups.append(DeductionGroup(id: key, advanceNumber: advance, receiptNumbers: [number], rows: rows))
            }
        }
        return groups
    }

    /// The VAT the advance was taxed with, in CZK: converted at the advance's rate for a foreign currency
    /// (§ 37a odst. 2 písm. b) ZDPH); nil when a row has no rate.
    private static func vatTaxedCZK(_ rows: [AdvanceDeduction]) -> Decimal? {
        var total = Decimal(0)
        for row in rows {
            if row.currency == .czk {
                total += row.vat
            } else if let rate = row.exchangeRate {
                total += rate.toCZK(row.vat)
            } else {
                return nil
            }
        }
        return total
    }

    // MARK: Notes

    private func notes(_ document: Document) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: Spacing.m) {
                TextField(text: Binding(get: { document.note ?? "" }, set: { model.setNote($0) }), axis: .vertical) {
                    Text(L.fieldNote)
                }
                .textRole(.body)
                TextField(text: Binding(get: { document.footer ?? "" }, set: { model.setFooter($0) }), axis: .vertical) {
                    Text(L.fieldFooter)
                }
                .textRole(.body)
            }
            .padding(.top, Spacing.s)
        } label: {
            Text(L.notesOnPDF).textRole(.sectionTitle)
        }
    }
}

/// The totals bar pinned above the scrolling content (design-system.md §8.6): on macOS 26 a safe-area bar
/// with the system's scroll edge effect, before that an opaque inset with a divider (design check E035).
private struct TotalsBarAttachment<Bar: View>: ViewModifier {
    let bar: Bar

    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content.safeAreaBar(edge: .top, spacing: 0) { bar }
        } else {
            inset(content)
        }
        #else
        inset(content)
        #endif
    }

    private func inset(_ content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                bar
                Divider()
            }
            .background(.background)
        }
    }
}

// MARK: - Client field

/// The client as a text field with type-ahead on name, IČO and VAT ID (screens-flows.md §2c, design-system.md
/// §8.4). While typing, the matches list under the field with their defaults and caution chips, and the
/// last row is New Client “X”…; ↩ picks the highlighted row, ↓/↑ move, Esc and leaving the field revert.
/// The list is drawn by the app on every macOS version, so a keyboard user has the same path everywhere.
struct ClientField<Focus: Hashable>: View {
    let model: DraftEditorModel
    let focus: FocusState<Focus?>.Binding
    let focusValue: Focus
    let newClient: @MainActor (String) -> Void
    /// After a pick: the first line's Description takes focus.
    let picked: @MainActor () -> Void

    @Environment(\.locale) private var locale
    @State private var text = ""
    /// True once the user typed into the focused field: the suggestions show and ↩ picks.
    @State private var editing = false
    @State private var highlighted = 0

    private var isFocused: Bool { focus.wrappedValue == focusValue }
    private var query: String { text.trimmingCharacters(in: .whitespaces) }
    private var matches: [Customer] { model.matchingCustomers(text) }
    private var currentName: String { model.customer?.party.name ?? "" }

    /// The field's text; a change written by the field editor (the user typing) opens the suggestions.
    private var typedText: Binding<String> {
        Binding(get: { text }, set: { newText in
            guard newText != text else { return }
            text = newText
            if isFocused {
                editing = true
                highlighted = 0
            }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Only typing opens the list: the text set by Esc, a pick or focus never re-arms it, so Esc
            // then ↩ moves on instead of picking the first suggestion.
            TextField(text: typedText, prompt: Text(L.clientPrompt)) { Text(L.fieldClient) }
                .labelsHidden()
                .textRole(.body)
                .frame(maxWidth: 360)
                .focused(focus, equals: focusValue)
                .onSubmit {
                    if editing { pickHighlighted() } else { picked() }
                }
                .onKeyPress(.escape) {
                    revert()
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    if editing { move(1) } else { editing = true }
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    move(-1)
                    return .handled
                }
                .onChange(of: isFocused) { _, focusedNow in
                    if focusedNow {
                        text = currentName
                        editing = false
                    } else if editing {
                        revert()
                    }
                }
                .onChange(of: currentName, initial: true) { _, name in
                    if !isFocused { text = name }
                }
            if isFocused, editing {
                suggestions
            }
            if let document = model.document, document.customerID != nil, !(isFocused && editing) {
                HStack(spacing: Spacing.s) {
                    if document.customer.vatIdentifier == nil, document.hasReverseCharge {
                        chip(L.vatIDMissing)
                    }
                    if document.customer.address.street.isEmpty || document.customer.address.city.isEmpty {
                        chip(L.addressMissing)
                    }
                }
            }
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(matches.enumerated()), id: \.element.id) { index, customer in
                Button { pick(customer) } label: {
                    suggestionRow(customer)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Spacing.s)
                .padding(.vertical, Spacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(index == highlighted ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: Radius.s))
            }
            Button { newClient(query) } label: {
                Label {
                    Text(query.isEmpty ? L.newClientEllipsis : L.newClientNamed(query)).textRole(.body)
                } icon: {
                    Image(systemName: "person.badge.plus")
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(highlighted == matches.count ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: Radius.s))
        }
        .padding(Spacing.xs)
        .frame(maxWidth: 360)
        .background(.background, in: RoundedRectangle(cornerRadius: Radius.m))
        .overlay(RoundedRectangle(cornerRadius: Radius.m).stroke(.separator))
    }

    /// Name, then "IČO · country · default currency · document language · VAT treatment" (design-system.md
    /// §8.4), so a client found by its IČO shows it, and the caution chips.
    private func suggestionRow(_ customer: Customer) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(verbatim: customer.party.name).textRole(.body)
            HStack(spacing: Spacing.s) {
                Text(Self.suggestionLine(customer)).textRole(.rowSecondary)
                if customer.party.vatIdentifier == nil, customer.vatStatus.defaultServiceTreatment == .reverseChargeEU {
                    chip(L.vatIDMissing)
                }
                if customer.party.address.street.isEmpty || customer.party.address.city.isEmpty {
                    chip(L.addressMissing)
                }
            }
        }
    }

    static func suggestionLine(_ customer: Customer) -> LocalizedStringResource {
        let country = customer.party.address.countryCode
        let language = String(localized: customer.language == .czech ? L.languageCzech : L.languageEnglish)
        let treatment = String(localized: TreatmentChoice(customer.vatStatus.defaultServiceTreatment).title)
        if let ico = customer.party.identificationNumber?.digits {
            return L.clientSuggestionLine(ico, country, customer.currency.code, language, treatment)
        }
        return L.clientSuggestionLineNoICO(country, customer.currency.code, language, treatment)
    }

    private func chip(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .textRole(.badge)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xxs)
            .background(Color.orange.opacity(0.2), in: Capsule())
    }

    private func move(_ delta: Int) {
        highlighted = max(0, min(matches.count, highlighted + delta))
    }

    private func pickHighlighted() {
        if highlighted < matches.count {
            pick(matches[highlighted])
        } else {
            newClient(query)
        }
    }

    private func pick(_ customer: Customer) {
        model.setCustomer(customer.id)
        text = customer.party.name
        editing = false
        picked()
    }

    private func revert() {
        text = currentName
        editing = false
    }
}

// MARK: - Cells

/// The due days ("30") of the header, written to the draft as they are typed like every other field,
/// so ⌘↩ Issue or ⌘Q right after typing take the new term. Text that is not a whole number is ignored
/// while typing; leaving the field shows the draft's days again.
struct DueDaysField: View {
    let model: DraftEditorModel

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(text: $text) { Text(L.fieldDue) }
            .labelsHidden()
            .textRole(.amount)
            .multilineTextAlignment(.trailing)
            .focused($focused)
            .onChange(of: text) { _, newText in
                guard focused, let days = Int(newText.trimmingCharacters(in: .whitespaces)), days >= 0,
                      days != model.dueDays else { return }
                model.setDueDays(days)
            }
            .onChange(of: model.dueDays, initial: true) { _, days in
                if !focused { text = String(days) }
            }
            .onChange(of: focused) { _, focusedNow in
                if !focusedNow { text = String(model.dueDays) }
            }
            .onSubmit { text = String(model.dueDays) }
    }
}

/// A text cell of the lines grid: writes as it is typed, ↩ moves down, Esc restores the value the cell
/// had when it gained focus.
struct LineTextCell<Focus: Hashable>: View {
    let label: LocalizedStringResource
    let value: String
    let focus: FocusState<Focus?>.Binding
    let focusValue: Focus
    let commit: @MainActor (String) -> Void
    let onSubmit: @MainActor () -> Void

    @State private var original = ""

    private var isFocused: Bool { focus.wrappedValue == focusValue }

    var body: some View {
        TextField(text: Binding(get: { value }, set: { commit($0) })) { Text(label) }
            .labelsHidden()
            .textRole(.body)
            .focused(focus, equals: focusValue)
            .onChange(of: isFocused) { _, focusedNow in
                if focusedNow { original = value }
            }
            .onKeyPress(.escape) {
                if original != value { commit(original) }
                return .handled
            }
            .onSubmit { onSubmit() }
    }
}

/// A numeric cell of the lines grid (screens-flows.md §2c, design-system.md §8.3, §8.5). A number is
/// written as it is typed; text that is not a number stays in the cell with a red outline and a trailing
/// warning symbol that says what to type, the model counts the cell as ⛔, and the value from before the
/// edit stands: a typo never leaves a shorter number behind. Esc restores that value; ↩ moves down.
struct AmountField<Focus: Hashable>: View {
    let cell: NumberCell
    let label: LocalizedStringResource
    let value: Decimal
    let fractionLength: ClosedRange<Int>
    let model: DraftEditorModel
    let focus: FocusState<Focus?>.Binding
    let focusValue: Focus
    let commit: @MainActor (Decimal) -> Void
    let onSubmit: @MainActor () -> Void

    @Environment(\.locale) private var locale
    @State private var text = ""
    /// The value when the cell gained focus.
    @State private var original: Decimal?
    @State private var invalid = false

    private var isFocused: Bool { focus.wrappedValue == focusValue }
    private var fixIt: String { String(localized: L.enterNumber(FixIt.numberExample(locale))) }

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            TextField(text: $text) { Text(label) }
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .textRole(.amount)
                .focused(focus, equals: focusValue)
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.s).stroke(Color.red, lineWidth: invalid ? 1.5 : 0)
                }
                .accessibilityHint(Text(verbatim: invalid ? fixIt : ""))
                // A rebuilt cell (after the preview, a relayout) shows the invalid text it held, still ⛔,
                // or the stored value (screens-flows.md §2c: never lose input).
                .onAppear {
                    if let kept = model.invalidText(of: cell) {
                        text = kept
                        invalid = true
                    } else {
                        text = formatted(value)
                        setInvalid(nil)
                    }
                }
                .onChange(of: value) { _, newValue in
                    guard !isFocused else { return }
                    text = formatted(newValue)
                    setInvalid(nil)
                }
                .onChange(of: text) { _, newText in
                    guard isFocused else { return }
                    if let parsed = parse(newText) {
                        setInvalid(nil)
                        if parsed != value { commit(parsed) }
                    } else {
                        setInvalid(newText)
                        if let original, original != value { commit(original) }
                    }
                }
                .onChange(of: isFocused) { _, focusedNow in
                    if focusedNow {
                        original = value
                    } else {
                        finish()
                    }
                }
                .onKeyPress(.escape) {
                    revert()
                    return .handled
                }
                .onSubmit {
                    finish()
                    if !invalid { onSubmit() }
                }
            if invalid {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(Text(verbatim: fixIt))
                    .accessibilityLabel(Text(verbatim: fixIt))
            }
        }
    }

    /// An empty cell is zero.
    private func parse(_ text: String) -> Decimal? {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : DecimalInput.parse(text, locale: locale)
    }

    /// Shows the canonical form of a valid number; invalid text stays until it is fixed or reverted.
    private func finish() {
        if let parsed = parse(text) {
            setInvalid(nil)
            if parsed != value { commit(parsed) }
            text = formatted(parsed)
        } else {
            setInvalid(text)
        }
    }

    private func revert() {
        let restored = original ?? value
        setInvalid(nil)
        if restored != value { commit(restored) }
        text = formatted(restored)
    }

    /// Always tells the model (its `setCell` ignores a repeat), which keeps the text for a rebuilt cell.
    private func setInvalid(_ invalidText: String?) {
        let flag = invalidText != nil
        if invalid != flag { invalid = flag }
        model.setCell(cell, invalidText: invalidText)
    }

    private func formatted(_ amount: Decimal) -> String {
        amount.formatted(Decimal.FormatStyle(locale: locale).precision(.fractionLength(fractionLength)))
    }
}

/// The per-line Czech VAT rate as a text field (screens-flows.md §2c: no pop-up, so no Tab-to-control):
/// "21", "12" or "0" map to the rates in force on the tax point; macOS 15 suggests them under the field.
/// Any other text is invalid the way an amount cell is. Shown as a percentage in the UI locale.
struct VATRateField<Focus: Hashable>: View {
    let line: DocumentLine
    let kind: VATRateKind
    let day: CalendarDay
    let model: DraftEditorModel
    let focus: FocusState<Focus?>.Binding
    let focusValue: Focus
    let commit: @MainActor (VATRateKind) -> Void
    let onSubmit: @MainActor () -> Void

    @Environment(\.locale) private var locale
    @State private var text = ""
    @State private var invalid = false
    @State private var original: VATRateKind?

    private var isFocused: Bool { focus.wrappedValue == focusValue }
    private var rates: [VATRate] { CzechVATRates.rates(on: day) }
    private var cell: NumberCell { NumberCell(lineID: line.id, column: .vatRate) }
    private var fixIt: String {
        String(localized: L.vatRateFixIt(rates.map { Self.percentText($0.percent, locale: locale) }.formatted(.list(type: .or))))
    }

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            withSuggestions(field)
            if invalid {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(Text(verbatim: fixIt))
                    .accessibilityLabel(Text(verbatim: fixIt))
            }
        }
    }

    private var field: some View {
        TextField(text: $text) { Text(L.colVATRate) }
            .labelsHidden()
            .textRole(.amount)
            .focused(focus, equals: focusValue)
            .overlay {
                RoundedRectangle(cornerRadius: Radius.s).stroke(Color.red, lineWidth: invalid ? 1.5 : 0)
            }
            .accessibilityHint(Text(verbatim: invalid ? fixIt : ""))
            // A rebuilt cell shows the invalid text it held, still ⛔, or the rate (screens-flows.md §2c); a
            // treatment without a rate drops the entry in the model (`dropRateCellsOfUntaxedLines`).
            .onAppear {
                if let kept = model.invalidText(of: cell) {
                    text = kept
                    invalid = true
                } else {
                    text = display(kind)
                    setInvalid(nil)
                }
            }
            .onChange(of: kind) { _, newKind in
                guard !isFocused else { return }
                text = display(newKind)
                setInvalid(nil)
            }
            .onChange(of: day) { _, _ in
                if !isFocused, !invalid { text = display(kind) }
            }
            .onChange(of: text) { _, newText in
                guard isFocused else { return }
                apply(newText, finishing: false)
            }
            .onChange(of: isFocused) { _, focusedNow in
                if focusedNow {
                    original = kind
                } else {
                    apply(text, finishing: true)
                }
            }
            .onKeyPress(.escape) {
                if let original, original != kind { commit(original) }
                setInvalid(nil)
                text = display(original ?? kind)
                return .handled
            }
            .onSubmit {
                apply(text, finishing: true)
                if !invalid { onSubmit() }
            }
    }

    @ViewBuilder private func withSuggestions<Field: View>(_ field: Field) -> some View {
        if #available(macOS 15, *) {
            field.textInputSuggestions {
                ForEach(rates, id: \.kind) { rate in
                    Text(verbatim: Self.percentText(rate.percent, locale: locale))
                        .textInputCompletion(rate.percent.plainString)
                }
            }
        } else {
            field
        }
    }

    /// "21", "21%" and "21 %" all name the standard rate; an empty field is not an error while typing.
    private func apply(_ text: String, finishing: Bool) {
        let trimmed = text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = DecimalInput.parsePercent(trimmed), let rate = rates.first(where: { $0.percent == value }) {
            setInvalid(nil)
            if rate.kind != kind { commit(rate.kind) }
            if finishing { self.text = display(rate.kind) }
        } else if trimmed.isEmpty || text == display(kind) {
            // Empty, or the cell's own display left untouched ("Not in force"): the validator reports a
            // rate that is not in force; tabbing through is not a typing error.
            setInvalid(nil)
            if finishing { self.text = display(kind) }
        } else {
            setInvalid(text)
        }
    }

    /// Always tells the model (its `setCell` ignores a repeat), which keeps the text for a rebuilt cell.
    private func setInvalid(_ invalidText: String?) {
        let flag = invalidText != nil
        if invalid != flag { invalid = flag }
        model.setCell(cell, invalidText: invalidText)
    }

    private func display(_ kind: VATRateKind) -> String {
        guard let rate = CzechVATRates.rate(kind, on: day) else { return String(localized: L.rateNotInForce) }
        return Self.percentText(rate.percent, locale: locale)
    }

    /// "21%" in English, "21 %" in Czech: the percent style of the UI locale.
    static func percentText(_ percent: Decimal, locale: Locale) -> String {
        (percent / 100).formatted(Decimal.FormatStyle.Percent(locale: locale).precision(.fractionLength(0)))
    }
}

// MARK: - Rate forms

/// The inline rate form (screens-flows.md §2c, design-system.md §8.9 "missing"): the tax point's rate is
/// not stored, so the user types it for the prefilled publication day, or imports the ČNB file. ↩ saves
/// with the source "Typed" and the document takes the rate at once. Errors show under the field, in the
/// editor and in the Issue sheet alike.
struct RateEntryForm<Focus: Hashable>: View {
    let model: DraftEditorModel
    let stores: Stores
    let focus: FocusState<Focus?>.Binding
    let focusValue: Focus

    @Environment(\.locale) private var locale
    @Environment(\.textScale) private var textScale
    @State private var text = ""
    @State private var day = Date()
    @State private var importing = false
    @State private var importLine: String?

    private var parsed: Decimal? { DecimalInput.parseRate(text) }
    private var invalid: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && parsed == nil }

    var body: some View {
        if let document = model.document {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Label {
                    Text(L.rateMissing(document.currency.code, model.neededRateDay.formatted(locale))).textRole(.body)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                }
                HStack(spacing: Spacing.m) {
                    TextField(text: $text) {
                        Text(L.rateFieldLabel(document.currency.code))
                    }
                    .textRole(.amount)
                    .frame(width: 120 * textScale)
                    .focused(focus, equals: focusValue)
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.s).stroke(Color.red, lineWidth: invalid ? 1.5 : 0)
                    }
                    .onSubmit { save() }
                    DatePicker(selection: $day, displayedComponents: .date) { Text(L.rateDateLabel) }
                    Button { save() } label: { Text(L.saveRate) }
                        .disabled((parsed ?? 0) <= 0)
                    Button { importing = true } label: { Text(L.importRates) }
                }
                if invalid {
                    InlineMessage(L.enterRateNumber(FixIt.rateExample(locale)))
                }
                if let importLine {
                    Text(verbatim: importLine).textRole(.caption)
                }
                if let rateError = model.rateError {
                    InlineMessage(rateError)
                }
            }
            .onAppear { day = model.neededRateDay.midnight(in: .current) }
            .onChange(of: model.neededRateDay) { _, needed in day = needed.midnight(in: .current) }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .text, .data], allowsMultipleSelection: false) { result in
                guard let outcome = RateImport.perform(result, stores: stores, locale: locale) else { return }
                importLine = outcome.line
                if outcome.count != nil { model.refreshRate() }
            }
        }
    }

    private func save() {
        guard let parsed, parsed > 0 else { return }
        model.saveManualRate(parsed, validFor: CalendarDay(day, in: .current))
        if model.rateError == nil { text = "" }
    }
}

/// Change… on a resolved rate (design-system.md §8.9): a corrected value, saved over the stored one for
/// its day, so a mistyped rate is not frozen at issue and reused by the next document with that date.
struct RateChangePopover: View {
    let model: DraftEditorModel
    let rate: ExchangeRate

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.textScale) private var textScale
    @State private var text: String
    @State private var day: Date
    @FocusState private var focused: Bool

    init(model: DraftEditorModel, rate: ExchangeRate) {
        self.model = model
        self.rate = rate
        _text = State(initialValue: DraftEditorView.rateText(rate, locale: .current))
        _day = State(initialValue: rate.validFor.midnight(in: .current))
    }

    private var parsed: Decimal? { DecimalInput.parseRate(text) }
    private var invalid: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && parsed == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.m) {
                TextField(text: $text) { Text(L.rateFieldLabel(rate.currency.code)) }
                    .textRole(.amount)
                    .frame(width: 120 * textScale)
                    .focused($focused)
                    .onSubmit { save() }
                DatePicker(selection: $day, displayedComponents: .date) { Text(L.rateDateLabel) }
            }
            if invalid {
                InlineMessage(L.enterRateNumber(FixIt.rateExample(locale)))
            }
            if let rateError = model.rateError {
                InlineMessage(rateError)
            }
            HStack {
                Spacer()
                Button { dismiss() } label: { Text(L.cancel) }
                    .keyboardShortcut(.cancelAction)
                Button { save() } label: { Text(L.saveRate) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled((parsed ?? 0) <= 0)
            }
        }
        .padding(Spacing.l)
        .frame(width: 380 * textScale)
        .onAppear { focused = true }
    }

    private func save() {
        guard let parsed, parsed > 0 else { return }
        model.saveManualRate(parsed, validFor: CalendarDay(day, in: .current), replace: true)
        if model.rateError == nil { dismiss() }
    }
}
