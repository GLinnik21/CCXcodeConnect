import Foundation
import Logging
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOWebSocket
import NIOFoundationCompat

private let logger = Logger(label: "ws")

public final class WebSocketServer: @unchecked Sendable {
    private let authToken: String
    private let group: MultiThreadedEventLoopGroup
    private var channel: Channel?
    private var clientChannels: [ObjectIdentifier: Channel] = [:]
    private var stopped = false
    public var requestHandler = MCPRequestHandler()
    public var toolRouter: MCPToolRouter? {
        get { requestHandler.toolRouter }
        set { requestHandler.toolRouter = newValue }
    }
    public var onClientConnected: (() -> Void)?
    public var onClientDisconnected: (() -> Void)?
    public var onIdeConnected: ((Int32) -> Void)?

    private static let pingInterval: TimeInterval = 30
    private static let pongTimeout: TimeInterval = 60
    private var pingTimer: DispatchSourceTimer?
    private var lastPongTimes: [ObjectIdentifier: Date] = [:]
    private var lastPingScheduledTime: Date = Date()

    public var connectedClientCount: Int { clientChannels.count }

    public init(authToken: String) {
        self.authToken = authToken
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    public func start() async throws -> Int {
        let upgrader = NIOWebSocketServerUpgrader(
            shouldUpgrade: { [authToken] (channel, head) in
                let remote = channel.remoteAddress?.description ?? "?"
                let authHeader = head.headers["X-Claude-Code-Ide-Authorization"].first
                guard authHeader == authToken else {
                    logger.warning("upgrade rejected: bad auth from \(remote)")
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
                logger.info("listening on 127.0.0.1:\(port)")
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
        stopPingTimer()
        let clients = clientChannels.values
        let server = channel
        clientChannels.removeAll()
        lastPongTimes.removeAll()
        channel = nil
        for ch in clients { ch.close(promise: nil) }
        server?.close(promise: nil)
        group.shutdownGracefully { _ in }
    }

    public func sendNotification(_ notification: JSONRPCNotification) {
        guard !stopped else { return }
        guard let data = try? JSONEncoder().encode(notification) else { return }
        for (_, ch) in clientChannels {
            ch.eventLoop.execute {
                let buffer = ch.allocator.buffer(data: data)
                let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
                ch.writeAndFlush(frame, promise: nil)
            }
        }
    }

    private func startPingTimer() {
        guard pingTimer == nil else { return }
        lastPingScheduledTime = Date()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + Self.pingInterval, repeating: Self.pingInterval)
        timer.setEventHandler { [weak self] in
            self?.pingTick()
        }
        timer.resume()
        self.pingTimer = timer
    }

    private func stopPingTimer() {
        pingTimer?.cancel()
        pingTimer = nil
    }

    private func pingTick() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastPingScheduledTime)
        lastPingScheduledTime = now

        let isSleepWake = elapsed > Self.pingInterval * 1.5
        if isSleepWake {
            logger.info("sleep detected (\(Int(elapsed))s since last tick), resetting pong timestamps")
        }

        var timedOut: [ObjectIdentifier] = []
        for (id, lastPong) in lastPongTimes {
            if isSleepWake {
                lastPongTimes[id] = now
            } else if now.timeIntervalSince(lastPong) > Self.pongTimeout {
                timedOut.append(id)
            }
        }

        for id in timedOut {
            if let ch = clientChannels.removeValue(forKey: id) {
                lastPongTimes.removeValue(forKey: id)
                logger.warning("pong timeout, closing client \(ch.remoteAddress?.description ?? "?")")
                ch.close(promise: nil)
            }
        }

        if !timedOut.isEmpty && clientChannels.isEmpty {
            stopPingTimer()
            onClientDisconnected?()
        }

        for (_, ch) in clientChannels {
            ch.eventLoop.execute {
                let emptyBuffer = ch.allocator.buffer(capacity: 0)
                let frame = WebSocketFrame(fin: true, opcode: .ping, data: emptyBuffer)
                ch.writeAndFlush(frame, promise: nil)
            }
        }
    }

    fileprivate func handlePong(_ channel: Channel) {
        lastPongTimes[ObjectIdentifier(channel)] = Date()
    }

    fileprivate func handleConnected(_ channel: Channel) {
        let wasEmpty = clientChannels.isEmpty
        let id = ObjectIdentifier(channel)
        logger.info("client connected: \(channel.remoteAddress?.description ?? "?") (total: \(clientChannels.count + 1))")
        clientChannels[id] = channel
        lastPongTimes[id] = Date()
        startPingTimer()
        if wasEmpty {
            onClientConnected?()
        }
    }

    fileprivate func handleDisconnected(_ channel: Channel) {
        let id = ObjectIdentifier(channel)
        guard clientChannels.removeValue(forKey: id) != nil else { return }
        lastPongTimes.removeValue(forKey: id)
        logger.info("client disconnected (remaining: \(clientChannels.count))")
        if clientChannels.isEmpty {
            stopPingTimer()
            onClientDisconnected?()
        }
    }

    fileprivate func handleMessage(_ text: String, from senderChannel: Channel) {
        guard let data = text.data(using: .utf8) else {
            logger.error("ws: received non-UTF8 message, dropping")
            return
        }

        let decoder = JSONDecoder()
        guard let request = try? decoder.decode(JSONRPCRequest.self, from: data) else {
            let preview = String(text.prefix(200))
            logger.warning("ws: failed to decode JSON-RPC request: \(preview)")
            return
        }

        let idStr = request.id.map { "\($0)" } ?? "nil"
        if request.method == "tools/call",
           let name = request.params?["name"]?.stringValue {
            logger.info("req tools/call \(name) id=\(idStr)")
        } else {
            logger.info("req \(request.method) id=\(idStr)")
        }

        if request.method == "ide_connected", request.id == nil,
           let pid = request.params?["pid"]?.intValue {
            logger.info("ide_connected: Claude Code PID=\(pid)")
            onIdeConnected?(Int32(pid))
        }

        Task {
            let response = await handleRequest(request)
            if let resp = response {
                if let err = resp.error {
                    logger.warning("res error id=\(idStr): \(err.message)")
                } else {
                    logger.info("res ok id=\(idStr)")
                }
                self.sendResponse(resp, to: senderChannel)
            }
        }
    }

    private func handleRequest(_ request: JSONRPCRequest) async -> JSONRPCResponse? {
        await requestHandler.handleRequest(request)
    }

    private func sendResponse(_ response: JSONRPCResponse, to channel: Channel) {
        guard let data = try? JSONEncoder().encode(response) else { return }
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
    private var didNotifyConnect = false
    private var didNotifyDisconnect = false

    init(server: WebSocketServer) {
        self.server = server
    }

    func handlerAdded(context: ChannelHandlerContext) {
        if context.channel.isActive, !didNotifyConnect {
            didNotifyConnect = true
            server?.handleConnected(context.channel)
        }
    }

    func channelActive(context: ChannelHandlerContext) {
        guard !didNotifyConnect else { return }
        didNotifyConnect = true
        server?.handleConnected(context.channel)
    }

    func channelInactive(context: ChannelHandlerContext) {
        guard !didNotifyDisconnect else { return }
        didNotifyDisconnect = true
        server?.handleDisconnected(context.channel)
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        guard !didNotifyDisconnect else { return }
        didNotifyDisconnect = true
        server?.handleDisconnected(context.channel)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)

        switch frame.opcode {
        case .text:
            var data = frame.unmaskedData
            let text = data.readString(length: data.readableBytes) ?? ""
            if frame.fin {
                if textBuffer.isEmpty {
                    server?.handleMessage(text, from: context.channel)
                } else {
                    textBuffer += text
                    server?.handleMessage(textBuffer, from: context.channel)
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
                server?.handleMessage(textBuffer, from: context.channel)
                textBuffer = ""
            }

        case .ping:
            let pong = WebSocketFrame(fin: true, opcode: .pong, data: frame.unmaskedData)
            context.writeAndFlush(wrapOutboundOut(pong), promise: nil)

        case .pong:
            server?.handlePong(context.channel)

        case .connectionClose:
            logger.info("ws: received connection close frame")
            let close = WebSocketFrame(fin: true, opcode: .connectionClose, data: context.channel.allocator.buffer(capacity: 0))
            context.writeAndFlush(wrapOutboundOut(close)).whenComplete { _ in
                context.close(promise: nil)
            }

        default:
            logger.warning("ws: unrecognized frame opcode: \(frame.opcode)")
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        logger.error("ws: channel error: \(error)")
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
