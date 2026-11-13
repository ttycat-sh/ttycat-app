// The name an agent goes by: the one you gave it, else the folder it's in, which is all it had before and
// what makes two in one folder look alike. The daemon keeps the names (daemon/agent_names.py), for every
// kind of agent alike; this is what the app makes of what's typed. No side effects: all testable.
import Foundation

enum AgentName {
  static let longest = 40  // as the daemon keeps it: NAME_MAX

  /// What was typed, as it will be kept: one line, no longer than a name is.
  static func kept(_ typed: String) -> String {
    let line = typed.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return String(line.prefix(longest)).trimmingCharacters(in: .whitespaces)
  }

  /// What to ask the daemon to call it, "" for no name of its own. nil: what's typed changes nothing,
  /// being the name it has, or its folder while it has none.
  static func change(_ typed: String, for row: AgentRow) -> String? {
    let name = kept(typed)
    if name == (row.name ?? "") { return nil }
    return row.name == nil && name == row.p ? nil : name
  }
}
