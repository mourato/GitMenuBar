@testable import GitMenuBar
import XCTest

final class AgentProjectActivityLeadTests: XCTestCase {
    func testRunningAgentLeadsOverAnEarlierRecentOne() {
        let recent = AgentProjectActivity(harness: .codex, status: .recent(Date()))
        let running = AgentProjectActivity(harness: .claudeCode, status: .running)
        XCTAssertEqual(AgentProjectActivity.lead(in: [recent, running]), running)
    }

    func testFirstAgentLeadsWhenNoneRuns() {
        let first = AgentProjectActivity(harness: .codex, status: .recent(Date()))
        let second = AgentProjectActivity(harness: .opencode, status: .recent(Date()))
        XCTAssertEqual(AgentProjectActivity.lead(in: [first, second]), first)
    }

    func testNoAgentsHaveNoLead() {
        XCTAssertNil(AgentProjectActivity.lead(in: []))
    }
}
