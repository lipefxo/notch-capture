import Foundation
import AppKit
import SwiftUI

/// UserDefaults keys for the expanded inbox's two density controls. Keeping
/// these in one place prevents previews and the real surface from drifting.
enum InboxRefinementPreferences {
    static let utilityShelfExpandedKey = "NotchCapture.expandedInbox.utilityShelfExpanded"
    static let folderSectionExpandedKey = "NotchCapture.expandedInbox.folderSectionExpanded"

    static let utilityShelfStartsExpanded = false
    static let folderSectionStartsExpanded = false
}

enum InboxFolderSectionPolicy {
    /// A collapsed section keeps its disclosure row but gives every capture
    /// row back to the scroll viewport.
    static func visibleFolderCount(folderCount: Int, isExpanded: Bool) -> Int {
        guard isExpanded else { return 0 }
        return max(0, folderCount)
    }

    static func countLabel(for folderCount: Int) -> String {
        "\(folderCount) \(folderCount == 1 ? "folder" : "folders")"
    }
}

enum InboxComposerPresentationPolicy {
    static func placeholder(
        destination: String,
        isAtRoot: Bool,
        searchesAllFolders: Bool = false
    ) -> String {
        if isAtRoot || searchesAllFolders {
            return "Search all items, add an item, or / for actions"
        }
        return "Search \(destination), add an item, or / for actions"
    }

    static func accessibilityLabel(
        destination: String,
        isAtRoot: Bool,
        searchesAllFolders: Bool = false
    ) -> String {
        if isAtRoot || searchesAllFolders {
            return "Search all items, add an item, or slash for actions"
        }
        return "Search \(destination), add an item, or slash for actions"
    }

    static func emptySearchHint(destination: String) -> String {
        "No matching items. Press Return to add this thought to \(destination)."
    }

    static func matchingSearchHint(destination: String, count: Int) -> String {
        let noun = count == 1 ? "match" : "matches"
        return "\(count) \(noun). Return opens the first result; Command-Return adds a new item to \(destination)."
    }
}

struct InboxTextInsertionResult: Equatable {
    let text: String
    /// The insertion point measured in UTF-16 offsets, matching AppKit's
    /// `NSTextView.selectedRange()` representation.
    let caretUTF16Offset: Int
}

enum InboxComposerEditingPolicy {
    /// Replaces the current selection with a newline and leaves the caret
    /// immediately after it. AppKit text views expose selections as UTF-16
    /// ranges, so doing this with NSString keeps emoji and composed text safe.
    static func insertingNewline(
        in text: String,
        selectedRange: NSRange
    ) -> InboxTextInsertionResult {
        let source = text as NSString
        let length = source.length
        let rawLocation = selectedRange.location == NSNotFound
            ? length
            : selectedRange.location
        let location = min(max(0, rawLocation), length)
        let availableLength = length - location
        let replacementLength = min(max(0, selectedRange.length), availableLength)
        let replacementRange = NSRange(location: location, length: replacementLength)
        let updated = source.replacingCharacters(in: replacementRange, with: "\n")
        return InboxTextInsertionResult(
            text: updated,
            caretUTF16Offset: location + 1
        )
    }
}

@MainActor
enum InboxNativeTextEditing {
    /// Inserts a newline into an AppKit field editor without allowing the
    /// field's default Return action to submit or select the entire draft.
    /// `updateText` lets both the composer and inline row editor mirror the
    /// native edit into their respective model state.
    @discardableResult
    static func insertNewline(
        into editor: NSTextView,
        updateText: (String) -> Void
    ) -> Bool {
        let selection = editor.selectedRange()
        let result = InboxComposerEditingPolicy.insertingNewline(
            in: editor.string,
            selectedRange: selection
        )
        editor.insertText("\n", replacementRange: selection)
        let updatedText = editor.string
        updateText(updatedText)
        editor.setSelectedRange(
            NSRange(location: result.caretUTF16Offset, length: 0)
        )

        // A binding update can cause SwiftUI to refresh the field editor on
        // the next run loop turn. Reapply the caret only if this is still the
        // same text, preserving a selected replacement range.
        DispatchQueue.main.async { [weak editor] in
            guard let editor,
                  editor.window != nil,
                  editor.string == updatedText else { return }
            editor.setSelectedRange(
                NSRange(location: result.caretUTF16Offset, length: 0)
            )
        }
        return true
    }
}

/// A compact, readable shortcut badge used in the composer while an action is
/// available. It keeps the keyboard contract visible without stealing the
/// field's input focus.
struct InlineKeyboardHint: View {
    let shortcut: String
    let action: String
    let spokenShortcut: String?

    init(shortcut: String, action: String, spokenShortcut: String? = nil) {
        self.shortcut = shortcut
        self.action = action
        self.spokenShortcut = spokenShortcut
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(shortcut)
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(NotchTheme.primaryText)
                .padding(.horizontal, 4)
                .frame(height: 18)
                .background(NotchTheme.selectedControl)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            Text(action)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(NotchTheme.secondaryText)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(spokenShortcut ?? shortcut), \(action)")
    }
}
