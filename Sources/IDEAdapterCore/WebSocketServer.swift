import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOWebSocket
import NIOFoundationCompat

public final class WebSocketServer: @unchecked Sendable {
    private let authToken: String
    private let group: MultiThreadedEventLoopGroup
    private var channel: Channel?
    private var clientChannel: Channel?
    private var stopped = false
    public var toolRouter: MCPToolRouter?
    public var onClientConnected: (() -> Void)?
    public var onClientDisconnected: (() -> Void)?

    public init(authToken: String) {
        self.authToken = authToken
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    public func start() async throws -> Int {
        let upgrader = NIOWebSocketServerUpgrader(
            shouldUpgrade: { [authToken] (channel, head) in
                let authHeader = head.headers["X-Claude-Code-Ide-Authorization"].first
                guard authHeader == authToken else {
                    return channel.eventLoop.makeFailedFuture(WebSocketError.authFailed)
                }
                var headers = HTTPHeaders()
                if let proto = head.headers["Sec-WebSocket-Protocol"].first {
                    headers.add(name: "Sec-WebSocket-Protocol", value: proto)
                }
                return channel.eventLoop.makeSucceededFuture(headers)
            },
            upgradePipelineHandler: { [weak self] channel, _ in
                guard let self else { return channel.eventLoop.makeSucceededFuture(()) }
                let handler = WebSocketHandler(server: self)
                return channel.pipeline.addHandler(handler)
            }
        )

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 16)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                let httpHandler = HTTPByteBufferRequestDecoder()
                let config: NIOHTTPServerUpgradeConfiguration = (
                    upgraders: [upgrader],
                    completionHandler: { ctx in
                        _ = ctx.pipeline.syncOperations.removeHandler(httpHandler)
                    }
                )
                return channel.pipeline.configureHTTPServerPipeline(withServerUpgrade: config).flatMap {
                    channel.pipeline.addHandler(httpHandler)
                }
            }

        var lastError: Error?
        for _ in 0..<10 {
            let port = Int.random(in: 10000...65535)
            do {
                let ch = try await bootstrap.bind(host: "127.0.0.1", port: port).get()
                self.channel = ch
                print("WebSocket server listening on 127.0.0.1:\(port)")
                return port
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError ?? WebSocketError.bindFailed
    }

    public func stop() {
        stopped = true
        let client = clientChannel
        let server = channel
        clientChannel = nil
        channel = nil
        client?.close(promise: nil)
        server?.close(promise: nil)
        group.shutdownGracefully { _ in }
    }

    public func sendNotification(_ notification: JSONRPCNotification) {
        guard !stopped, let channel = clientChannel else { return }
        guard let data = try? JSONEncoder().encode(notification) else { return }
        channel.eventLoop.execute {
            let buffer = channel.allocator.buffer(data: data)
            let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
            channel.writeAndFlush(frame, promise: nil)
        }
    }

    fileprivate func handleConnected(_ channel: Channel) {
        self.clientChannel = channel
        onClientConnected?()
    }

    fileprivate func handleDisconnected() {
        self.clientChannel = nil
        onClientDisconnected?()
    }

    fileprivate func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        let decoder = JSONDecoder()
        guard let request = try? decoder.decode(JSONRPCRequest.self, from: data) else { return }

        Task {
            let response = await handleRequest(request)
            if let resp = response {
                self.sendResponse(resp)
            }
        }
    }

