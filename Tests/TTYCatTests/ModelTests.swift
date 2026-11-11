import Foundation
import Testing
@testable import TTYCat

/// A daemon that isn't there: it keeps what it was asked, and answers what the test tells it to.
final class FakeDaemon: DaemonClient, @unchecked Sendable {
  private let lock = NSLock()
  private var asked: [[String: Any]] = []
  private var answers: [String: Data] = [:]

  /// What to say to requests of this kind (`t`). Anything else gets `{"ok": true}`.
  func answer(_ kind: String, with json: String) {
    lock.withLock { answers[kind] = Data(json.utf8) }
  }

  var requests: [[String: Any]] { lock.withLock { asked } }
  func requests(_ kind: String) -> [[String: Any]] { requests.filter { $0["t"] as? String == kind } }

  func send(_ body: Data, timeout: Int) async -> Data? {
    let request = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
    return lock.withLock {
      asked.append(request)
      return answers[request["t"] as? String ?? ""] ?? Data(#"{"ok": true}"#.utf8)
    }
  }
}

struct FakeHooks: HookTool {
  func hook(_ action: String) async -> (ok: Bool, installed: Bool) { (true, true) }
}

private let prompt = AgentRow(
  id: "b1", s: "blocked", a: "CC", n: "Claude", p: "api", body: "rm -rf build", rev: "r1", ask: "approve")

private func status(_ rows: [AgentRow]) -> DaemonStatus {
  DaemonStatus(
    pid: 1, s: rows, pet: nil,
    board: BoardInfo(connected: false, port: nil, fw: nil, name: nil, outdated: false, silent: [], probing: false),
    machines: [], flash: nil)
}

@MainActor private func model(_ daemon: FakeDaemon, rows: [AgentRow] = [prompt]) -> TTYCatModel {
  let model = TTYCatModel(daemon: daemon, hooks: FakeHooks(), notifies: false)
  model.took(status(rows))
  return model
}

/// Waits for what was started to finish, without a fixed sleep.
@MainActor private func until(_ done: () -> Bool) async {
  for _ in 0..<400 where !done() { try? await Task.sleep(for: .milliseconds(5)) }
}

@MainActor @Suite struct AnsweringPrompts {
  @Test func anAnswerNamesTheExactPromptItWasShownFor() async {
    let daemon = FakeDaemon()
    let m = model(daemon)
    m.answer(prompt, action: "deny")
    #expect(m.answering == "r1")
    await until { m.answering == nil }
    let sent = daemon.requests("app-act").first { $0["a"] as? String == "deny" }
    #expect(sent?["id"] as? String == "b1")
    #expect(sent?["rev"] as? String == "r1")
  }

  @Test func aSecondAnswerWaitsForTheFirst() async {
    let daemon = FakeDaemon()
    let m = model(daemon)
    #expect(m.answer(id: "b1", rev: "r1", action: "deny"))
    #expect(!m.answer(id: "b1", rev: "r1", action: "allow"))
    await until { m.answering == nil }
    #expect(daemon.requests("app-act").compactMap { $0["a"] as? String }.filter { $0 == "allow" }.isEmpty)
  }

  @Test func whatTheDaemonRefusesIsSaid() async {
    let daemon = FakeDaemon()
    daemon.answer("app-act", with: #"{"ok": false, "msg": "that prompt is gone"}"#)
    let m = model(daemon)
    m.answer(prompt, action: "deny")
    await until { m.toast != nil }
    #expect(m.toast == "that prompt is gone")
    #expect(m.answering == nil)
  }

  @Test func theDenyKeyWaitsForTheButtonsAndNeverAllows() async {
    let daemon = FakeDaemon()
    let m = model(daemon)
    #expect(m.heroAsk?.id == "b1")
    #expect(!m.handle(.deny))  // its buttons don't work yet
    #expect(daemon.requests("app-act").isEmpty)
    m.armedAsk = "r1"
    #expect(m.handle(.deny))
    await until { m.answering == nil }
    #expect(daemon.requests("app-act").compactMap { $0["a"] as? String } == ["deny"])
  }

  @Test func theDenyKeyLeavesQuestionsAndTerminalPromptsAlone() {
    let daemon = FakeDaemon()
    var question = prompt
    question.ask = "choice"
    let m = model(daemon, rows: [question])
    m.armedAsk = "r1"
    #expect(!m.handle(.deny))
    #expect(daemon.requests.isEmpty)
  }
}

@MainActor @Suite struct WhatTheDaemonSaid {
  @Test func agentsShowAsTheDaemonListsThem() {
    let m = model(FakeDaemon(), rows: [
      AgentRow(id: "a", s: "done", a: "CX", n: "Codex", p: "tokens"),
      AgentRow(id: "b", s: "working", a: "CC", n: "Claude", p: "shop"),
    ])
    #expect(m.hero == .done)
    #expect(m.listRows.map(\.id) == ["b"])
    #expect(m.working == 1)
  }

  @Test func anAgentOpenedInThePanelIsNotOpenedInTheWindowNorTheOtherWay() {
    let a = AgentRow(id: "a", s: "working", a: "CC", n: "Claude", p: "shop")
    let b = AgentRow(id: "b", s: "idle", a: "CC", n: "Claude", p: "docs")
    let m = model(FakeDaemon(), rows: [a, b])
    m.select(a)
    #expect(m.selectedRow(inWindow: false)?.id == "a")
    #expect(m.selectedRow(inWindow: true) == nil)
    m.select(b, inWindow: true)
    #expect(m.selectedRow(inWindow: false)?.id == "a")
    #expect(m.selectedRow(inWindow: true)?.id == "b")
    m.closeAgent(inWindow: true)
    #expect(m.selected == "a" && m.window.selected == nil)
    m.window.selected = "b"
    m.took(status([a]))  // b ended: only its page closes
    #expect(m.selected == "a" && m.window.selected == nil)
  }

  @Test func anAgentThatEndedClosesItsPage() {
    let m = model(FakeDaemon(), rows: [AgentRow(id: "a", s: "working", a: "CC", n: "Claude", p: "shop")])
    m.selected = "a"
    m.took(status([]))
    #expect(m.selected == nil)
    #expect(m.hero == .ready)
  }

  @Test func theArrowKeysMoveOnlyOnTheListOfAgents() {
    let m = model(FakeDaemon(), rows: [
      AgentRow(id: "a", s: "working", a: "CC", n: "Claude", p: "shop"),
      AgentRow(id: "b", s: "idle", a: "CC", n: "Claude", p: "docs"),
    ])
    #expect(m.handle(.down) && m.highlighted == "a")
    #expect(m.handle(.down) && m.highlighted == "b")
    #expect(m.handle(.open) && m.selected == "b")
    #expect(!m.handle(.down))  // an agent's page is open
    #expect(m.handle(.back) && m.selected == nil)
    m.page = .pet
    #expect(!m.handle(.down))
  }

  @Test func aReplyIsReadAsTheDaemonWritesIt() {
    #expect(DaemonReply(Data(#"{"ok": true}"#.utf8)) == DaemonReply(ok: true))
    #expect(DaemonReply(Data(#"{"ok": false, "msg": "no"}"#.utf8)).problem() == "no")
    #expect(DaemonReply(Data(#"{"ok": false, "msg": ""}"#.utf8)).problem(or: "couldn't") == "couldn't")
    #expect(DaemonReply(nil).problem() == "the daemon didn't answer")
    #expect(!DaemonReply(Data("not json".utf8)).ok)
  }
}
