import CoreGraphics
import Foundation
import InvoicingCore

public enum DocumentPDFError: Error, Sendable {
    /// Core Graphics could not create the PDF context.
    case graphicsContextUnavailable
}

/// Renders a document as an A4 PDF with Core Graphics and Core Text (ADR 0010). The layout follows the
/// document's kind: an advance request prints the not-a-tax-document clause and no tax point, a payment
/// tax document prints the payment date and no payment block, a final invoice prints the advances it
/// deducts. A draft gets the three draft markers of screens-flows.md §2c: the watermark, the number
/// placeholder and the QR placeholder. Czech number and date formats on every document; bilingual
/// documents add the English gloss after each Czech label (design-system.md §9).
public enum DocumentPDF {
    /// A4 in points.
    public static let pageSize = CGSize(width: 595.276, height: 841.89)
    /// About 30 mm, the QR platba standard's size for typical content (design-system.md §5.3).
    public static let qrCodeSide: CGFloat = 85

    /// Renders the document as it is, computing its amounts first.
    public static func render(_ document: Document) throws -> Data {
        try render(document, totals: try DocumentTotals.compute(for: document))
    }

    /// Renders the document with amounts the caller computed. Two passes: the first counts the pages,
    /// the second prints "Strana n / N".
    public static func render(_ document: Document, totals: DocumentTotals) throws -> Data {
        let pages = try DocumentPDFRenderer(document: document, totals: totals, totalPages: nil).run().pages
        return try DocumentPDFRenderer(document: document, totals: totals, totalPages: pages).run().data
    }

    /// "FV-2026-001 Beispiel GmbH.pdf": the number and the customer (screens-flows.md §2i), without the
    /// characters a file name cannot carry. A draft has no number and is named "Koncept".
    public static func fileName(for document: Document) -> String {
        let raw = [document.number ?? "Koncept", document.customer.name].filter { !$0.isEmpty }.joined(separator: " ")
        var cleaned = ""
        for character in raw {
            if character == "/" || character == "\\" || character == ":" {
                cleaned.append("-")
            } else if character.isNewline || character == "\u{0}" {
                cleaned.append(" ")
            } else {
                cleaned.append(character)
            }
        }
        let collapsed = cleaned.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let trimmed = String(collapsed.prefix(120))
        return (trimmed.isEmpty ? "document" : trimmed) + ".pdf"
    }
}

/// One rendering pass. The class holds the styles and the document; `run()` writes every page.
final class DocumentPDFRenderer {
    private let document: Document
    private let totals: DocumentTotals
    private let totalPages: Int?
    private let language: DocumentLanguage
    private let isDraft: Bool
    private let currency: Currency

    // Fixed colours: a PDF has no appearance, the page is always white paper (design-system.md §4.1).
    private let ink: CGColor
    private let grey: CGColor
    private let ruleColor: CGColor
    private let band: CGColor

    private let styleTitle: PDFTextStyle
    private let styleSubtitle: PDFTextStyle
    private let styleName: PDFTextStyle
    private let styleBody: PDFTextStyle
    private let styleBodyBold: PDFTextStyle
    private let styleSmall: PDFTextStyle
    private let styleLabel: PDFTextStyle
    private let styleNumber: PDFTextStyle
    private let styleBig: PDFTextStyle
    private let styleTableHeader: PDFTextStyle
    private let styleWatermark: PDFTextStyle

    private let columnGap: CGFloat = 6

