import Foundation

/// A rule the document breaks, or a point to check before it is issued.
public struct ValidationIssue: Hashable, Sendable, Identifiable {
    public enum Severity: String, Sendable, Codable {
        /// The document must not be issued like this.
        case error
        /// The document can be issued, but the user should look.
        case warning
    }

    public enum Code: String, Sendable, Codable, CaseIterable {
        case supplierNameMissing, supplierAddressIncomplete, supplierVATIdentifierMissing
        case supplierIdentificationNumberMissing, supplierRegistryEntryMissing
        case customerNameMissing, customerAddressIncomplete, customerVATIdentifierRequired, customerVATIdentifierNotEU
        case numberMissing, noLines, lineTextMissing, lineQuantityNegative, lineQuantityZero, lineDiscountOutOfRange
        case rateNotInForce, exemptReferenceMissing, mixedTreatments
        case taxPointDateMissing, taxPointAfterIssueDate, issuedAfterDeadline, dueDateBeforeIssueDate
        case exchangeRateMissing, exchangeRateCurrencyMismatch, exchangeRateAfterTaxPoint, exchangeRateStale
        case advanceDeductionsOnWrongKind, advanceRateDiffers, advancesExceedSupply
        case paymentInstructionsMissing, bankAccountCurrencyDiffers, amountsUnavailable
    }

    public let code: Code
    public let severity: Severity
    /// The line the issue is about, when any.
    public let lineID: String?
    /// A value the message mentions, e.g. a date or a currency code.
    public let detail: String?

    public init(code: Code, severity: Severity, lineID: String? = nil, detail: String? = nil) {
        self.code = code
        self.severity = severity
        self.lineID = lineID
        self.detail = detail
    }

    public var id: String { lineID.map { "\(code.rawValue)#\($0)" } ?? code.rawValue }

    public var isError: Bool { severity == .error }

    /// The message for the user, in the interface language.
    public func message(language: DocumentLanguage) -> String {
        let texts = Self.texts(for: code)
        let template = language == .czech ? texts.cs : texts.en
        return template.replacingOccurrences(of: "{detail}", with: detail ?? "")
    }

