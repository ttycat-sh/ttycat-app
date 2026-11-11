// What the panel and the menu bar show, kept up to date once a second.
import AppKit
import ServiceManagement
import SwiftUI
import UserNotifications

enum Page: Equatable {
  case agents, pet
  case extra(String)  // from an extension
}

@MainActor
final class TTYCatModel: ObservableObject {
  @Published var status: DaemonStatus?
  @Published var page = Page.agents
  @Published var petEvent: PetEvent?
  @Published var icon = MenuIcon.make(pose: .nap, tick: 0, faded: true, needs: 0)
  @Published var toast: String?
  @Published var hookInstalled: Bool?
  @Published var setups: [AgentSetup] = []   // each agent, and what can be added to it: see AgentSetup.swift
  @Published var setupBusy = false
  @Published var seenSetups: Set<String>?    // what has been asked about; nil until the first list is in
  private var setupsReadAt = Date.distantPast
  @Published var loginState = SMAppService.mainApp.status
  @Published var problem: String?
  @Published var sampled = false
  @Published var selected: String?              // the agent whose page is open in the panel; the window's is its own
  @Published var highlighted: String?           // the row the arrow keys are on
  var armedAsk: String?                         // the rev of the prompt whose buttons work now: see AskCard
  @Published var activity: [ActivityItem] = []
  @Published var answering: String?             // the rev of the prompt being answered
  @Published private(set) var pinnedAsk: String?
  @Published var notifyPermission = UNAuthorizationStatus.notDetermined
  @Published var notifyProblem: String?
  @Published var notifyAsks = UserDefaults.standard.object(forKey: "notifyAsks") as? Bool ?? true
  @Published var notifyFinishes = UserDefaults.standard.object(forKey: "notifyFinishes") as? Bool ?? true
  @Published var notifySound = UserDefaults.standard.object(forKey: "notifySound") as? Bool ?? true

  @Published var boardEverSeen = UserDefaults.standard.bool(forKey: "boardEverSeen")
  @Published var welcomed = UserDefaults.standard.bool(forKey: "welcomed")
  @Published var setupSeen = UserDefaults.standard.bool(forKey: "setupSeen")  // since the welcome: see SetupNudge
  @Published var panelHeight: CGFloat = 0
  @Published var maxPanelHeight: CGFloat = 2000  // how far down the screen it can go
  @Published var firmwareImage = FirmwareImage.inApp()
  @Published var flashStarting = false
  @Published var appUpdateReady: String?  // a newer app Sparkle found on its schedule: Setup offers it
  let appUpdater = AppUpdater()
  @Published var registerRefused: String?  // why the folder chosen in Setup wasn't taken, shown under its button
  @Published var firmwarePlan = FirmwarePlan.notConnected

  let window = WindowModel()  // which pane the window is on, and whether it's showing
  let supervisor = Supervisor()
  private let daemon: DaemonClient
  private let hooks: HookTool
  private let notifies: Bool

  /// `daemon` and `hooks` are the real ones unless a test says otherwise. `notifies`: off where there's
  /// no app to post a notification from.
  init(daemon: DaemonClient = SocketDaemon(), hooks: HookTool? = nil, notifies: Bool = true) {
    self.daemon = daemon
    self.hooks = hooks ?? supervisor
    self.notifies = notifies
  }
  private var boardAsksSeen: Int?
  private var lastFlashState: String?
  private var lastCoreState: String?
  private var seenNeeds: Set<String>?
  private var seenPetEv: Int?
  private var seenPetTotal: Int?
  private var seenPetLevel: Int?
  private var pendingHello: PetEvent.Kind?  // a welcome back, saved for when the Pet page is open to give it
  private var petTimer: Timer?
  var handsOffUntil = Date.distantPast
  var lastPanelClick = Date.distantPast
  private lazy var alerts = Alerts()  // lazily: it can't exist outside the app bundle, as in --preview
  private var planner = AlertPlanner()
  private var permissionTick = 0
  private var polling = false
  private var pollTimer: Timer?
  private var iconTimer: Timer?
  private var iconTick = 0
  private var iconKey = ""
  private var toastGeneration = 0

