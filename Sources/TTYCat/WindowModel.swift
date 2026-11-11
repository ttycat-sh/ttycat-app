// Which panes the window has and which one it's on. No side effects: all testable.
import Observation

struct PaneItem: Equatable, Identifiable {
  let id: String
  let title: String
  var icon = PixelIcon.navGrid  // 7 x 7 pixels, for the sidebar
  var summary: String?            // a line under the title
}

enum WindowPanes {
  static let welcome = "welcome", agents = "agents", general = "general", notifications = "notifications"
  static let board = "board", advanced = "advanced", about = "about", agentSetup = "agent-setup"

  /// The sidebar, in its groups: the welcome while it's wanted, the agents and what an extension gives to
  /// look at, then the settings. The board has a pane only on a Mac that has had one.
  /// `extra`: an extension's panes, in its order, and whether each is a setting.
  static func groups(welcomed: Bool, boardMatters: Bool, extra: [(pane: PaneItem, settings: Bool)]) -> [[PaneItem]] {
    var settings = [
      PaneItem(id: general, title: "General", icon: PixelIcon.navGear, summary: "How ttycat starts and stops."),
      PaneItem(id: agentSetup, title: "Agents", icon: PixelIcon.navKey, summary: "What ttycat shows of each agent, and what it can add to them. Nothing is added unless you turn it on."),
      PaneItem(id: notifications, title: "Notifications", icon: PixelIcon.navBell, summary: "When ttycat calls you, and what it says."),
    ]
    if boardMatters {
      settings.append(PaneItem(id: board, title: "Board", icon: PixelIcon.navChip, summary: "The board on your desk: its name, and what it runs."))
    }
    settings += extra.filter(\.settings).map(\.pane)
    settings += [
      PaneItem(id: advanced, title: "Advanced", icon: PixelIcon.navPrompt, summary: "The daemon that watches your agents, and removing ttycat."),
      PaneItem(id: about, title: "About", icon: PixelIcon.navInfo),
    ]
    let first = welcomed ? [] : [PaneItem(id: welcome, title: "Welcome", icon: PixelIcon.navHeart)]
    let look = [PaneItem(id: agents, title: "Agents", icon: PixelIcon.navGrid)]
      + extra.filter { !$0.settings }.map(\.pane)
    return [first, look, settings].filter { !$0.isEmpty }
  }

  /// The row of the sidebar that stands for every setting: they're one place, with a list of their own.
  static let settings = "settings"

  /// The sidebar as it's drawn: the last group of `groups` is the settings, and here they're one row.
  static func sidebar(_ groups: [[PaneItem]]) -> [[PaneItem]] {
    guard groups.count > 1 || groups.first?.contains(where: { $0.id == general }) == true else { return groups }
    return Array(groups.dropLast()) + [[PaneItem(id: settings, title: "Settings", icon: PixelIcon.navGear)]]
  }

  /// The settings there are, for the list beside them.
  static func settingsList(_ groups: [[PaneItem]]) -> [PaneItem] {
    groups.last { $0.contains { $0.id == general } } ?? []
  }

  /// The setting to open from the sidebar: the one last looked at if it's still there, or the first.
  static func setting(_ last: String, in list: [PaneItem]) -> String? {
    (list.first { $0.id == last } ?? list.first)?.id
  }

  /// The pane to show: the one asked for if it's there, or else the first. A pane can go while the window
  /// is on it, as the welcome does, or the board's when it's forgotten.
  static func shown(_ wanted: String, in groups: [[PaneItem]]) -> PaneItem? {
    let all = groups.flatMap { $0 }
    return all.first { $0.id == wanted } ?? all.first { $0.id == agents } ?? all.first
  }

  /// Under the app's name in the sidebar: how things stand, in a few words.
  static func status(daemonUp: Bool, agents: Int, needs: Int) -> String {
    guard daemonUp else { return "Daemon stopped" }
    if needs > 0 { return "\(needs) need\(needs == 1 ? "s" : "") you" }
    return agents == 0 ? "No agents running" : "\(agents) agent\(agents == 1 ? "" : "s") running"
  }
}

/// The window's own state: nothing here is about agents.
@MainActor @Observable
final class WindowModel {
  var pane = WindowPanes.agents
  var setting = WindowPanes.general  // the setting last looked at: where the sidebar's Settings goes
  var isOpen = false
  var filter = AgentFilter()  // which agents the Agents pane lists
  // The agent open in the window, and what it's been doing. The panel has its own: the two are looked
  // at separately, and opening an agent in one leaves the other where it was.
  var selected: String?
  var activity: [ActivityItem] = []
  var about: AgentAbout?  // of the same agent
  var activityFor: String?  // the agent `activity` is about: the one shown can change before its own arrives
  var preview = false  // a --preview of the window, not the panel

  /// For what's only worth fetching while someone is looking at it.
  func isShowing(_ id: String) -> Bool { isOpen && pane == id }
}
