/// The deadline for issuing a tax document (§ 28 odst. 8 and 9 ZDPH).
public enum IssueDeadline {
    /// The last day the document may be issued, or nil for an advance request (not a tax document) or a
    /// document without lines.
    public static func lastDay(for document: Document) -> CalendarDay? {
        guard document.kind.isTaxDocument, !document.lines.isEmpty else { return nil }
        return lastDay(treatments: document.treatments, taxPoint: document.taxPoint)
    }

    /// The strictest deadline over the treatments on one document.
    public static func lastDay(treatments: [VATTreatment], taxPoint: CalendarDay) -> CalendarDay? {
        treatments.map { lastDay(treatment: $0, taxPoint: taxPoint) }.min()
    }

    /// 15 days from the day the obligation arose for supplies taxed or exempt in the Czech Republic
    /// (§ 28 odst. 8 ZDPH); 15 days from the end of the month for services with the place of supply in
    /// another member state or a third country, and for advances received on them (§ 28 odst. 9 písm. b)–d)).
    public static func lastDay(treatment: VATTreatment, taxPoint: CalendarDay) -> CalendarDay {
        switch treatment {
        case .reverseChargeEU, .outsideEU:
            return taxPoint.endOfMonth.adding(days: 15)
        case .taxable, .exempt:
            return taxPoint.adding(days: 15)
        }
    }
}
