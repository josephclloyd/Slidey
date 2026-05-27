import Combine
import XCTest
@testable import Slidey

final class PendingOpensTests: XCTestCase {
    func testInitialStateIsNil() {
        let opens = PendingOpens()
        XCTAssertNil(opens.pending)
    }

    func testSendPublishesURL() {
        let opens = PendingOpens()
        let url = URL(fileURLWithPath: "/tmp/test")
        let expectation = expectation(description: "pending updated")

        let cancellable = opens.$pending
            .dropFirst()
            .sink { value in
                if value == url {
                    expectation.fulfill()
                }
            }

        opens.send(url)
        waitForExpectations(timeout: 1)
        _ = cancellable
    }
}
