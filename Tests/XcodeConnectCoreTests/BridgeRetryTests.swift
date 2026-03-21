import XCTest
@testable import XcodeConnectCore

final class BridgeRetryTests: XCTestCase {

    private let noDelay: @Sendable (Int) -> UInt64 = { _ in 0 }

    func testDelayCalculation() {
        XCTAssertEqual(BridgeRetry.delay(forAttempt: 0), 2)
        XCTAssertEqual(BridgeRetry.delay(forAttempt: 1), 4)
        XCTAssertEqual(BridgeRetry.delay(forAttempt: 2), 6)
        XCTAssertEqual(BridgeRetry.delay(forAttempt: 3), 8)
        XCTAssertEqual(BridgeRetry.delay(forAttempt: 4), 10)
        XCTAssertEqual(BridgeRetry.delay(forAttempt: 5), 10)
        XCTAssertEqual(BridgeRetry.delay(forAttempt: 99), 10)
    }

    func testSucceedsOnFirstAttempt() async {
        let counter = AtomicCounter()
        await BridgeRetry.execute(
            maxRetries: 3,
            delayNanoseconds: noDelay,
            shouldContinue: { true },
            operation: { counter.increment() }
        )
        XCTAssertEqual(counter.value, 1)
    }

    func testRetriesUntilSuccess() async {
        let counter = AtomicCounter()
        await BridgeRetry.execute(
            maxRetries: 5,
            delayNanoseconds: noDelay,
            shouldContinue: { true },
            operation: {
                let n = counter.increment()
                if n < 3 { throw RetryTestError.fail }
            }
        )
        XCTAssertEqual(counter.value, 3)
    }

    func testGivesUpAfterMaxRetries() async {
        let counter = AtomicCounter()
        await BridgeRetry.execute(
            maxRetries: 3,
            delayNanoseconds: noDelay,
            shouldContinue: { true },
            operation: {
                counter.increment()
                throw RetryTestError.fail
            }
        )
        XCTAssertEqual(counter.value, 3)
    }

    func testStopsWhenShouldContinueReturnsFalse() async {
        let counter = AtomicCounter()
        await BridgeRetry.execute(
            maxRetries: 10,
            delayNanoseconds: noDelay,
            shouldContinue: { counter.value < 2 },
            operation: {
                counter.increment()
                throw RetryTestError.fail
            }
        )
        XCTAssertEqual(counter.value, 2)
    }

    func testSingleMaxRetry() async {
        let counter = AtomicCounter()
        await BridgeRetry.execute(
            maxRetries: 1,
            delayNanoseconds: noDelay,
            shouldContinue: { true },
            operation: {
                counter.increment()
                throw RetryTestError.fail
            }
        )
        XCTAssertEqual(counter.value, 1)
    }

    // MARK: - AdapterServer.shutdown stops retry

    func testShutdownStopsRetryViaShouldContinue() async {
        let counter = AtomicCounter()
        let shouldRun = AtomicFlag(true)

        await BridgeRetry.execute(
            maxRetries: 10,
            delayNanoseconds: noDelay,
            shouldContinue: { shouldRun.value },
            operation: {
                let n = counter.increment()
                if n == 2 { shouldRun.set(false) }
                throw RetryTestError.fail
            }
        )
        XCTAssertEqual(counter.value, 2)
    }

    // MARK: - MCPBridgeClient auto-restart state

    func testStopResetsHasStartedOnce() async {
        let client = MCPBridgeClient()
        do {
            try await client.callTool(name: "test", arguments: [:])
        } catch {
            XCTAssertTrue(error is BridgeError)
        }
        client.stop()
        do {
            try await client.callTool(name: "test", arguments: [:])
        } catch let error as BridgeError {
            XCTAssertEqual(error.errorDescription, "Bridge process not running")
        } catch {
            XCTFail("Expected BridgeError.notRunning, got \(error)")
        }
    }
}

private enum RetryTestError: Error {
    case fail
}

private final class AtomicCounter: @unchecked Sendable {
    private var _value = 0
    private let lock = NSLock()

    var value: Int { lock.withLock { _value } }

    @discardableResult
    func increment() -> Int {
        lock.withLock { _value += 1; return _value }
    }
}

private final class AtomicFlag: @unchecked Sendable {
    private var _value: Bool
    private let lock = NSLock()

    init(_ initial: Bool) { _value = initial }

    var value: Bool { lock.withLock { _value } }

    func set(_ v: Bool) { lock.withLock { _value = v } }
}
