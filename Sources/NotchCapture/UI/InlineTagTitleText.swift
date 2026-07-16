import Foundation
import SwiftUI

enum InlineTagTitleFormatter {
    private static let linkScheme = "notch-capture"
    private static let linkHost = "tag"

    static func renderedTitle(_ title: String, tags: [AppViewModel.TagSummary]) -> String {
        let mentionedNames = Set(
            CaptureTagParser.mentions(in: title).map { CaptureTagParser.normalize($0.name) }
        )
        var appendedNames: Set<String> = []
        let missingTags = tags.compactMap { tag -> String? in
            let normalized = CaptureTagParser.normalize(tag.name)
            guard !mentionedNames.contains(normalized), appendedNames.insert(normalized).inserted else {
                return nil
            }
            return "@\(tag.name)"
        }

        guard !missingTags.isEmpty else { return title }
        let suffix = missingTags.joined(separator: " ")
        return title.isEmpty ? suffix : "\(title) \(suffix)"
    }

    static func attributedTitle(
        _ title: String,
        tags: [AppViewModel.TagSummary],
        includesLinks: Bool = true
    ) -> AttributedString {
        let renderedTitle = renderedTitle(title, tags: tags)
        let tagsByName = Dictionary(tags.map { (CaptureTagParser.normalize($0.name), $0) }) { first, _ in first }
        var result = AttributedString()
        var cursor = renderedTitle.startIndex

        for mention in CaptureTagParser.mentions(in: renderedTitle) {
            result.append(AttributedString(String(renderedTitle[cursor..<mention.range.lowerBound])))

            var token = AttributedString(String(renderedTitle[mention.range]))
            if let tag = tagsByName[CaptureTagParser.normalize(mention.name)] {
                token.font = .system(size: 12.5, weight: .regular, design: .monospaced)
                token.foregroundColor = NotchTheme.tagAccent(seed: tag.colorSeed)
                if includesLinks {
                    token.link = tagURL(for: tag.id)
                }
            }
            result.append(token)
            cursor = mention.range.upperBound
        }

        result.append(AttributedString(String(renderedTitle[cursor...])))
        return result
    }

    static func tagURL(for id: UUID) -> URL {
        var components = URLComponents()
        components.scheme = linkScheme
        components.host = linkHost
        components.path = "/\(id.uuidString)"
        return components.url!
    }

    static func tagID(from url: URL) -> UUID? {
        guard url.scheme == linkScheme, url.host == linkHost else { return nil }
        return UUID(uuidString: url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    static func isTagURL(_ url: URL) -> Bool {
        url.scheme == linkScheme && url.host == linkHost
    }
}

struct InlineTagTitleText: View {
    let title: String
    let tags: [AppViewModel.TagSummary]
    let onTagSelected: (AppViewModel.TagSummary) -> Void

    var body: some View {
        Text(InlineTagTitleFormatter.attributedTitle(title, tags: tags))
            .environment(\.openURL, OpenURLAction { url in
                guard InlineTagTitleFormatter.isTagURL(url) else { return .systemAction }
                guard let id = InlineTagTitleFormatter.tagID(from: url),
                      let tag = tags.first(where: { $0.id == id }) else {
                    return .discarded
                }
                onTagSelected(tag)
                return .handled
            })
    }
}
