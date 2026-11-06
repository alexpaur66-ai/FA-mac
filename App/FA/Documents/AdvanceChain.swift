// The advance chain of one document (screens-flows.md §2d): advance → payments → tax documents → final
// invoice, for the chain line under the issued view's header and for Document ▸ Show Related Documents ▸.
// Text only: no symbol, tint or status style per step (design-system.md §8, the chain line entry).

import InvoicingCore
import InvoicingData
import SwiftUI

/// What the chain line offers in the place of the missing step: one `.bordered` button.
enum ChainNextStep: Equatable {
    /// The tax document for the oldest received payment that needs one and has none.
    case createTaxDocument(advanceID: String, payment: DocumentPayment)
    case createFinalInvoice(advanceID: String)
}

/// One step of the chain line.
struct ChainItem: Identifiable, Equatable {
    enum Role: Equatable {
        case advance, payment, taxDocument, finalInvoice
    }

    let id: String
    let role: Role
    /// The document the step opens; nil for a payment and for a step that does not exist yet.
    var documentID: String?
    var number: String?
    var isDraft = false
    /// The document the chain is shown for: plain text, not a link.
    var isCurrent = false
    /// The advance's status word ("Paid"), on an advance step only.
    var stateWord: String?
    /// A received payment's day.
    var day: CalendarDay?
    /// The missing step offered as the next-step button instead of plain text.
    var next: ChainNextStep?

    var exists: Bool { documentID != nil || day != nil }

    /// "Advance ZF 2026-0003 · Paid", "Payment 12. 11. 2026", "Tax document (draft)", "Final invoice".
    func text(locale: Locale) -> String {
        switch role {
        case .advance:
            let number = number ?? ""
            return stateWord.map { String(localized: L.chainAdvanceState(number, $0)) } ?? String(localized: L.chainAdvance(number))
        case .payment:
            return day.map { String(localized: L.chainPayment($0.formatted(locale))) } ?? String(localized: L.chainPaymentFuture)
        case .taxDocument:
            if let number { return String(localized: L.chainTaxDocument(number)) }
            return String(localized: isDraft ? L.chainTaxDocumentDraft : L.chainTaxDocumentFuture)
        case .finalInvoice:
            if let number { return String(localized: L.chainFinal(number)) }
            return String(localized: isDraft ? L.chainFinalDraft : L.chainFinalFuture)
        }
    }

    /// The VoiceOver label of a link: "Advance ZF 2026-0003, paid".
    func accessibilityText(locale: Locale) -> String {
        guard role == .advance, let number, let stateWord else { return text(locale: locale) }
        return String(localized: L.chainAdvanceSpoken(number, stateWord.localizedLowercase))
    }

    /// The item of Document ▸ Show Related Documents ▸, in title case: "Tax Document DD 2026-0007",
    /// "Final Invoice (Draft)".
    var menuTitle: String {
        switch role {
        case .advance: String(localized: L.relatedAdvance(number ?? ""))
        case .payment: ""
        case .taxDocument: number.map { String(localized: L.relatedTaxDocument($0)) } ?? String(localized: L.relatedTaxDocumentDraft)
        case .finalInvoice: number.map { String(localized: L.relatedFinal($0)) } ?? String(localized: L.relatedFinalDraft)
        }
    }
}

struct AdvanceChain: Equatable {
    var items: [ChainItem]

    /// The chain's other documents, in line order: the links, and the items of Show Related Documents ▸.
    var relatedDocuments: [ChainItem] {
        items.filter { $0.documentID != nil && !$0.isCurrent }
    }

    /// The chain of `documentID`, or nil when the document is in none: an invoice, a final invoice that
    /// deducts no advance, or an advance with no step besides itself (closed without payment).
    static func of(_ documentID: String, stores: Stores, states: [DocumentState]) throws -> AdvanceChain? {
        guard let current = states.first(where: { $0.id == documentID }) else { return nil }
        let summary = current.summary
        func state(number: String?) -> DocumentState? {
            guard let number else { return nil }
            return states.first { $0.summary.kind == .advanceRequest && $0.summary.number == number }
        }

        var advanceIDs: [String] = []
        switch summary.kind {
        case .invoice:
            return nil
        case .advanceRequest:
            advanceIDs = [documentID]
        case .paymentTaxDocument:
            if let payment = try stores.documents.payment(ofReceipt: documentID) {
                advanceIDs = [payment.documentID]
            } else if let advance = state(number: summary.relatedDocumentNumber) {
                advanceIDs = [advance.id]
            }
        case .finalInvoice:
            if summary.status == .issued {
                advanceIDs = try stores.documents.deductions(ofFinalInvoice: documentID).compactMap(\.advanceRequestID)
                advanceIDs += try stores.documents.paidAdvances(ofFinalInvoice: documentID).map(\.advanceRequestID)
            }
            if advanceIDs.isEmpty, let advance = state(number: summary.relatedDocumentNumber) {
                advanceIDs = [advance.id]
            }
        }
        advanceIDs = DocumentLinks.unique(advanceIDs)
        guard !advanceIDs.isEmpty else { return nil }

        var items: [ChainItem] = []
        var finals: [ChainItem] = []
        // Only an advance shown on its own can offer a next step: a final invoice already exists.
        let offersNextStep = advanceIDs.count == 1
        for advanceID in advanceIDs {
            guard let advance = states.first(where: { $0.id == advanceID }) else { continue }
            let label = DocumentStateInputs(advance).label
            items.append(ChainItem(
                id: "advance-\(advanceID)", role: .advance, documentID: advanceID, number: advance.summary.number,
                isCurrent: advanceID == documentID, stateWord: String(localized: label.style.label)))

            let received = try stores.documents.payments(for: advanceID).filter { $0.kind == .received }
            let advanceFinals = try finalInvoices(of: advance, stores: stores, states: states)
            let isClosed = advance.closure != nil
            let next = offersNextStep && !isClosed && advanceFinals.isEmpty
                ? nextStep(advance, received: received, states: states) : nil

            if received.isEmpty {
                if !isClosed {
                    items.append(ChainItem(id: "payment-\(advanceID)", role: .payment))
                    if advance.taxDocumentRequired {
                        items.append(ChainItem(id: "tax-\(advanceID)", role: .taxDocument))
                    }
                }
            }
            for payment in received {
                items.append(ChainItem(id: "payment-\(payment.id)", role: .payment, day: payment.paidOn))
                guard advance.taxDocumentRequired else { continue }
                var step = ChainItem(id: "tax-\(payment.id)", role: .taxDocument)
                if let receiptID = payment.receiptDocumentID {
                    let receipt = states.first { $0.id == receiptID }
                    step.documentID = receiptID
                    step.number = receipt?.summary.number
                    step.isDraft = receipt?.summary.status == .draft
                    step.isCurrent = receiptID == documentID
                } else if case .createTaxDocument(_, let missing)? = next, missing.id == payment.id {
                    step.next = next
                } else if isClosed {
                    continue
                }
                items.append(step)
            }
            for finalItem in advanceFinals where !finals.contains(where: { $0.id == finalItem.id }) {
                finals.append(finalItem)
            }
            if advanceFinals.isEmpty && !isClosed {
                var step = ChainItem(id: "final-\(advanceID)", role: .finalInvoice)
                if case .createFinalInvoice? = next { step.next = next }
                finals.append(step)
            }
        }
        for index in finals.indices where finals[index].documentID == documentID {
            finals[index].isCurrent = true
        }
        items += finals
        // A chain of the current document alone says nothing (an advance closed without payment).
        guard items.count > 1 else { return nil }
        return AdvanceChain(items: items)
    }