  var rows: [AgentRow] { AgentOrder.shown(status?.s ?? []) }
  @Published var panelHarness: String?  // the panel's tab: one kind of agent, or all
  var panelFilter: AgentFilter { AgentFilter(harness: panelHarness).settled(for: rows) }
  var working: Int { rows.filter { $0.s == "working" }.count }
  var needs: Int { rows.filter(\.needsYou).count }
  var boardConnected: Bool { status?.board.connected == true }
  /// The board is optional. Someone without one shouldn't be told it's missing.
  var boardMatters: Bool { Self.boardMatters(everSeen: boardEverSeen, board: status?.board) }

  /// Only a board that has said hello, now or before. A port that stays silent is any USB serial device
  /// until then: on a Mac that never had a board, it isn't offered firmware.
  nonisolated static func boardMatters(everSeen: Bool, board: BoardInfo?) -> Bool {
    everSeen || board?.connected == true
  }
  var asks: [AgentRow] { rows.filter { $0.s == "blocked" } }
  var selectedRow: AgentRow? { rows.first { $0.id == selected } }

  /// The agent open where this is asked from: the panel and the window each have their own.
  func selectedRow(inWindow: Bool) -> AgentRow? {
    let id = inWindow ? window.selected : selected
    return rows.first { $0.id == id }
  }

  func activity(inWindow: Bool) -> [ActivityItem] { inWindow ? window.activity : activity }

  /// The agent open beside the window's list: the one clicked, or else the first of those listed, so
  /// there's always one to read. Showing the first isn't opening it: a finished one stays "done".
  var windowAgent: AgentRow? {
    selectedRow(inWindow: true) ?? window.filter.settled(for: rows).apply(rows).first ?? rows.first
  }

  func closeAgent(inWindow: Bool) {
    if inWindow { window.selected = nil } else { selected = nil }
  }
  /// The rows under the card at the top of the Agents page.
  /// The card at the top goes by the daemon's order, as the board does: an agent that failed, or one
  /// that just finished, is news. Everything under it is in the order of `rows`.
  var top: AgentRow? { status?.s.first }
  var listRows: [AgentRow] { panelFilter.apply(AgentList.below(rows, ask: heroAsk?.id, top: top)) }

  /// The prompt on the card. It stays until it's settled: one arriving while you're reading
  /// or clicking waits its turn, instead of taking the place of the one you meant.
  var heroAsk: AgentRow? { asks.first { $0.rev == pinnedAsk } }

  /// Called with each new list.
  func pinAsk() {
    if asks.contains(where: { $0.rev == pinnedAsk }) { return }
    pinnedAsk = (asks.first { $0.ask != "terminal" } ?? asks.first)?.rev
  }
  var ownsDaemon: Bool { status.map { supervisor.ownsDaemon(pid: $0.pid) } ?? false }

  /// The mark on the panel's gear: something in the window wants a look.
  var setupMarked: Bool {
    (boardMatters && firmwarePlan.wantsAttention) || !setupOffers.isEmpty || !SetupOffers.broken(setups).isEmpty || SetupNudge.wanted(
      welcomed: welcomed, setupSeen: setupSeen, hook: hookInstalled, notifications: notifyPermission, notifyAsks: notifyAsks)
  }

  var hero: HeroKind {
    HeroKind.make(
      daemonUp: status != nil, top: top?.s, flashBusy: flashBusy, boardKnown: boardEverSeen, boardConnected: boardConnected)
  }

  func finishWelcome() {
    welcomed = true
    sawSetupOffers()  // the welcome asked
    UserDefaults.standard.set(true, forKey: "welcomed")
  }

  /// The window, from the panel or anywhere else: on the pane asked for, or where it was.
  func showSettings(_ pane: String? = nil) {
    if let pane { window.pane = pane }
    showWindow()
  }

  /// Settings, from the gear or Command-comma: the setting last looked at, unless one is open already.
  func openSettings() {
    let list = WindowPanes.settingsList(panes)
    if !list.contains(where: { $0.id == window.pane }), let setting = WindowPanes.setting(window.setting, in: list) {
      window.pane = setting
    }
    showWindow()
  }

  /// The window's panes, as things stand: an extension's among them.
  var panes: [[PaneItem]] {
    WindowPanes.groups(
      welcomed: welcomed, boardMatters: boardMatters,
      extra: Extensions.panes.map {
        (PaneItem(id: $0.id, title: $0.title, icon: $0.icon, summary: $0.summary), $0.settings)
      })
  }

