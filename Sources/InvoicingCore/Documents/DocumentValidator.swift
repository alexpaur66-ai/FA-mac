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
        case intraCommunityGoodsVATIdentifierRequired, intraCommunityGoodsVATIdentifierNotEU
        case numberMissing, noLines, lineTextMissing, lineQuantityNegative, lineQuantityZero, lineDiscountOutOfRange
        case rateNotInForce, exemptReferenceMissing, mixedTreatments
        case taxPointDateMissing, taxPointAfterIssueDate, issuedAfterDeadline, dueDateBeforeIssueDate
        case exchangeRateMissing, exchangeRateCurrencyMismatch, exchangeRateAfterTaxPoint, exchangeRateStale
        case advanceDeductionsOnWrongKind, advanceDeductedTwice, advanceCurrencyDiffers, advanceRateDiffers, advanceExchangeRateDiffers
        case advancesExceedSupply
        case documentTotalNegative, receivedAmountNotPositive
        case paymentInstructionsMissing, bankAccountCurrencyDiffers, amountsUnavailable
        case paymentQRCodeNameTooLong, paymentQRCodeUnavailable
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

    /// The message for the user, in the interface language. A date in `detail` (always stored as ISO
    /// "2026-11-19") is printed the Czech way in Czech messages.
    public func message(language: DocumentLanguage) -> String {
        let texts = Self.texts(for: code)
        let template = language == .czech ? texts.cs : texts.en
        var value = detail ?? ""
        if language == .czech, let day = CalendarDay(iso: value) { value = day.czechString }
        return template.replacingOccurrences(of: "{detail}", with: value)
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
        case .intraCommunityGoodsVATIdentifierRequired:
            return ("Dodání zboží do jiného členského státu je osvobozeno, jen když odběratel sdělil své DIČ z jiného členského státu (§ 64 odst. 1 písm. a) ZDPH); doklad ho musí uvádět (§ 29 odst. 1 písm. d) ZDPH).",
                    "Goods supplied to another member state are exempt only when the customer has given their VAT ID from another member state (§ 64(1)(a) of the VAT Act); the document must carry it (§ 29(1)(d) of the VAT Act).")
        case .intraCommunityGoodsVATIdentifierNotEU:
            return ("DIČ odběratele {detail} není z jiného členského státu EU; osvobození podle § 64 ZDPH se neuplatní.",
                    "The customer's VAT ID {detail} is not from another EU member state; the § 64 exemption does not apply.")
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
            return ("Datum plnění {detail} je po datu vystavení; služba se považuje za poskytnutou nejpozději dnem vystavení daňového dokladu (§ 21 odst. 3 ZDPH), u plnění s českou DPH proto uveďte datum plnění shodné s datem vystavení.",
                    "The date of supply {detail} is after the issue date; a service is deemed supplied no later than the day its tax document is issued (§ 21(3) of the VAT Act), so for a supply with Czech VAT set the date of supply to the issue date.")
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
        case .advanceDeductedTwice:
            return ("Záloha {detail} je odečtena dvakrát; každý daňový doklad k platbě lze odečíst jen jednou za každý režim DPH.",
                    "The advance {detail} is deducted twice; each payment tax document can be deducted only once per VAT treatment.")
        case .advanceCurrencyDiffers:
            return ("Záloha {detail} je v jiné měně než doklad.",
                    "The advance {detail} is in another currency than the document.")
        case .advanceRateDiffers:
            return ("Zálohy byly zdaněny jinou sazbou než plnění; výpočet podle § 37a odst. 3 ZDPH prověřte s účetní.",
                    "The advances were taxed at a different rate than the supply; check the § 37a(3) computation with your accountant.")
        case .advanceExchangeRateDiffers:
            return ("Záporný rozdíl se přepočítává kurzem uplatněným u zálohy (§ 37a odst. 2 písm. b) ZDPH); kurz zálohy chybí nebo byly zálohy přepočteny různými kurzy, použit je kurz dokladu – prověřte s účetní.",
                    "A negative difference is converted at the exchange rate applied to the advance (§ 37a(2)(b) of the VAT Act); the advance's rate is missing or the advances used different rates, so the document's rate was used – check with your accountant.")
        case .advancesExceedSupply:
            return ("Odečtené zálohy převyšují plnění; základ daně je záporný (§ 37a odst. 2 písm. b) ZDPH).",
                    "The deducted advances exceed the supply; the tax base is negative (§ 37a(2)(b) of the VAT Act).")
        case .documentTotalNegative:
            return ("Doklad nebo jeho řádek rekapitulace DPH je záporný; opravný daňový doklad (§ 45 ZDPH) zatím není podporován.",
                    "The document or a row of its VAT summary is negative; corrective tax documents (§ 45 of the VAT Act) are not supported yet.")
        case .receivedAmountNotPositive:
            return ("Daňový doklad k přijaté platbě musí znít na kladnou částku.",
                    "A tax document for a received payment must be for a positive amount.")
        case .paymentInstructionsMissing:
            return ("Doklad neuvádí bankovní spojení.",
                    "The document has no bank details.")
        case .bankAccountCurrencyDiffers:
            return ("Účet je vedený v měně {detail}, doklad je v jiné měně.",
                    "The bank account is kept in {detail}, the document is in another currency.")
        case .amountsUnavailable:
            return ("Částky dokladu nelze spočítat; zkontrolujte položky, odečtené zálohy a kurz.",
                    "The document's amounts cannot be computed; check the lines, the deducted advances and the exchange rate.")
        case .paymentQRCodeNameTooLong:
            return ("Název dodavatele je pro QR kód k platbě příliš dlouhý (nejvýše {detail} znaků); doklad se vystaví bez QR kódu.",
                    "The supplier's name is too long for the payment QR code (at most {detail} characters); the document will be issued without the code.")
        case .paymentQRCodeUnavailable:
            return ("QR kód k platbě nelze vytvořit (částka nebo text přesahuje limity formátu); doklad se vystaví bez QR kódu.",
                    "The payment QR code cannot be created (the amount or a text exceeds the format's limits); the document will be issued without the code.")
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

        // Customer: § 29 odst. 1 písm. c) and d), odst. 2 písm. c) ZDPH; § 64 odst. 1 písm. a) ZDPH.
        if document.customer.name.trimmingWhitespace().isEmpty { add(.customerNameMissing, .error) }
        if !Self.isComplete(document.customer.address) { add(.customerAddressIncomplete, .error) }
        let treatments = document.treatments
        // A VAT ID from another member state: the reverse charge prints it, the § 64 exemption depends on it.
        for treatment in treatments where treatment.requiresCustomerVATID {
            let goods = treatment == .intraCommunityGoods
            if let vatIdentifier = document.customer.vatIdentifier {
                if vatIdentifier.isCzech || !vatIdentifier.isEU {
                    add(goods ? .intraCommunityGoodsVATIdentifierNotEU : .customerVATIdentifierNotEU, .error, detail: vatIdentifier.value)
                }
            } else {
                add(goods ? .intraCommunityGoodsVATIdentifierRequired : .customerVATIdentifierRequired, .error)
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
            case .intraCommunityGoods, .reverseChargeEU, .outsideEU:
                break
            }
        }
        if document.hasReverseCharge && treatments.contains(where: { $0.chargesVAT }) { add(.mixedTreatments, .warning) }

        // Dates: § 29 odst. 1 písm. g) and h), § 28 ZDPH.
        if isTaxDocument && document.taxPointDate == nil { add(.taxPointDateMissing, .error) }
        // The warning is about services (§ 21 odst. 3); goods sent to another member state may be invoiced
        // before they leave, and § 22 odst. 1 then counts them on the issue date.
        let intraCommunityGoodsOnly = !treatments.isEmpty && treatments.allSatisfy { $0 == .intraCommunityGoods }
        if let taxPointDate = document.taxPointDate, taxPointDate > document.issueDate, !intraCommunityGoodsOnly {
            add(.taxPointAfterIssueDate, .warning, detail: taxPointDate.isoString)
        }
        if document.dueDate < document.issueDate { add(.dueDateBeforeIssueDate, .error, detail: document.dueDate.isoString) }
        if let deadline = IssueDeadline.lastDay(for: document), document.issueDate > deadline {
            add(.issuedAfterDeadline, .warning, detail: deadline.isoString)
        }

        // Advances: § 37a ZDPH.
        if !document.advanceDeductions.isEmpty && !document.kind.deductsAdvances { add(.advanceDeductionsOnWrongKind, .error) }
        // One deduction per payment tax document and VAT treatment (ADR 0004); a payment tax document with
        // several treatments legitimately gives several rows with the same number.
        var seenDeductions = Set<String>()
        var reportedTwice = Set<String>()
        for deduction in document.advanceDeductions {
            let number = deduction.documentNumber.trimmingWhitespace()
            if !seenDeductions.insert(number + "|" + deduction.treatment.groupingKey).inserted, reportedTwice.insert(number).inserted {
                add(.advanceDeductedTwice, .error, detail: number)
            }
            if let currency = deduction.currency, currency != document.currency {
                add(.advanceCurrencyDiffers, .error, detail: number)
            }
        }

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
                    // Any row with Czech VAT needs its CZK tax amount, even when the rows net to zero.
                    let chargesCzechVAT = totals.rows.contains {
                        $0.treatment.chargesVAT || $0.vat != 0 || $0.taxableVAT != 0 || $0.deductedVAT != 0
                    }
                    add(.exchangeRateMissing, chargesCzechVAT ? .error : .warning)
                }
            }
            if document.kind.deductsAdvances {
                if totals.rows.contains(where: { $0.taxableBase < 0 }) { add(.advancesExceedSupply, .warning) }
                // Deductions and their percentages per summary row, matched to rows by the same rule as the totals.
                let lineTreatments = document.treatments
                var deductionsByKey: [String: [AdvanceDeduction]] = [:]
                var percentsByKey: [String: Set<Decimal>] = [:]
                for deduction in document.advanceDeductions {
                    let key = DocumentTotals.rowKey(for: deduction, lineTreatments: lineTreatments)
                    deductionsByKey[key, default: []].append(deduction)
                    if let percent = deduction.ratePercent {
                        percentsByKey[key, default: []].insert(percent)
                    }
                }
                let suppliesCzechVAT = totals.rows.contains { $0.treatment.chargesVAT && $0.base != 0 }
                for row in totals.rows {
                    guard var percents = percentsByKey[row.treatment.groupingKey] else { continue }
                    if let rate = row.rate { percents.insert(rate.percent) }
                    // A taxed advance left on its own row next to a taxable supply: § 37a odst. 3 territory.
                    let deductionOnly = row.base == 0 && row.deductedBase != 0
                    if percents.count > 1 || (deductionOnly && row.treatment.chargesVAT && suppliesCzechVAT) {
                        add(.advanceRateDiffers, .warning)
                        break
                    }
                }
                // § 37a odst. 2 písm. b): a negative difference in a foreign currency is converted at the
                // advance's exchange rate; without one rate shared by the row's advances the document's was used.
                if document.currency != .czk, totals.rows.contains(where: { row in
                    row.taxableBase < 0
                        && DocumentTotals.advanceExchangeRate(of: deductionsByKey[row.treatment.groupingKey] ?? [], in: document.currency) == nil
                }) {
                    add(.advanceExchangeRateDiffers, .warning)
                }
            } else if document.kind == .paymentTaxDocument {
                if totals.amountDue <= 0 || totals.rows.contains(where: { $0.taxableBase < 0 }) {
                    add(.receivedAmountNotPositive, .error)
                }
            } else if totals.amountDue < 0 || totals.rows.contains(where: { $0.taxableBase < 0 }) {
                // Negative lines are fine as discounts inside a positive document, not as a negative document
                // or VAT row: that is a corrective tax document (§ 45 ZDPH), Phase 2 (ADR 0004).
                add(.documentTotalNegative, .error)
            }
            if totals.amountDue > 0 {
                if let payment = document.payment {
                    if let accountCurrency = payment.bankConnection.currency, accountCurrency != document.currency {
                        add(.bankAccountCurrencyDiffers, .warning, detail: accountCurrency.code)
                    }
                    if let qrIssue = Self.paymentQRCodeIssue(for: document, totals: totals) { issues.append(qrIssue) }
                } else {
                    add(.paymentInstructionsMissing, .warning)
                }
            }
        } catch DocumentAmountError.exchangeRateCurrencyMismatch(let rateCurrency, _) {
            add(.exchangeRateCurrencyMismatch, .error, detail: rateCurrency.code)
        } catch {
            // The message is fixed; the detail keeps the error for logs and bug reports.
            add(.amountsUnavailable, .error, detail: String(describing: error))
        }

        return issues
    }

    /// The warning when the document's payment QR code cannot be encoded, so the PDF would print a notice
    /// in its place (ADR 0010). A draft is probed with a stand-in number: what breaks the payload (the EPC's
    /// 70-character name, an amount above the format's maximum) does not depend on the number.
    private static func paymentQRCodeIssue(for document: Document, totals: DocumentTotals) -> ValidationIssue? {
        guard let kind = document.payment?.qrCode, kind != PaymentQRKind.none else { return nil }
        var probe = document
        if (probe.number ?? "").trimmingWhitespace().isEmpty { probe.number = "0" }
        do {
            switch kind {
            case .qrPlatba: _ = try probe.qrPlatba(totals: totals)?.encoded()
            case .sepa: _ = try probe.sepaQRCode(totals: totals)?.encoded()
            case .none: break
            }
            return nil
        } catch SEPAQRCode.EncodingError.tooLong(let element, let maximum, _) where element == "Name" {
            return ValidationIssue(code: .paymentQRCodeNameTooLong, severity: .warning, detail: String(maximum))
        } catch {
            return ValidationIssue(code: .paymentQRCodeUnavailable, severity: .warning)
        }
    }

    /// True when the document can be issued: no errors.
    public static func canIssue(_ document: Document) -> Bool {
        !validate(document, forIssue: true).contains(where: \.isError)
    }

    /// A street, a city and an ISO 3166-1 alpha-2 country code: "Czechia" or "CZE" would print as a country
    /// line and be treated as a foreign address.
    static func isComplete(_ address: PostalAddress) -> Bool {
        let country = address.countryCode.trimmingWhitespace()
        return !address.street.trimmingWhitespace().isEmpty && !address.city.trimmingWhitespace().isEmpty
            && country.count == 2 && country.allSatisfy { $0.isASCII && $0.isLetter }
    }
}
