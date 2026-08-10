import Foundation

/// Canonicalizes authored dialog text before it crosses the speech API boundary.
///
/// The server remains responsible for validating arbitrary input. This cleanup only removes
/// copy/paste artifacts and normalizes typography that speech providers commonly tokenize in
/// surprising ways. It deliberately preserves letters from every language and ElevenLabs style
/// tags such as `[whispers]`.
public enum DialogSpeechTextSanitizer {

    /// Returns a stable speech transcript with canonical Unicode composition, ordinary spaces,
    /// ASCII variants of common typographic punctuation, no invisible formatting controls, and
    /// no parenthesis delimiters that can collapse several spoken words into one alignment token.
    public static func sanitize(_ text: String) -> String {
        let normalized = text.precomposedStringWithCanonicalMapping
        var result = ""
        var needsSpace = false

        func appendSpaceIfNeeded() {
            if needsSpace, !result.isEmpty {
                result.append(" ")
            }
            needsSpace = false
        }

        for scalar in normalized.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                needsSpace = !result.isEmpty
                continue
            }

            switch scalar.properties.generalCategory {
            case .control:
                // Treat pasted control bytes as a boundary so two neighboring words cannot be
                // accidentally joined after cleanup.
                needsSpace = !result.isEmpty
                continue
            case .format:
                // Zero-width spaces, direction marks, joiners, and BOMs have no spoken form.
                continue
            default:
                break
            }

            // ElevenLabs can return an entire parenthesized phrase as one forced-alignment word
            // even though the transcript contains whitespace inside it. Removing only the
            // delimiters preserves every spoken word while keeping alignment tokenization stable.
            switch scalar.value {
            case 0x0028, 0xFE59, 0xFF08:
                needsSpace = !result.isEmpty
                continue
            case 0x0029, 0xFE5A, 0xFF09:
                continue
            default:
                break
            }

            appendSpaceIfNeeded()
            switch scalar.value {
            case 0x2018, 0x2019, 0x201A, 0x201B, 0x02BC, 0xFF07:
                result.append("'")
            case 0x201C, 0x201D, 0x201E, 0x201F, 0x00AB, 0x00BB, 0xFF02:
                result.append("\"")
            case 0x2026:
                result.append("...")
            case 0x2010, 0x2011, 0x2012, 0x2013, 0x2014, 0x2015, 0x2212, 0xFF0D:
                result.append("-")
            case 0xFFFD:
                // A replacement character means decoding already lost the original byte. It has
                // no reliable spoken value, so do not send it to the speech provider.
                break
            default:
                result.unicodeScalars.append(scalar)
            }
        }

        return result
    }
}

extension DialogScript {

    /// Returns a copy whose spoken turns are safe to validate, cache, and generate from.
    /// Metadata and author notes are intentionally untouched.
    public var sanitizedForSpeech: DialogScript {
        var sanitized = self
        for index in sanitized.turns.indices {
            sanitized.turns[index].text = DialogSpeechTextSanitizer.sanitize(
                sanitized.turns[index].text)
        }
        return sanitized
    }
}
