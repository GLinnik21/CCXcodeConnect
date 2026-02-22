import Foundation
import IDEAdapterCore
import Logging

LoggingSystem.bootstrap { StreamLogHandler.standardError(label: $0) }

let workspacePath: String? = {
    let args = CommandLine.arguments
    guard let idx = args.firstIndex(of: "--workspace"), idx + 1 < args.count else { return nil }
    return args[idx + 1]
}()

signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)

if let workspacePath {
    let server = AdapterServer(targetWorkspace: workspacePath)
    server.onStateChange = { state in
        var parts: [String] = []
        parts.append("Xcode: \(state.xcodeRunning ? "running" : "not running")")
        parts.append("Claude: \(state.claudeConnected ? "connected" : "disconnected")")
        if let pid = state.connectedPID {
            parts.append("PID: \(pid)")
        }
        if let ws = state.workspaceName {
            parts.append("Workspace: \(ws)")
        }
        print(parts.joined(separator: " | "))
    }

    let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    sigintSource.setEventHandler {
        server.shutdown()
        CFRunLoopStop(CFRunLoopGetMain())
    }
    sigintSource.resume()

    let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    sigtermSource.setEventHandler {
        server.shutdown()
        CFRunLoopStop(CFRunLoopGetMain())
    }
    sigtermSource.resume()

    Task {
        do {
            let port = try await server.start()
            print("Server started on port \(port) for workspace: \(workspacePath)")
        } catch {
            print("Failed to start: \(error)")
            CFRunLoopStop(CFRunLoopGetMain())
        }
    }

    CFRunLoopRun()
    server.shutdown()
} else {
    let supervisor = AdapterSupervisor()
    supervisor.onStateChange = { states in
        if states.isEmpty {
            print("Xcode: not running")
            return
        }
        for state in states {
            var parts: [String] = []
            parts.append("Xcode: \(state.xcodeRunning ? "running" : "not running")")
            parts.append("Claude: \(state.claudeConnected ? "connected" : "disconnected")")
            if let pid = state.connectedPID {
                parts.append("PID: \(pid)")
            }
            if let ws = state.workspaceName {
                parts.append("Workspace: \(ws)")
            }
            if let port = state.port {
                parts.append("Port: \(port)")
            }
            print(parts.joined(separator: " | "))
        }
    }

    let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    sigintSource.setEventHandler {
        supervisor.shutdown()
        CFRunLoopStop(CFRunLoopGetMain())
    }
    sigintSource.resume()

    let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    sigtermSource.setEventHandler {
        supervisor.shutdown()
        CFRunLoopStop(CFRunLoopGetMain())
    }
    sigtermSource.resume()

    supervisor.start()
    print("Supervisor started (multi-workspace mode)")

    CFRunLoopRun()
    supervisor.shutdown()
}
