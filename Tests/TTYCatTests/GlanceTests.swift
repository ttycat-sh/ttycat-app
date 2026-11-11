import Testing
import UserNotifications
@testable import TTYCat

private func hero(up: Bool = true, top: String? = nil, flashing: Bool = false, known: Bool = false, connected: Bool = false) -> HeroKind {
  HeroKind.make(daemonUp: up, top: top, flashBusy: flashing, boardKnown: known, boardConnected: connected)
}

@Test func withoutABoardTheHeroIsOnlyEverAboutAgents() {
  #expect(hero() == .ready)
  #expect(hero(top: "working") == .clear)
  #expect(hero(top: "idle") == .clear)
  #expect(hero(top: "done") == .done)
  #expect(hero(top: "error") == .error)
  #expect(hero(up: false, top: "working") == .stopped)
}

@Test func anUnpluggedBoardNeverHidesAnAgentThatFinishedOrFailed() {
  #expect(hero(top: "done", known: true) == .done)
  #expect(hero(top: "error", known: true) == .error)
  #expect(hero(top: "working", known: true) == .unplugged)
  #expect(hero(known: true) == .unplugged)
  #expect(hero(top: "working", known: true, connected: true) == .clear)
  #expect(hero(known: true, connected: true) == .ready)
}

@Test func aFirmwareUpdateIsSaidAheadOfAnythingButAnError() {
  #expect(hero(top: "done", flashing: true, known: true, connected: true) == .updating)
  #expect(hero(top: "error", flashing: true, known: true, connected: true) == .error)
  #expect(hero(flashing: true, known: true) == .updating)  // the board is away while it's written
}

private func nudge(welcomed: Bool = true, seen: Bool = false, hook: Bool? = true,
                   notifications: UNAuthorizationStatus = .authorized, asks: Bool = true) -> Bool {
  SetupNudge.wanted(welcomed: welcomed, setupSeen: seen, hook: hook, notifications: notifications, notifyAsks: asks)
}

@Test func setupIsMarkedForWhatWasLeftOffTheFirstTime() {
  #expect(!nudge())
  #expect(nudge(hook: false))
  #expect(nudge(notifications: .notDetermined))
}

@Test func theMarkIsNeverThereDuringTheWelcomeNorAfterSetupWasOpened() {
  #expect(!nudge(welcomed: false, hook: false, notifications: .notDetermined))
  #expect(!nudge(seen: true, hook: false, notifications: .notDetermined))
}

@Test func theMarkIsOnlyForWhatAClickInSetupCanTurnOn() {
  #expect(!nudge(hook: nil))  // Claude's settings can't be read: nothing to tick
  #expect(!nudge(notifications: .denied))  // refused in System Settings: that was an answer
  #expect(!nudge(notifications: .notDetermined, asks: false))  // they don't want to be told
}

private func row(_ id: String, _ s: String) -> AgentRow { AgentRow(id: id, s: s, a: "CC", n: "Claude", p: id) }

@Test func thePromptOnTheCardIsNotListedAgainBelowIt() {
  let rows = [row("a", "blocked"), row("b", "blocked"), row("c", "working")]
  #expect(AgentList.below(rows, ask: "b").map(\.id) == ["a", "c"])
}

@Test func aFirstAgentThatFailedOrFinishedIsTheHeroAndNotARow() {
  #expect(AgentList.below([row("a", "done"), row("b", "working")], ask: nil).map(\.id) == ["b"])
  #expect(AgentList.below([row("a", "error"), row("b", "done")], ask: nil).map(\.id) == ["b"])
  #expect(AgentList.below([row("a", "working"), row("b", "done")], ask: nil).map(\.id) == ["a", "b"])
  #expect(AgentList.below([], ask: nil).isEmpty)
}

