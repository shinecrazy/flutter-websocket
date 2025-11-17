import Flutter
import UIKit
import Starscream
import Foundation

@objc public class SwiftWebSocketSupportPlugin: NSObject, FlutterPlugin {
    private var webSocket: WebSocket?
    private var methodChannel: FlutterMethodChannel?
    private var textEventChannel: FlutterEventChannel?
    private var byteEventChannel: FlutterEventChannel?
    private var textStreamHandler: WebSocketStreamHandler?
    private var byteStreamHandler: WebSocketStreamHandler?

    @objc public static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(name: "tech.sharpbitstudio.web_socket_support/methods", binaryMessenger: registrar.messenger())
        let textEventChannel = FlutterEventChannel(name: "tech.sharpbitstudio.web_socket_support/text", binaryMessenger: registrar.messenger())
        let byteEventChannel = FlutterEventChannel(name: "tech.sharpbitstudio.web_socket_support/byte", binaryMessenger: registrar.messenger())

        let instance = WebSocketSupportPlugin()
        instance.methodChannel = methodChannel
        instance.textEventChannel = textEventChannel
        instance.byteEventChannel = byteEventChannel

        registrar.addMethodCallDelegate(instance, channel: methodChannel)

        let textStreamHandler = WebSocketStreamHandler()
        let byteStreamHandler = WebSocketStreamHandler()

        instance.textStreamHandler = textStreamHandler
        instance.byteStreamHandler = byteStreamHandler

        textEventChannel.setStreamHandler(textStreamHandler)
        byteEventChannel.setStreamHandler(byteStreamHandler)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "connect":
            connect(call: call, result: result)
        case "disconnect":
            disconnect(call: call, result: result)
        case "sendTextMessage":
            sendTextMessage(call: call, result: result)
        case "sendByteMessage":
            sendByteMessage(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func connect(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let serverUrl = args["serverUrl"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing serverUrl", details: nil))
            return
        }

        var request = URLRequest(url: URL(string: serverUrl)!)

        // Set headers if provided
        if let options = args["options"] as? [String: Any],
           let headers = options["headers"] as? [String: String] {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        // Configure WebSocket options
        if let options = args["options"] as? [String: Any],
           let pingInterval = options["pingInterval"] as? Int64,
           pingInterval > 0 {
            // Starscream doesn't have direct ping interval setting in v4,
            // but we can implement this with a timer if needed
        }

        // Create WebSocket instance
        webSocket = WebSocket(request: request)
        webSocket?.delegate = self

        // Connect
        webSocket?.connect()

        result(true)
    }

    private func disconnect(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing arguments", details: nil))
            return
        }

        let code = args["code"] as? Int ?? 1000
        let reason = args["reason"] as? String ?? "Client done."

        webSocket?.disconnect()
        result(true)
    }

    private func sendTextMessage(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let message = args["message"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing message", details: nil))
            return
        }

        webSocket?.write(string: message)
        result(true)
    }

    private func sendByteMessage(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let messageData = args["message"] as? FlutterStandardTypedData else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing message", details: nil))
            return
        }

        let data = messageData.data
        webSocket?.write(data: data)
        result(true)
    }

    private func sendEventToFlutter(method: String, arguments: [String: Any]) {
        DispatchQueue.main.async {
            self.methodChannel?.invokeMethod(method, arguments: arguments)
        }
    }
}

// MARK: - WebSocketDelegate
extension WebSocketSupportPlugin: WebSocketDelegate {
    public func didReceive(event: WebSocketEvent, client: WebSocket) {
        switch event {
        case .connected:
            let connection = WebSocketConnection(webSocket: client, textStreamHandler: textStreamHandler, byteStreamHandler: byteStreamHandler)
            sendEventToFlutter(method: "onOpened", arguments: [:])

            // Store the connection for sending messages
            // Note: In a real implementation, you might want to manage multiple connections

        case .disconnected(let reason, let code):
            sendEventToFlutter(method: "onClosed", arguments: [
                "code": code,
                "reason": reason ?? "Unknown reason"
            ])

        case .text(let text):
            textStreamHandler?.sendEvent(text)

        case .binary(let data):
            byteStreamHandler?.sendEvent(data)

        case .ping(_):
            break // Ping received, Starscream handles pong automatically

        case .pong(_):
            break // Pong received

        case .viabilityChanged(_):
            break // Connection viability changed

        case .reconnectSuggested(_):
            break // Reconnection suggested

        case .cancelled:
            sendEventToFlutter(method: "onClosed", arguments: [
                "code": 1000,
                "reason": "Connection cancelled"
            ])

        case .error(let error):
            let errorMessage = error?.localizedDescription ?? "Unknown error"
            let errorType = type(of: error?.self)?.description() ?? "UnknownError"

            sendEventToFlutter(method: "onFailure", arguments: [
                "throwableType": errorType,
                "errorMessage": errorMessage,
                "causeMessage": errorMessage
            ])

            // Also send error to event channels
            if let error = error {
                textStreamHandler?.sendError(error)
                byteStreamHandler?.sendError(error)
            }
        }
    }
}

// MARK: - WebSocketConnection
public class WebSocketConnection: NSObject {
    private weak var webSocket: WebSocket?
    private weak var textStreamHandler: WebSocketStreamHandler?
    private weak var byteStreamHandler: WebSocketStreamHandler?

    init(webSocket: WebSocket, textStreamHandler: WebSocketStreamHandler?, byteStreamHandler: WebSocketStreamHandler?) {
        self.webSocket = webSocket
        self.textStreamHandler = textStreamHandler
        self.byteStreamHandler = byteStreamHandler
        super.init()
    }

    public func sendTextMessage(_ message: String) {
        webSocket?.write(string: message)
    }

    public func sendByteMessage(_ data: Data) {
        webSocket?.write(data: data)
    }

    public func disconnect(code: Int = 1000, reason: String = "Client done.") {
        webSocket?.disconnect()
    }
}

// MARK: - WebSocketStreamHandler
public class WebSocketStreamHandler: NSObject, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    public func sendEvent(_ event: Any) {
        DispatchQueue.main.async {
            self.eventSink?(event)
        }
    }

    public func sendError(_ error: Error) {
        DispatchQueue.main.async {
            self.eventSink?(FlutterError(
                code: "WEBSOCKET_ERROR",
                message: error.localizedDescription,
                details: nil
            ))
        }
    }
}

// MARK: - NSError description extension
extension NSError: CustomStringConvertible {
    public var description: String {
        return self.localizedDescription
    }
}

extension Optional where Wrapped: Error {
    func description() -> String {
        return self?.localizedDescription ?? "Unknown error"
    }
}