    private static func texts(for code: Code) -> (cs: String, en: String) {
        switch code {
        case .supplierNameMissing:
            return ("Chybí obchodní firma dodavatele (§ 29 odst. 1 písm. a) ZDPH).",
                    "The supplier's name is missing (§ 29(1)(a) of the VAT Act).")
        case .supplierAddressIncomplete:
            return ("Adresa sídla dodavatele je neúplná (§ 29 odst. 1 písm. a) ZDPH).",
                    "The supplier's address is incomplete (§ 29(1)(a) of the VAT Act).")
        case .supplierVATIdentifierMissing:
            return ("Chybí DIČ dodavatele (§ 29 odst. 1 písm. b) ZDPH).",
                    "The supplier's VAT ID (DIČ) is missing (§ 29(1)(b) of the VAT Act).")
        case .supplierIdentificationNumberMissing:
            return ("Chybí IČO dodavatele (§ 435 občanského zákoníku).",
                    "The supplier's IČO is missing (§ 435 of the Civil Code).")
        case .supplierRegistryEntryMissing:
            return ("Chybí údaj o zápisu v obchodním rejstříku (§ 435 občanského zákoníku); u podnikatele nezapsaného v rejstříku lze ignorovat.",
                    "The commercial register entry is missing (§ 435 of the Civil Code); ignore for a business not entered in the register.")
        case .customerNameMissing:
            return ("Chybí název odběratele (§ 29 odst. 1 písm. c) ZDPH).",
                    "The customer's name is missing (§ 29(1)(c) of the VAT Act).")
        case .customerAddressIncomplete:
            return ("Adresa sídla odběratele je neúplná (§ 29 odst. 1 písm. c) ZDPH).",
                    "The customer's address is incomplete (§ 29(1)(c) of the VAT Act).")
        case .customerVATIdentifierRequired:
            return ("Při přenesení daňové povinnosti musí doklad obsahovat DIČ odběratele (§ 29 odst. 1 písm. d) a odst. 2 písm. c) ZDPH).",
                    "A reverse-charge document must carry the customer's VAT ID (§ 29(1)(d) and (2)(c) of the VAT Act).")
        case .customerVATIdentifierNotEU:
            return ("DIČ odběratele {detail} není z jiného členského státu EU; přenesení daňové povinnosti podle § 9 odst. 1 ZDPH se neuplatní.",
                    "The customer's VAT ID {detail} is not from another EU member state; the § 9(1) reverse charge does not apply.")
        case .numberMissing:
            return ("Doklad nemá evidenční číslo (§ 29 odst. 1 písm. e) ZDPH).",
                    "The document has no number (§ 29(1)(e) of the VAT Act).")
        case .noLines:
            return ("Doklad nemá žádnou položku (§ 29 odst. 1 písm. f) ZDPH).",
                    "The document has no lines (§ 29(1)(f) of the VAT Act).")
        case .lineTextMissing:
            return ("Položka nemá popis plnění (§ 29 odst. 1 písm. f) ZDPH).",
                    "A line has no description of the supply (§ 29(1)(f) of the VAT Act).")
        case .lineQuantityNegative:
            return ("Položka má záporné množství; opravný daňový doklad (§ 45 ZDPH) zatím není podporován.",
                    "A line has a negative quantity; corrective tax documents (§ 45 of the VAT Act) are not supported yet.")
        case .lineQuantityZero:
            return ("Položka má nulové množství.",
                    "A line has a zero quantity.")
        case .lineDiscountOutOfRange:
            return ("Sleva musí být mezi 0 a 100 %.",
                    "The discount must be between 0 and 100 %.")
        case .rateNotInForce:
            return ("Sazba DPH položky neplatila k datu plnění {detail} (§ 47 ZDPH).",
                    "The line's VAT rate was not in force on {detail} (§ 47 of the VAT Act).")
        case .exemptReferenceMissing:
            return ("Osvobozené plnění musí uvádět ustanovení, podle kterého je osvobozeno (§ 29 odst. 2 písm. a) ZDPH).",
                    "An exempt supply must cite the provision it is exempt under (§ 29(2)(a) of the VAT Act).")
        case .mixedTreatments:
            return ("Doklad kombinuje plnění s českou DPH a přenesení daňové povinnosti; obvykle se vystavují zvlášť.",
                    "The document mixes Czech VAT and reverse-charge lines; they are usually issued separately.")
        case .taxPointDateMissing:
            return ("Chybí datum uskutečnění plnění nebo přijetí platby (§ 29 odst. 1 písm. h) ZDPH).",
                    "The date of supply or of payment receipt is missing (§ 29(1)(h) of the VAT Act).")
        case .taxPointAfterIssueDate:
            return ("Datum plnění {detail} je po datu vystavení.",
                    "The date of supply {detail} is after the issue date.")
        case .issuedAfterDeadline:
            return ("Doklad je vystaven po lhůtě; měl být vystaven nejpozději {detail} (§ 28 ZDPH).",
                    "The document is issued late; the deadline was {detail} (§ 28 of the VAT Act).")
        case .dueDateBeforeIssueDate:
            return ("Datum splatnosti {detail} předchází datu vystavení.",
                    "The due date {detail} is before the issue date.")
        case .exchangeRateMissing:
            return ("Chybí kurz pro přepočet na Kč (§ 4 odst. 8 a § 29 odst. 1 písm. l) ZDPH).",
                    "The exchange rate for the CZK amounts is missing (§ 4(8) and § 29(1)(l) of the VAT Act).")
        case .exchangeRateCurrencyMismatch:
            return ("Kurz je pro měnu {detail}, doklad je v jiné měně.",
                    "The exchange rate is for {detail}, not the document's currency.")
        case .exchangeRateAfterTaxPoint:
            return ("Kurz ze dne {detail} je pozdější než datum plnění (§ 4 odst. 8 ZDPH).",
                    "The exchange rate of {detail} is later than the date of supply (§ 4(8) of the VAT Act).")
        case .exchangeRateStale:
            return ("Kurz je ze dne {detail}, více než týden před datem plnění; zkontrolujte, zda je kurzovní lístek úplný.",
                    "The exchange rate is from {detail}, more than a week before the date of supply; check that the rate table is complete.")
        case .advanceDeductionsOnWrongKind:
            return ("Zálohy lze odečíst jen na konečné faktuře.",
                    "Advances can only be deducted on a final invoice.")
        case .advanceRateDiffers:
            return ("Zálohy byly zdaněny jinou sazbou než plnění; výpočet podle § 37a odst. 3 ZDPH prověřte s účetní.",
                    "The advances were taxed at a different rate than the supply; check the § 37a(3) computation with your accountant.")
        case .advancesExceedSupply:
            return ("Odečtené zálohy převyšují plnění; základ daně je záporný (§ 37a odst. 2 písm. b) ZDPH).",
                    "The deducted advances exceed the supply; the tax base is negative (§ 37a(2)(b) of the VAT Act).")
        case .paymentInstructionsMissing:
            return ("Doklad neuvádí bankovní spojení.",
                    "The document has no bank details.")
        case .bankAccountCurrencyDiffers:
            return ("Účet je vedený v měně {detail}, doklad je v jiné měně.",
                    "The bank account is kept in {detail}, the document is in another currency.")
        case .amountsUnavailable:
            return ("Částky nelze spočítat: {detail}",
                    "The amounts cannot be computed: {detail}")
        }
    }
}

