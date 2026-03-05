import SwiftUI
import AppKit

/// Custom attribute key to mark removed (red) text ranges as non-editable
private let kIsRemoved = NSAttributedString.Key("WordieDiffRemoved")

/// A contiguous group of non-unchanged diff tokens (a single "edit site")
struct DiffSite {
    let tokenStart: Int      // first token index (inclusive)
    let tokenEnd: Int        // last token index (exclusive)
    var displayRange: NSRange // range in the attributed string
    var oldContent: String    // concatenated removed text
    var newContent: String    // concatenated added text
}

// MARK: - Custom NSTextView subclass for key handling

class DiffNSTextView: NSTextView {
    enum Command {
        case nextSite, prevSite, acceptSite, rejectSite
    }
    var onDiffCommand: ((Command) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
            switch event.charactersIgnoringModifiers {
            case "j": onDiffCommand?(.nextSite); return true
            case "k": onDiffCommand?(.prevSite); return true
            case "y": onDiffCommand?(.acceptSite); return true
            case "n": onDiffCommand?(.rejectSite); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - EditableDiffView

struct EditableDiffView: NSViewRepresentable {
    @Binding var oldText: String
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

        let textView = DiffNSTextView()
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
        textView.onDiffCommand = { [weak coordinator = context.coordinator] cmd in
            coordinator?.handleCommand(cmd)
        }

        scrollView.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.currentOldText = oldText
        context.coordinator.currentNewText = newText
        context.coordinator.oldTextBinding = $oldText
        context.coordinator.newTextBinding = $newText
        context.coordinator.applyDiff()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.isInternalEdit { return }
        if coordinator.currentOldText != oldText || coordinator.currentNewText != newText {
            coordinator.currentOldText = oldText
            coordinator.currentNewText = newText
            coordinator.oldTextBinding = $oldText
            coordinator.newTextBinding = $newText
            coordinator.applyDiff()
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: DiffNSTextView?
        var currentOldText: String = ""
        var currentNewText: String = ""
        var oldTextBinding: Binding<String>?
        var newTextBinding: Binding<String>?
        var isApplyingDiff = false
        var isInternalEdit = false

        var tokens: [DiffToken] = []
        var sites: [DiffSite] = []
        var selectedSiteIndex: Int? = nil

        // MARK: Apply diff

        func applyDiff() {
            guard let textView = textView, let storage = textView.textStorage else { return }
            isApplyingDiff = true

            tokens = DiffEngine.diff(old: currentOldText, new: currentNewText)
            sites = computeSites()

            // Validate selected index
            if let idx = selectedSiteIndex {
                if sites.isEmpty {
                    selectedSiteIndex = nil
                } else if idx >= sites.count {
                    selectedSiteIndex = sites.count - 1
                }
            }

            let savedCursor = cursorOffsetInNewText()
            let attributed = buildAttributedString()
            storage.setAttributedString(attributed)

            let restored = displayPosition(forNewTextOffset: savedCursor, in: storage)
            textView.setSelectedRange(NSRange(location: min(restored, storage.length), length: 0))

            isApplyingDiff = false
        }

        // MARK: Compute sites

        private func computeSites() -> [DiffSite] {
            var result: [DiffSite] = []
            var i = 0
            var displayOffset = 0

            while i < tokens.count {
                if case .unchanged(let s) = tokens[i] {
                    displayOffset += s.count
                    i += 1
                    continue
                }

                let start = i
                let displayStart = displayOffset
                var oldContent = ""
                var newContent = ""

                while i < tokens.count {
                    switch tokens[i] {
                    case .unchanged:
                        break // exit inner loop
                    case .removed(let s):
                        oldContent += s
                        displayOffset += s.count
                        i += 1
                        continue
                    case .added(let s):
                        newContent += s
                        displayOffset += s.count
                        i += 1
                        continue
                    }
                    break
                }

                result.append(DiffSite(
                    tokenStart: start,
                    tokenEnd: i,
                    displayRange: NSRange(location: displayStart, length: displayOffset - displayStart),
                    oldContent: oldContent,
                    newContent: newContent
                ))
            }
            return result
        }

        // MARK: Build attributed string

        private func buildAttributedString() -> NSAttributedString {
            let attributed = NSMutableAttributedString()
            let baseFont = NSFont.systemFont(ofSize: 14)

            // Map each token index to its site index (if any)
            var tokenToSite: [Int: Int] = [:]
            for (siteIdx, site) in sites.enumerated() {
                for t in site.tokenStart..<site.tokenEnd {
                    tokenToSite[t] = siteIdx
                }
            }

            for (tokenIdx, token) in tokens.enumerated() {
                let isSelected = tokenToSite[tokenIdx] == selectedSiteIndex

                switch token {
                case .unchanged(let s):
                    attributed.append(NSAttributedString(string: s, attributes: [
                        .font: baseFont,
                        .foregroundColor: NSColor.textColor,
                        kIsRemoved: false
                    ]))

                case .removed(let s):
                    if isSelected {
                        attributed.append(NSAttributedString(string: s, attributes: [
                            .font: baseFont,
                            .foregroundColor: NSColor.white,
                            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                            .backgroundColor: NSColor.systemRed,
                            kIsRemoved: true
                        ]))
                    } else {
                        attributed.append(NSAttributedString(string: s, attributes: [
                            .font: baseFont,
                            .foregroundColor: NSColor.systemRed,
                            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                            .backgroundColor: NSColor.systemRed.withAlphaComponent(0.1),
                            kIsRemoved: true
                        ]))
                    }

                case .added(let s):
                    if isSelected {
                        attributed.append(NSAttributedString(string: s, attributes: [
                            .font: baseFont,
                            .foregroundColor: NSColor.white,
                            .backgroundColor: NSColor.systemGreen,
                            kIsRemoved: false
                        ]))
                    } else {
                        attributed.append(NSAttributedString(string: s, attributes: [
                            .font: baseFont,
                            .foregroundColor: NSColor.systemGreen,
                            .backgroundColor: NSColor.systemGreen.withAlphaComponent(0.1),
                            kIsRemoved: false
                        ]))
                    }
                }
            }
            return attributed
        }

        // MARK: Command handling

        func handleCommand(_ cmd: DiffNSTextView.Command) {
            switch cmd {
            case .nextSite:
                guard !sites.isEmpty else { return }
                if let idx = selectedSiteIndex {
                    selectedSiteIndex = min(idx + 1, sites.count - 1)
                } else {
                    selectedSiteIndex = 0
                }
                applyDiff()
                scrollToSelectedSite()

            case .prevSite:
                guard !sites.isEmpty else { return }
                if let idx = selectedSiteIndex {
                    selectedSiteIndex = max(idx - 1, 0)
                } else {
                    selectedSiteIndex = sites.count - 1
                }
                applyDiff()
                scrollToSelectedSite()

            case .acceptSite:
                guard let idx = selectedSiteIndex, idx < sites.count else { return }
                acceptSiteAt(idx)

            case .rejectSite:
                guard let idx = selectedSiteIndex, idx < sites.count else { return }
                rejectSiteAt(idx)
            }
        }

        private func scrollToSelectedSite() {
            guard let idx = selectedSiteIndex, idx < sites.count, let textView = textView else { return }
            textView.scrollRangeToVisible(sites[idx].displayRange)
        }

        // MARK: Accept / Reject individual site

        private func acceptSiteAt(_ index: Int) {
            let site = sites[index]

            // Accept: update oldText so this site's removed content is replaced with added content
            // Reconstruct oldText: unchanged → keep, removed → keep (except at this site), added → skip (except at this site)
            var newOld = ""
            for (i, token) in tokens.enumerated() {
                let inSite = i >= site.tokenStart && i < site.tokenEnd
                switch token {
                case .unchanged(let s):
                    newOld += s
                case .removed(let s):
                    if !inSite { newOld += s }
                    // At this site: skip removed (old) text
                case .added(let s):
                    if inSite { newOld += s }
                    // Outside this site: skip added (not part of old)
                }
            }

            currentOldText = newOld
            // newText stays the same

            adjustSelectionAfterSiteRemoval(removedIndex: index)

            isInternalEdit = true
            oldTextBinding?.wrappedValue = newOld
            applyDiff()
            scrollToSelectedSite()
            isInternalEdit = false
        }

        private func rejectSiteAt(_ index: Int) {
            let site = sites[index]

            // Reject: update newText so this site's added content is replaced with removed content
            // Reconstruct newText: unchanged → keep, added → keep (except at this site), removed → skip (except at this site)
            var newNew = ""
            for (i, token) in tokens.enumerated() {
                let inSite = i >= site.tokenStart && i < site.tokenEnd
                switch token {
                case .unchanged(let s):
                    newNew += s
                case .added(let s):
                    if !inSite { newNew += s }
                    // At this site: skip added (new) text
                case .removed(let s):
                    if inSite { newNew += s }
                    // Outside this site: skip removed (not part of new)
                }
            }

            currentNewText = newNew
            // oldText stays the same

            adjustSelectionAfterSiteRemoval(removedIndex: index)

            isInternalEdit = true
            newTextBinding?.wrappedValue = newNew
            applyDiff()
            scrollToSelectedSite()
            isInternalEdit = false
        }

        /// After removing a site, adjust selectedSiteIndex to point at the next logical site.
        private func adjustSelectionAfterSiteRemoval(removedIndex: Int) {
            let remainingSites = sites.count - 1
            if remainingSites <= 0 {
                selectedSiteIndex = nil
            } else if removedIndex >= remainingSites {
                // Was at or past the last remaining site → select the new last
                selectedSiteIndex = remainingSites - 1
            }
            // Otherwise selectedSiteIndex stays the same (the next site shifts into this index)
        }

        // MARK: NSTextViewDelegate

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            if isApplyingDiff { return true }
            guard let storage = textView.textStorage else { return true }

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

            var extracted = ""
            storage.enumerateAttribute(kIsRemoved, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                if (value as? Bool) != true {
                    let s = storage.string as NSString
                    extracted += s.substring(with: range)
                }
            }

            currentNewText = extracted
            selectedSiteIndex = nil  // Clear site selection on manual edit

            isInternalEdit = true
            newTextBinding?.wrappedValue = extracted
            applyDiff()
            isInternalEdit = false
        }

        // MARK: Cursor helpers

        private func isInsideRemovedRun(at pos: Int, in storage: NSTextStorage) -> Bool {
            var effectiveRange = NSRange()
            let val = storage.attribute(kIsRemoved, at: pos, effectiveRange: &effectiveRange) as? Bool ?? false
            if !val { return false }
            return pos > effectiveRange.location
        }

        private func cursorOffsetInNewText() -> Int {
            guard let storage = textView?.textStorage else { return 0 }
            let cursorPos = textView?.selectedRange().location ?? 0
            var newOffset = 0
            storage.enumerateAttribute(kIsRemoved, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
                let isRemoved = (value as? Bool) ?? false
                let relevantEnd = min(range.location + range.length, cursorPos)
                if relevantEnd > range.location && !isRemoved {
                    newOffset += relevantEnd - range.location
                }
                if range.location >= cursorPos {
                    stop.pointee = true
                }
            }
            return newOffset
        }

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
    }
}
