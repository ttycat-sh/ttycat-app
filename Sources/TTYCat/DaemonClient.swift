// Talking to the daemon without blocking: one request, one reply. A protocol, so what the app does with
// the daemon's answers can be tested with no daemon there.
import Foundation

protocol DaemonClient: Sendable {
  /// nil if the daemon isn't there, or didn't answer in time.
  func send(_ body: Data, timeout: Int) async -> Data?
}

/// What the daemon says to something it was asked to do.
struct DaemonReply: Equatable {
  var ok: Bool
  var message: String?

  /// Why it didn't, in the daemon's words if it gave any.
  func problem(or fallback: String = "the daemon didn't answer") -> String {
    message?.isEmpty == false ? message! : fallback
  }

  init(ok: Bool, message: String? = nil) {
    self.ok = ok
    self.message = message
  }

  init(_ data: Data?) {
    let reply = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    ok = reply?["ok"] as? Bool ?? false
    message = reply?["msg"] as? String
  }
}

extension DaemonClient {
  func data(_ request: [String: Any], timeout: Int = 3) async -> Data? {
    guard let body = try? JSONSerialization.data(withJSONObject: request) else { return nil }
    return await send(body, timeout: timeout)
  }

  /// Something to do: it says whether it did.
  func act(_ request: [String: Any], timeout: Int = 3) async -> DaemonReply {
    DaemonReply(await data(request, timeout: timeout))
  }

  /// Something to know.
  func ask<Reply: Decodable>(_ type: Reply.Type, _ request: [String: Any], timeout: Int = 3) async -> Reply? {
    await data(request, timeout: timeout).flatMap { try? JSONDecoder().decode(type, from: $0) }
  }
}

/// The daemon's control socket. Its reads block, so they have a queue of their own: Swift's own
/// threads are few, and one waiting on a socket is one fewer for everything else.
struct SocketDaemon: DaemonClient {
  private static let queue = DispatchQueue(label: "sh.ttycat.daemon", qos: .userInitiated, attributes: .concurrent)

  func send(_ body: Data, timeout: Int) async -> Data? {
    await withCheckedContinuation { done in
      Self.queue.async { done.resume(returning: Ctl.send(body, timeout: timeout)) }
    }
  }
}

/// `ttycatd.py hook …`: the one thing that edits Claude's settings. Runs a process to its end.
protocol HookTool: Sendable {
  func hook(_ action: String) async -> (ok: Bool, installed: Bool)
  /// `ttycatd.py setup …`: what it printed, as JSON. See AgentSetup.swift.
  func setup(_ arguments: [String]) async -> Data?
}

extension HookTool {
  func setup(_ arguments: [String]) async -> Data? { nil }
}

extension Supervisor: HookTool {
  func hook(_ action: String) async -> (ok: Bool, installed: Bool) {
    await withCheckedContinuation { done in
      DispatchQueue.global(qos: .userInitiated).async { done.resume(returning: self.tool(["hook", action])) }
    }
  }

  func setup(_ arguments: [String]) async -> Data? {
    await withCheckedContinuation { done in
      DispatchQueue.global(qos: .userInitiated).async { done.resume(returning: self.toolOutput(["setup"] + arguments)) }
    }
  }
}