    /// The final invoices of an advance: the issued ones that deducted its tax documents or settled its
    /// payments as paid in advance, and the drafts made from it (their related document is its number).
    private static func finalInvoices(of advance: DocumentState, stores: Stores, states: [DocumentState]) throws -> [ChainItem] {
        var ids = try stores.documents.deductions(ofAdvanceRequest: advance.id).map(\.finalInvoiceID)
        ids += try stores.documents.paidAdvances(ofAdvanceRequest: advance.id).map(\.finalInvoiceID)
        if let number = advance.summary.number {
            ids += states.filter {
                $0.summary.kind == .finalInvoice && $0.summary.status == .draft && $0.summary.relatedDocumentNumber == number
            }.map(\.id)
        }
        return DocumentLinks.unique(ids).map { id in
            let invoice = states.first { $0.id == id }
            return ChainItem(id: "final-\(id)", role: .finalInvoice, documentID: id, number: invoice?.summary.number,
                             isDraft: invoice?.summary.status == .draft)
        }
    }

    /// The advance's next step (screens-flows.md §2d): Create Tax Document for the oldest received payment
    /// that needs one and has none; Create Final Invoice once every tax document is issued, or at once on an
    /// EU-goods advance that has a payment. None while nothing is paid or the missing step is a draft.
    private static func nextStep(_ advance: DocumentState, received: [DocumentPayment], states: [DocumentState]) -> ChainNextStep? {
        guard !received.isEmpty, advance.paid.amount > 0 else { return nil }
        if advance.taxDocumentRequired {
            if let missing = received.first(where: { $0.receiptDocumentID == nil }) {
                return .createTaxDocument(advanceID: advance.id, payment: missing)
            }
            let draftReceipt = received.contains { payment in
                states.first { $0.id == payment.receiptDocumentID }?.summary.status == .draft
            }
            if draftReceipt { return nil }
        }
        return .createFinalInvoice(advanceID: advance.id)
    }
}

/// The chain line: the steps as text separated by arrows, the other documents as links, and the next-step
/// button in the place of the missing step. It wraps onto more lines in a narrow column.
struct ChainLine: View {
    let chain: AdvanceChain
    /// Shows a document of the chain: an issued one in its issued view, a draft in the editor.
    let open: @MainActor (ChainItem) -> Void
    let perform: @MainActor (ChainNextStep) -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        ChainFlowLayout(spacing: Spacing.xs, lineSpacing: Spacing.xs) {
            ForEach(Array(chain.items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Text(verbatim: "→").textRole(.rowSecondary).accessibilityHidden(true)
                }
                step(item)
            }
        }
    }

    @ViewBuilder private func step(_ item: ChainItem) -> some View {
        if let next = item.next {
            Button { perform(next) } label: { Text(Self.title(next)) }
                .buttonStyle(.bordered)
        } else if item.documentID != nil && !item.isCurrent {
            Button { open(item) } label: { Text(verbatim: item.text(locale: locale)).textRole(.body) }
                .buttonStyle(.link)
                .accessibilityLabel(Text(verbatim: item.accessibilityText(locale: locale)))
        } else {
            Text(verbatim: item.text(locale: locale))
                .textRole(item.exists ? .body : .rowSecondary)
        }
    }

    static func title(_ next: ChainNextStep) -> LocalizedStringResource {
        switch next {
        case .createTaxDocument: L.createTaxDocument
        case .createFinalInvoice: L.createFinalInvoice
        }
    }
}

/// Lays its children out left to right and wraps onto a new line when the width runs out.
private struct ChainFlowLayout: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
