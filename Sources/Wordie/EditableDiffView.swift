import SwiftUI
import AppKit

/// Custom attribute key to mark removed (red) text ranges as non-editable
private let kIsRemoved = NSAttributedString.Key("WordieDiffRemoved")

struct EditableDiffView: NSViewRepresentable {
    let oldText: String
    @Binding var newText: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = true
        textView.backgroundColor = .textBackgroundColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.delegate = context.coordinator

        scrollView.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.oldText = oldText
        context.coordinator.currentNewText = newText
        context.coordinator.newTextBinding = $newText
        context.coordinator.applyDiff()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        // Only reapply if the data changed externally (not from our own edits)
        if coordinator.oldText != oldText || (!coordinator.isInternalEdit && coordinator.currentNewText != newText) {
            coordinator.oldText = oldText
            coordinator.currentNewText = newText
            coordinator.newTextBinding = $newText
            coordinator.applyDiff()
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: NSTextView?
        var oldText: String = ""
        var currentNewText: String = ""
        var newTextBinding: Binding<String>?
        var isApplyingDiff = false
        var isInternalEdit = false

        /// Rebuild the attributed diff string and apply it, preserving cursor position.
        func applyDiff() {
            guard let textView = textView, let storage = textView.textStorage else { return }
            isApplyingDiff = true

            let tokens = DiffEngine.diff(old: oldText, new: currentNewText)

            // Save cursor as an offset into the "new text" (non-removed characters)
            let savedCursorInNew = cursorOffsetInNewText()

            let attributed = buildAttributedString(from: tokens)
            storage.setAttributedString(attributed)

            // Restore cursor from "new text" offset back to display position
            let restored = displayPosition(forNewTextOffset: savedCursorInNew, in: storage)
            textView.setSelectedRange(NSRange(location: min(restored, storage.length), length: 0))

            isApplyingDiff = false
        }

        // MARK: - NSTextViewDelegate

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            if isApplyingDiff { return true }
            guard let storage = textView.textStorage else { return true }

            // For deletions or replacements that span text, check if any part is removed
            if range.length > 0 {
                var touchesRemoved = false
                storage.enumerateAttribute(kIsRemoved, in: range) { value, _, stop in
                    if (value as? Bool) == true {
                        touchesRemoved = true
                        stop.pointee = true
                    }
                }
                if touchesRemoved { return false }
            }

            // For pure insertions (range.length == 0), block if cursor is inside a removed run
            if range.length == 0 && range.location < storage.length {
                if isInsideRemovedRun(at: range.location, in: storage) {
                    return false
                }
            }

            return true
        }

        func textDidChange(_ notification: Notification) {
            if isApplyingDiff { return }
            guard let textView = textView, let storage = textView.textStorage else { return }

            // Extract the current "new text" = everything that isn't marked removed
            var extracted = ""
            storage.enumerateAttribute(kIsRemoved, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                if (value as? Bool) != true {
                    let s = storage.string as NSString
                    extracted += s.substring(with: range)
                }
            }

            currentNewText = extracted
            isInternalEdit = true
            newTextBinding?.wrappedValue = extracted
            applyDiff()
            isInternalEdit = false
        }

        // MARK: - Helpers

        /// Check if a position is strictly inside (not at the boundary of) a removed run.
        private func isInsideRemovedRun(at pos: Int, in storage: NSTextStorage) -> Bool {
            var effectiveRange = NSRange()
            let val = storage.attribute(kIsRemoved, at: pos, effectiveRange: &effectiveRange) as? Bool ?? false
            if !val { return false }
            // It's removed at this position. Allow insertion at the very start of the removed run
            // (that means we're inserting *before* it), but block inside or at the end.
            return pos > effectiveRange.location
        }

        /// Convert the current cursor position in the display text to an offset in "new text" space.
        private func cursorOffsetInNewText() -> Int {
            guard let storage = textView?.textStorage else { return 0 }
            let cursorPos = textView?.selectedRange().location ?? 0
            var newOffset = 0
            storage.enumerateAttribute(kIsRemoved, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
                let isRemoved = (value as? Bool) ?? false
                // How much of this run is before the cursor?
                let runEnd = range.location + range.length
                let relevantEnd = min(runEnd, cursorPos)
                if relevantEnd > range.location && !isRemoved {
                    newOffset += relevantEnd - range.location
                }
                if range.location >= cursorPos {
                    stop.pointee = true
                }
            }
            return newOffset
        }

        /// Convert a "new text" offset back to a display position in the attributed string.
        private func displayPosition(forNewTextOffset target: Int, in storage: NSTextStorage) -> Int {
            var accumulated = 0
            var result = storage.length
            storage.enumerateAttribute(kIsRemoved, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
                let isRemoved = (value as? Bool) ?? false
                if !isRemoved {
                    let remaining = target - accumulated
                    if remaining <= range.length {
                        result = range.location + remaining
                        stop.pointee = true
                        return
                    }
                    accumulated += range.length
                }
            }
            return result
        }

        /// Build the styled NSAttributedString from diff tokens.
        private func buildAttributedString(from tokens: [DiffToken]) -> NSAttributedString {
            let attributed = NSMutableAttributedString()
            let baseFont = NSFont.systemFont(ofSize: 14)

            for token in tokens {
                switch token {
                case .unchanged(let s):
                    attributed.append(NSAttributedString(string: s, attributes: [
                        .font: baseFont,
                        .foregroundColor: NSColor.textColor,
                        kIsRemoved: false
                    ]))

                case .removed(let s):
                    attributed.append(NSAttributedString(string: s, attributes: [
                        .font: baseFont,
                        .foregroundColor: NSColor.systemRed,
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                        .backgroundColor: NSColor.systemRed.withAlphaComponent(0.1),
                        kIsRemoved: true
                    ]))

                case .added(let s):
                    attributed.append(NSAttributedString(string: s, attributes: [
                        .font: baseFont,
                        .foregroundColor: NSColor.systemGreen,
                        .backgroundColor: NSColor.systemGreen.withAlphaComponent(0.1),
                        kIsRemoved: false
                    ]))
                }
            }
            return attributed
        }
    }
}
