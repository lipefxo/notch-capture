import SwiftUI
import XCTest
@testable import NotchCapture

@MainActor
final class InlineTagTitleFormatterTests: XCTestCase {
    func testExistingLinkedMentionsAreStyledAndLinkedCaseInsensitively() throws {
        let home = AppViewModel.TagSummary(name: "Home", colorSeed: 0.1)
        let title = InlineTagTitleFormatter.attributedTitle(
            "Email lipe@example.com about @home and @HOME with @Guest",
            tags: [home]
        )

        XCTAssertEqual(String(title.characters), "Email lipe@example.com about @home and @HOME with @Guest")
        let links = linkedRuns(in: title)
        XCTAssertEqual(links.map(\.text), ["@home", "@HOME"])
        XCTAssertEqual(links.map(\.url), [
            InlineTagTitleFormatter.tagURL(for: home.id),
            InlineTagTitleFormatter.tagURL(for: home.id),
        ])
        XCTAssertTrue(links.allSatisfy { $0.color != nil })
        XCTAssertTrue(links.allSatisfy { $0.font != nil })
    }

    func testMissingTagsAppendOnceInItemOrderWithoutDuplicatingMentions() {
        let work = AppViewModel.TagSummary(name: "Work")
        let home = AppViewModel.TagSummary(name: "Home")
        let duplicateWork = AppViewModel.TagSummary(id: work.id, name: "work")

        XCTAssertEqual(
            InlineTagTitleFormatter.renderedTitle(
                "Plan with @HOME",
                tags: [work, home, duplicateWork]
            ),
            "Plan with @HOME @Work"
        )
        XCTAssertEqual(
            InlineTagTitleFormatter.renderedTitle("", tags: [work, home]),
            "@Work @Home"
        )
    }

    func testUnlinkedMentionsAndEmailAddressesRemainPlain() {
        let title = InlineTagTitleFormatter.attributedTitle(
            "Ask @Guest at lipe@example.com",
            tags: []
        )

        XCTAssertEqual(String(title.characters), "Ask @Guest at lipe@example.com")
        XCTAssertTrue(linkedRuns(in: title).isEmpty)
    }

    func testPresentationTitleRetainsTagStylingWithoutInteractiveLinks() {
        let home = AppViewModel.TagSummary(name: "Home", colorSeed: 0.1)
        let title = InlineTagTitleFormatter.attributedTitle(
            "Plan @Home",
            tags: [home],
            includesLinks: false
        )

        XCTAssertEqual(String(title.characters), "Plan @Home")
        XCTAssertTrue(linkedRuns(in: title).isEmpty)
        XCTAssertTrue(title.runs.contains { $0.foregroundColor != nil && $0.font != nil })
    }

    func testTagLinksRoundTripTheirIdentityAndRejectOtherURLs() throws {
        let id = UUID()
        let url = InlineTagTitleFormatter.tagURL(for: id)

        XCTAssertTrue(InlineTagTitleFormatter.isTagURL(url))
        XCTAssertEqual(InlineTagTitleFormatter.tagID(from: url), id)
        XCTAssertFalse(InlineTagTitleFormatter.isTagURL(try XCTUnwrap(URL(string: "https://example.com"))))
        XCTAssertNil(InlineTagTitleFormatter.tagID(from: try XCTUnwrap(URL(string: "notch-capture://tag/not-a-uuid"))))
    }

    private func linkedRuns(in title: AttributedString) -> [(text: String, url: URL, color: Color?, font: Font?)] {
        title.runs.compactMap { run in
            guard let link = run.link else { return nil }
            return (String(title[run.range].characters), link, run.foregroundColor, run.font)
        }
    }
}
