import Foundation
import Logging

private let logger = Logger(label: "bridge.retry")

enum BridgeRetry {
    static let maxRetries = 10

    static func delay(forAttempt attempt: Int) -> Int {
        min(2 * (attempt + 1), 10)
    }

    static func execute(
        maxRetries: Int = BridgeRetry.maxRetries,
        delayNanoseconds: @Sendable (Int) -> UInt64 = { attempt in UInt64(BridgeRetry.delay(forAttempt: attempt)) * 1_000_000_000 },
        shouldContinue: @Sendable () -> Bool,
        operation: @Sendable () async throws -> Void
    ) async {
        for attempt in 0..<maxRetries {
            do {
                try await operation()
                return
            } catch {
                logger.error("bridge attempt \(attempt + 1)/\(maxRetries) failed: \(error)")

                guard attempt + 1 < maxRetries else {
                    logger.error("bridge failed after \(maxRetries) retries, giving up")
                    return
                }

                guard shouldContinue() else {
                    logger.info("retry cancelled")
                    return
                }

                let ns = delayNanoseconds(attempt)
                logger.info("retrying in \(ns / 1_000_000_000)s (attempt \(attempt + 1)/\(maxRetries))")
                try? await Task.sleep(nanoseconds: ns)
            }
        }
    }
}