    private func handleRequest(_ request: JSONRPCRequest) async -> JSONRPCResponse? {
        switch request.method {
        case "initialize":
            let result = MCPInitializeResult(
                protocolVersion: "2024-11-05",
                capabilities: MCPCapabilities(tools: MCPToolsCapability(listChanged: true)),
                serverInfo: MCPServerInfo(name: "xcode-ide-adapter", version: "1.0.0")
            )
            guard let encoded = try? JSONEncoder().encode(result),
                  let jsonValue = try? JSONDecoder().decode(JSONValue.self, from: encoded) else {
                return JSONRPCResponse(id: request.id, error: .internalError)
            }
            return JSONRPCResponse(id: request.id, result: jsonValue)

        case "notifications/initialized":
            return nil

        case "tools/list":
            guard let router = toolRouter else {
                return JSONRPCResponse(id: request.id, result: .object(["tools": .array([])]))
            }
            let tools = router.listTools()
            guard let encoded = try? JSONEncoder().encode(tools),
                  let jsonArray = try? JSONDecoder().decode(JSONValue.self, from: encoded) else {
                return JSONRPCResponse(id: request.id, result: .object(["tools": .array([])]))
            }
            return JSONRPCResponse(id: request.id, result: .object(["tools": jsonArray]))

        case "tools/call":
            guard let router = toolRouter,
                  let params = request.params?.objectValue,
                  let name = params["name"]?.stringValue else {
                return JSONRPCResponse(id: request.id, error: .invalidParams("Missing tool name"))
            }
            let arguments = params["arguments"]?.objectValue ?? [:]
            let result = await router.callTool(name: name, arguments: arguments)
            guard let encoded = try? JSONEncoder().encode(result),
                  let jsonValue = try? JSONDecoder().decode(JSONValue.self, from: encoded) else {
                return JSONRPCResponse(id: request.id, error: .internalError)
            }
            return JSONRPCResponse(id: request.id, result: jsonValue)

        case "ping":
            return JSONRPCResponse(id: request.id, result: .object([:]))

        default:
            if request.method.starts(with: "notifications/") {
                return nil
            }
            return JSONRPCResponse(id: request.id, error: .methodNotFound)
        }
    }

    private func sendResponse(_ response: JSONRPCResponse) {
        guard let channel = clientChannel,
              let data = try? JSONEncoder().encode(response) else { return }
        channel.eventLoop.execute {
            let buffer = channel.allocator.buffer(data: data)
            let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
            channel.writeAndFlush(frame, promise: nil)
        }
    }
}

private final class WebSocketHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    private weak var server: WebSocketServer?
    private var textBuffer = ""

    init(server: WebSocketServer) {
        self.server = server
    }

    func handlerAdded(context: ChannelHandlerContext) {
        if context.channel.isActive {
            server?.handleConnected(context.channel)
        }
    }

    func channelActive(context: ChannelHandlerContext) {
        server?.handleConnected(context.channel)
    }

    func channelInactive(context: ChannelHandlerContext) {
        server?.handleDisconnected()
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        server?.handleDisconnected()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)

        switch frame.opcode {
        case .text:
            var data = frame.unmaskedData
            let text = data.readString(length: data.readableBytes) ?? ""
            if frame.fin {
                if textBuffer.isEmpty {
                    server?.handleMessage(text)
                } else {
                    textBuffer += text
                    server?.handleMessage(textBuffer)
                    textBuffer = ""
                }
            } else {
                textBuffer += text
            }

        case .continuation:
            var data = frame.unmaskedData
            let text = data.readString(length: data.readableBytes) ?? ""
            textBuffer += text
            if frame.fin {
                server?.handleMessage(textBuffer)
                textBuffer = ""
            }

        case .ping:
            let pong = WebSocketFrame(fin: true, opcode: .pong, data: frame.unmaskedData)
            context.writeAndFlush(wrapOutboundOut(pong), promise: nil)

        case .connectionClose:
            let close = WebSocketFrame(fin: true, opcode: .connectionClose, data: context.channel.allocator.buffer(capacity: 0))
            context.writeAndFlush(wrapOutboundOut(close)).whenComplete { _ in
                context.close(promise: nil)
            }

        default:
            break
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}

private final class HTTPByteBufferRequestDecoder: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        if case .head(let head) = part {
            if head.uri != "/" && head.uri != "/mcp" {
                let response = HTTPResponseHead(version: head.version, status: .notFound)
                context.write(wrapOutboundOut(.head(response)), promise: nil)
                context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
            }
        }
    }
}

public enum WebSocketError: Error {
    case authFailed
    case bindFailed
}