/// Checks a document against § 29 and § 28 ZDPH, § 435 of the Civil Code and its own consistency.
public enum DocumentValidator {
    /// Days between the exchange rate's day and the tax point beyond which the rate most likely comes from
    /// an incomplete rate table rather than from a weekend or holiday (the ČNB publishes every working day).
    public static let exchangeRateStaleAfterDays = 7

    /// All issues of `document`. `forIssue` adds the checks that only matter when the document is issued,
    /// today just its number. Errors block issuing; warnings are for the user to judge.
    public static func validate(_ document: Document, forIssue: Bool = true) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        func add(_ code: ValidationIssue.Code, _ severity: ValidationIssue.Severity, line: String? = nil, detail: String? = nil) {
            issues.append(ValidationIssue(code: code, severity: severity, lineID: line, detail: detail))
        }
        let isTaxDocument = document.kind.isTaxDocument

        // Supplier: § 29 odst. 1 písm. a) and b) ZDPH; § 435 občanského zákoníku.
        if document.supplier.name.trimmingWhitespace().isEmpty { add(.supplierNameMissing, .error) }
        if !Self.isComplete(document.supplier.address) { add(.supplierAddressIncomplete, .error) }
        if isTaxDocument && document.supplier.vatIdentifier == nil { add(.supplierVATIdentifierMissing, .error) }
        if document.supplier.identificationNumber == nil { add(.supplierIdentificationNumberMissing, .warning) }
        if document.supplier.registryEntry == nil && document.supplier.address.isCzech { add(.supplierRegistryEntryMissing, .warning) }

        // Customer: § 29 odst. 1 písm. c) and d), odst. 2 písm. c) ZDPH.
        if document.customer.name.trimmingWhitespace().isEmpty { add(.customerNameMissing, .error) }
        if !Self.isComplete(document.customer.address) { add(.customerAddressIncomplete, .error) }
        let treatments = document.treatments
        if document.hasReverseCharge {
            if let vatIdentifier = document.customer.vatIdentifier {
                if vatIdentifier.isCzech || !vatIdentifier.isEU {
                    add(.customerVATIdentifierNotEU, .error, detail: vatIdentifier.value)
                }
            } else {
                add(.customerVATIdentifierRequired, .error)
            }
        }

        // Number: § 29 odst. 1 písm. e) ZDPH.
        if forIssue && (document.number ?? "").trimmingWhitespace().isEmpty { add(.numberMissing, .error) }

