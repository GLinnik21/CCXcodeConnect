import Foundation
import IDEAdapterCore

let server = AdapterServer()
server.onStateChange = { state in
    var parts: [String] = []
    parts.append("Xcode: \(state.xcodeRunning ? "running" : "not running")")
    parts.append("Claude: \(state.claudeConnected ? "connected" : "disconnected")")
    if let ws = state.workspaceName {
        parts.append("Workspace: \(ws)")
    }
    print(parts.joined(separator: " | "))
}

signal(SIGINT, SIG_IGN)
let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigintSource.setEventHandler {
    server.shutdown()
    CFRunLoopStop(CFRunLoopGetMain())
}
sigintSource.resume()

signal(SIGTERM, SIG_IGN)
let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigtermSource.setEventHandler {
    server.shutdown()
    CFRunLoopStop(CFRunLoopGetMain())
}
sigtermSource.resume()

Task {
    do {
        let port = try await server.start()
        print("Server started on port \(port)")
    } catch {
        print("Failed to start: \(error)")
        CFRunLoopStop(CFRunLoopGetMain())
    }
}

CFRunLoopRun()
server.shutdown()
