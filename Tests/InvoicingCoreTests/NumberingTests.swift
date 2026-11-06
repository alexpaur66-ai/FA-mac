import Foundation
import Testing
@testable import InvoicingCore

@Suite struct DocumentNumberPatternTests {
    @Test func formatsTokens() throws {
        let pattern = try DocumentNumberPattern(template: "FV-{YYYY}-{NNN}")
        #expect(pattern.format(year: 2026, counter: 1) == "FV-2026-001")
        #expect(pattern.format(year: 2026, counter: 1000) == "FV-2026-1000")
        #expect(pattern.counterWidth == 3)
        #expect(pattern.description == "FV-{YYYY}-{NNN}")
        let short = try DocumentNumberPattern(template: "{YY}{NNNN}")
        #expect(short.format(year: 2026, counter: 7) == "260007")
        let counterOnly = try DocumentNumberPattern(template: "{NNNNN}")
        #expect(counterOnly.format(year: 2026, counter: 42) == "00042")
        let advance = try DocumentNumberPattern(template: "ZF{YYYY}/{NN}")
        #expect(advance.format(year: 2026, counter: 3) == "ZF2026/03")
    }

    @Test func parsesCountersBack() throws {
        let pattern = try DocumentNumberPattern(template: "FV-{YYYY}-{NNN}")
        #expect(pattern.parseCounter(from: "FV-2026-001", year: 2026) == 1)
        #expect(pattern.parseCounter(from: "FV-2026-1000", year: 2026) == 1000)
        #expect(pattern.parseCounter(from: "FV-2025-001", year: 2026) == nil)
        #expect(pattern.parseCounter(from: "FA-2026-001", year: 2026) == nil)
        #expect(pattern.parseCounter(from: "FV-2026-001x", year: 2026) == nil)
        #expect(pattern.parseCounter(from: "FV-2026-", year: 2026) == nil)
        let compact = try DocumentNumberPattern(template: "{YYYY}{NNN}")
        #expect(compact.parseCounter(from: "2026001", year: 2026) == 1)
        #expect(compact.parseCounter(from: "20261234", year: 2026) == 1234)
        let suffixed = try DocumentNumberPattern(template: "{NNN}/{YY}")
        #expect(suffixed.format(year: 2026, counter: 12) == "012/26")
        #expect(suffixed.parseCounter(from: "012/26", year: 2026) == 12)
        #expect(suffixed.parseCounter(from: "1012/26", year: 2026) == 1012)
        #expect(suffixed.parseCounter(from: "012/27", year: 2026) == nil)
    }

    @Test func parsesCounterFollowedDirectlyByYear() throws {
        for template in ["{NNN}{YYYY}", "{NNN}{YY}"] {
            let pattern = try DocumentNumberPattern(template: template)
            for counter in [1, 2026, 12345] {
                #expect(pattern.parseCounter(from: pattern.format(year: 2026, counter: counter), year: 2026) == counter)
            }
            #expect(pattern.parseCounter(from: pattern.format(year: 2025, counter: 1), year: 2026) == nil)
        }
        let full = try DocumentNumberPattern(template: "{NNN}{YYYY}")
        #expect(full.format(year: 2026, counter: 1) == "0012026")
        #expect(full.parseCounter(from: "0012026", year: 2026) == 1)
        #expect(full.parseCounter(from: "2026", year: 2026) == nil)   // no counter digits at all
        #expect(full.containsYear)
        let yearless = try DocumentNumberPattern(template: "FV-{NNN}")
        #expect(!yearless.containsYear)
    }

    @Test func parsesTheLastIssuedNumber() throws {
        let pattern = try DocumentNumberPattern(template: "FV {YYYY}-{NNNN}")
        let full = try #require(pattern.parseIssuedNumber(" FV 2026-0041 ", latestYear: 2026))
        #expect(full.year == 2026 && full.counter == 41)
        let bare = try #require(pattern.parseIssuedNumber("2025-0107", latestYear: 2026))
        #expect(bare.year == 2025 && bare.counter == 107)
        #expect(pattern.parseIssuedNumber("ZF 2026-0041", latestYear: 2026) == nil)
        #expect(pattern.parseIssuedNumber("FV 2027-0001", latestYear: 2026) == nil)
        #expect(pattern.parseIssuedNumber("", latestYear: 2026) == nil)
        let short = try DocumentNumberPattern(template: "{YY}{NNN}")
        let shortParsed = try #require(short.parseIssuedNumber("26042", latestYear: 2026))
        #expect(shortParsed.year == 2026 && shortParsed.counter == 42)
        let plain = try DocumentNumberPattern(template: "DD-{NNNNN}")
        let plainParsed = try #require(plain.parseIssuedNumber("00012", latestYear: 2026))
        #expect(plainParsed.year == 2026 && plainParsed.counter == 12)
    }