        // Lines: § 29 odst. 1 písm. f), i), k) and odst. 2 písm. a) ZDPH.
        if document.lines.isEmpty { add(.noLines, .error) }
        for line in document.lines {
            if line.text.trimmingWhitespace().isEmpty {
                // § 29 odst. 3 písm. c): a payment tax document may leave the scope out when it is not known yet.
                add(.lineTextMissing, document.kind == .paymentTaxDocument ? .warning : .error, line: line.id)
            }
            if line.quantity < 0 {
                add(.lineQuantityNegative, .error, line: line.id)
            } else if line.quantity == 0 {
                add(.lineQuantityZero, .warning, line: line.id)
            }
            if line.discountPercent < 0 || line.discountPercent > 100 { add(.lineDiscountOutOfRange, .error, line: line.id) }
            switch line.treatment {
            case .taxable(let kind):
                if CzechVATRates.rate(kind, on: document.taxPoint) == nil {
                    add(.rateNotInForce, .error, line: line.id, detail: document.taxPoint.isoString)
                }
            case .exempt(let reference):
                if reference.trimmingWhitespace().isEmpty { add(.exemptReferenceMissing, .error, line: line.id) }
            case .reverseChargeEU, .outsideEU:
                break
            }
        }
        if document.hasReverseCharge && treatments.contains(where: { $0.chargesVAT }) { add(.mixedTreatments, .warning) }

        // Dates: § 29 odst. 1 písm. g) and h), § 28 ZDPH.
        if isTaxDocument && document.taxPointDate == nil { add(.taxPointDateMissing, .error) }
        if let taxPointDate = document.taxPointDate, taxPointDate > document.issueDate {
            add(.taxPointAfterIssueDate, .warning, detail: taxPointDate.isoString)
        }
        if document.dueDate < document.issueDate { add(.dueDateBeforeIssueDate, .error, detail: document.dueDate.isoString) }
        if let deadline = IssueDeadline.lastDay(for: document), document.issueDate > deadline {
            add(.issuedAfterDeadline, .warning, detail: deadline.isoString)
        }

        // Advances: § 37a ZDPH.
        if !document.advanceDeductions.isEmpty && !document.kind.deductsAdvances { add(.advanceDeductionsOnWrongKind, .error) }

        // Amounts and the exchange rate: § 29 odst. 1 písm. j) and l), § 4 odst. 8 ZDPH.
        do {
            let totals = try DocumentTotals.compute(for: document)
            if isTaxDocument && document.currency != .czk {
                if let rate = document.exchangeRate {
                    if rate.validFor > document.taxPoint {
                        add(.exchangeRateAfterTaxPoint, .error, detail: rate.validFor.isoString)
                    } else if document.taxPoint.days(since: rate.validFor) > exchangeRateStaleAfterDays {
                        add(.exchangeRateStale, .warning, detail: rate.validFor.isoString)
                    }
                } else {
                    // Without Czech VAT there is no CZK tax amount to print, but the souhrnné hlášení still needs CZK values.
                    add(.exchangeRateMissing, totals.taxableVAT == 0 ? .warning : .error)
                }
            }
            if document.kind.deductsAdvances {
                if totals.rows.contains(where: { $0.taxableBase < 0 }) { add(.advancesExceedSupply, .warning) }
                var percentsByKey: [String: Set<Decimal>] = [:]
                for deduction in document.advanceDeductions {
                    if let percent = deduction.ratePercent {
                        percentsByKey[deduction.treatment.groupingKey, default: []].insert(percent)
                    }
                }
                for row in totals.rows {
                    guard var percents = percentsByKey[row.treatment.groupingKey] else { continue }
                    if let rate = row.rate, row.base != 0 { percents.insert(rate.percent) }
                    if percents.count > 1 {
                        add(.advanceRateDiffers, .warning)
                        break
                    }
                }
            }
            if totals.amountDue > 0 {
                if let payment = document.payment {
                    if let accountCurrency = payment.bankConnection.currency, accountCurrency != document.currency {
                        add(.bankAccountCurrencyDiffers, .warning, detail: accountCurrency.code)
                    }
                } else {
                    add(.paymentInstructionsMissing, .warning)
                }
            }
        } catch DocumentAmountError.exchangeRateCurrencyMismatch(let rateCurrency, _) {
            add(.exchangeRateCurrencyMismatch, .error, detail: rateCurrency.code)
        } catch {
            add(.amountsUnavailable, .error, detail: String(describing: error))
        }

        return issues
    }

    /// True when the document can be issued: no errors.
    public static func canIssue(_ document: Document) -> Bool {
        !validate(document, forIssue: true).contains(where: \.isError)
    }

    static func isComplete(_ address: PostalAddress) -> Bool {
        !address.street.trimmingWhitespace().isEmpty && !address.city.trimmingWhitespace().isEmpty
            && !address.countryCode.trimmingWhitespace().isEmpty
    }
}
