import Foundation
import XCTest
@testable import NotchCapture

final class InboxRefinementTests: XCTestCase {
    func testFolderDisclosureLeavesRowsCollapsedByDefaultAndRestoresAllRowsWhenExpanded() {
        XCTAssertEqual(
            InboxFolderSectionPolicy.visibleFolderCount(
                folderCount: 5,
                isExpanded: InboxRefinementPreferences.folderSectionStartsExpanded
            ),
            0
        )
        XCTAssertEqual(
            InboxFolderSectionPolicy.visibleFolderCount(
                folderCount: 5,
                isExpanded: true
            ),
            5
        )
        XCTAssertEqual(
            InboxFolderSectionPolicy.countLabel(for: 5),
            "5 folders"
        )
    }

    func testFolderDisclosureNeverProducesNegativeVisibleRows() {
        XCTAssertEqual(
            InboxFolderSectionPolicy.visibleFolderCount(
                folderCount: -1,
                isExpanded: true
            ),
            0
        )
        XCTAssertEqual(
            InboxFolderSectionPolicy.visibleFolderCount(
                folderCount: 4,
                isExpanded: false
            ),
            0
        )
    }

    func testComposerPlaceholderNamesTheSearchScope() {
        XCTAssertEqual(
            InboxComposerPresentationPolicy.placeholder(
                destination: "Projects",
                isAtRoot: false
            ),
            "Search Projects, add an item, or / for actions"
        )
        XCTAssertEqual(
            InboxComposerPresentationPolicy.placeholder(
                destination: "Inbox",
                isAtRoot: true
            ),
            "Search all items, add an item, or / for actions"
        )
        XCTAssertEqual(
            InboxComposerPresentationPolicy.placeholder(
                destination: "Projects",
                isAtRoot: false,
                searchesAllFolders: true
            ),
            "Search all items, add an item, or / for actions"
        )
    }

    func testMatchingHintExplainsBothReturnPathsAndDestination() {
        XCTAssertEqual(
            InboxComposerPresentationPolicy.matchingSearchHint(
                destination: "Projects",
                count: 2
            ),
            "2 matches. Return opens the first result; Command-Return adds a new item to Projects."
        )
        XCTAssertEqual(
            InboxComposerPresentationPolicy.emptySearchHint(destination: "Inbox"),
            "No matching items. Press Return to add this thought to Inbox."
        )
    }

    func testShiftReturnInsertionReplacesSelectionAndKeepsUTF16Caret() {
        let result = InboxComposerEditingPolicy.insertingNewline(
            in: "A🙂B",
            selectedRange: NSRange(location: 3, length: 0)
        )

        XCTAssertEqual(result.text, "A🙂\nB")
        XCTAssertEqual(result.caretUTF16Offset, 4)

        let replacement = InboxComposerEditingPolicy.insertingNewline(
            in: "First line",
            selectedRange: NSRange(location: 6, length: 4)
        )
        XCTAssertEqual(replacement.text, "First \n")
        XCTAssertEqual(replacement.caretUTF16Offset, 7)
    }
}
