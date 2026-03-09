import XCTest
@testable import Wordie

final class DiffEngineTests: XCTestCase {

    // MARK: - tokenize

    func testTokenizeEmpty() {
        XCTAssertEqual(DiffEngine.tokenize(""), [])
    }

    func testTokenizeSingleWord() {
        XCTAssertEqual(DiffEngine.tokenize("hello"), ["hello"])
    }

    func testTokenizeWordAndSpace() {
        XCTAssertEqual(DiffEngine.tokenize("hello world"), ["hello", " ", "world"])
    }

    func testTokenizeLeadingAndTrailingSpace() {
        XCTAssertEqual(DiffEngine.tokenize(" hi "), [" ", "hi", " "])
    }

    func testTokenizeMultipleSpaces() {
        XCTAssertEqual(DiffEngine.tokenize("a  b"), ["a", "  ", "b"])
    }

    // MARK: - diff (basic)

    func testDiffIdentical() {
        let tokens = DiffEngine.diff(old: "hello", new: "hello")
        XCTAssertEqual(tokens.count, 1)
        if case .unchanged(let s) = tokens[0] { XCTAssertEqual(s, "hello") }
        else { XCTFail("Expected unchanged") }
    }

    func testDiffSingleWordChange() {
        let tokens = DiffEngine.diff(old: "cat", new: "dog")
        let kinds = tokens.map { kindString($0) }
        XCTAssertTrue(kinds.contains("removed:cat"))
        XCTAssertTrue(kinds.contains("added:dog"))
        XCTAssertFalse(kinds.contains(where: { $0.hasPrefix("unchanged") }))
    }

    func testDiffPrefixSuffix() {
        let tokens = DiffEngine.diff(old: "I like cats", new: "I like dogs")
        let kinds = tokens.map { kindString($0) }
        XCTAssertTrue(kinds.contains("unchanged:I"))
        XCTAssertTrue(kinds.contains("unchanged: "))
        XCTAssertTrue(kinds.contains("unchanged:like"))
        XCTAssertTrue(kinds.contains("removed:cats"))
        XCTAssertTrue(kinds.contains("added:dogs"))
    }

    // MARK: - buildSitePlans: basic

    func testNoSitesWhenIdentical() {
        let tokens = DiffEngine.diff(old: "hello world", new: "hello world")
        let sites = DiffEngine.buildSitePlans(from: tokens)
        XCTAssertEqual(sites.count, 0)
    }

    func testSingleSiteForOneWordChange() {
        let tokens = DiffEngine.diff(old: "I like cats", new: "I like dogs")
        let sites = DiffEngine.buildSitePlans(from: tokens)
        XCTAssertEqual(sites.count, 1)
        XCTAssertEqual(sites[0].oldContent, "cats")
        XCTAssertEqual(sites[0].newContent, "dogs")
    }

    // MARK: - buildSitePlans: merging

    func testAdjacentWordChangesAreMergedAcrossSpace() {
        // "old1 old2" → "new1 new2": both words change, separated by a space that is unchanged.
        // The two sites should be merged into one.
        let tokens = DiffEngine.diff(old: "foo bar", new: "baz qux")
        let sites = DiffEngine.buildSitePlans(from: tokens)
        XCTAssertEqual(sites.count, 1, "Two adjacent word-changes separated by a space should merge into one site")
        XCTAssertEqual(sites[0].oldContent, "foo bar")
        XCTAssertEqual(sites[0].newContent, "baz qux")
    }

    func testCapitalizeEveryWord() {
        // The real-world failure case: every word gets capitalized.
        let old = "been going pretty good overall"
        let new = "Been Going Pretty Good Overall"
        let tokens = DiffEngine.diff(old: old, new: new)
        let sites = DiffEngine.buildSitePlans(from: tokens)
        XCTAssertEqual(sites.count, 1,
            "All capitalized-word changes separated only by spaces should merge into a single site")
        XCTAssertEqual(sites[0].oldContent, "been going pretty good overall")
        XCTAssertEqual(sites[0].newContent, "Been Going Pretty Good Overall")
    }

    func testUnchangedFirstWordThenAllChange() {
        // "I going pretty" → "I Going Pretty": "I" is unchanged, rest capitalize.
        let tokens = DiffEngine.diff(old: "I going pretty", new: "I Going Pretty")
        let sites = DiffEngine.buildSitePlans(from: tokens)
        XCTAssertEqual(sites.count, 1,
            "Changes after an unchanged prefix should still merge into one site")
        XCTAssertEqual(sites[0].oldContent, "going pretty")
        XCTAssertEqual(sites[0].newContent, "Going Pretty")
    }

    func testSitesNotMergedAcrossNewline() {
        // Two changes separated by a newline should NOT be merged.
        let old = "foo\nbar"
        let new = "baz\nqux"
        let tokens = DiffEngine.diff(old: old, new: new)
        let sites = DiffEngine.buildSitePlans(from: tokens)
        XCTAssertEqual(sites.count, 2,
            "Changes separated by a newline should remain as separate sites")
    }

    func testSitesNotMergedAcrossUnchangedWord() {
        // "old1 SAME old2" → "new1 SAME new2": gap contains an unchanged word, not just whitespace.
        let old = "red SAME blue"
        let new = "green SAME purple"
        let tokens = DiffEngine.diff(old: old, new: new)
        let sites = DiffEngine.buildSitePlans(from: tokens)
        XCTAssertEqual(sites.count, 2,
            "Changes separated by an unchanged word should remain as separate sites")
        XCTAssertEqual(sites[0].oldContent, "red")
        XCTAssertEqual(sites[0].newContent, "green")
        XCTAssertEqual(sites[1].oldContent, "blue")
        XCTAssertEqual(sites[1].newContent, "purple")
    }

    func testMergePreservesCorrectContent() {
        // Verify that oldContent/newContent include the bridging whitespace
        let tokens = DiffEngine.diff(old: "a b", new: "x y")
        let sites = DiffEngine.buildSitePlans(from: tokens)
        XCTAssertEqual(sites.count, 1)
        // The merged site's old/new content should include the space
        XCTAssertEqual(sites[0].oldContent, "a b")
        XCTAssertEqual(sites[0].newContent, "x y")
    }

    func testMergedSiteContentIncludesSpaces() {
        // Block rendering relies on oldContent/newContent already containing the bridging
        // whitespace. This test would catch a regression where spaces are stripped out,
        // which would cause "been going..." to render as "beengoing..." in the display.
        let sites = DiffEngine.buildSitePlans(from: DiffEngine.diff(
            old: "been going pretty good overall",
            new: "Been Going Pretty Good Overall"))
        XCTAssertEqual(sites.count, 1)
        XCTAssertTrue(sites[0].oldContent.contains(" "),
            "oldContent must include spaces so block rendering shows 'been going...' not 'beengoing...'")
        XCTAssertTrue(sites[0].newContent.contains(" "),
            "newContent must include spaces so block rendering shows 'Been Going...' not 'BeenGoing...'")
        XCTAssertEqual(sites[0].oldContent, "been going pretty good overall")
        XCTAssertEqual(sites[0].newContent, "Been Going Pretty Good Overall")
    }

    // MARK: - Helpers

    private func kindString(_ token: DiffToken) -> String {
        switch token {
        case .unchanged(let s): return "unchanged:\(s)"
        case .added(let s):     return "added:\(s)"
        case .removed(let s):   return "removed:\(s)"
        }
    }
}
