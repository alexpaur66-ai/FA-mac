import Foundation

/// The Czech "QR platba" payment string (Short Payment Descriptor, SPAYD, version 1.0) that banking
/// apps scan to prefill a domestic transfer.
///
/// Format per the specification at qr-platba.cz (read 5 Nov 2026):
/// `SPD*1.0*ACC:CZ5855000000001265098001+RZBCCZPP*AM:480.50*CC:CZK*MSG:PLATBA ZA ZBOZI*X-VS:1234567890`
/// Fields are `KEY:VALUE` pairs separated by `*`; a value must not contain `*` (written as `%2A`);
/// the string may contain any ISO-8859-1 character, and other characters may be percent-encoded.
/// Keys every Czech bank processes for a domestic payment: ACC (one account), AM, CC (CZK), DT,
/// MSG, X-VS, X-SS, X-KS. The optional CRC32 field is not produced: the specification page does not
/// pin down the exact string it is computed over, and no bank requires it.
public struct QRPlatba: Hashable, Sendable {
    public enum EncodingError: Error, Equatable, Sendable {
        /// The value for `key` is longer than the format allows.
        case tooLong(key: String, maximum: Int, actual: Int)
        /// The amount is negative, zero, has more than two decimals, or exceeds 9 999 999,99.
        case invalidAmount(Decimal)
        /// The payer reference (RF) must be a whole number of at most 16 digits.
        case invalidPaymentReference(String)
        /// The payment type (PT) must be 1–3 characters from the QR alphanumeric set.
        case invalidPaymentType(String)
    }

    /// Account to pay to (ACC). With a BIC the field reads `IBAN+BIC`.
    public var iban: IBAN
    public var bic: BIC?
    /// Amount with at most two decimals (AM). Nil leaves the amount for the payer to type.
    public var amount: Decimal?
    /// ISO 4217 code (CC). Czech banks process CZK for domestic payments; other codes are passed
    /// through as the format allows but the bank may refuse them.
    public var currency: Currency?
    /// Due date (DT).
    public var dueDate: CalendarDay?
    /// Variabilní, specifický and konstantní symbol (X-VS, X-SS, X-KS).
    public var variableSymbol: PaymentSymbol?
    public var specificSymbol: PaymentSymbol?
    public var constantSymbol: PaymentSymbol?
    /// Message for the recipient (MSG), at most 60 characters after encoding.
    public var message: String?
    /// Recipient name (RN), at most 35 characters after encoding.
    public var recipientName: String?
    /// Payer-side payment reference (RF): a whole number of at most 16 digits.
    public var paymentReference: String?
    /// Payment type (PT), for example "IP" to request an instant payment.
    public var paymentType: String?
    /// Strip diacritics and uppercase MSG and RN so they fit the compact QR alphanumeric mode
    /// ("Platba za zboží" → "PLATBA ZA ZBOZI"). Czech banking apps show the result as typed here.
    public var foldsTextToQRAlphanumeric = true

    public init(iban: IBAN, bic: BIC? = nil, amount: Decimal? = nil, currency: Currency? = nil, dueDate: CalendarDay? = nil,
                variableSymbol: PaymentSymbol? = nil, specificSymbol: PaymentSymbol? = nil, constantSymbol: PaymentSymbol? = nil,
                message: String? = nil, recipientName: String? = nil, paymentReference: String? = nil, paymentType: String? = nil) {
        self.iban = iban
        self.bic = bic
        self.amount = amount
        self.currency = currency
        self.dueDate = dueDate
        self.variableSymbol = variableSymbol
        self.specificSymbol = specificSymbol
        self.constantSymbol = constantSymbol
        self.message = message
        self.recipientName = recipientName
        self.paymentReference = paymentReference
        self.paymentType = paymentType
    }

    public static let header = "SPD*1.0"
    /// 9 999 999,99: the largest amount the AM field (10 characters) can carry.
    public static let maximumAmount = Decimal(sign: .plus, exponent: -2, significand: 999_999_999)

    /// Maximum length of each value as given by the specification.
    static let maximumLengths: [String: Int] = [
        "ACC": 46, "AM": 10, "CC": 3, "RF": 16, "RN": 35, "DT": 8, "PT": 3, "MSG": 60,
        "X-VS": 10, "X-SS": 10, "X-KS": 10,
    ]

    /// The complete string to encode into the QR code.
    public func encoded() throws -> String {
        var fields: [(String, String)] = []

        var account = iban.value
        if let bic { account += "+" + bic.value }
        fields.append(("ACC", account))

        if let amount {
            guard amount > 0, amount.fits(scale: 2), amount <= Self.maximumAmount else {
                throw EncodingError.invalidAmount(amount)
            }
            fields.append(("AM", amount.plainString(minimumFractionDigits: 2)))
        }
        if let currency { fields.append(("CC", currency.code)) }
        if let paymentReference {
            let digits = paymentReference.trimmingWhitespace()
            guard !digits.isEmpty, digits.count <= 16, digits.allSatisfy(\.isASCIIDigit) else {
                throw EncodingError.invalidPaymentReference(paymentReference)
            }
            fields.append(("RF", digits))
        }
        if let recipientName { fields.append(("RN", Self.encodeText(recipientName, fold: foldsTextToQRAlphanumeric))) }
        if let dueDate {
            fields.append(("DT", String(dueDate.year).leftPadded(to: 4) + String(dueDate.month).leftPadded(to: 2) + String(dueDate.day).leftPadded(to: 2)))
        }
        if let paymentType {
            let type = paymentType.trimmingWhitespace().uppercased()
            guard (1...3).contains(type.count), type.allSatisfy({ PaymentStringText.qrAlphanumeric.contains($0) && $0 != "*" }) else {
                throw EncodingError.invalidPaymentType(paymentType)
            }
            fields.append(("PT", type))
        }
        if let message { fields.append(("MSG", Self.encodeText(message, fold: foldsTextToQRAlphanumeric))) }
        if let variableSymbol { fields.append(("X-VS", variableSymbol.digits)) }
        if let specificSymbol { fields.append(("X-SS", specificSymbol.digits)) }
        if let constantSymbol { fields.append(("X-KS", constantSymbol.digits)) }

        for (key, value) in fields {
            if let maximum = Self.maximumLengths[key], value.count > maximum {
                throw EncodingError.tooLong(key: key, maximum: maximum, actual: value.count)
            }
        }
        return ([Self.header] + fields.map { "\($0.0):\($0.1)" }).joined(separator: "*")
    }

    /// Prepares free text for a value: whitespace collapsed, optionally folded to the QR alphanumeric
    /// set, `*` and `%` always percent-encoded, characters outside ISO-8859-1 percent-encoded as UTF-8.
    static func encodeText(_ text: String, fold: Bool) -> String {
        var prepared = PaymentStringText.collapsingWhitespace(text)
        if fold { prepared = PaymentStringText.strippingDiacritics(prepared).uppercased() }
        return PaymentStringText.percentEncoding(prepared) { character in
            guard character != "*", character != "%" else { return false }
            guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return false }
            return scalar.value >= 0x20 && scalar.value <= 0xFF && scalar.value != 0x7F
        }
    }
}