    init(document: Document, totals: DocumentTotals, totalPages: Int?) {
        self.document = document
        self.totals = totals
        self.totalPages = totalPages
        language = document.language
        isDraft = document.status == .draft
        currency = document.currency

        let ink = CGColor(srgbRed: 0.10, green: 0.10, blue: 0.12, alpha: 1)
        let grey = CGColor(srgbRed: 0.45, green: 0.45, blue: 0.47, alpha: 1)
        self.ink = ink
        self.grey = grey
        ruleColor = CGColor(srgbRed: 0.78, green: 0.78, blue: 0.80, alpha: 1)
        band = CGColor(srgbRed: 0.945, green: 0.945, blue: 0.955, alpha: 1)

        styleTitle = PDFTextStyle(font: .bold(15), color: ink)
        styleSubtitle = PDFTextStyle(font: .regular(9), color: grey)
        styleName = PDFTextStyle(font: .bold(11), color: ink)
        styleBody = PDFTextStyle(font: .regular(9), color: ink)
        styleBodyBold = PDFTextStyle(font: .bold(9), color: ink)
        styleSmall = PDFTextStyle(font: .regular(7.5), color: ink)
        styleLabel = PDFTextStyle(font: .regular(7.5), color: grey)
        styleNumber = PDFTextStyle(font: .bold(13), color: ink)
        styleBig = PDFTextStyle(font: .bold(12), color: ink)
        styleTableHeader = PDFTextStyle(font: .bold(7.5), color: ink)
        // Mid-grey at a fixed alpha, so the watermark survives Dark Mode and printing (design-system.md §4.1).
        styleWatermark = PDFTextStyle(font: .bold(72), color: CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 0.18))
    }

    func run() throws -> (data: Data, pages: Int) {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { throw DocumentPDFError.graphicsContextUnavailable }
        var mediaBox = CGRect(origin: .zero, size: DocumentPDF.pageSize)
        let title = [document.kind.title(language: .czech), document.number ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        let info: [CFString: Any] = [kCGPDFContextTitle: title, kCGPDFContextCreator: "FA"]
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary) else {
            throw DocumentPDFError.graphicsContextUnavailable
        }
        let writer = PDFPageWriter(context: context, pageSize: DocumentPDF.pageSize,
                                   marginLeft: 46, marginRight: 46, marginTop: 46, marginBottom: 40)
        writer.onPageStart = { [weak self] writer, page in self?.pageStart(writer, page: page) }
        writer.onPageEnd = { [weak self] writer, page in self?.pageEnd(writer, page: page) }

        writer.startPage()
        drawHeader(writer)
        drawParties(writer)
        drawLines(writer)
        drawSummary(writer)
        drawPayment(writer)
        drawClauses(writer)
        writer.finishPage()
        context.closePDF()
        return (Data(referencing: data), writer.page)
    }

    // MARK: Helpers

    private func label(_ label: DocumentLabel) -> String { PDFStrings.label(label, language) }
    private func money(_ amount: Decimal, _ currency: Currency? = nil) -> String { PDFFormat.money(amount, currency ?? self.currency) }

    /// "IČO 12345679 · DIČ CZ12345679"; bilingual documents gloss the VAT ID.
    private func identifiers(_ party: Party) -> String? {
        var parts: [String] = []
        if let ico = party.identificationNumber { parts.append("IČO \(ico.digits)") }
        if let dic = party.vatIdentifier { parts.append((language == .english ? "DIČ / VAT ID " : "DIČ ") + dic.value) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func countryName(_ code: String) -> String {
        let locale = Locale(identifier: language == .english ? "en_GB" : "cs_CZ")
        return locale.localizedString(forRegionCode: code) ?? code
    }

    private var numberText: String { document.number ?? PDFStrings.numberPlaceholder(language) }

    // MARK: Pages

    private func pageStart(_ writer: PDFPageWriter, page: Int) {
        if isDraft {
            writer.watermark(PDFStrings.watermark, styleWatermark)
        }
        guard page > 1 else { return }
        let heading = "\(document.kind.title(language: .czech)) \(numberText) (\(PDFStrings.continued(language)))"
        writer.text(heading, styleLabel, x: writer.contentLeft, top: writer.y, width: writer.contentWidth)
        writer.move(styleLabel.font.lineHeight + 8)
    }

    private func pageEnd(_ writer: PDFPageWriter, page: Int) {
        let top = writer.bottomLimit + 6
        writer.rule(top: top, x: writer.contentLeft, width: writer.contentWidth, color: ruleColor)
        let pageLabel = PDFStrings.bilingual("Strana", "Page", language)
        let pages = totalPages.map { "\(pageLabel) \(page) / \($0)" } ?? "\(pageLabel) \(page)"
        let pagesWidth = writer.width(of: pages, styleLabel) + 4
        writer.text(pages, styleLabel, x: writer.contentRight - pagesWidth, top: top + 4, width: pagesWidth, alignment: .right)
        let left = "\(numberText) · \(document.supplier.name)"
        writer.text(left, styleLabel, x: writer.contentLeft, top: top + 4, width: writer.contentWidth - pagesWidth - 12)
    }

    // MARK: Header: supplier and title

    private func drawHeader(_ writer: PDFPageWriter) {
        let leftWidth = writer.contentWidth * 0.55
        let rightX = writer.contentLeft + leftWidth + 12
        let rightWidth = writer.contentWidth - leftWidth - 12
        let supplier = document.supplier

        var leftY = writer.y
        leftY += writer.text(supplier.name, styleName, x: writer.contentLeft, top: leftY, width: leftWidth)
        leftY += 2
        for line in supplier.address.lines(countryName: countryName(supplier.address.countryCode), alwaysIncludeCountry: language == .english) {
            leftY += writer.text(line, styleBody, x: writer.contentLeft, top: leftY, width: leftWidth)
        }
        if let ids = identifiers(supplier) {
            leftY += writer.text(ids, styleBody, x: writer.contentLeft, top: leftY, width: leftWidth)
        }
        let contact = [supplier.email, supplier.phone].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        if !contact.isEmpty {
            leftY += writer.text(contact, styleBody, x: writer.contentLeft, top: leftY, width: leftWidth)
        }
        if let registry = supplier.registryEntry {
            // § 435 OZ: the registry entry on every business document.
            leftY += 3
            leftY += writer.paragraph(registry.sentence(language: .czech), styleLabel, x: writer.contentLeft, top: leftY, width: leftWidth)
            if language == .english {
                leftY += writer.paragraph(registry.sentence(language: .english), styleLabel, x: writer.contentLeft, top: leftY, width: leftWidth)
            }
        }

        var rightY = writer.y
        rightY += writer.text(document.kind.title(language: .czech), styleTitle, x: rightX, top: rightY, width: rightWidth, alignment: .right)
        if language == .english {
            rightY += writer.text(document.kind.title(language: .english), styleSubtitle, x: rightX, top: rightY, width: rightWidth, alignment: .right)
        }
        rightY += 8
        rightY += writer.text(label(.documentNumber), styleLabel, x: rightX, top: rightY, width: rightWidth, alignment: .right)
        if let number = document.number {
            rightY += writer.text(number, styleNumber, x: rightX, top: rightY, width: rightWidth, alignment: .right)
        } else {
            rightY += writer.paragraph(PDFStrings.numberPlaceholder(language), styleBodyBold, x: rightX, top: rightY, width: rightWidth)
        }

        writer.moveTo(max(leftY, rightY) + 12)
        writer.rule(top: writer.y, x: writer.contentLeft, width: writer.contentWidth, color: ink, lineWidth: 0.75)
        writer.move(12)
    }

    // MARK: Customer and dates

    private func drawParties(_ writer: PDFPageWriter) {
        let columnWidth = (writer.contentWidth - 16) / 2
        let rightX = writer.contentLeft + columnWidth + 16
        let customer = document.customer

        var leftY = writer.y
        leftY += writer.text(label(.customer), styleLabel, x: writer.contentLeft, top: leftY, width: columnWidth)
        leftY += 3
        leftY += writer.paragraph(customer.name, PDFTextStyle(font: .bold(10.5), color: ink), x: writer.contentLeft, top: leftY, width: columnWidth)
        for line in customer.address.lines(countryName: countryName(customer.address.countryCode)) {
            leftY += writer.text(line, styleBody, x: writer.contentLeft, top: leftY, width: columnWidth)
        }
        if let ids = identifiers(customer) {
            leftY += 2
            leftY += writer.text(ids, styleBody, x: writer.contentLeft, top: leftY, width: columnWidth)
        }

        var rows: [(String, String)] = [(label(.issueDate), PDFFormat.day(document.issueDate))]
        switch document.kind {
        case .advanceRequest:
            break // No date of supply: nothing has been supplied or received yet.
        case .paymentTaxDocument:
            rows.append((label(.paymentReceivedDate), PDFFormat.day(document.taxPoint)))
        case .invoice, .finalInvoice:
            rows.append((label(.taxPointDate), PDFFormat.day(document.taxPoint)))
        }
        if document.kind != .paymentTaxDocument {
            rows.append((label(.dueDate), PDFFormat.day(document.dueDate)))
        }
        if let order = document.orderReference, !order.isEmpty {
            rows.append((label(.orderReference), order))
        }
        if let payment = document.payment, document.kind != .paymentTaxDocument {
            if let symbol = payment.variableSymbol { rows.append((label(.variableSymbol), symbol.digits)) }
            if let symbol = payment.constantSymbol { rows.append((label(.constantSymbol), symbol.digits)) }
            if let symbol = payment.specificSymbol { rows.append((label(.specificSymbol), symbol.digits)) }
        }

        let labelWidth = columnWidth * 0.62
        let valueX = rightX + labelWidth + columnGap
        let valueWidth = columnWidth - labelWidth - columnGap
        var rightY = writer.y
        for (caption, value) in rows {
            let captionHeight = writer.height(of: caption, styleLabel, width: labelWidth)
            writer.paragraph(caption, styleLabel, x: rightX, top: rightY, width: labelWidth)
            writer.text(value, styleBodyBold, x: valueX, top: rightY, width: valueWidth, alignment: .right)
            rightY += max(captionHeight, styleBodyBold.font.lineHeight) + 3
        }

        writer.moveTo(max(leftY, rightY) + 14)
    }

    // MARK: Lines

    private enum ColumnKey {
        case description, quantity, unit, unitPrice, discount, rate, base, vat, total
    }

    private struct Column {
        let key: ColumnKey
        let title: String
        let width: CGFloat
        let alignment: PDFAlignment
    }

    private func tableColumns(_ writer: PDFPageWriter) -> [Column] {
        let lines = document.lines
        let hasUnits = lines.contains { !($0.unit ?? "").isEmpty }
        let hasDiscount = lines.contains { $0.discountPercent != 0 }
        let chargesVAT = lines.contains { $0.treatment.chargesVAT }
        var fixed: [Column] = [Column(key: .quantity, title: label(.quantity), width: 50, alignment: .right)]
        if hasUnits { fixed.append(Column(key: .unit, title: label(.unit), width: 34, alignment: .left)) }
        fixed.append(Column(key: .unitPrice, title: label(.unitPrice), width: 72, alignment: .right))
        if hasDiscount { fixed.append(Column(key: .discount, title: label(.discount), width: 44, alignment: .right)) }
        if chargesVAT {
            fixed.append(Column(key: .rate, title: label(.vatRate), width: 42, alignment: .right))
            fixed.append(Column(key: .base, title: label(.base), width: 74, alignment: .right))
            fixed.append(Column(key: .vat, title: label(.vat), width: 66, alignment: .right))
        }
        fixed.append(Column(key: .total, title: label(.total), width: 78, alignment: .right))
        let used = fixed.reduce(CGFloat(0)) { $0 + $1.width + columnGap }
        let description = Column(key: .description, title: label(.description), width: max(80, writer.contentWidth - used), alignment: .left)
        return [description] + fixed
    }

    /// The header row: a light band with the column titles, two lines on bilingual documents.
    private func drawTableHeader(_ writer: PDFPageWriter, columns: [Column]) {
        let lineHeight = styleTableHeader.font.lineHeight
        let height = (language == .english ? 2 * lineHeight : lineHeight) + 6
        writer.fill(CGRect(x: writer.contentLeft, y: writer.y, width: writer.contentWidth, height: height), color: band)
        var x = writer.contentLeft
        for column in columns {
            if language == .english {
                let parts = column.title.components(separatedBy: " / ")
                let czech = parts.first ?? column.title
                let english = parts.count > 1 ? parts.dropFirst().joined(separator: " / ") : ""
                writer.text(czech, styleTableHeader, x: x, top: writer.y + 3, width: column.width, alignment: column.alignment)
                writer.text(english, PDFTextStyle(font: .regular(7.5), color: grey), x: x, top: writer.y + 3 + lineHeight, width: column.width,
                            alignment: column.alignment)
            } else {
                writer.text(column.title, styleTableHeader, x: x, top: writer.y + 3, width: column.width, alignment: column.alignment)
            }
            x += column.width + columnGap
        }
        writer.move(height)
        writer.rule(top: writer.y, x: writer.contentLeft, width: writer.contentWidth, color: ink, lineWidth: 0.5)
    }

    private func cell(_ key: ColumnKey, line: DocumentLine, amounts: LineAmounts?) -> String {
        switch key {
        case .description: return line.text
        case .quantity: return PDFFormat.number(line.quantity)
        case .unit: return line.unit ?? ""
        case .unitPrice: return money(line.unitPrice)
        case .discount: return line.discountPercent == 0 ? "" : PDFFormat.percent(line.discountPercent)
        case .rate:
            if line.treatment.chargesVAT {
                return amounts?.rate.map { PDFFormat.percent($0.percent) } ?? ""
            }
            return PDFStrings.rateCell(line.treatment)
        case .base: return amounts.map { money($0.net) } ?? ""
        case .vat: return amounts.map { line.treatment.chargesVAT ? money($0.vat) : "—" } ?? ""
        case .total: return amounts.map { money($0.gross) } ?? ""
        }
    }

    private func drawLines(_ writer: PDFPageWriter) {
        let columns = tableColumns(writer)
        guard let descriptionWidth = columns.first?.width else { return }
        writer.ensure(60)
        drawTableHeader(writer, columns: columns)
        for (index, line) in document.lines.enumerated() {
            let amounts = index < totals.lines.count ? totals.lines[index] : nil
            let descriptionHeight = writer.height(of: line.text, styleBody, width: descriptionWidth)
            let rowHeight = max(descriptionHeight, styleBody.font.lineHeight) + 6
            if writer.ensure(rowHeight) {
                drawTableHeader(writer, columns: columns)
            }
            var x = writer.contentLeft
            let top = writer.y + 3
            for column in columns {
                let value = cell(column.key, line: line, amounts: amounts)
                if column.key == .description {
                    writer.paragraph(value, styleBody, x: x, top: top, width: column.width)
                } else {
                    writer.text(value, styleBody, x: x, top: top, width: column.width, alignment: column.alignment)
                }
                x += column.width + columnGap
            }
            writer.move(rowHeight)
            writer.rule(top: writer.y, x: writer.contentLeft, width: writer.contentWidth, color: ruleColor, lineWidth: 0.3)
        }
        if document.lines.isEmpty {
            writer.move(4)
        }
    }

    // MARK: VAT summary and totals

    private struct SummaryRow {
        let caption: String
        let values: [Decimal]
        let currency: Currency
        let emphasised: Bool
        let small: Bool
    }

    private var showsVAT: Bool { totals.rows.contains { $0.treatment.chargesVAT } }

    private func summaryRows() -> [SummaryRow] {
        var rows: [SummaryRow] = []
        for row in totals.rows {
            let percent = row.appliedRatePercent ?? row.rate?.percent
            let caption = PDFStrings.treatment(row.treatment, percent: percent, language)
            let deducted = row.deductedBase != 0 || row.deductedVAT != 0
            if deducted {
                rows.append(SummaryRow(caption: "\(caption) – \(PDFStrings.supplyRow(language))", values: values(row.base, row.vat, row.gross),
                                       currency: currency, emphasised: false, small: false))
                rows.append(SummaryRow(caption: label(.advanceDeductions),
                                       values: values(-row.deductedBase, -row.deductedVAT, -(row.deductedBase + row.deductedVAT)),
                                       currency: currency, emphasised: false, small: false))
                rows.append(SummaryRow(caption: PDFStrings.afterDeduction(language), values: values(row.taxableBase, row.taxableVAT, row.taxableGross),
                                       currency: currency, emphasised: true, small: false))
            } else {
                rows.append(SummaryRow(caption: caption, values: values(row.base, row.vat, row.gross), currency: currency, emphasised: false, small: false))
            }
            // § 29 odst. 1 písm. l) ZDPH: the tax in CZK on a foreign-currency document; the base goes with it.
            if row.treatment.chargesVAT, currency != .czk, let baseCZK = row.taxableBaseCZK, let vatCZK = row.taxableVATCZK, let rate = row.exchangeRate {
                rows.append(SummaryRow(caption: PDFStrings.inCZKAtRate(rate, language), values: values(baseCZK, vatCZK, baseCZK + vatCZK),
                                       currency: .czk, emphasised: false, small: true))
            }
        }
        return rows
    }

    /// Base, VAT and total when the document charges VAT; the total alone otherwise (§ 29 odst. 3 písm. e) ZDPH).
    private func values(_ base: Decimal, _ vat: Decimal, _ gross: Decimal) -> [Decimal] {
        showsVAT ? [base, vat, gross] : [gross]
    }

    private func totalRows() -> [(caption: String, value: String, emphasised: Bool)] {
        var rows: [(caption: String, value: String, emphasised: Bool)] = []
        if showsVAT {
            rows.append((PDFStrings.totalExcludingVAT(language), money(totals.totalBase), false))
            rows.append((label(.vat), money(totals.totalVAT), false))
        }
        rows.append((label(.total), money(totals.totalGross), true))
        let deducted = totals.deductedBase + totals.deductedVAT
        if deducted != 0 {
            rows.append((label(.advanceDeductions), money(-deducted), false))
        }
        return rows
    }

    /// Lays out (or only measures, when `draw` is false) the summary block: the VAT summary on the left,
    /// the totals on the right, the deducted advances underneath. Returns the height used.
    @discardableResult
    private func summaryBlock(_ writer: PDFPageWriter, top: CGFloat, draw: Bool) -> CGFloat {
        let leftWidth = writer.contentWidth * 0.58
        let rightX = writer.contentLeft + leftWidth + 14
        let rightWidth = writer.contentWidth - leftWidth - 14
        let numberWidth: CGFloat = 68
        let valueColumns = showsVAT ? 3 : 1
        let captionWidth = leftWidth - CGFloat(valueColumns) * (numberWidth + columnGap)

        // Left: the VAT summary.
        var leftY = top
        if draw { writer.text(label(.vatSummary), styleLabel, x: writer.contentLeft, top: leftY, width: leftWidth) }
        leftY += styleLabel.font.lineHeight + 3
        let headers = showsVAT ? [label(.base), label(.vat), label(.total)] : [label(.total)]
        var headerHeight: CGFloat = 0
        for (index, header) in headers.enumerated() {
            let x = writer.contentLeft + captionWidth + CGFloat(index) * (numberWidth + columnGap)
            headerHeight = max(headerHeight, writer.height(of: header, styleLabel, width: numberWidth))
            if draw { writer.paragraph(header, styleLabel, x: x, top: leftY, width: numberWidth) }
        }
        leftY += headerHeight + 2
        if draw { writer.rule(top: leftY, x: writer.contentLeft, width: leftWidth, color: ruleColor) }
        leftY += 3
        for row in summaryRows() {
            let style = row.small ? styleLabel : (row.emphasised ? styleBodyBold : styleBody)
            let captionHeight = writer.height(of: row.caption, style, width: captionWidth - 4)
            if draw {
                writer.paragraph(row.caption, style, x: writer.contentLeft, top: leftY, width: captionWidth - 4)
                for (index, value) in row.values.enumerated() {
                    let x = writer.contentLeft + captionWidth + CGFloat(index) * (numberWidth + columnGap)
                    writer.text(money(value, row.currency), style, x: x, top: leftY, width: numberWidth, alignment: .right)
                }
            }
            leftY += max(captionHeight, style.font.lineHeight) + 3
        }

        // Right: the totals and the amount due.
        var rightY = top
        let captionRight = rightWidth * 0.5
        for row in totalRows() {
            let style = row.emphasised ? styleBodyBold : styleBody
            if draw {
                writer.text(row.caption, styleLabel, x: rightX, top: rightY + 1, width: captionRight)
                writer.text(row.value, style, x: rightX + captionRight, top: rightY, width: rightWidth - captionRight, alignment: .right)
            }
            rightY += style.font.lineHeight + 4
        }
        rightY += 4
        let dueHeight = styleBig.font.lineHeight + 10
        if draw {
            writer.fill(CGRect(x: rightX - 6, y: rightY, width: rightWidth + 12, height: dueHeight), color: band)
            let caption = document.kind == .paymentTaxDocument ? label(.alreadyPaid) : label(.amountDue)
            writer.text(caption, styleBodyBold, x: rightX, top: rightY + 6, width: captionRight)
            writer.text(money(totals.amountDue), styleBig, x: rightX + captionRight, top: rightY + 4, width: rightWidth - captionRight, alignment: .right)
        }
        rightY += dueHeight

        var y = max(leftY, rightY) + 6
        // A final invoice names every advance it deducts (§ 37a ZDPH).
        if document.kind.deductsAdvances, !document.advanceDeductions.isEmpty {
            y += 2
            for deduction in document.advanceDeductions {
                let text = PDFStrings.deductionLine(number: deduction.documentNumber, paymentDate: deduction.paymentDate, language)
                    + ": " + money(-deduction.gross, deduction.currency ?? currency)
                let height = writer.height(of: text, styleSmall, width: writer.contentWidth)
                if draw { writer.paragraph(text, styleSmall, x: writer.contentLeft, top: y, width: writer.contentWidth) }
                y += height + 1
            }
        }
        return y - top
    }

    private func drawSummary(_ writer: PDFPageWriter) {
        writer.move(10)
        let height = summaryBlock(writer, top: writer.y, draw: false)
        writer.ensure(min(height, writer.bottomLimit - writer.marginTop - 20))
        let used = summaryBlock(writer, top: writer.y, draw: true)
        writer.move(used)
    }

    // MARK: Payment details and QR code

    /// The QR code a draft will carry once issued (`PaymentInstructions.standard`), for the placeholder.
    private func defaultQRKind() -> PaymentQRKind {
        switch currency {
        case .czk: return .qrPlatba
        case .eur: return .sepa
        default: return .none
        }
    }

    private func qrPayload(_ kind: PaymentQRKind) -> String? {
        switch kind {
        case .qrPlatba: return try? document.qrPlatba(totals: totals)?.encoded()
        case .sepa: return try? document.sepaQRCode(totals: totals)?.encoded()
        case .none: return nil
        }
    }

    private func drawPayment(_ writer: PDFPageWriter) {
        // A payment tax document records money already received; a document with nothing to pay asks for nothing.
        guard document.kind != .paymentTaxDocument, totals.amountDue > 0 else { return }
        let payment = document.payment
        let qrKind = payment?.qrCode ?? (isDraft ? defaultQRKind() : PaymentQRKind.none)
        var rows: [(String, String)] = []
        if let payment {
            let bank = payment.bankConnection
            if let domestic = bank.domesticAccount { rows.append((label(.bankAccount), domestic.description)) }
            rows.append((label(.iban), bank.iban.formatted))
            if let bic = bank.bic { rows.append((label(.bic), bic.value)) }
            if let name = bank.bankName, !name.isEmpty { rows.append((PDFStrings.bankName(language), name)) }
            if let symbol = payment.variableSymbol { rows.append((label(.variableSymbol), symbol.digits)) }
            if let symbol = payment.constantSymbol { rows.append((label(.constantSymbol), symbol.digits)) }
            if let symbol = payment.specificSymbol { rows.append((label(.specificSymbol), symbol.digits)) }
            if let reference = payment.creditorReference { rows.append((label(.paymentReference), reference.formatted)) }
        }
        rows.append((label(.amountDue), money(totals.amountDue)))
        rows.append((label(.dueDate), PDFFormat.day(document.dueDate)))

        let rowHeight: CGFloat = 13
        let qrSide = DocumentPDF.qrCodeSide
        let showsQR = qrKind != .none
        let qrBlockHeight = showsQR ? qrSide + styleLabel.font.lineHeight + 4 : 0
        let textHeight = styleLabel.font.lineHeight + 4 + CGFloat(rows.count) * rowHeight
        writer.move(10)
        writer.ensure(max(textHeight, qrBlockHeight) + 4)
        let top = writer.y
        let textWidth = writer.contentWidth - (showsQR ? qrSide + 24 : 0)
        var y = top
        y += writer.text(label(.paymentDetails), styleLabel, x: writer.contentLeft, top: y, width: textWidth)
        y += 4
        let captionWidth: CGFloat = min(170, textWidth * 0.45)
        for (caption, value) in rows {
            writer.text(caption, styleLabel, x: writer.contentLeft, top: y + 1, width: captionWidth)
            writer.text(value, styleBody, x: writer.contentLeft + captionWidth + columnGap, top: y, width: textWidth - captionWidth - columnGap)
            y += rowHeight
        }

        if showsQR {
            let rect = CGRect(x: writer.contentRight - qrSide, y: top, width: qrSide, height: qrSide)
            if isDraft {
                // A draft has no variable symbol yet, so its code could not be matched to a payment (design-system.md §8.8).
                writer.dashedBox(rect, color: grey)
                let placeholder = PDFStrings.qrPlaceholder(language)
                let height = writer.height(of: placeholder, styleLabel, width: rect.width - 10)
                writer.paragraph(placeholder, styleLabel, x: rect.minX + 5, top: rect.minY + (rect.height - height) / 2, width: rect.width - 10)
            } else if let payload = qrPayload(qrKind), let modules = QRModules.generate(payload) {
                writer.qrCode(modules, in: rect, color: ink)
                writer.text(PDFStrings.qrCaption(qrKind), styleLabel, x: rect.minX - 10, top: rect.maxY + 3, width: rect.width + 20, alignment: .center)
            }
        }
        writer.moveTo(max(y, top + qrBlockHeight) + 6)
    }

    // MARK: Clauses, note and footer text

    private func drawClauses(_ writer: PDFPageWriter) {
        var texts: [String] = []
        for clause in DocumentClause.clauses(for: document, totals: totals) {
            switch (clause, language) {
            case (.reverseCharge, .english):
                // The English text already starts with the prescribed Czech wording.
                texts.append(clause.text(language: .english))
            case (_, .english):
                texts.append(clause.text(language: .czech))
                texts.append(clause.text(language: .english))
            case (_, .czech):
                texts.append(clause.text(language: .czech))
            }
        }
        if !texts.isEmpty {
            writer.move(6)
            writer.ensure(30)
            writer.rule(top: writer.y, x: writer.contentLeft, width: writer.contentWidth, color: ruleColor)
            writer.move(8)
            for text in texts {
                let height = writer.height(of: text, styleBody, width: writer.contentWidth)
                writer.ensure(height + 2)
                writer.paragraph(text, styleBody, x: writer.contentLeft, top: writer.y, width: writer.contentWidth)
                writer.move(height + 2)
            }
        }
        if let note = document.note, !note.isEmpty {
            writer.move(8)
            let height = writer.height(of: note, styleBody, width: writer.contentWidth)
            writer.ensure(styleLabel.font.lineHeight + height + 4)
            writer.move(writer.text(label(.note), styleLabel, x: writer.contentLeft, top: writer.y, width: writer.contentWidth) + 2)
            writer.paragraph(note, styleBody, x: writer.contentLeft, top: writer.y, width: writer.contentWidth)
            writer.move(height)
        }
        if let footer = document.footer, !footer.isEmpty {
            writer.move(12)
            let height = writer.height(of: footer, styleLabel, width: writer.contentWidth)
            writer.ensure(height)
            writer.paragraph(footer, styleLabel, x: writer.contentLeft, top: writer.y, width: writer.contentWidth)
            writer.move(height)
        }
    }
}
