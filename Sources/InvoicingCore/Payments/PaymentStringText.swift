import Foundation

/// Text helpers shared by the payment QR string formats.
enum PaymentStringText {
    /// Characters a QR code can store in its compact alphanumeric mode (ISO/IEC 18004):
    /// digits, uppercase A–Z, space and `$ % * + - . / :`. The QR platba specification recommends
    /// staying inside this set so the code stays small.
    static let qrAlphanumeric: Set<Character> = Set("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:")

    /// Letters that do not decompose into a base letter plus a combining mark.
    private static let foldedLetters: [Character: String] = [
        "ß": "ss", "ẞ": "SS", "Ø": "O", "ø": "o", "Æ": "AE", "æ": "ae", "Œ": "OE", "œ": "oe",
        "Ł": "L", "ł": "l", "Đ": "D", "đ": "d", "Þ": "TH", "þ": "th", "Ð": "D", "ð": "d",
        "Ħ": "H", "ħ": "h", "Ŧ": "T", "ŧ": "t", "İ": "I", "ı": "i", "Ŋ": "N", "ŋ": "n",
    ]

    /// Removes diacritics ("Příliš žluťoučký kůň" → "Prilis zlutoucky kun") and spells the few letters
    /// that have no decomposition with ASCII letters. Everything else is left as it is.
    static func strippingDiacritics(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            if let folded = foldedLetters[character] {
                result += folded
                continue
            }
            let decomposed = String(character).decomposedStringWithCanonicalMapping
            let scalars = decomposed.unicodeScalars.filter { scalar in
                switch scalar.properties.generalCategory {
                case .nonspacingMark, .spacingMark, .enclosingMark: return false
                default: return true
                }
            }
            result.unicodeScalars.append(contentsOf: scalars)
        }
        return result
    }

    /// Percent-encodes every byte of the UTF-8 form of `text` whose character is not in `allowed`,
    /// as `%XX` with uppercase hex. Used for the characters a format forbids in a value.
    static func percentEncoding(_ text: String, keeping allowed: (Character) -> Bool) -> String {
        var result = ""
        for character in text {
            if allowed(character) {
                result.append(character)
            } else {
                for byte in String(character).utf8 {
                    result += "%" + String(byte, radix: 16, uppercase: true).leftPadded(to: 2)
                }
            }
        }
        return result
    }

    /// Collapses runs of whitespace (including line breaks) into single spaces and trims the ends.
    static func collapsingWhitespace(_ text: String) -> String {
        var result = ""
        var pendingSpace = false
        for character in text {
            if character.isWhitespace || character.isNewline {
                pendingSpace = !result.isEmpty
            } else {
                if pendingSpace { result.append(" "); pendingSpace = false }
                result.append(character)
            }
        }
        return result
    }
}
