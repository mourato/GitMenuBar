@testable import GitMenuBar
import XCTest

final class ConventionalCommitSubjectTests: XCTestCase {
    func testParsePlainSubject() {
        let result = ConventionalCommitSubjectParser.parse("Update the README")

        XCTAssertEqual(result, ConventionalCommitSubject(type: nil, scope: nil, isBreaking: false, subject: "Update the README"))
    }

    func testParseFixPrefix() {
        let result = ConventionalCommitSubjectParser.parse("fix: keep the history list stable")

        XCTAssertEqual(result.type, "fix")
        XCTAssertNil(result.scope)
        XCTAssertFalse(result.isBreaking)
        XCTAssertEqual(result.subject, "keep the history list stable")
    }

    func testParseScopedFeaturePrefix() {
        let result = ConventionalCommitSubjectParser.parse("feat(history): show commit metadata")

        XCTAssertEqual(result.type, "feat")
        XCTAssertEqual(result.scope, "history")
        XCTAssertFalse(result.isBreaking)
        XCTAssertEqual(result.subject, "show commit metadata")
    }

    func testParseBreakingChangeMarker() {
        let result = ConventionalCommitSubjectParser.parse("feat!: change the history row")

        XCTAssertEqual(result.type, "feat")
        XCTAssertNil(result.scope)
        XCTAssertTrue(result.isBreaking)
        XCTAssertEqual(result.subject, "change the history row")

        let scopedResult = ConventionalCommitSubjectParser.parse("feat(history)!: change the history row")

        XCTAssertEqual(scopedResult.type, "feat")
        XCTAssertEqual(scopedResult.scope, "history")
        XCTAssertTrue(scopedResult.isBreaking)
        XCTAssertEqual(scopedResult.subject, "change the history row")
    }

    func testTreatMergeSubjectAsPlainText() {
        let result = ConventionalCommitSubjectParser.parse("Merge branch 'feature/history'")

        XCTAssertEqual(result, ConventionalCommitSubject(type: nil, scope: nil, isBreaking: false, subject: "Merge branch 'feature/history'"))
    }

    func testKeepColonsInsideTheSubject() {
        let result = ConventionalCommitSubjectParser.parse("fix: preserve URLs: https://example.com")

        XCTAssertEqual(result.type, "fix")
        XCTAssertNil(result.scope)
        XCTAssertFalse(result.isBreaking)
        XCTAssertEqual(result.subject, "preserve URLs: https://example.com")
    }

    func testUnknownTypeRemainsAvailableForPlainTextRendering() {
        let result = ConventionalCommitSubjectParser.parse("release: prepare the next version")

        XCTAssertEqual(result.type, "release")
        XCTAssertFalse(ConventionalCommitSubjectParser.isKnownType(result.type ?? ""))
        XCTAssertEqual(result.subject, "prepare the next version")
    }

    func testEmptySubjectRemainsParsedButCanFallBackToTheRawMessage() {
        let result = ConventionalCommitSubjectParser.parse("fix:")

        XCTAssertEqual(result.type, "fix")
        XCTAssertNil(result.scope)
        XCTAssertFalse(result.isBreaking)
        XCTAssertEqual(result.subject, "")
    }
}
