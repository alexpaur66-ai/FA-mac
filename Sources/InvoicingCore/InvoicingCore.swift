/// The pure-Swift core of FA-mac: money, VAT rules, exchange rates, document rules,
/// numbering and payment QR strings. No UI, no database, no network.
///
/// Every rule that comes from Czech VAT law (zákon č. 235/2004 Sb., "ZDPH") cites its
/// paragraph in a comment, and docs/compliance-checklist.md lists them all.
public enum InvoicingCore {
    /// Version of the core module, shown in the app's About box.
    public static let version = "0.1.0"
}
