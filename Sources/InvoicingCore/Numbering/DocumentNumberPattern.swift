/// A template for document numbers, for example "{YYYY}{NNN}" → "2026001" or "FV-{YYYY}-{NNN}" → "FV-2026-001".
///
/// Tokens: `{YYYY}` four-digit year, `{YY}` two-digit year, `{N…}` the counter zero-padded to the
/// number of N characters. Exactly one counter token is required; any other characters are literal.
/// Document numbers must be unique and continuous within a series (§ 29 odst. 1 písm. e) ZDPH:
/// "evidenční číslo daňového dokladu"); the data layer enforces uniqueness, this type only formats.
public struct DocumentNumberPattern: Hashable, Sendable, CustomStringConvertible {
    public enum PatternError: Error, Equatable, Sendable {
        case missingCounter
        case multipleCounters
        case unknownToken(String)
        case unterminatedToken
    }

    enum Segment: Hashable, Sendable {
        case literal(String)
        case year4
        case year2
        case counter(width: Int)
    }

    public let template: String
    let segments: [Segment]

    public init(template: String) throws {
        var segments: [Segment] = []
        var literal = ""
        var counters = 0
        var iterator = template.makeIterator()

        func flushLiteral() {
            if !literal.isEmpty { segments.append(.literal(literal)); literal = "" }
        }

        while let character = iterator.next() {
            guard character == "{" else { literal.append(character); continue }
            var token = ""
            var terminated = false
            while let next = iterator.next() {
                if next == "}" { terminated = true; break }
                token.append(next)
            }
            guard terminated else { throw PatternError.unterminatedToken }
            flushLiteral()
            switch token {
            case "YYYY": segments.append(.year4)
            case "YY": segments.append(.year2)
            default:
                guard !token.isEmpty, token.allSatisfy({ $0 == "N" }) else { throw PatternError.unknownToken(token) }
                counters += 1
                segments.append(.counter(width: token.count))
            }
        }
        flushLiteral()
        guard counters > 0 else { throw PatternError.missingCounter }
        guard counters == 1 else { throw PatternError.multipleCounters }
        self.template = template
        self.segments = segments
    }

    /// Minimum number of digits of the counter.
    public var counterWidth: Int {
        for segment in segments { if case .counter(let width) = segment { return width } }
        return 1
    }

    /// True when the template has a `{YYYY}` or `{YY}` token, so numbers of different years differ.
    public var containsYear: Bool {
        segments.contains { $0 == .year4 || $0 == .year2 }
    }

    /// Formats a number; a counter wider than the pattern is never truncated.
    public func format(year: Int, counter: Int) -> String {
        var result = ""
        for segment in segments {
            switch segment {
            case .literal(let text): result += text
            case .year4: result += String(year).leftPadded(to: 4)
            case .year2: result += String(year % 100).leftPadded(to: 2)
            case .counter(let width): result += String(counter).leftPadded(to: width)
            }
        }
        return result
    }

    /// Reads the counter back from a number that was formatted for `year`; nil if it does not match.
    public func parseCounter(from number: String, year: Int) -> Int? {
        // Every segment but the counter formats to a fixed text for `year`, so the counter is
        // whatever lies between the text before it and the text after it; it may be wider than
        // the pattern, and a year token right after it ("{NNN}{YYYY}") is still found.
        var head = ""
        var tail = ""
        var seenCounter = false
        for segment in segments {
            let text: String
            switch segment {
            case .counter: seenCounter = true; continue
            case .literal(let literal): text = literal
            case .year4: text = String(year).leftPadded(to: 4)
            case .year2: text = String(year % 100).leftPadded(to: 2)
            }
            if seenCounter { tail += text } else { head += text }
        }
        guard number.count > head.count + tail.count, number.hasPrefix(head), number.hasSuffix(tail) else { return nil }
        let digits = number.dropFirst(head.count).dropLast(tail.count)
        guard digits.allSatisfy(\.isASCIIDigit) else { return nil }
        return Int(digits)
    }

    public var description: String { template }
}

extension DocumentNumberPattern: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let template = try container.decode(String.self)
        do {
            try self.init(template: template)
        } catch {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid number pattern: \(template)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(template)
    }
}
