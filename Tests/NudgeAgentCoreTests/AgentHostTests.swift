import Testing
@testable import NudgeAgentCore

struct AgentHostTests {
    @Test
    func conductorRunsManySessions() {
        #expect(AgentHost(appName: "Conductor", bundleID: "com.conductor.app").runsManySessions)
    }

    @Test
    func terminalsAndUnknownHostsDoNotRunManySessions() {
        #expect(!AgentHost(appName: "Terminal", bundleID: "com.apple.Terminal").runsManySessions)
        #expect(!AgentHost(appName: "Visual Studio Code", bundleID: "com.microsoft.VSCode").runsManySessions)
        #expect(!AgentHost(appName: "Unknown terminal").runsManySessions)
    }
}
