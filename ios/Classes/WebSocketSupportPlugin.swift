import Flutter
import UIKit
import Starscream
import Foundation

@objc public class SwiftWebSocketSupportPlugin: NSObject, FlutterPlugin {
    @objc static let methodChannelName = "tech.sharpbitstudio.web_socket_support/methods"
    @objc static let textEventChannelName = "tech.sharpbitstudio.web_socket_support/text"
    @objc static let byteEventChannelName = "tech.sharpbitstudio.web_socket_support/byte"

    private var webSocket: WebSocket?
    private var methodChannel: FlutterMethodChannel?
    private var textEventChannel: FlutterEventChannel?
    private var byteEventChannel: FlutterEventChannel?
    private var textStreamHandler: WebSocketStreamHandler?
    private var byteStreamHandler: WebSocketStreamHandler?

    @objc public static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(name: methodChannelName, binaryMessenger: registrar.messenger())
        let textEventChannel = FlutterEventChannel(name: textEventChannelName, binaryMessenger: registrar.messenger())
        let byteEventChannel = FlutterEventChannel(name: byteEventChannelName, binaryMessenger: registrar.messenger())

        let instance = SwiftWebSocketSupportPlugin()
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

    @objc public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
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
extension SwiftWebSocketSupportPlugin: WebSocketDelegate {
    public func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        switch event {
        case .connected(let headers):
            let connection = WebSocketConnection(webSocket: client as? WebSocket, textStreamHandler: textStreamHandler, byteStreamHandler: byteStreamHandler)
            sendEventToFlutter(method: "onOpened", arguments: [:])

        case .disconnected(let reason, let code):
            sendEventToFlutter(method: "onClosed", arguments: [
                "code": Int(code),
                "reason": reason
            ])

        case .text(let text):
            textStreamHandler?.sendEvent(text)

        case .binary(let data):
            byteStreamHandler?.sendEvent(data)

        case .ping(_):
            break

        case .pong(_):
            break

        case .viabilityChanged(_):
            break

        case .reconnectSuggested(_):
            break

        case .cancelled:
            sendEventToFlutter(method: "onClosed", arguments: [
                "code": 1000,
                "reason": "Connection cancelled"
            ])

        case .peerClosed:
            sendEventToFlutter(method: "onClosed", arguments: [
                "code": 1000,
                "reason": "Peer closed"
            ])

        case .error(let error):
            let errorMessage = error?.localizedDescription ?? "Unknown error"
            let errorType: String

            if let error = error {
                errorType = String(describing: type(of: error))
            } else {
                errorType = "UnknownError"
            }

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
    private weak var webSocketClient: WebSocketClient?
    private weak var textStreamHandler: WebSocketStreamHandler?
    private weak var byteStreamHandler: WebSocketStreamHandler?

    init(webSocket: WebSocket?, textStreamHandler: WebSocketStreamHandler?, byteStreamHandler: WebSocketStreamHandler?) {
        self.webSocketClient = webSocket
        self.textStreamHandler = textStreamHandler
        self.byteStreamHandler = byteStreamHandler
        super.init()
    }

    public func sendTextMessage(_ message: String) {
        webSocketClient?.write(string: message, completion: nil)
    }

    public func sendByteMessage(_ data: Data) {
        webSocketClient?.write(data: data, completion: nil)
    }

    public func disconnect(code: Int = 1000, reason: String = "Client done.") {
        webSocketClient?.disconnect(closeCode: UInt16(code))
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