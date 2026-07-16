import Foundation

enum TagColorSeed {
    static func random() -> Double {
        Double.random(in: 0..<1)
    }

    static func stable(for id: UUID) -> Double {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in id.uuidString.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Double(hash % 10_000) / 10_000
    }
}

struct ParsedTagText: Equatable, Sendable {
    let text: String
    let tagNames: [String]

    var isTagOnly: Bool { text.isEmpty && !tagNames.isEmpty }
}

struct CaptureTagMention: Equatable {
    let name: String
    let range: Range<String.Index>
}

enum CaptureTagParser {
    private static let expression = try! NSRegularExpression(
        pattern: #"(?<!\S)@([\p{L}\p{N}_-]+)"#
    )

    static func parse(_ input: String) -> ParsedTagText {
        var names: [String] = []
        var seen: Set<String> = []

        for mention in mentions(in: input) {
            let normalized = normalize(mention.name)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            names.append(mention.name)
        }

        return ParsedTagText(
            text: removingTagMentions(in: input),
            tagNames: names
        )
    }

    static func mentions(in input: String) -> [CaptureTagMention] {
        let range = NSRange(input.startIndex..., in: input)
        return expression.matches(in: input, range: range).compactMap { match in
            guard let tokenRange = Range(match.range(at: 0), in: input),
                  let nameRange = Range(match.range(at: 1), in: input) else {
                return nil
            }
            return CaptureTagMention(name: String(input[nameRange]), range: tokenRange)
        }
    }

    /// Removes intentional tag tokens while leaving emails and unmatched mentions untouched.
    /// When `tagNames` is nil, every recognized tag token is removed.
    static func removingTagMentions(in input: String, matching tagNames: [String]? = nil) -> String {
        let normalizedNames = tagNames.map { Set($0.map(normalize)) }
        let mutable = NSMutableString(string: input)
        let range = NSRange(input.startIndex..., in: input)
        let matches = expression.matches(in: input, range: range)
        for match in matches.reversed() {
            guard normalizedNames == nil || normalizedNames?.contains(normalizedName(in: input, match: match)) == true else {
                continue
            }
            mutable.replaceCharacters(in: match.range, with: "")
        }
        return cleanedText(mutable as String)
    }

    /// Rewrites occurrences of one attached tag without changing surrounding prose.
    static func replacingTagMentions(
        in input: String,
        matching tagName: String,
        with replacementName: String
    ) -> String {
        let target = normalize(tagName)
        let mutable = NSMutableString(string: input)
        let range = NSRange(input.startIndex..., in: input)
        let matches = expression.matches(in: input, range: range)
        for match in matches.reversed() where normalizedName(in: input, match: match) == target {
            mutable.replaceCharacters(in: match.range, with: "@\(replacementName)")
        }
        return mutable as String
    }

    static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    static func normalizedDisplayName(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
    }

    /// Returns the tag fragment currently being typed, excluding `@`.
    static func activeTagFragment(in input: String) -> String? {
        guard let at = input.lastIndex(of: "@") else { return nil }
        if at != input.startIndex {
            let previous = input.index(before: at)
            guard input[previous].isWhitespace else { return nil }
        }
        let fragment = input[input.index(after: at)...]
        guard fragment.allSatisfy(isTagCharacter) else { return nil }
        return String(fragment)
    }

    static func isTagCharacter(_ character: Character) -> Bool {
        character == "-" || character == "_" || character.unicodeScalars.allSatisfy {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
        }
    }

    private static func cleanLine(_ line: String) -> String {
        line.replacingOccurrences(of: #"[\t ]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func normalizedName(in input: String, match: NSTextCheckingResult) -> String {
        guard let range = Range(match.range(at: 1), in: input) else { return "" }
        return normalize(String(input[range]))
    }

    private static func cleanedText(_ input: String) -> String {
        let cleanedLines = input.components(separatedBy: .newlines).map(cleanLine)
        var first = 0
        var last = cleanedLines.count
        while first < last && cleanedLines[first].isEmpty { first += 1 }
        while last > first && cleanedLines[last - 1].isEmpty { last -= 1 }
        return cleanedLines[first..<last].joined(separator: "\n")
    }
}
