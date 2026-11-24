import Foundation
import Testing
@testable import NudgeAgentCore

struct ExpectedActivationTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    @Test
    func expectedAppIsConsumedOnceThenForgotten() {
        var expected = ExpectedActivation()
        expected.expect(processIdentifier: 42, at: start)

        let first = expected.consume(processIdentifier: 42, at: start.addingTimeInterval(0.5))
        let second = expected.consume(processIdentifier: 42, at: start.addingTimeInterval(0.6))

        #expect(first)
        #expect(!second)
    }

    @Test
    func otherAppsDoNotConsumeOrClearTheExpectation() {
        var expected = ExpectedActivation()
        expected.expect(processIdentifier: 42, at: start)

        let other = expected.consume(processIdentifier: 7, at: start.addingTimeInterval(0.1))
        let expectedApp = expected.consume(processIdentifier: 42, at: start.addingTimeInterval(0.2))

        #expect(!other)
        #expect(expectedApp)
    }

    @Test
    func expectationExpiresAfterTheWindowAndIsCleared() {
        var expected = ExpectedActivation()
        expected.expect(processIdentifier: 42, at: start)

        let late = expected.consume(processIdentifier: 42, at: start.addingTimeInterval(ExpectedActivation.window + 0.1))
        // Expired expectations are cleared, so an earlier time can't revive one.
        let revived = expected.consume(processIdentifier: 42, at: start.addingTimeInterval(0.1))

        #expect(!late)
        #expect(!revived)
    }

    @Test
    func expectationHoldsUpToTheWindow() {
        var expected = ExpectedActivation()
        expected.expect(processIdentifier: 42, at: start)

        let atTheEdge = expected.consume(processIdentifier: 42, at: start.addingTimeInterval(ExpectedActivation.window))

        #expect(atTheEdge)
    }

    @Test
    func laterExpectReplacesTheEarlierOne() {
        var expected = ExpectedActivation()
        expected.expect(processIdentifier: 42, at: start)
        expected.expect(processIdentifier: 7, at: start.addingTimeInterval(1))

        let replaced = expected.consume(processIdentifier: 42, at: start.addingTimeInterval(1.1))
        let replacement = expected.consume(processIdentifier: 7, at: start.addingTimeInterval(1.2))

        #expect(!replaced)
        #expect(replacement)
    }

    @Test
    func replacingTheExpectationRestartsTheWindow() {
        var expected = ExpectedActivation()
        expected.expect(processIdentifier: 42, at: start)
        expected.expect(processIdentifier: 42, at: start.addingTimeInterval(1.5))

        let consumed = expected.consume(
            processIdentifier: 42,
            at: start.addingTimeInterval(1.5 + ExpectedActivation.window - 0.1)
        )

        #expect(consumed)
    }

    @Test
    func nothingExpectedMeansNothingConsumed() {
        var expected = ExpectedActivation()

        let consumed = expected.consume(processIdentifier: 42, at: start)

        #expect(!consumed)
    }
}
