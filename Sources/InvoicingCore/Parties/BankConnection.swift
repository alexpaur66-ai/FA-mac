/// A bank account the supplier wants to be paid to: the IBAN (always), the Czech domestic form when
/// the account is Czech, the BIC for payments from abroad, and the currency the account is kept in.
public struct BankConnection: Hashable, Sendable, Codable {
    public var iban: IBAN
    public var bic: BIC?
    public var bankName: String?
    /// The account's currency; nil when the account is multi-currency or unknown.
    public var currency: Currency?

    public init(iban: IBAN, bic: BIC? = nil, bankName: String? = nil, currency: Currency? = nil) {
        self.iban = iban
        self.bic = bic
        self.bankName = bankName
        self.currency = currency
    }

    /// From a Czech domestic account number; nil when the number does not form a valid IBAN.
    public init?(czech account: CzechBankAccount, bic: BIC? = nil, bankName: String? = nil, currency: Currency? = nil) {
        guard let iban = IBAN.czech(account) else { return nil }
        self.init(iban: iban, bic: bic, bankName: bankName, currency: currency)
    }

    /// "19-2000145399/0800" for a Czech IBAN, nil otherwise.
    public var domesticAccount: CzechBankAccount? { iban.czechAccount }

    /// What a Czech document prints: the domestic form when available, else the IBAN.
    public var domesticLabel: String { domesticAccount?.description ?? iban.formatted }
}
