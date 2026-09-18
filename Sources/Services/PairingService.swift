import Foundation
import Network
import Observation

/// Receives API keys from a trusted Mac on the same network, so nobody has to
/// type a 100-character key on a floating keyboard.
///
/// Neither assistant allows a third-party app to sign in with a personal
/// account — Anthropic restricts subscription OAuth to its own surfaces, and
/// Google's equivalent would need a scope covering the whole cloud project — so
/// this is the closest honest thing to a login: the keys travel from the Mac
/// that already holds them, over the local network, gated by a code that only
/// shows on the headset.
@MainActor
@Observable
final class PairingService {
    enum State: Equatable {
        case idle
        case listening(code: String, port: UInt16)
        case received(providers: [Provider])
        case failed(String)
    }

    private(set) var state: State = .idle

    private var listener: NWListener?
    private var expiry: Task<Void, Never>?
    private var code = ""

    /// How long the window stays open. Long enough to walk to the Mac, short
    /// enough that a forgotten session does not stay open all day.
    private let window: Duration = .seconds(180)

    var onKeys: ((Provider, String) -> Void)?

    func start() {
        stop()
        code = String(format: "%06d", Int.random(in: 0...999_999))
        #if DEBUG
            // A fixed code and a logged port make the round trip testable on a
            // simulator, where touch never reaches the app.
            if let forced = ProcessInfo.processInfo.environment["PARALLAX_PAIRING_CODE"] {
                code = forced
            }
        #endif

        do {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = false
            let listener = try NWListener(using: parameters)
            listener.service = NWListener.Service(
                name: "Parallax",
                type: "_parallax._tcp"
            )
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.stateUpdateHandler = { [weak self] update in
                Task { @MainActor in
                    guard let self else { return }
                    switch update {
                    case .ready:
                        let port = listener.port?.rawValue ?? 0
                        #if DEBUG
                            NSLog("[pairing] listening on port %d", Int(port))
                        #endif
                        self.state = .listening(code: self.code, port: port)
                    case .failed(let error):
                        self.state = .failed(error.localizedDescription)
                        self.stop()
                    default:
                        break
                    }
                }
            }
            listener.start(queue: .main)
            self.listener = listener

            let window = window
            expiry = Task { [weak self] in
                try? await Task.sleep(for: window)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in self?.stop() }
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        expiry?.cancel()
        expiry = nil
        listener?.cancel()
        listener = nil
        if case .listening = state { state = .idle }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(on: connection, buffer: Data())
    }

    /// The payload is one JSON object followed by a newline; a key can exceed a
    /// single TCP read, so keep reading until the terminator arrives.
    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8 * 1024) {
            [weak self] chunk, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                var buffer = buffer
                if let chunk { buffer.append(chunk) }

                if let newline = buffer.firstIndex(of: 0x0A) {
                    self.handle(buffer[..<newline], on: connection)
                    return
                }
                if isComplete || error != nil {
                    if !buffer.isEmpty { self.handle(buffer[...], on: connection) }
                    else { connection.cancel() }
                    return
                }
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    private func handle(_ payload: Data.SubSequence, on connection: NWConnection) {
        func reply(_ text: String) {
            connection.send(
                content: Data((text + "\n").utf8),
                completion: .contentProcessed { _ in connection.cancel() }
            )
        }

        guard
            let root = try? JSONSerialization.jsonObject(with: Data(payload)) as? [String: Any],
            let sent = root["code"] as? String,
            let keys = root["keys"] as? [String: String]
        else {
            reply(#"{"ok":false,"error":"malformed"}"#)
            return
        }
        // Constant work regardless of where the mismatch is; the code is short
        // and the window is one connection wide anyway.
        guard sent == code, !code.isEmpty else {
            reply(#"{"ok":false,"error":"wrong code"}"#)
            return
        }

        var accepted: [Provider] = []
        for provider in Provider.allCases {
            guard let key = keys[provider.rawValue], !key.isEmpty else { continue }
            onKeys?(provider, key)
            accepted.append(provider)
        }
        reply(#"{"ok":true}"#)
        state = .received(providers: accepted)
        // One code, one use.
        code = ""
        stop()
    }
}
