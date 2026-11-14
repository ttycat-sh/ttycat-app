import AppKit
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

@MainActor @Suite struct NamingAgents {
  private let shop = AgentRow(id: "w1", s: "working", a: "CC", n: "Claude", p: "shop")
  private var named: AgentRow {
    var row = AgentRow(id: "w1", s: "working", a: "CC", n: "Claude", p: "the login fix")
    (row.name, row.folder) = ("the login fix", "shop")
    return row
  }

  @Test func anAgentGoesByItsFolderUntilItHasAName() {
    #expect(shop.title == "shop" && shop.folderBesideName == nil)
    #expect(named.title == "the login fix" && named.folderBesideName == "shop")
    var same = named
    same.name = "shop"
    #expect(same.folderBesideName == nil)  // not said twice
    #expect(named.alertTitle == "Claude \u{B7} the login fix" && shop.alertTitle == "Claude \u{B7} shop")
  }

  @Test func theAppIsToldTheNameAsItWasTyped() throws {
    let json = #"{"id":"w1","s":"working","a":"CC","n":"Claude","p":"Zoe's fix","name":"Zoë's fix ✨","folder":"shop"}"#
    let row = try JSONDecoder().decode(AgentRow.self, from: Data(json.utf8))
    #expect(row.title == "Zoë's fix ✨" && row.p == "Zoe's fix" && row.folder == "shop")
  }

  @Test func whatsTypedIsKeptAsOneLineNoLongerThanAName() {
    #expect(AgentName.kept("  the   login\n fix ") == "the login fix")
    #expect(AgentName.kept(String(repeating: "x", count: 90)).count == AgentName.longest)
    #expect(AgentName.kept("   ") == "")
  }

  @Test func onlyAChangeIsAskedFor() {
    #expect(AgentName.change("the login fix", for: shop) == "the login fix")
    #expect(AgentName.change(" shop ", for: shop) == nil)  // its folder, while it has no name
    #expect(AgentName.change("", for: shop) == nil)
    #expect(AgentName.change("the login fix ", for: named) == nil)
    #expect(AgentName.change("the tests", for: named) == "the tests")
    #expect(AgentName.change("  ", for: named) == "")  // no name: by its folder again
    #expect(AgentName.change("shop", for: named) == "shop")
  }

  @Test func aNameCanBeFilteredByAndSoCanItsFolder() {
    var filter = AgentFilter()
    filter.text = "login"
    #expect(filter.shows(named) && !filter.shows(shop))
    filter.text = "SHOP"
    #expect(filter.shows(named) && filter.shows(shop))
  }

  @Test func renamingAsksTheDaemonWhichKeepsTheName() async {
    let daemon = FakeDaemon()
    let m = model(daemon, rows: [shop])
    m.rename(shop, to: "  the login   fix ")
    await until { !daemon.requests("agent-name").isEmpty }
    let sent = daemon.requests("agent-name").first
    #expect(sent?["id"] as? String == "w1" && sent?["name"] as? String == "the login fix")
    #expect(m.toast == nil)
  }

  @Test func takingANameBackAsksForNone() async {
    let daemon = FakeDaemon()
    let m = model(daemon, rows: [named])
    m.rename(named, to: "")
    await until { !daemon.requests("agent-name").isEmpty }
    #expect(daemon.requests("agent-name").first?["name"] as? String == "")
  }

  @Test func nothingIsAskedWhenNothingChanges() async {
    let daemon = FakeDaemon()
    let m = model(daemon, rows: [named])
    m.rename(named, to: "the login fix")
    m.rename(AgentRow(id: "1/down", s: "error", a: "--", p: "not reachable"), to: "x")  // a machine, not an agent
    try? await Task.sleep(for: .milliseconds(40))
    #expect(daemon.requests("agent-name").isEmpty)
  }

  @Test func renamingOpensItsPageWhereItWasAskedFor() {
    let other = AgentRow(id: "w2", s: "working", a: "CC", n: "Claude", p: "shop")
    let m = model(FakeDaemon(), rows: [shop, other])
    m.startRenaming(other)  // in the panel
    #expect(m.selected == "w2" && m.isRenaming(other, inWindow: false) && !m.isRenaming(shop, inWindow: false))
    #expect(m.window.selected == nil && m.window.renaming == nil)  // the window is left where it was
    m.startRenaming(shop, inWindow: true)  // a right click on its card
    #expect(m.window.selected == "w1" && m.isRenaming(shop, inWindow: true) && m.renaming == "w2")
    m.startRenaming(AgentRow(id: "1/down", s: "error", a: "--", p: "not reachable"))  // a machine, not an agent
    #expect(m.renaming == "w2")
  }

  @Test func aNameHalfTypedIsDroppedWithItsPage() {
    let other = AgentRow(id: "w2", s: "working", a: "CC", n: "Claude", p: "shop")
    let m = model(FakeDaemon(), rows: [shop, other])
    m.startRenaming(shop)
    m.select(other)  // another agent's page
    #expect(m.renaming == nil)
    m.startRenaming(shop)
    m.select(shop)  // its own again: still being typed
    #expect(m.renaming == "w1")
    m.closeAgent(inWindow: false)
    #expect(m.renaming == nil)
    m.startRenaming(shop)
    #expect(m.handle(.back) == true && m.renaming == nil && m.selected == nil)
    m.startRenaming(shop)
    m.panelOpening()  // closed and opened again
    #expect(m.renaming == nil)
    m.startRenaming(shop, inWindow: true)
    m.select(other, inWindow: true)
    #expect(m.window.renaming == nil)
  }

  @Test func aClickInTheRowsMenuIsntAClickOutsideThePanel() {
    // The panel floats where menus do, and closes for a click in any other window of the app's.
    let menu = NSWindow()
    menu.level = .popUpMenu
    #expect(StatusPanel.isMenu(menu) && !StatusPanel.isMenu(NSWindow()))
  }

  @Test func escDropsANameBeingTypedBeforeThePanel() {
    let m = model(FakeDaemon(), rows: [shop])
    #expect(!m.stopRenaming())  // nothing being typed: the panel closes
    m.startRenaming(shop)
    #expect(m.stopRenaming() && m.renaming == nil && m.selected == "w1")  // its page stays
  }

  @Test func aNameTheDaemonRefusesIsSaid() async {
    let daemon = FakeDaemon()
    daemon.answer("agent-name", with: #"{"ok": false, "msg": "that agent has gone"}"#)
    let m = model(daemon, rows: [shop])
    m.rename(shop, to: "the login fix")
    await until { m.toast != nil }
    #expect(m.toast?.contains("that agent has gone") == true)
  }
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
