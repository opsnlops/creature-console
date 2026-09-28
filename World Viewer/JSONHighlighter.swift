import SwiftUI

/// Colors one line of pretty-printed JSON for the Mundane view. The World's encoder writes one
/// value per line and escapes newlines inside strings, so a line never starts or ends inside a
/// string and each can be read on its own.
enum JSONHighlighter {
    enum Token: Equatable {
        case key(String)
        case string(String)
        case number(String)
        case literal(String)
        case punctuation(String)
    }

    /// The line split into tokens; whitespace rides along as punctuation so the pieces joined
    /// are the line again.
    static func tokens(of line: Substring) -> [Token] {
        var tokens: [Token] = []
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == "\"" {
                let end = endOfString(in: line, from: index)
                let text = String(line[index..<end])
                tokens.append(isKey(after: end, in: line) ? .key(text) : .string(text))
                index = end
            } else if character == "-" || character.isNumber {
                var end = line.index(after: index)
                while end < line.endIndex, "0123456789.eE+-".contains(line[end]) {
                    end = line.index(after: end)
                }
                tokens.append(.number(String(line[index..<end])))
                index = end
            } else if let literal = ["true", "false", "null"].first(where: {
                line[index...].hasPrefix($0)
            }) {
                tokens.append(.literal(literal))
                index = line.index(index, offsetBy: literal.count)
            } else {
                var end = line.index(after: index)
                while end < line.endIndex, !"\"-tfn".contains(line[end]), !line[end].isNumber {
                    end = line.index(after: end)
                }
                tokens.append(.punctuation(String(line[index..<end])))
                index = end
            }
        }
        return tokens
    }

    /// The Mundane view's page and its colors: Material Palenight, a soft indigo page made
    /// for reading code at night - and purple, as a purple rabbit's world should be. The
    /// system purple and green were too dim on a dark page to read.
    enum Palette {
        static let page = rgb(0x292D3E)
        static let key = rgb(0xC792EA)
        static let string = rgb(0xC3E88D)
        static let number = rgb(0xF78C6C)
        static let literal = rgb(0x82AAFF)
        static let punctuation = rgb(0x89DDFF)

        private static func rgb(_ hex: Int) -> Color {
            Color(
                red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255)
        }
    }

    static func highlighted(_ line: Substring) -> AttributedString {
        var result = AttributedString()
        for token in tokens(of: line) {
            let (text, color): (String, Color) =
                switch token {
                case .key(let text): (text, Palette.key)
                case .string(let text): (text, Palette.string)
                case .number(let text): (text, Palette.number)
                case .literal(let text): (text, Palette.literal)
                case .punctuation(let text): (text, Palette.punctuation)
                }
            var piece = AttributedString(text)
            piece.foregroundColor = color
            result += piece
        }
        return result
    }

    /// Just past the closing quote of the string opening at `start`, escapes skipped; the
    /// line's end if it never closes.
    private static func endOfString(in line: Substring, from start: Substring.Index)
        -> Substring.Index
    {
        var index = line.index(after: start)
        while index < line.endIndex {
            if line[index] == "\\" {
                index = line.index(after: index)
                if index < line.endIndex { index = line.index(after: index) }
                continue
            }
            if line[index] == "\"" { return line.index(after: index) }
            index = line.index(after: index)
        }
        return line.endIndex
    }

    /// A string is a key when the next thing after it is a colon.
    private static func isKey(after end: Substring.Index, in line: Substring) -> Bool {
        line[end...].first { !$0.isWhitespace } == ":"
    }
}
