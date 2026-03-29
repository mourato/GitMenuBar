@testable import GitMenuBar
import XCTest

final class BranchMenuRowAdapterTests: XCTestCase {
    func testCurrentBranchAdapterDisablesDestructiveActions() {
        let adapter = BranchMenuRowAdapter(branchName: "main", currentBranchName: "main")

        XCTAssertTrue(adapter.isCurrentBranch)
        XCTAssertFalse(adapter.canMerge)
        XCTAssertFalse(adapter.canDelete)
        XCTAssertTrue(adapter.canRename)
    }

    func testNonCurrentBranchAdapterEnablesContextActions() {
        let adapter = BranchMenuRowAdapter(branchName: "feature", currentBranchName: "main")

        XCTAssertFalse(adapter.isCurrentBranch)
        XCTAssertTrue(adapter.canMerge)
        XCTAssertTrue(adapter.canDelete)
        XCTAssertTrue(adapter.canRename)
    }
}
