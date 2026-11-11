import AppKit
import Testing
@testable import TTYCat

private func ids(_ groups: [[PaneItem]]) -> [[String]] { groups.map { $0.map(\.id) } }

private let proPanes: [(pane: PaneItem, settings: Bool)] = [
  (PaneItem(id: "usage", title: "Usage"), false),
  (PaneItem(id: "log", title: "Log"), false),
  (PaneItem(id: "look", title: "Look"), true),
]

@Suite struct TheWindowsPanes {
  @Test func withoutABoardOrAnExtensionItsOnlyTheAppsSettings() {
    let groups = WindowPanes.groups(welcomed: true, boardMatters: false, extra: [])
    #expect(ids(groups) == [["agents"], ["general", "agent-setup", "notifications", "advanced", "about"]])
  }

  @Test func theBoardHasAPaneOnlyOnAMacThatHasHadOne() {
    let groups = WindowPanes.groups(welcomed: true, boardMatters: true, extra: [])
    #expect(ids(groups) == [["agents"], ["general", "agent-setup", "notifications", "board", "advanced", "about"]])
  }

  @Test func theWelcomeComesFirstUntilItsDone() {
    #expect(ids(WindowPanes.groups(welcomed: false, boardMatters: false, extra: [])).first == ["welcome"])
    #expect(!WindowPanes.groups(welcomed: true, boardMatters: false, extra: []).flatMap { $0 }.contains { $0.id == "welcome" })
  }

  @Test func anExtensionsPanesGoWithTheirKind() {
    let groups = WindowPanes.groups(welcomed: true, boardMatters: false, extra: proPanes)
    #expect(ids(groups) == [["agents", "usage", "log"], ["general", "agent-setup", "notifications", "look", "advanced", "about"]])
  }

  @Test func aPaneThatHasGoneFallsBackToGeneral() {
    let groups = WindowPanes.groups(welcomed: true, boardMatters: false, extra: proPanes)
    #expect(WindowPanes.shown("log", in: groups)?.id == "log")
    #expect(WindowPanes.shown("board", in: groups)?.id == "agents")  // the board was forgotten
    #expect(WindowPanes.shown("welcome", in: groups)?.id == "agents")  // the welcome was finished
    #expect(WindowPanes.shown("general", in: []) == nil)
  }

  @Test func theSidebarSaysHowThingsStandInAFewWords() {
    #expect(WindowPanes.status(daemonUp: false, agents: 3, needs: 1) == "Daemon stopped")
    #expect(WindowPanes.status(daemonUp: true, agents: 0, needs: 0) == "No agents running")
    #expect(WindowPanes.status(daemonUp: true, agents: 1, needs: 0) == "1 agent running")
    #expect(WindowPanes.status(daemonUp: true, agents: 3, needs: 0) == "3 agents running")
    #expect(WindowPanes.status(daemonUp: true, agents: 3, needs: 1) == "1 needs you")
    #expect(WindowPanes.status(daemonUp: true, agents: 3, needs: 2) == "2 need you")
  }

  @Test func theSidebarHasOneRowForAllTheSettings() {
    let groups = WindowPanes.groups(welcomed: true, boardMatters: true, extra: proPanes)
    #expect(ids(WindowPanes.sidebar(groups)) == [["agents", "usage", "log"], ["settings"]])
    #expect(WindowPanes.settingsList(groups).map(\.id) == ["general", "agent-setup", "notifications", "board", "look", "advanced", "about"])
    #expect(ids(WindowPanes.sidebar(WindowPanes.groups(welcomed: false, boardMatters: false, extra: []))) == [["welcome"], ["agents"], ["settings"]])
    #expect(WindowPanes.sidebar([]).isEmpty)
  }

  @Test func settingsOpenWhereTheyWereLeft() {
    let list = WindowPanes.settingsList(WindowPanes.groups(welcomed: true, boardMatters: false, extra: proPanes))
    #expect(WindowPanes.setting("look", in: list) == "look")
    #expect(WindowPanes.setting("board", in: list) == "general")  // the board was forgotten since
    #expect(WindowPanes.setting("general", in: []) == nil)
  }

