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

enum CaptureTagParser {
    private static let expression = try! NSRegularExpression(
        pattern: #"(?<!\S)@([\p{L}\p{N}_-]+)"#
    )

    static func parse(_ input: String) -> ParsedTagText {
        let range = NSRange(input.startIndex..., in: input)
        let matches = expression.matches(in: input, range: range)
        var names: [String] = []
        var seen: Set<String> = []

        for match in matches {
            guard let nameRange = Range(match.range(at: 1), in: input) else { continue }
            let name = String(input[nameRange])
            let normalized = normalize(name)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            names.append(name)
        }

        let mutable = NSMutableString(string: input)
        for match in matches.reversed() {
            mutable.replaceCharacters(in: match.range, with: "")
        }

        let cleanedLines = (mutable as String)
            .components(separatedBy: .newlines)
            .map(cleanLine)
        var first = 0
        var last = cleanedLines.count
        while first < last && cleanedLines[first].isEmpty { first += 1 }
        while last > first && cleanedLines[last - 1].isEmpty { last -= 1 }

        return ParsedTagText(
            text: cleanedLines[first..<last].joined(separator: "\n"),
            tagNames: names
        )
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
}
