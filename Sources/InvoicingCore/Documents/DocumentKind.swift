/// The document types of v0.1 (docs/adr/0004-document-model-and-validation.md).
public enum DocumentKind: String, Sendable, Codable, CaseIterable {
    /// Faktura – daňový doklad: the tax document for a supply (§ 26, § 28 odst. 1, § 29 ZDPH).
    case invoice
    /// Zálohová faktura (výzva k platbě): asks the customer for an advance. Not a tax document, because
    /// no supply has taken place and no payment has been received yet (§ 26 odst. 1 ZDPH), and it says so.
    case advanceRequest
    /// Daňový doklad k přijaté platbě: the tax document for an advance received before the supply
    /// (§ 20a odst. 2, § 28 odst. 1 ZDPH). § 29 odst. 3 písm. c) and d) let it omit the scope of the
    /// supply, when unknown, and the unit price.
    case paymentTaxDocument
    /// Konečná faktura – daňový doklad: the tax document for the supply that deducts the advances already
    /// taxed on payment tax documents; its tax base is the difference (§ 37a ZDPH).
    case finalInvoice

    /// True for every kind but the advance request.
    public var isTaxDocument: Bool { self != .advanceRequest }

    /// True when the document carries advance deductions (§ 37a ZDPH).
    public var deductsAdvances: Bool { self == .finalInvoice }

    /// The heading printed on the document.
    public func title(language: DocumentLanguage) -> String {
        switch (self, language) {
        case (.invoice, .czech): return "Faktura – daňový doklad"
        case (.invoice, .english): return "Invoice – tax document"
        case (.advanceRequest, .czech): return "Zálohová faktura"
        case (.advanceRequest, .english): return "Advance invoice"
        case (.paymentTaxDocument, .czech): return "Daňový doklad k přijaté platbě"
        case (.paymentTaxDocument, .english): return "Tax document for received payment"
        case (.finalInvoice, .czech): return "Faktura – daňový doklad (vyúčtování záloh)"
        case (.finalInvoice, .english): return "Final invoice – tax document"
        }
    }
}

/// Where a document is in its life: a draft can change, an issued document is frozen and kept for
/// ten years (§ 35, § 35a ZDPH). Payment state lives with the payments, not here.
public enum DocumentStatus: String, Sendable, Codable, CaseIterable {
    case draft
    case issued
}
