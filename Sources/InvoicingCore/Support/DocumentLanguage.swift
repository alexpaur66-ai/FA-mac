/// Language of the texts printed on a document. Documents for Czech customers are Czech; documents
/// for foreign customers are bilingual (Czech first, English second) so the Czech tax authority and
/// the customer can both read them.
public enum DocumentLanguage: String, Sendable, Codable, CaseIterable {
    case czech = "cs"
    case english = "en"
}
