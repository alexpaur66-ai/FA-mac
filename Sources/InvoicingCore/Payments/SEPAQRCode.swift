import Foundation

/// The payload of a SEPA credit transfer QR code ("EPC QR code", in Germany "Girocode") that EU
/// banking apps scan to prefill a euro transfer.
///
/// Format per EPC069-12 version 3.1 (European Payments Council, 19 March 2024, read 5 Nov 2026):
/// twelve elements separated by LF, in this order: service tag `BCD`, version (`001` or `002`),
/// character set (`1` = UTF-8), identification `SCT`, BIC, name (≤ 70), IBAN, amount (`EUR` +
/// 0.01…999999999.99), purpose (≤ 4), structured remittance (≤ 35, ISO 11649 creditor reference) or
/// unstructured remittance (≤ 140, only one of the two), beneficiary-to-originator information (≤ 70).
/// The last populated element is not followed by a separator; the payload is at most 331 bytes.
/// The QR code itself must use error correction level M and at most version 13.
public struct SEPAQRCode: Hashable, Sendable {
    public enum Version: String, Hashable, Sendable, Codable {
        /// BIC mandatory: for transfers that may involve participants outside the EEA.
        case v001 = "001"
        /// BIC optional: the usual choice for transfers between EEA accounts.
        case v002 = "002"
    }

    public enum EncodingError: Error, Equatable, Sendable {
        case emptyName
        case tooLong(element: String, maximum: Int, actual: Int)
        /// Version 001 requires the beneficiary's BIC.
        case bicRequired
        /// Below 0.01, above 999 999 999.99, or more than two decimals.
        case invalidAmount(Decimal)
        /// Purpose codes are 1–4 letters or digits (ISO 20022 external purpose codes such as GDDS).
        case invalidPurpose(String)
        /// Structured and unstructured remittance information cannot both be present.
        case bothRemittanceForms
        case payloadTooLarge(bytes: Int, maximum: Int)
    }

    public var version: Version
    public var bic: BIC?
    /// Beneficiary name, at most 70 characters. Diacritics are kept; the payload is UTF-8.
    public var name: String
    public var iban: IBAN
    /// Amount in euro; the format carries no other currency.
    public var amount: Decimal?
    /// ISO 20022 purpose code, e.g. "GDDS" (goods) or "SCVE" (services).
    public var purpose: String?
    /// Structured remittance: the ISO 11649 creditor reference the payer's bank passes on unchanged.
    public var creditorReference: CreditorReference?
    /// Unstructured remittance text, at most 140 characters. Not allowed together with `creditorReference`.
    public var remittanceText: String?
    /// Beneficiary-to-originator information, at most 70 characters.
    public var information: String?

    public init(version: Version = .v002, bic: BIC? = nil, name: String, iban: IBAN, amount: Decimal? = nil, purpose: String? = nil,
                creditorReference: CreditorReference? = nil, remittanceText: String? = nil, information: String? = nil) {
        self.version = version
        self.bic = bic
        self.name = name
        self.iban = iban
        self.amount = amount
        self.purpose = purpose
        self.creditorReference = creditorReference
        self.remittanceText = remittanceText
        self.information = information
    }

    public static let serviceTag = "BCD"
    public static let identification = "SCT"
    /// Character set code 1: UTF-8.
    public static let characterSet = "1"
    public static let maximumPayloadBytes = 331
    public static let minimumAmount = Decimal(sign: .plus, exponent: -2, significand: 1)
    public static let maximumAmount = Decimal(sign: .plus, exponent: -2, significand: 99_999_999_999)
    /// The QR code must be generated with error correction level M and may not exceed version 13.
    public static let maximumQRVersion = 13

    /// The complete payload to encode into the QR code (UTF-8, LF separated).
    public func encoded() throws -> String {
        // NFC first, so a decomposed "é" (e + U+0301, common in text pasted on macOS) counts and travels
        // as one character, as it does for the bank.
        let name = PaymentStringText.collapsingWhitespace(self.name).precomposedStringWithCanonicalMapping
        guard !name.isEmpty else { throw EncodingError.emptyName }
        try Self.check(name, element: "Name", maximum: 70)

        if version == .v001, bic == nil { throw EncodingError.bicRequired }

        var amountText = ""
        if let amount {
            guard amount >= Self.minimumAmount, amount <= Self.maximumAmount, amount.fits(scale: 2) else {
                throw EncodingError.invalidAmount(amount)
            }
            amountText = "EUR" + amount.plainString(minimumFractionDigits: 2)
        }

        var purposeText = ""
        if let purpose {
            let code = purpose.trimmingWhitespace().uppercased()
            guard (1...4).contains(code.count), code.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
                throw EncodingError.invalidPurpose(purpose)
            }
            purposeText = code
        }

        // An empty or blank text is no remittance information, so it does not conflict with a reference.
        let remittance = remittanceText.map(PaymentStringText.collapsingWhitespace)?.precomposedStringWithCanonicalMapping ?? ""
        if creditorReference != nil, !remittance.isEmpty { throw EncodingError.bothRemittanceForms }
        try Self.check(remittance, element: "Remittance Information (Unstructured)", maximum: 140)
        let information = self.information.map(PaymentStringText.collapsingWhitespace)?.precomposedStringWithCanonicalMapping ?? ""
        try Self.check(information, element: "Beneficiary to Originator information", maximum: 70)

        var lines = [
            Self.serviceTag, version.rawValue, Self.characterSet, Self.identification,
            bic?.value ?? "", name, iban.value, amountText, purposeText,
            creditorReference?.value ?? "", remittance, information,
        ]
        // The last populated element is not followed by a separator; the IBAN (element 7) is always present.
        while lines.count > 7, let last = lines.last, last.isEmpty { lines.removeLast() }

        let payload = lines.joined(separator: "\n")
        let bytes = payload.utf8.count
        guard bytes <= Self.maximumPayloadBytes else {
            throw EncodingError.payloadTooLarge(bytes: bytes, maximum: Self.maximumPayloadBytes)
        }
        return payload
    }

    /// Counts Unicode scalars (code points), as bank parsers do, not Swift grapheme clusters: a letter
    /// with a combining mark that has no precomposed form is two characters for the bank.
    private static func check(_ value: String, element: String, maximum: Int) throws {
        let length = value.unicodeScalars.count
        if length > maximum { throw EncodingError.tooLong(element: element, maximum: maximum, actual: length) }
    }
}
