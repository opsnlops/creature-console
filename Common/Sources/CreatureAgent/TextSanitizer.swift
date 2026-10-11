import Foundation

/// Makes text safe for Beaky's voice. Her words are written to be spoken by the ad-hoc speech
/// pipeline, which cannot say emoji or pictographs; Communicator shows the same text so what
/// she says aloud and what she writes never differ. Symbols a voice reads aloud stay: "C++" is
/// "C plus plus", "$20" twenty dollars (#225).
struct TextSanitizer {
    private static let replacementSpace = " "

    static func sanitize(_ input: String) -> SanitizationResult {
        guard !input.isEmpty else {
            return SanitizationResult(text: "", removedCharacters: 0)
        }

        var cleaned = String.UnicodeScalarView()
        var removed = 0
        var previousWasSpace = false

        for scalar in input.unicodeScalars {
            let isWhitespace = CharacterSet.whitespacesAndNewlines.contains(scalar)
            if isWhitespace {
                if previousWasSpace {
                    continue
                }
                cleaned.append(contentsOf: replacementSpace.unicodeScalars)
                previousWasSpace = true
                continue
            }

            if shouldDrop(scalar) {
                removed += 1
                continue
            }

            cleaned.append(scalar)
            previousWasSpace = false
        }

        let trimmed = String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
        return SanitizationResult(text: trimmed, removedCharacters: removed)
    }

    private static func shouldDrop(_ scalar: UnicodeScalar) -> Bool {
        if CharacterSet.controlCharacters.contains(scalar) {
            return true
        }
        // Unicode marks the ASCII digits, "#", and "*" as Emoji=Yes because they are keycap
        // bases; only scalars that actually present as emoji, or non-ASCII emoji-capable
        // scalars, are pictures a voice cannot say.
        if scalar.properties.isEmojiPresentation || (scalar.properties.isEmoji && !scalar.isASCII) {
            return true
        }
        // Variation selector and combining keycap: leftovers of emoji sequences.
        if scalar.value == 0xFE0F || scalar.value == 0x20E3 {
            return true
        }
        if CharacterSet.symbols.contains(scalar) {
            return !isSpoken(scalar)
        }
        return false
    }

    /// The symbols the voice says: printable ASCII (`+`, `$`, `=`, `<`...), every currency
    /// sign, and a few from weather and arithmetic.
    private static func isSpoken(_ scalar: UnicodeScalar) -> Bool {
        scalar.isASCII || scalar.properties.generalCategory == .currencySymbol
            || spokenSymbols.contains(scalar)
    }

    private static let spokenSymbols: Set<UnicodeScalar> = ["°", "±", "×", "÷"]
}

struct SanitizationResult {
    let text: String
    let removedCharacters: Int
}
