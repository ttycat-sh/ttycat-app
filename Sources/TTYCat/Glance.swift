// What the Agents page leads with, and whether the panel's gear asks for the window to be opened. No side effects: all testable.
import UserNotifications

/// The card at the top of the Agents page when no prompt is waiting. Agents come before the board:
/// one that failed or finished is never hidden behind a board that's unplugged.
enum HeroKind: Equatable {
  case stopped    // no daemon
  case error      // the first agent failed
  case updating   // firmware is being written
  case done       // the first agent finished
  case unplugged  // a board this Mac knows isn't connected
  case ready      // no agents yet
  case clear      // agents, and none needs you

  /// `top`: the state of the first row in the daemon's order, if there is one.
  static func make(daemonUp: Bool, top: String?, flashBusy: Bool, boardKnown: Bool, boardConnected: Bool) -> HeroKind {
    guard daemonUp else { return .stopped }
    if top == "error" { return .error }
    if flashBusy { return .updating }
    if top == "done" { return .done }
    if boardKnown && !boardConnected { return .unplugged }
    return top == nil ? .ready : .clear
  }
}

/// Without a board, the hook and notifications are the whole of how the app reaches you. Someone who
/// left one off the first time is shown where it is, once: the mark goes when the window has been opened.
enum SetupNudge {
  static func wanted(welcomed: Bool, setupSeen: Bool, hook: Bool?, notifications: UNAuthorizationStatus, notifyAsks: Bool) -> Bool {
    guard welcomed, !setupSeen else { return false }
    // Only what a click in the window can still turn on: a refusal in System Settings was an answer.
    return hook == false || (notifyAsks && notifications == .notDetermined)
  }
}

/// The rows under the card at the top. As on the board, what needs you is the hero: the prompt on the
/// card, or else a first agent that failed or finished, isn't listed again below it.
enum AgentList {
  /// `top`: the daemon's first row, which is what the card shows. The list has its own order.
  static func below(_ rows: [AgentRow], ask: String?, top: AgentRow? = nil) -> [AgentRow] {
    if let ask { return rows.filter { $0.id != ask } }
    guard let top = top ?? rows.first, top.s == "error" || top.s == "done" else { return rows }
    return rows.filter { $0.id != top.id }
  }
}

extension ActivityItem {
  /// The daemon counts back from now, "-4s". Here it's how long ago, as everywhere else in the panel.
  var shownAge: String { age.hasPrefix("-") ? String(age.dropFirst()) : age }
}
