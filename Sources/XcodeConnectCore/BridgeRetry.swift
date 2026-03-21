import Foundation
import Logging

private let logger = Logger(label: "bridge.retry")

enum BridgeRetry {
    static func delay(forAttempt attempt: Int, maxDelay: Int = 10) -> Int {
        min(2 * (attempt + 1), maxDelay)
    }

    static func execute(
        settings: AdapterSettingsProviding,
        shouldContinue: @Sendable () -> Bool,
        operation: @Sendable () async throws -> Void
    ) async {
        await execute(
            maxRetries: settings.bridgeMaxRetries,
            delayNanoseconds: { attempt in UInt64(delay(forAttempt: attempt, maxDelay: settings.bridgeMaxRetryDelay)) * 1_000_000_000 },
            shouldContinue: shouldContinue,
            operation: operation
        )
    }

    static func execute(
        maxRetries: Int,
        delayNanoseconds: @Sendable (Int) -> UInt64,
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
