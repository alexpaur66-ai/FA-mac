/// The supplier's own data: the party printed on every document, the accounts to be paid to and the
/// defaults a new document starts from. Kept once as the company profile; each document gets a copy of
/// the party when it is created, so later edits of the profile never change an issued document (§ 35 ZDPH).
public struct CompanyProfile: Hashable, Sendable, Codable {
    public var supplier: Party
    /// Accounts the company can be paid to, in display order.
    public var bankConnections: [BankConnection]
    /// True for a plátce DPH: the documents are tax documents and carry VAT.
    public var isVATPayer: Bool
    public var defaultCurrency: Currency
    /// Days from the issue date to the due date when the customer has no term of their own.
    public var defaultPaymentTermDays: Int
    /// Text printed at the foot of every document.
    public var footer: String?

    public init(supplier: Party, bankConnections: [BankConnection] = [], isVATPayer: Bool = true,
                defaultCurrency: Currency = .czk, defaultPaymentTermDays: Int = 14, footer: String? = nil) {
        self.supplier = supplier
        self.bankConnections = bankConnections
        self.isVATPayer = isVATPayer
        self.defaultCurrency = defaultCurrency
        self.defaultPaymentTermDays = max(0, defaultPaymentTermDays)
        self.footer = footer
    }

    /// The account to print for a document in `currency`: the first account kept in that currency, else
    /// the first account without a currency (multi-currency), else the first account at all.
    public func bankConnection(for currency: Currency) -> BankConnection? {
        bankConnections.first { $0.currency == currency }
            ?? bankConnections.first { $0.currency == nil }
            ?? bankConnections.first
    }
}
