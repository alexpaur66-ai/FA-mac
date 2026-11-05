/// Small string helpers shared by the core. Internal on purpose.
extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}

extension String {
    /// Removes leading and trailing whitespace without needing Foundation.
    func trimmingWhitespace() -> String {
        String(drop(while: { $0.isWhitespace }).reversed().drop(while: { $0.isWhitespace }).reversed())
    }

    /// Pads on the left to `width` characters; never truncates.
    func leftPadded(to width: Int, with pad: Character = "0") -> String {
        count >= width ? self : String(repeating: pad, count: width - count) + self
    }
}