  private func showWindow() {
    noteSetupSeen()
    AppWindow.shared?.show()
    StatusPanel.shared?.close()  // after: it sits above other windows, and closing it first could hide the app
  }

  /// The window has been opened. Written once, not each time.
  func noteSetupSeen() {
    guard welcomed, !setupSeen else { return }
    setupSeen = true
    UserDefaults.standard.set(true, forKey: "setupSeen")
  }

  /// Back to how the app is on a Mac that never had a board, until one is plugged in again. Only this
  /// app's memory of it: the board, its name and what it may approve are the daemon's, and stay.
  func forgetBoard() {
    guard !boardConnected, !flashBusy else { return }
    boardEverSeen = false
    UserDefaults.standard.removeObject(forKey: "boardEverSeen")
    show("Board forgotten. Plug one in and it's back.")
  }

  func start() {
    Task {
      _ = await hooks.hook("repair")  // the app may have moved since the hook was added
      refreshHook()
    }
    alerts.start(model: self)
    for start in Extensions.started { start(self) }
    refreshPermission()  // never asks by itself: see turnOnNotifications
    startAppUpdates()
    poll()
    // Common modes: these must keep going while the panel's open.
    let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.poll() }
    }
    RunLoop.main.add(timer, forMode: .common)
    pollTimer = timer
    let frames = Timer(timeInterval: 0.34, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.working > 0 else { return }
        self.iconTick += 1
        self.updateIcon()
      }
    }
    RunLoop.main.add(frames, forMode: .common)
    iconTimer = frames
  }

  /// Once a second, and after anything that changes what the daemon would say.
  func poll() {
    if polling { return }
    polling = true
    Task {
      let (selected, inWindow) = (self.selected, window.isShowing(WindowPanes.agents) ? windowAgent?.id : window.selected)
      // Each asked in a task of its own, at once. (`async let` over these aborted in the Swift runtime
      // when its task was freed, once the reply grew.)
      let asked = Task { await self.daemon.ask(DaemonStatus.self, ["t": "status"]) }
      let fetched = Task { selected == nil ? nil : await self.fetchActivity(selected!) }
      // The same agent open in both is asked about once.
      let fetchedForWindow = Task { inWindow == nil || inWindow == selected ? nil : await self.fetchActivity(inWindow!) }
      let (reply, items, windowItems) = await (asked.value, fetched.value, fetchedForWindow.value)
      polling = false
      took(reply)
      if reply != nil { refreshSetups(ifOlderThan: 300) }
      if let items, self.selected == selected { activity = items.items }
      if let inWindow, let shown = inWindow == selected ? items : windowItems {
        (window.activity, window.about, window.activityFor) = (shown.items, shown.about, inWindow)
      }
    }
  }

  /// What the daemon said, or nil if it said nothing: everything shown follows from this.
  func took(_ reply: DaemonStatus?) {
    status = reply
    Look.apply(reply?.look)
    for polled in Extensions.polled { polled(self) }
    pinAsk()
    stepAlerts()
    stepFirmware()
    stepPet()
    // The agent ended: its page has nothing left to show.
    if let reply, let open = selected, !reply.s.contains(where: { $0.id == open }) {
      selected = nil
    }
    if let reply, let open = window.selected, !reply.s.contains(where: { $0.id == open }) {
      window.selected = nil
    }
    supervisor.tick(heard: reply != nil)
    problem = supervisor.problem
    updateIcon()
  }

  private func fetchActivity(_ id: String) async -> ActivityReply? {
    await daemon.ask(ActivityReply.self, ["t": "activity", "id": id])
  }

  private func updateIcon() {
    let faded = status == nil  // never for the board: most people have none, and the app works without
    // With nothing going on it's Bit as ever, greyed. Asleep is only for a daemon that isn't running.
    let pose: BitPose = faded ? .nap : needs > 0 ? .alert : working > 0 ? .work : .idle
    let quiet = faded || pose == .idle
    let key = "\(pose)-\(quiet)-\(needs)-\(pose == .work ? iconTick : 0)"
    if key == iconKey { return }
    iconKey = key
    icon = MenuIcon.make(pose: pose, tick: iconTick, faded: quiet, needs: needs)
  }

  // ---------------------------------------------------------------- keys

  /// A key pressed in the panel. False if it did nothing here, and goes on to whatever would have had it.
  func handle(_ key: PanelKey) -> Bool {
    if key == .settings {
      openSettings()
      return true
    }
    guard page == .agents else { return false }
    switch key {
    case .close, .settings:
      return false  // the panel's own, and done above
    case .up, .down:
      guard selected == nil else { return false }
      highlighted = PanelKeys.moved(
        from: highlighted, by: key == .down ? 1 : -1, in: listRows.filter(\.canOpen).map(\.id))
      return true
    case .open:
      guard selected == nil, let row = listRows.first(where: { $0.id == highlighted }) else { return false }
      select(row)
      return true
    case .back:
      guard selected != nil else { return false }
      selected = nil
      return true
    case .deny:
      // Only the prompt on screen, and only once its buttons work: a key is held to the same delay as a click.
      let shown = selected == nil ? heroAsk : selectedRow
      guard let shown, shown.s == "blocked", shown.ask == "approve", let rev = shown.rev, rev == armedAsk else { return false }
      answer(shown, action: "deny")
      return true
    }
  }

  // ---------------------------------------------------------------- actions

  /// Opens an agent's page where it was clicked: in the panel, or in the window. Never in both.
  func select(_ row: AgentRow, inWindow: Bool = false) {
    guard row.canOpen else { return }
    if inWindow {
      if window.activityFor != row.id { (window.activity, window.about, window.activityFor) = ([], nil, row.id) }
      window.selected = row.id
    } else {
      activity = []
      selected = row.id
    }
    let id = row.id
    let done = row.s == "done"
    Task {
      if done { _ = await daemon.act(["t": "app-act", "a": "seen", "id": id]) }  // as on the board
      guard let items = await fetchActivity(id) else { return }
      if inWindow {
        if window.selected == id { (window.activity, window.about, window.activityFor) = (items.items, items.about, id) }
      } else if selected == id {
        activity = items.items
      }
    }
  }

  /// Goes only to the prompt with this rev: if it's gone, the daemon refuses and nothing is decided.
  func answer(_ row: AgentRow, action: String, picks: [[String: Any]]? = nil) {
    guard let rev = row.rev else { return }
    answer(id: row.id, rev: rev, action: action, picks: picks)
  }

  /// False if nothing was sent, because another answer is still on its way.
  @discardableResult
  func answer(id: String, rev: String, action: String, picks: [[String: Any]]? = nil) -> Bool {
    guard answering == nil else { return false }
    answering = rev
    var request: [String: Any] = ["t": "app-act", "a": action, "id": id, "rev": rev]
    if let picks { request["ans"] = picks }
    Task {
      let reply = await daemon.act(request, timeout: 5)
      answering = nil
      if !reply.ok { show(reply.problem()) }
      poll()
    }
    return true
  }

  func open(_ row: AgentRow) {
    guard row.canOpen else { return }
    let id = row.id
    Task {
      let reply = await daemon.act(["t": "app-act", "a": "open", "id": id], timeout: 8)
      if reply.ok {
        StatusPanel.shared?.close()
      } else {
        show(reply.problem(or: "couldn't open it"))
      }
    }
  }

  func show(_ message: String) {
    toast = message
    if notifies, !Alerts.panelIsOpen { alerts.postNote(message) }  // nowhere else to see it
    toastGeneration += 1
    let generation = toastGeneration
    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
      MainActor.assumeIsolated {
        if generation == self.toastGeneration { self.toast = nil }
      }
    }
  }

  // ---------------------------------------------------------------- notifications

  /// Your eyes are probably on an agent whose pane is focused in a terminal in front, if you
  /// touched the Mac lately. Long enough without input, and it may need calling after all.
  private func watching() -> (AgentRow) -> Bool {
    let panel = Alerts.panelIsOpen
    let anyInput = CGEventType(rawValue: ~0)!
    let recent = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput) < 120
    let inFront = status?.term != nil && NSWorkspace.shared.frontmostApplication?.localizedName == status?.term
    return { row in panel || (recent && inFront && row.foc == true) }
  }

  private func stepAlerts() {
    guard notifies else { return }
    permissionTick += 1
    if permissionTick % 5 == 0 { refreshPermission() }
    guard status != nil else { return }  // no news: everything stays as it is
    let allowed = notifyPermission == .authorized || notifyPermission == .provisional
    let steps = planner.plan(
      rows, now: Date(), watching: watching(), asks: allowed && notifyAsks, finishes: allowed && notifyFinishes)
    for step in steps {
      switch step {
      case .ask(let id):
        if let row = rows.first(where: { $0.id == id }) { alerts.postAsk(row, sound: notifySound) }
      case .finished(let id):
        if let row = rows.first(where: { $0.id == id }) { alerts.postFinished(row) }
      case .clear(let id):
        alerts.clear(id)
      }
    }
  }

  func alertReply(_ reply: AlertReply, id: String, rev: String, delivered: Date) {
    let row = rows.first { $0.id == id }
    switch reply {
    case .nothing:
      break
    case .show:
      page = .agents
      if let row { select(row) }
      Alerts.openPanel()
    case .open:
      guard let row else { return show("that agent has ended") }
      if row.s == "done" {  // seen, as when it's opened anywhere else
        Task { _ = await daemon.act(["t": "app-act", "a": "seen", "id": id]) }
      }
      open(row)
    case .deny:
      sendAlertAnswer(id: id, rev: rev, action: "deny", picks: nil, delivered: delivered)
    case .choose(let number):
      sendAlertAnswer(id: id, rev: rev, action: "answer", picks: [["o": [number], "t": ""]], delivered: delivered)
    case .type(let text):
      sendAlertAnswer(id: id, rev: rev, action: "answer", picks: [["o": [Int](), "t": text]], delivered: delivered)
    }
  }

  /// As on the board: a click this soon after a prompt appears isn't an answer to it.
  private func sendAlertAnswer(id: String, rev: String, action: String, picks: [[String: Any]]?, delivered: Date) {
    let tooSoon = Date().timeIntervalSince(delivered) < 0.6
    if tooSoon || !answer(id: id, rev: rev, action: action, picks: picks) {
      planner.forget(id)  // the notification's been used up; the prompt still needs one
    }
  }

  func refreshPermission() {
    guard notifies, !window.preview else { return }
    alerts.refreshPermission { status in
      DispatchQueue.main.async { MainActor.assumeIsolated { self.notifyPermission = status } }
    }
  }

  /// Only from a click. macOS answered a request made in the background with a refusal and no
  /// prompt, and remembered it; and starting up must not take the focus to ask from the front.
  func turnOnNotifications() {
    NSApp.activate()
    alerts.requestPermission { status, problem in
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          self.notifyPermission = status
          self.notifyProblem = problem
        }
      }
    }
  }

  func setNotify(asks: Bool? = nil, finishes: Bool? = nil, sound: Bool? = nil) {
    if let asks {
      notifyAsks = asks
      UserDefaults.standard.set(asks, forKey: "notifyAsks")
    }
    if let finishes {
      notifyFinishes = finishes
      UserDefaults.standard.set(finishes, forKey: "notifyFinishes")
    }
    if let sound {
      notifySound = sound
      UserDefaults.standard.set(sound, forKey: "notifySound")
    }
  }

  func stopAlerts() { alerts.stop() }

  // ---------------------------------------------------------------- the pet

  /// Goes to the daemon: the board shows the change at its next update too.
  func petAct(_ action: String, arg: String = "", done: (() -> Void)? = nil) {
    Task {
      let reply = await daemon.act(["t": "app-act", "a": action, "id": "", "rev": arg])
      if reply.ok {
        done?()
      } else {
        show(reply.problem())
      }
      poll()
    }
  }

  /// Agents come first, as on the board: something new leaves the pet at once. What was already
  /// waiting stays out of the way, with a line saying so.
  private func stepPet() {
    guard status != nil else { return }
    notePetEvents()
    let now = HandsOff.needs(in: rows)
    let fresh = seenNeeds.map { now.subtracting($0) } ?? []
    seenNeeds = now
    guard page == .pet, !fresh.isEmpty else { return }
    handsOffUntil = Date().addingTimeInterval(HandsOff.afterInterruption)
    page = .agents
  }

  /// A pat from either place, and turns agents finish, show the same here as on the board.
  private func notePetEvents() {
    guard let pet = status?.pet else { return }
    if let seen = seenPetEv, pet.ev != seen, let kind = PetEvent.Kind(rawValue: pet.evk ?? "") {
      if kind.isHello, page != .pet {
        pendingHello = kind
      } else {
        petEvent = PetEvent(kind: kind, at: Date())
      }
    }
    seenPetEv = pet.ev
    // A level can come from age alone, with no turn to show.
    if let total = seenPetTotal, let level = seenPetLevel, pet.total > total || pet.level > level {
      petEvent = PetEvent(kind: .reward, at: Date(), turns: max(0, pet.total - total), levelUp: pet.level > level)
    }
    seenPetTotal = pet.total
    seenPetLevel = pet.level
  }

  /// Quicker while you're looking at it, so a tap on the board shows here at once.
  func petPageOpen(_ open: Bool) {
    petTimer?.invalidate()
    petTimer = nil
    guard open, StatusPanel.shared != nil else { return }  // a --preview shows only its sample data
    if let kind = pendingHello {
      pendingHello = nil
      petEvent = PetEvent(kind: kind, at: Date())
    }
    let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.poll() }
    }
    RunLoop.main.add(timer, forMode: .common)
    petTimer = timer
  }

  /// What's waiting on you comes before the pet whenever the panel opens.
  func panelOpening() {
    highlighted = nil
    armedAsk = nil
    Task { _ = await daemon.act(["t": "app-act", "a": "pet-here", "id": ""]) }
    if page == .pet, needs > 0 {
      handsOffUntil = Date().addingTimeInterval(HandsOff.afterInterruption)
      page = .agents
    }
  }

  // ---------------------------------------------------------------- firmware

  var flashBusy: Bool { flashStarting || status?.flash?.busy == true || status?.core?.busy == true }

  func stepFirmware() {
    let board = status?.board
    if board?.connected == true, !boardEverSeen {
      boardEverSeen = true
      UserDefaults.standard.set(true, forKey: "boardEverSeen")
    }
    firmwarePlan = FirmwarePlan.make(status: status, image: bestFirmware.image)
    noticeBoardAsking()

    // An update takes a while: you may have closed the panel by the time it ends.
    let state = status?.flash?.state
    if state != lastFlashState, let flash = status?.flash, lastFlashState != nil {
      if flash.job == "read" {
        if state == "done" { show(status?.core?.registered == true ? "\(boardTitle) is registered: its updates show in Settings > Board"
                                  : "\(boardTitle) was read, but not registered: see ~/.ttycat/ttycatd.log") }
        if state == "failed" { show("Couldn't register \(boardTitle): \(flash.msg)") }
      } else {
        if state == "done" { show("\(boardTitle) updated to \(flash.to ?? "the new firmware")") }
        if state == "failed" { show("\(boardTitle) update failed: \(flash.msg)") }
      }
    }
    if state != nil { lastFlashState = state }

    // A core update takes minutes: it's said when it ends, wherever you are.
    let core = status?.core
    if core?.state != lastCoreState, let core, lastCoreState != nil {
      if core.state == "done" { show("\(boardTitle) updated to core \(core.to ?? "")") }
      if core.state == "failed" { show("\(boardTitle)'s core update failed: \(core.msg)") }
    }
    if let state = core?.state { lastCoreState = state }
  }

  /// Builds the newest signed core release with the board's own folder, then writes it: daemon/core_update.py.
  func updateCore() {
    guard !flashBusy else { return }
    flashStarting = true
    Task {
      // The release is checked and unpacked before the build starts; that's quick.
      let reply = await daemon.act(["t": "core-update"], timeout: 30)
      flashStarting = false
      if !reply.ok { show(reply.problem()) }
      poll()
    }
  }

  /// "Choose its folder", in the window: where a board of the person's own has its code, so ttycat's updates
  /// can be built for it. The daemon checks the folder fits the board, then reads what the board runs as the
  /// copy to put back: daemon/ttycatd.py start_register. A sheet on the window, where how it went then shows.
  func chooseBoardFolder() {
    guard !flashBusy, let name = status?.board.name else { return }
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true  // New Folder, for a board whose folder isn't made yet
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose"
    panel.message = "The folder with \(boardTitle)'s own code, named \(name)"
    if let folder = status?.core?.folder {
      panel.directoryURL = URL(fileURLWithPath: folder).deletingLastPathComponent()
    }
    let chosen: (NSApplication.ModalResponse) -> Void = { response in
      MainActor.assumeIsolated {
        guard response == .OK, let url = panel.url else { return }
        self.registerBoard(folder: url.path)
      }
    }
    showSettings(WindowPanes.board)
    if let window = AppWindow.shared?.window {
      panel.beginSheetModal(for: window, completionHandler: chosen)
    } else {
      panel.begin(completionHandler: chosen)
    }
  }

  private func registerBoard(folder: String) {
    guard !flashBusy else { return }
    flashStarting = true
    registerRefused = nil
    Task {
      let reply = await daemon.act(["t": "register", "folder": folder], timeout: 10)
      flashStarting = false
      if !reply.ok { registerRefused = reply.problem() }
      poll()
    }
  }

  /// A board that can't approve yet was tapped: the prompt comes up here, where it can be answered.
  /// Said once, for that tap. Setup never nags about it: nothing should push anyone towards approving.
  private func noticeBoardAsking() {
    guard let board = status?.board else { return }
    let asks = board.asks ?? 0
    defer { boardAsksSeen = asks }
    guard let seen = boardAsksSeen, asks > seen else { return }
    page = .agents
    if let row = rows.first(where: { $0.id == board.asked && $0.s == "blocked" }) {
      pinnedAsk = row.rev
      select(row)
    }
    Alerts.openPanel()
    show("\(board.label ?? board.fw ?? "It") can't approve yet. Settings > Board can change that.")
  }

  /// The firmware to offer the official board, and where it is: see FirmwareImage.best.
  var bestFirmware: (image: FirmwareImage?, folder: String?) {
    FirmwareImage.best(carried: firmwareImage, carriedFolder: FirmwareImage.folder, status: status)
  }

  /// Whether the daemon asks ttycat's update server what's new: on start, then every hour.
  /// The app's own updates, in a release: the same setting as the board's, kept by the daemon.
  private func startAppUpdates() {
    appUpdater.ready = { [weak self] version in
      guard let self else { return }
      if let version, version != self.appUpdateReady { self.show("ttycat \(version) is ready to install: Settings > About") }
      self.appUpdateReady = version
    }
    let setting = URL(fileURLWithPath: NSHomeDirectory() + "/.ttycat/updates.json")
    let check = (try? Data(contentsOf: setting))
      .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["check"] as? Bool ?? true
    appUpdater.start(checking: check)
  }

  func setUpdateCheck(_ on: Bool) {
    appUpdater.setChecking(on)
    Task {
      _ = await daemon.act(["t": "updates", "check": on])
      poll()
    }
  }

  /// `unknown`: you've agreed to overwrite a device that hasn't said what it is. `port`: which one.
  func updateFirmware(unknown: Bool = false, port: String? = nil) {
    guard !flashBusy, let folder = bestFirmware.folder else { return }
    flashStarting = true
    // The image's hashes are checked first; that's quick.
    var request: [String: Any] = ["t": "flash", "dir": folder, "unknown": unknown]
    if let port { request["port"] = port }
    Task {
      let reply = await daemon.act(request, timeout: 8)
      flashStarting = false
      if !reply.ok { show(reply.problem()) }
      poll()
    }
  }

  /// What to call the board: the name it was given, or plainly "Board".
  var boardTitle: String { status?.board.label ?? "Board" }

  /// Names the board that's plugged in. Empty takes the name away. Approving stays with each build.
  func nameBoard(_ name: String) {
    Task {
      let reply = await daemon.act(["t": "name", "name": name])
      if !reply.ok { show(reply.problem()) }
      poll()
    }
  }

  /// Whether the custom firmware that's plugged in may say yes to prompts.
  func setDeviceApproves(_ name: String, _ on: Bool) {
    Task {
      let reply = await daemon.act(["t": "device", "fw": name, "approve": on])
      if !reply.ok { show(reply.problem()) }
      poll()
    }
  }

  func restartDaemon() {
    supervisor.restart(runningPid: status?.pid)
    status = nil
    updateIcon()
  }

  /// What to ask about, once each: an agent on this Mac that ttycat could do more for.
  var setupOffers: [SetupOffer] { seenSetups.map { SetupOffers.make(setups, seen: $0) } ?? [] }

  /// Read when the app starts, when the window shows it, and now and then: an agent installed later is found this way.
  func refreshSetups(ifOlderThan age: TimeInterval = 0) {
    guard !window.preview, Date().timeIntervalSince(setupsReadAt) >= age else { return }
    setupsReadAt = Date()
    Task {
      guard let data = await hooks.setup(["list"]), let list = try? JSONDecoder().decode(SetupList.self, from: data) else { return }
      tookSetups(list.agents)
    }
  }

  func tookSetups(_ agents: [AgentSetup], stored: [String]? = UserDefaults.standard.stringArray(forKey: "seenSetups")) {
    setups = agents
    if seenSetups == nil {
      seenSetups = SetupOffers.seen(stored: stored, welcomed: welcomed, agents: agents)
      if stored == nil, !window.preview { UserDefaults.standard.set(Array(seenSetups ?? []), forKey: "seenSetups") }
    }
  }

  /// Everything offered now has had its answer, whatever it was: it isn't asked again.
  func sawSetupOffers() {
    guard let seen = seenSetups else { return }
    let all = seen.union(setups.filter(\.found).flatMap { $0.adds.map(\.id) })
    guard all != seen else { return }
    seenSetups = all
    if !window.preview { UserDefaults.standard.set(Array(all), forKey: "seenSetups") }
  }

  /// Adds or removes the one thing named, and only that.
  func changeSetup(_ id: String, install: Bool) {
    setupBusy = true
    seenSetups?.insert(id)
    if let seen = seenSetups, !window.preview { UserDefaults.standard.set(Array(seen), forKey: "seenSetups") }
    Task {
      let data = await hooks.setup([install ? "install" : "remove", id])
      let reply = data.flatMap { try? JSONDecoder().decode(SetupReply.self, from: $0) }
      if let data = await hooks.setup(["list"]), let list = try? JSONDecoder().decode(SetupList.self, from: data) {
        setups = list.agents
      }
      setupBusy = false
      refreshHook()
      if reply?.ok != true { show(reply?.msg.map { "couldn't change it: \($0)" } ?? "couldn't change that agent's settings") }
    }
  }

  func refreshHook() {
    guard !window.preview else { return }  // a --preview shows only its sample data
    Task {
      let result = await hooks.hook("status")
      hookInstalled = result.ok ? result.installed : nil
    }
  }

  func refreshLogin() { if !window.preview { loginState = SMAppService.mainApp.status } }

  /// Everything ttycat added to this Mac taken away, after asking: its hook in Claude's settings, its
  /// login item, what an extension added, and if you choose, ~/.ttycat with Bit in it. Then it quits
  /// and moves itself to the Trash. The board, if there is one, keeps its firmware.
  func uninstall() {
    StatusPanel.shared?.close()  // the panel sits above other windows: the alert would be behind it
    NSApp.activate()
    let alert = NSAlert()
    alert.messageText = "Uninstall ttycat?"
    alert.informativeText = "It takes its hook out of Claude's settings and removes its login item, then quits "
      + "and moves itself to the Trash. Claude asks in the terminal again, as before."
      + (boardMatters ? " The board keeps its firmware." : "")
    let everything = NSButton(checkboxWithTitle: "Also delete Bit, its level, and ttycat's settings", target: nil, action: nil)
    everything.state = .off
    alert.accessoryView = everything
    alert.addButton(withTitle: "Uninstall")
    alert.addButton(withTitle: "Cancel")
    alert.buttons[0].hasDestructiveAction = true
    guard alert.runModal() == .alertFirstButtonReturn else { return }

    // Only changes Claude's settings if the hook is there: someone without Claude has none to change.
    let found = supervisor.hook("status")
    let removed = found.ok && !found.installed ? found : supervisor.hook("remove")
    for uninstalling in Extensions.uninstalling { uninstalling(self) }
    try? SMAppService.mainApp.unregister()
    stopAlerts()
    supervisor.stopForQuit()
    if !removed.ok {
      // Never leave someone with a hook they didn't know about: the app stays, so they can try again.
      let failed = NSAlert()
      failed.messageText = "ttycat couldn't change Claude's settings"
      failed.informativeText = "Its hook is still in ~/.claude/settings.json, so ttycat stays installed. Open Settings to try again."
      failed.runModal()
      restartDaemon()
      return
    }
    if everything.state == .on {
      try? FileManager.default.removeItem(atPath: NSHomeDirectory() + "/.ttycat")
      if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
    }
    try? FileManager.default.trashItem(at: Bundle.main.bundleURL, resultingItemURL: nil)  // not from a disk image
    exit(0)  // not NSApp.terminate: nothing left to stop, and nothing should write its settings back
  }

  func setStartAtLogin(_ on: Bool) {
    do {
      if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    } catch {
      show("login item: \(error.localizedDescription)")
    }
    refreshLogin()
  }
}
