// Looking at some of the agents: one kind of agent, one state, or both. As the board's tabs do, it only
// narrows what's listed. What needs you is never lost to it: the prompt's card stays, and anything else
// that needs you and isn't shown is counted, with a way back.
import SwiftUI

struct AgentFilter: Equatable {
  enum State: String, CaseIterable { case needs, working, done, idle }

  var harness: String?  // an agent's two letters, as on the board's tabs: CC, CX, OC, PI
  var state: State?
  var text = ""         // typed: what an agent's name, folder, kind or machine has to contain

  private var typed: String { text.trimmingCharacters(in: .whitespaces) }
  var isOn: Bool { harness != nil || state != nil || !typed.isEmpty }

  static func state(of row: AgentRow) -> State {
    if row.needsYou { return .needs }
    return row.s == "working" ? .working : row.s == "done" ? .done : .idle
  }

  /// The filter as it applies to these rows: a kind of agent that has none left is no longer chosen, so
  /// the list never sits empty behind a tab that has gone.
  func settled(for rows: [AgentRow]) -> AgentFilter {
    var out = self
    if let harness, !rows.contains(where: { $0.a == harness }) { out.harness = nil }
    return out
  }

  func shows(_ row: AgentRow) -> Bool {
    guard (harness == nil || row.a == harness) && (state == nil || Self.state(of: row) == state) else { return false }
    let typed = self.typed
    return typed.isEmpty || [row.title, row.folder, row.n, row.host].contains { $0?.localizedCaseInsensitiveContains(typed) == true }
  }

  func apply(_ rows: [AgentRow]) -> [AgentRow] { isOn ? rows.filter(shows) : rows }

  /// How many need you and aren't among what's shown.
  func hiddenNeeds(_ rows: [AgentRow]) -> Int { isOn ? rows.filter { $0.needsYou && !shows($0) }.count : 0 }

  struct Harness: Equatable, Identifiable {
    let id: String     // CC
    let name: String   // Claude
    let count: Int
    let needs: Int
  }

  /// The kinds of agent there are now, most of first. With one kind or none there's nothing to choose.
  static func harnesses(_ rows: [AgentRow]) -> [Harness] {
    var order: [String] = []
    var found: [String: Harness] = [:]
    for row in rows {
      guard let code = row.a, code != "--" else { continue }  // a machine that can't be reached is no agent
      if found[code] == nil { order.append(code) }
      let was = found[code]
      found[code] = Harness(id: code, name: row.n ?? code, count: (was?.count ?? 0) + 1, needs: (was?.needs ?? 0) + (row.needsYou ? 1 : 0))
    }
    let all = order.compactMap { found[$0] }
    return all.count < 2 ? [] : all.enumerated().sorted { a, b in
      a.element.count != b.element.count ? a.element.count > b.element.count : a.offset < b.offset
    }.map(\.element)
  }
}

/// The kinds of agent, as tabs: All, then each. One with something that needs you says so with a dot.
struct HarnessTabs: View {
  @Environment(\.inWindow) private var inWindow
  let harnesses: [AgentFilter.Harness]
  let total: Int
  let chosen: String?
  var short = false  // two letters each, sharing the width: for the panel, and the window's column
  let pick: (String?) -> Void

  private var wide: Bool { inWindow && !short }

  var body: some View {
    HStack(spacing: wide ? Rhythm.tight : 2) {
      tab(nil, title: "All", count: total, needs: 0, says: "All agents")
      ForEach(harnesses) { h in
        tab(h.id, title: wide ? h.name : h.id, count: h.count, needs: h.needs, says: h.name)
      }
      if wide { Spacer(minLength: 0) }
    }
  }

  private func tab(_ id: String?, title: String, count: Int, needs: Int, says: String) -> some View {
    let on = chosen == id
    return Button {
      pick(id)
    } label: {
      HStack(spacing: Rhythm.tight) {
        if needs > 0 { Dot(on ? Palette.black : Palette.orange) }
        Caps(wide ? "\(title) \(count)" : title, color: on ? Palette.black : Palette.muted2)
      }
      .padding(.horizontal, wide ? 12 : 0)
      .frame(maxWidth: wide ? nil : .infinity, minHeight: inWindow ? 26 : 20)
      .help(says)
      .pixelBox(on ? Palette.orange : Palette.tile, border: on ? nil : Palette.line)
    }
    .buttonStyle(PixelPress())
    .accessibilityLabel("\(says), \(count)\(needs > 0 ? ", \(needs) need you" : "")")
    .accessibilityAddTraits(on ? .isSelected : [])
  }
}
