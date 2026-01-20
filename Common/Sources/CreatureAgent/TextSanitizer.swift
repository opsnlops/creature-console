import Foundation

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
        if scalar.properties.isEmojiPresentation || scalar.properties.isEmoji {
            return true
        }
        if scalar.value == 0xFE0F {
            return true
        }
        if CharacterSet.symbols.contains(scalar) {
            return true
        }
        return false
    }
}

struct SanitizationResult {
    let text: String
    let removedCharacters: Int
}
