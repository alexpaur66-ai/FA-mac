/// Which payment QR code the document carries (docs/adr/0003).
public enum PaymentQRKind: String, Sendable, Codable, CaseIterable {
    case none
    /// Czech QR platba (SPAYD 1.0), for payers with a Czech bank.
    case qrPlatba
    /// EPC QR code (EPC069-12) for SEPA credit transfers in EUR.
    case sepa
}

/// How the document is to be paid: the account and the identifiers the payer should quote.
public struct PaymentInstructions: Hashable, Sendable, Codable {
    public var bankConnection: BankConnection
    public var variableSymbol: PaymentSymbol?
    public var specificSymbol: PaymentSymbol?
    public var constantSymbol: PaymentSymbol?
    /// ISO 11649 reference for SEPA transfers, usually built from the document number.
    public var creditorReference: CreditorReference?
    /// Text for the payer's statement; the document number when nil.
    public var message: String?
    public var qrCode: PaymentQRKind

    public init(bankConnection: BankConnection, variableSymbol: PaymentSymbol? = nil, specificSymbol: PaymentSymbol? = nil,
                constantSymbol: PaymentSymbol? = nil, creditorReference: CreditorReference? = nil, message: String? = nil,
                qrCode: PaymentQRKind = .none) {
        self.bankConnection = bankConnection
        self.variableSymbol = variableSymbol
        self.specificSymbol = specificSymbol
        self.constantSymbol = constantSymbol
        self.creditorReference = creditorReference
        self.message = message
        self.qrCode = qrCode
    }

    /// The usual instructions for a numbered document: the variable symbol and the ISO 11649 reference
    /// are derived from the number, the QR code is QR platba for CZK and the EPC code for EUR.
    /// `variableSymbolPrefix` is the numbering series' prefix (`DocumentNumberSeries.variableSymbolPrefix`).
    public static func standard(for number: String, bankConnection: BankConnection, currency: Currency,
                                variableSymbolPrefix: String? = nil) -> PaymentInstructions {
        let alphanumeric = number.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        let qrCode: PaymentQRKind
        switch currency {
        case .czk: qrCode = .qrPlatba
        case .eur: qrCode = .sepa
        default: qrCode = .none
        }
        return PaymentInstructions(
            bankConnection: bankConnection,
            variableSymbol: PaymentSymbol.variable(fromDocumentNumber: number, prefix: variableSymbolPrefix),
            creditorReference: alphanumeric.isEmpty ? nil : CreditorReference(reference: alphanumeric),
            qrCode: qrCode
        )
    }
}