  @Test func everyPaneOfTheAppsHasAnIconOfItsOwn() {
    let panes = WindowPanes.groups(welcomed: false, boardMatters: true, extra: []).flatMap { $0 }
    #expect(Set(panes.map(\.icon)).count == panes.count)
    #expect(panes.allSatisfy { $0.icon.count == 7 && $0.icon.allSatisfy { $0 < 0x80 } })  // 7 rows of 7 bits
  }

  @Test func somethingIsOnlyBeingLookedAtWhileTheWindowIsOpenOnIt() async {
    await MainActor.run {
      let window = WindowModel()
      window.pane = "usage"
      #expect(!window.isShowing("usage"))
      window.isOpen = true
      #expect(window.isShowing("usage"))
      #expect(!window.isShowing("log"))
    }
  }
}

@Suite struct CountingAgents {
  @Test func eachAgentIsCountedOnceByWhatItsDoing() {
    let rows = ["blocked", "error", "working", "working", "done", "idle", "something new"].enumerated().map {
      AgentRow(id: "\($0.offset)", s: $0.element)
    }
    let tally = AgentTally(rows)
    #expect(tally.needs == 2 && tally.working == 2 && tally.done == 1 && tally.idle == 2)
    #expect(tally.needs + tally.working + tally.done + tally.idle == rows.count)
    #expect(AgentTally([]) == AgentTally([]))
  }
}

@Suite struct TheMeterOfAgents {
  private func tally(_ needs: Int, _ working: Int, _ done: Int, _ idle: Int) -> AgentTally {
    AgentTally(
      Array(repeating: "blocked", count: needs).map { AgentRow(id: "n", s: $0) }
        + Array(repeating: "working", count: working).map { AgentRow(id: "w", s: $0) }
        + Array(repeating: "done", count: done).map { AgentRow(id: "d", s: $0) }
        + Array(repeating: "idle", count: idle).map { AgentRow(id: "i", s: $0) })
  }

  @Test func itAlwaysFillsExactlyItsCells() {
    for counts in [(1, 0, 0, 0), (2, 2, 0, 1), (1, 1, 1, 1), (1, 40, 0, 3), (7, 3, 2, 9), (100, 1, 1, 1)] {
      let cells = tally(counts.0, counts.1, counts.2, counts.3).cells(48)
      #expect(cells.reduce(0, +) == 48)
    }
  }

  @Test func aStateWithAnAgentIsNeverHiddenAndOneWithoutIsNeverShown() {
    let cells = tally(1, 200, 0, 1).cells(48)
    #expect(cells[0] >= 1 && cells[3] >= 1)  // one agent that needs you still shows among two hundred
    #expect(cells[2] == 0)
    #expect(cells[1] > cells[0])
  }

  @Test func noAgentsIsAnEmptyMeter() {
    #expect(tally(0, 0, 0, 0).cells(48) == [0, 0, 0, 0])
    #expect(tally(1, 1, 1, 1).cells(3) == [0, 0, 0, 0])  // too few cells to show every state: none, not a lie
  }
}

@Suite struct Quitting {
  @Test func itAsksOnlyWhenItWouldStopWatchingAgents() {
    #expect(QuitCheck.asks(ownsDaemon: true, agents: 2))
    #expect(!QuitCheck.asks(ownsDaemon: true, agents: 0))
    #expect(!QuitCheck.asks(ownsDaemon: false, agents: 2))  // a daemon started elsewhere keeps running
  }

  @Test func itCountsInWords() {
    #expect(QuitCheck.message(agents: 1).hasPrefix("1 agent is running."))
    #expect(QuitCheck.message(agents: 3).hasPrefix("3 agents are running."))
  }
}

@MainActor @Suite struct OpeningTheWindow {
  @Test func commandCommaIsTheMacsKeyForSettingsEvenWhileTyping() {
    #expect(PanelKeys.key(code: 43, characters: ",", flags: .command, typing: false) == .settings)
    #expect(PanelKeys.key(code: 43, characters: ",", flags: .command, typing: true) == .settings)
    #expect(PanelKeys.key(code: 43, characters: ",", flags: [], typing: false) == nil)
    #expect(PanelKeys.key(code: 43, characters: ",", flags: [.command, .shift], typing: false) == nil)
  }