@Test func whatAnAgentDidSaysHowLongAgoWithoutTheMinus() {
  #expect(ActivityItem(age: "-4s", tone: 0, text: "").shownAge == "4s")
  #expect(ActivityItem(age: "-1m", tone: 0, text: "").shownAge == "1m")
  #expect(ActivityItem(age: "now", tone: 0, text: "").shownAge == "now")
  #expect(ActivityItem(age: "", tone: 0, text: "").shownAge == "")
}

@Test func aQuestionIsAnsweredByAPickOrByTypedWords() {
  #expect(QuestionFlow.answered(picked: [1], typed: ""))
  #expect(QuestionFlow.answered(picked: [], typed: " sqlite "))
  #expect(!QuestionFlow.answered(picked: [], typed: "   "))
}

@Test func nothingIsSentUntilEveryQuestionHasAnAnswer() {
  #expect(QuestionFlow.ready(picked: [[0], []], typed: ["", "both"]))
  #expect(!QuestionFlow.ready(picked: [[0], []], typed: ["", ""]))  // the one that isn't on screen counts too
  #expect(!QuestionFlow.ready(picked: [], typed: []))
}

@Suite struct AgentCountsTests {
  private func decoded(_ json: String) throws -> AgentRow {
    try JSONDecoder().decode(AgentRow.self, from: Data(json.utf8))
  }

