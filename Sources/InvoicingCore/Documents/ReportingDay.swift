/// The day a supply counts in the VAT return and the souhrnné hlášení.
public enum ReportingDay {
    /// Goods supplied to another member state exempt under § 64 ZDPH count on the 15th day of the month
    /// after the month of supply or, when the tax document was issued before that day, on its issue date
    /// (§ 22 odst. 1 ZDPH). Every other treatment counts on the tax point, as the rest of the app does.
    public static func day(treatment: VATTreatment, taxPoint: CalendarDay, issueDate: CalendarDay) -> CalendarDay {
        guard treatment == .intraCommunityGoods else { return taxPoint }
        let fifteenth = taxPoint.endOfMonth.adding(days: 15)
        return issueDate < fifteenth ? issueDate : fifteenth
    }
}