  @Test func theSettingsKeyLeavesWhatIsBeingLookedAtForTheSettingLastOpen() {
    let m = TTYCatModel(daemon: FakeDaemon(), hooks: FakeHooks(), notifies: false)
    m.window.setting = "notifications"
    m.window.pane = "agents"
    #expect(m.handle(.settings))
    #expect(m.window.pane == "notifications")
    m.window.pane = "about"
    m.openSettings()
    #expect(m.window.pane == "about")  // a setting is open already
  }

  @Test func itOpensOnThePaneAskedForAndTheMarkGoes() {
    let m = TTYCatModel(daemon: FakeDaemon(), hooks: FakeHooks(), notifies: false)
    m.welcomed = true
    m.setupSeen = false
    m.hookInstalled = false
    #expect(m.setupMarked)
    m.showSettings(WindowPanes.notifications)
    #expect(m.window.pane == "notifications")
    #expect(!m.setupMarked)
    #expect(m.handle(.settings))  // from any page of the panel
    #expect(m.window.pane == "notifications")  // where it was
  }

  @Test func theOldSetupScenesShowTheirPaneOfTheWindow() {
    #expect(Preview.pane(for: "setup") == "general")
    #expect(Preview.pane(for: "setup-denied") == "notifications")
    #expect(Preview.pane(for: "fw-update") == "board")
    #expect(Preview.pane(for: "welcome") == "welcome")
    #expect(Preview.pane(for: "window-about") == "about")
    #expect(Preview.pane(for: "needs") == nil)
  }
}

@Suite struct ScrollBars {
  let bounds = CGRect(x: 0, y: 0, width: 12, height: 400)

  @Test func theBarIsThinAndSitsAtTheOuterEdge() {
    let bar = ScrollBar.bar(knob: CGRect(x: 0, y: 100, width: 12, height: 120), in: bounds)
    #expect(bar.width == 4 && bar.maxX == 8)
    #expect(bar.minY == 102 && bar.height == 116)
  }

  @Test func aLongPageStillHasABarToCatch() {
    let bar = ScrollBar.bar(knob: CGRect(x: 0, y: 396, width: 12, height: 4), in: bounds)
    #expect(bar.height == 24)
    #expect(bar.maxY == 400)  // and it never leaves the scroller
    #expect(ScrollBar.bar(knob: CGRect(x: 0, y: 0, width: 12, height: 4), in: bounds).minY == 0)
  }
}

@Suite struct AgentSetupTests {
  private func addition(_ id: String, _ state: String) -> SetupAddition {
    SetupAddition(id: id, title: "Answer its prompts in ttycat", detail: "d", writes: "w", state: state)
  }

  private func agent(_ id: String, found: Bool, _ adds: [SetupAddition]) -> AgentSetup {
    AgentSetup(id: id, name: id.capitalized, found: found, shows: ["What it's doing"], adds: adds)
  }

  @Test func theDaemonsListIsReadAsItWritesIt() throws {
    let json = #"{"agents": [{"id": "claude", "name": "Claude Code", "found": true, "shows": ["What it's doing"], "adds": [{"id": "claude-hook", "title": "t", "detail": "d", "writes": "w", "state": "missing"}]}]}"#
    let list = try JSONDecoder().decode(SetupList.self, from: Data(json.utf8))
    #expect(list.agents.first?.adds.first?.id == "claude-hook")
    #expect(list.agents.first?.adds.first?.isOn == false)
  }

  @Test func onlyWhatIsMissingOnAnAgentThatIsHereAndNotYetAskedIsOffered() {
    let agents = [
      agent("claude", found: true, [addition("claude-hook", "missing"), addition("claude-line", "installed")]),
      agent("pi", found: false, [addition("pi-extension", "missing")]),
      agent("codex", found: true, [addition("codex-hook", "missing")]),
    ]
    #expect(SetupOffers.make(agents, seen: []).map(\.id) == ["claude-hook", "codex-hook"])
    #expect(SetupOffers.make(agents, seen: ["claude-hook"]).map(\.id) == ["codex-hook"])
  }