  @Test func countsComeWithTheRowAndEstimatesSaySo() throws {
    let counts = AgentCounts(try decoded(#"{"id": "a", "s": "working", "sub": 2, "sh": 1, "guess": ["sh"]}"#))
    #expect(counts.subagents?.text == "2")
    #expect(counts.shells?.text == "~1")
    #expect(counts.spoken == "2 subagents running, about 1 shell open")
  }

  @Test func noneAndNotKnownBothShowNothing() throws {
    #expect(AgentCounts(try decoded(#"{"id": "a", "s": "working", "sub": 0, "sh": 0}"#)).isEmpty)
    #expect(AgentCounts(try decoded(#"{"id": "a", "s": "working"}"#)).isEmpty)
  }
}

@Suite struct AgentOrderTests {
  private func row(_ id: String, _ s: String, _ age: Double) -> AgentRow { AgentRow(id: id, s: s, a: "CC", n: "Claude", p: id, age: age) }

  @Test func aFinishedAgentDoesNotJumpAheadOfOnesThatDidSomethingSince() {
    let rows = [row("done-old", "done", 12 * 86400), row("done-new", "done", 180), row("idle", "idle", 3000), row("work", "working", 5000)]
    #expect(AgentOrder.shown(rows).map(\.id) == ["work", "done-new", "idle", "done-old"])
  }

  @Test func whatNeedsYouIsStillFirst() {
    let rows = [row("done", "done", 1), row("work", "working", 2), row("error", "error", 900), row("ask", "blocked", 30)]
    #expect(AgentOrder.shown(rows).map(\.id) == ["ask", "error", "work", "done"])
  }

  @Test func equalsKeepTheDaemonsOrder() {
    #expect(AgentOrder.shown([row("a", "idle", 60), row("b", "idle", 60)]).map(\.id) == ["a", "b"])
  }
}

@Suite struct AgentFilterTests {
  private func row(_ id: String, _ a: String, _ s: String) -> AgentRow {
    AgentRow(id: id, s: s, a: a, n: ["CC": "Claude", "CX": "Codex"][a] ?? a, p: id)
  }
  private var rows: [AgentRow] {
    [row("ask", "CX", "blocked"), row("c1", "CC", "working"), row("c2", "CC", "done"), row("x1", "CX", "idle"), row("c3", "CC", "idle")]
  }

  @Test func oneKindOneStateOrBoth() {
    #expect(AgentFilter(harness: "CC").apply(rows).map(\.id) == ["c1", "c2", "c3"])
    #expect(AgentFilter(state: .idle).apply(rows).map(\.id) == ["x1", "c3"])
    #expect(AgentFilter(harness: "CC", state: .idle).apply(rows).map(\.id) == ["c3"])
    #expect(AgentFilter().apply(rows).count == 5)
    #expect(AgentFilter.state(of: row("e", "CC", "error")) == .needs)
  }

  @Test func whatNeedsYouAndIsNotShownIsCounted() {
    #expect(AgentFilter(harness: "CC").hiddenNeeds(rows) == 1)
    #expect(AgentFilter(harness: "CX").hiddenNeeds(rows) == 0)
    #expect(AgentFilter(state: .done).hiddenNeeds(rows) == 1)
    #expect(AgentFilter().hiddenNeeds(rows) == 0)
  }

  @Test func theKindsThereAreMostOfFirstAndNoneToChooseFromOne() {
    let kinds = AgentFilter.harnesses(rows)
    #expect(kinds.map(\.id) == ["CC", "CX"])
    #expect(kinds.map(\.count) == [3, 2])
    #expect(kinds.map(\.needs) == [0, 1])
    #expect(kinds.first?.name == "Claude")
    #expect(AgentFilter.harnesses([row("a", "CC", "idle"), row("b", "CC", "idle")]).isEmpty)
    #expect(AgentFilter.harnesses([row("a", "CC", "idle"), AgentRow(id: "1/down", s: "error", a: "--", p: "not reachable")]).isEmpty)
  }

  @Test func aKindWithNoAgentsLeftIsNoLongerChosen() {
    let only = AgentFilter(harness: "PI", state: .idle)
    #expect(only.settled(for: rows) == AgentFilter(state: .idle))
    #expect(AgentFilter(harness: "CC").settled(for: rows).harness == "CC")
  }

  @MainActor @Test func thePanelListsInTheSameOrderAndByItsTab() {
    let m = TTYCatModel(daemon: FakeDaemon(), hooks: FakeHooks(), notifies: false)
    var old = row("old", "CC", "idle"); old.age = 9000
    var idle = row("idle", "CX", "idle"); idle.age = 60
    var work = row("work", "CC", "working"); work.age = 500
    m.took(DaemonStatus(
      pid: 1, s: [old, work, idle], pet: nil,
      board: BoardInfo(connected: false, port: nil, fw: nil, name: nil, outdated: false, silent: [], probing: false),
      machines: [], flash: nil))
    #expect(m.rows.map(\.id) == ["work", "idle", "old"])
    m.panelHarness = "CC"
    #expect(m.listRows.map(\.id) == ["work", "old"])
    m.panelHarness = "PI"  // none of those: everything again
    #expect(m.listRows.count == 3)
  }
}

@Suite struct AgentFactsTests {
  private func facts(_ json: String) throws -> [String: AgentFacts.Fact] {
    let row = try JSONDecoder().decode(AgentRow.self, from: Data(json.utf8))
    return Dictionary(uniqueKeysWithValues: AgentFacts(row).facts.map { ($0.id, $0) })
  }

  @Test func whatAnAgentHasRunningIsSaidAndAnEstimateSaysSo() throws {
    let f = try facts(#"{"id": "a", "s": "working", "age": 200, "sub": 2, "sh": 1, "guess": ["sh"], "host": "studio"}"#)
    #expect(f["state"]?.value == "Working")
    #expect(f["since"]?.name == "For")
    #expect(f["since"]?.value == "3m")
    #expect(f["sub"]?.value == "2 running")
    #expect(f["sh"]?.value == "~1 open")
    #expect(f["sh"]?.note != nil)
    #expect(f["where"]?.value == "studio")
  }

  @Test func aRequestItMadeOpensOnlyAsAWebAddress() throws {
    let row = try JSONDecoder().decode(AgentRow.self, from: Data(
      #"{"id": "a", "s": "done", "prs": [{"url": "https://gitlab.example.com/g/api/-/merge_requests/41", "kind": "mr", "repo": "g/api", "n": 41}]}"#.utf8))
    #expect(row.prs?.first?.label == "MR !41")
    #expect(row.prs?.first?.destination?.host == "gitlab.example.com")
    #expect(PullLink(url: "https://github.com/a/b/pull/3", kind: "pr", repo: "a/b", n: 3).label == "PR #3")
    for bad in ["file:///etc/passwd", "http://github.com/a/b/pull/3", "javascript:alert(1)", "https:///pull/3", ""] {
      #expect(PullLink(url: bad, kind: "pr", repo: "a/b", n: 3).destination == nil)
    }
  }

  @Test func noneIsNotTheSameAsNotKnown() throws {
    let f = try facts(#"{"id": "a", "s": "blocked", "sub": 0}"#)
    #expect(f["sub"]?.value == "None")
    #expect(f["sh"]?.value == "Not shown")
    #expect(f["state"]?.tone == .needs)
    #expect(f["where"]?.value == "This Mac")
  }

  @Test func whatOnlySomeAgentsSayIsShownWhenSaidAndLeftOutOtherwise() throws {
    let row = try JSONDecoder().decode(AgentRow.self, from: Data(#"{"id": "a", "s": "idle"}"#.utf8))
    #expect(AgentFacts(row).facts.map(\.id) == ["state", "since", "sub", "sh", "where"])
    let about = try JSONDecoder().decode(
      AgentAbout.self, from: Data(#"{"model": "claude-opus-5-5-20260301", "ctx": 84200, "steps": 1, "up": 7300}"#.utf8))
    let f = Dictionary(uniqueKeysWithValues: AgentFacts(row, about: about).facts.map { ($0.id, $0.value) })
    #expect(f["model"] == "opus-5-5")
    #expect(f["ctx"] == "84k tokens")
    #expect(f["steps"] == "1 tool")
    #expect(f["up"] == "2h ago")
    #expect(AgentFacts.tokens(950) == "950" && AgentFacts.tokens(1_240_000) == "1.2M")
    #expect(AgentFacts.model("gpt-5[1m]") == "gpt-5")
    #expect(AgentFacts.folder("/Users/x/code/shop", home: "/Users/x") == "~/code/shop")
    #expect(AgentFacts.folder("/Users/xy/code", home: "/Users/x") == "/Users/xy/code")
  }

  @MainActor @Test func theWindowShowsTheFirstAgentUntilOneIsChosenWithoutOpeningIt() {
    let m = TTYCatModel(daemon: FakeDaemon(), hooks: FakeHooks(), notifies: false)
    var work = AgentRow(id: "work", s: "working", a: "CC", n: "Claude", p: "shop"); work.age = 5
    var idle = AgentRow(id: "idle", s: "idle", a: "CX", n: "Codex", p: "docs"); idle.age = 60
    m.took(DaemonStatus(
      pid: 1, s: [idle, work], pet: nil,
      board: BoardInfo(connected: false, port: nil, fw: nil, name: nil, outdated: false, silent: [], probing: false),
      machines: [], flash: nil))
    #expect(m.windowAgent?.id == "work")
    #expect(m.window.selected == nil)        // shown, not opened
    m.window.filter.harness = "CX"
    #expect(m.windowAgent?.id == "idle")     // the first of those listed
    m.select(work, inWindow: true)
    #expect(m.windowAgent?.id == "work")     // one that was chosen stays, whatever the list shows
  }
}

@Suite struct AgentFilterTextTests {
  private func row(_ id: String, _ n: String, host: String? = nil) -> AgentRow {
    AgentRow(id: id, s: "idle", a: "CC", n: n, p: id, host: host)
  }

  @Test func typingNarrowsByProjectKindOrMachine() {
    let rows = [row("web-shop", "Claude"), row("docs", "Codex"), row("riff", "Pi", host: "studio")]
    #expect(AgentFilter(text: "SHOP").apply(rows).map(\.id) == ["web-shop"])
    #expect(AgentFilter(text: "codex").apply(rows).map(\.id) == ["docs"])
    #expect(AgentFilter(text: "stud").apply(rows).map(\.id) == ["riff"])
    #expect(AgentFilter(text: "  ").apply(rows).count == 3)
    #expect(!AgentFilter(text: " ").isOn)
    #expect(AgentFilter(text: "x").isOn)
  }
}