    @Test func rejectsBadTemplates() {
        #expect(throws: DocumentNumberPattern.PatternError.missingCounter) { try DocumentNumberPattern(template: "FV-{YYYY}") }
        #expect(throws: DocumentNumberPattern.PatternError.multipleCounters) { try DocumentNumberPattern(template: "{NN}-{NN}") }
        #expect(throws: DocumentNumberPattern.PatternError.unknownToken("XX")) { try DocumentNumberPattern(template: "{XX}{NN}") }
        #expect(throws: DocumentNumberPattern.PatternError.unknownToken("")) { try DocumentNumberPattern(template: "{}{NN}") }
        #expect(throws: DocumentNumberPattern.PatternError.unterminatedToken) { try DocumentNumberPattern(template: "{NN") }
    }

    @Test func codable() throws {
        let pattern = try DocumentNumberPattern(template: "FV-{YYYY}-{NNN}")
        let data = try JSONEncoder().encode(pattern)
        #expect(String(decoding: data, as: UTF8.self) == #""FV-{YYYY}-{NNN}""#)
        let back = try JSONDecoder().decode(DocumentNumberPattern.self, from: data)
        #expect(back == pattern)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(DocumentNumberPattern.self, from: Data(#""{YYYY}""#.utf8))
        }
    }
}