  @Test func anAgentInstalledLaterIsAskedAboutThen() {
    let before = [agent("pi", found: false, [addition("pi-extension", "missing")])]
    let after = [agent("pi", found: true, [addition("pi-extension", "missing")])]
    let seen = SetupOffers.seen(stored: nil, welcomed: true, agents: before)
    #expect(SetupOffers.make(before, seen: seen).isEmpty)
    #expect(SetupOffers.make(after, seen: seen).map(\.id) == ["pi-extension"])
  }

  @Test func whatTheWelcomeAlreadyAskedIsNotAskedAgain() {
    let agents = [agent("claude", found: true, [addition("claude-hook", "missing")])]
    #expect(SetupOffers.seen(stored: nil, welcomed: true, agents: agents) == ["claude-hook"])
    #expect(SetupOffers.seen(stored: nil, welcomed: false, agents: agents).isEmpty)
    #expect(SetupOffers.seen(stored: ["x"], welcomed: true, agents: agents) == ["x"])
  }

  @MainActor @Test func notNowIsAnAnswer() {
    let m = TTYCatModel(daemon: FakeDaemon(), hooks: FakeHooks(), notifies: false)
    m.window.preview = true  // nothing is stored
    m.tookSetups([agent("claude", found: true, [addition("claude-hook", "missing")])], stored: [])
    #expect(m.setupOffers.map(\.id) == ["claude-hook"])
    #expect(m.setupMarked)
    m.sawSetupOffers()
    #expect(m.setupOffers.isEmpty)
  }

  @Test func oneWhoseProgramHasGoneIsSaidNotAsked() {
    let agents = [agent("claude", found: true, [addition("claude-hook", "broken")])]
    #expect(SetupOffers.make(agents, seen: []).isEmpty)
    #expect(SetupOffers.broken(agents).map(\.id) == ["claude-hook"])
    #expect(SetupOffers.stateWord("broken") == "needs repair")
  }
}

@Suite struct WelcomeSetupTests {
  private func agent(_ name: String, found: Bool) -> AgentSetup {
    AgentSetup(id: name.lowercased(), name: name, found: found, shows: ["What it's doing", "Subagents"], adds: [])
  }

  @Test func theAgentsHereAreListedAndTheOthersNamedForLater() {
    let welcome = WelcomeSetup([agent("Claude Code", found: true), agent("Codex", found: false), agent("Pi", found: false)])
    #expect(welcome.found.map(\.name) == ["Claude Code"])
    #expect(welcome.later == "Not on this Mac: Codex, Pi. If you install one later, ttycat finds it, and asks before adding anything to it.")
    #expect(WelcomeSetup.words(["What it's doing", "Subagents"]) == "what it's doing, subagents")
  }

  @Test func withEveryAgentHereOrNoListYetThereIsNothingToSayAboutLater() {
    #expect(WelcomeSetup([agent("Claude Code", found: true)]).later == nil)
    #expect(WelcomeSetup([]).later == nil)
    #expect(WelcomeSetup([agent("Pi", found: false)]).found.isEmpty)
  }
}

@Suite struct CapabilityTests {
  private func agent(can: [String: String]?, hook: String? = nil) -> AgentSetup {
    let adds = hook.map { [SetupAddition(id: "claude-hook", title: "t", detail: "d", writes: "w", state: $0)] } ?? []
    return AgentSetup(id: "a", name: "A", found: true, shows: [], adds: adds, can: can)
  }

  @Test func eachCountSaysHowSureItIsAndWhatCannotBeToldIsNotShown() {
    let cells = Capability.all(agent(can: ["state": "exact", "sub": "exact", "sh": "estimated"]))
    #expect(cells.map(\.name) == ["Activity", "Subagents", "Open shells", "Prompts"])
    #expect(cells.map(\.word) == ["Shown", "Counted", "Estimated", "In terminal"])
    #expect(Capability.all(agent(can: ["state": "exact"])).map(\.level) == [.yes, .no, .no, .no])
    #expect(Capability.all(agent(can: nil))[1].word == "Not shown")  // a daemon that doesn't say
  }

  @Test func promptsSayWhereTheyAreAnswered() {
    #expect(Capability.all(agent(can: nil, hook: "installed"))[3].word == "In ttycat")
    #expect(Capability.all(agent(can: nil, hook: "missing"))[3].word == "Off")
    #expect(Capability.all(agent(can: nil, hook: "broken"))[3].level == .no)
  }
}
