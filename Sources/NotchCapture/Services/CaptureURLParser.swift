import Foundation

enum CaptureURLParser {
    /// Recognizes a single web address entered into the composer or supplied as plain text.
    /// `www.` addresses are normalized because macOS text pasteboards do not always include a scheme.
    static func url(from text: String) -> URL? {
        let candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty,
              !candidate.contains(where: { $0.isWhitespace || $0.isNewline })
        else {
            return nil
        }

        let normalized = candidate.lowercased().hasPrefix("www.")
            ? "https://\(candidate)"
            : candidate
        guard let components = URLComponents(string: normalized),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host,
              !host.isEmpty
        else {
            return nil
        }
        return components.url
    }
}