@Suite struct DocumentNumberSeriesTests {
    @Test func issuesContinuousNumbersAndResetsYearly() throws {
        let pattern = try DocumentNumberPattern(template: "FV-{YYYY}-{NNN}")
        var series = try DocumentNumberSeries(id: "invoice", pattern: pattern, year: 2026)
        #expect(series.lastNumber == nil)
        let peeked = try series.peek(on: day("2026-01-10"))
        #expect(peeked == "FV-2026-001")
        #expect(series.lastCounter == 0)
        let first = try series.next(on: day("2026-01-10"))
        let second = try series.next(on: day("2026-03-01"))
        #expect(first == "FV-2026-001")
        #expect(second == "FV-2026-002")
        #expect(series.lastNumber == "FV-2026-002")
        let nextYear = try series.next(on: day("2027-01-05"))
        #expect(nextYear == "FV-2027-001")
        #expect(series.year == 2027)
        #expect(series.lastCounter == 1)
        let frozen = series
        #expect(throws: DocumentNumberSeries.NumberingError.dayBeforeSeriesYear(day("2026-12-31"), seriesYear: 2027)) {
            try frozen.peek(on: day("2026-12-31"))
        }
    }

    @Test func nonResettingSeriesKeepsCounting() throws {
        let pattern = try DocumentNumberPattern(template: "ZF{YYYY}-{NN}")
        var series = try DocumentNumberSeries(id: "advance", pattern: pattern, resetsYearly: false, year: 2026, lastCounter: 98)
        let a = try series.next(on: day("2026-12-31"))
        #expect(series.lastNumber == a)
        let b = try series.next(on: day("2027-01-02"))
        #expect(series.lastNumber == b)
        let c = try series.next(on: day("2026-06-01"))
        #expect(a == "ZF2026-99")
        #expect(b == "ZF2027-100")
        #expect(c == "ZF2026-101")
        #expect(series.lastNumber == "ZF2026-101")
        #expect(series.year == 2026)
        #expect(series.lastCounter == 101)
    }

    @Test func lastNumberUsesTheYearItWasIssuedIn() throws {
        let pattern = try DocumentNumberPattern(template: "ZF{YYYY}-{NN}")
        var series = try DocumentNumberSeries(id: "advance", pattern: pattern, resetsYearly: false, year: 2026, lastCounter: 98)
        let issued = try series.next(on: day("2027-01-02"))
        #expect(issued == "ZF2027-99")
        #expect(series.lastNumber == "ZF2027-99")
        let back = try JSONDecoder().decode(DocumentNumberSeries.self, from: JSONEncoder().encode(series))
        #expect(back == series)
        #expect(back.lastNumber == "ZF2027-99")
    }

    @Test func resettingSeriesNeedsAYearInThePattern() throws {
        let counterOnly = try DocumentNumberPattern(template: "{NNNNN}")
        #expect(throws: DocumentNumberSeries.NumberingError.resettingSeriesRequiresYearInPattern) {
            try DocumentNumberSeries(id: "invoice", pattern: counterOnly, resetsYearly: true, year: 2026)
        }
        var continuous = try DocumentNumberSeries(id: "invoice", pattern: counterOnly, resetsYearly: false, year: 2026)
        let first = try continuous.next(on: day("2026-01-10"))
        let second = try continuous.next(on: day("2027-01-05"))
        #expect(first == "00001")
        #expect(second == "00002")
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(DocumentNumberSeries.self, from: Data(#"{"id":"invoice","pattern":"FV-{NNN}","resetsYearly":true,"year":2026,"lastCounter":0}"#.utf8))
        }
    }

    @Test func rejectsImpossibleState() throws {
        let pattern = try DocumentNumberPattern(template: "FV-{YYYY}-{NNN}")
        #expect(throws: DocumentNumberSeries.NumberingError.invalidState(year: 2026, lastCounter: -3)) {
            try DocumentNumberSeries(id: "invoice", pattern: pattern, year: 2026, lastCounter: -3)
        }
        #expect(throws: DocumentNumberSeries.NumberingError.invalidState(year: 0, lastCounter: 0)) {
            try DocumentNumberSeries(id: "invoice", pattern: pattern, year: 0)
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(DocumentNumberSeries.self, from: Data(#"{"id":"invoice","pattern":"FV-{YYYY}-{NNN}","resetsYearly":true,"year":2026,"lastCounter":-3}"#.utf8))
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(DocumentNumberSeries.self, from: Data(#"{"id":"invoice","pattern":"FV-{YYYY}-{NNN}","resetsYearly":true,"year":0,"lastCounter":0}"#.utf8))
        }
    }

    @Test func codable() throws {
        let pattern = try DocumentNumberPattern(template: "{YYYY}{NNNN}")
        let series = try DocumentNumberSeries(id: "invoice", pattern: pattern, year: 2026, lastCounter: 5)
        let data = try JSONEncoder().encode(series)
        let back = try JSONDecoder().decode(DocumentNumberSeries.self, from: data)
        #expect(back == series)
        #expect(back.lastNumber == "20260005")
        #expect(back.variableSymbolPrefix == nil)
    }

    @Test func variableSymbolPrefix() throws {
        let pattern = try DocumentNumberPattern(template: "FV-{YYYY}-{NNN}")
        let prefixed = try DocumentNumberSeries(id: "invoice", pattern: pattern, year: 2026, variableSymbolPrefix: "1")
        #expect(prefixed.variableSymbolPrefix == "1")
        #expect(try DocumentNumberSeries(id: "invoice", pattern: pattern, year: 2026, variableSymbolPrefix: " ").variableSymbolPrefix == nil)
        #expect(try DocumentNumberSeries(id: "invoice", pattern: pattern, year: 2026, variableSymbolPrefix: " 12 ").variableSymbolPrefix == "12")
        for bad in ["0", "01", "1234", "1a", "x"] {
            #expect(throws: DocumentNumberSeries.NumberingError.invalidVariableSymbolPrefix(bad)) {
                try DocumentNumberSeries(id: "invoice", pattern: pattern, year: 2026, variableSymbolPrefix: bad)
            }
        }
        let data = try JSONEncoder().encode(prefixed)
        #expect(String(decoding: data, as: UTF8.self).contains(#""variableSymbolPrefix":"1""#))
        #expect(try JSONDecoder().decode(DocumentNumberSeries.self, from: data) == prefixed)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(DocumentNumberSeries.self, from: Data(#"{"id":"invoice","pattern":"FV-{YYYY}-{NNN}","resetsYearly":true,"year":2026,"lastCounter":0,"variableSymbolPrefix":"0"}"#.utf8))
        }
    }
}
