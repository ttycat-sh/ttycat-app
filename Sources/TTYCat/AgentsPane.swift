// The window's first pane: every agent at once, as cards. The panel is for the one that needs you now;
// this is for looking over all of them.
import SwiftUI

/// What's beside the list of agents: the one that's open, or the first of them. With no agents, why not.
struct AgentsPane: View {
  @EnvironmentObject var m: TTYCatModel

  var body: some View {
    if !m.setupOffers.isEmpty { SetupNotice(offers: m.setupOffers) }
    if m.status == nil {
      empty(word: "STOPPED", line: m.problem ?? "The daemon isn't running. ttycat is starting it.", pose: .nap)
    } else if let row = m.windowAgent {
      AgentDetail(row: row)
    } else {
      empty(word: "READY", line: "No agents yet. Start one in any terminal and it shows up here.", pose: .idle)
    }
  }

  private func empty(word: String, line: String, pose: BitPose) -> some View {
    HStack(spacing: 18) {
      BitView(pose: pose, dot: 6, dimmed: pose == .nap).frame(width: 100, height: 90).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 8) {
        Text(word).font(Pixel.display).foregroundStyle(pose == .nap ? Palette.orange : Palette.white)
        Text(line).font(Pixel.body).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(24)
    .frame(maxWidth: .infinity, alignment: .leading)
    .pixelBox(Palette.card, border: Palette.line)
  }
}

/// The agents, in a column beside the one that's open, as the settings have theirs. Filtering is the
/// Mac's own: a field to type in, and a pop-up button for each thing to choose by, drawn as the board is.
struct AgentsList: View {
  @EnvironmentObject var m: TTYCatModel
  static let width: CGFloat = 336
  private let gutter = Rhythm.apart         // left of everything in the column
  private let barGutter = Rhythm.section    // right of it: the scroll bar runs here, clear of the cards
  /// Fixed, so the cards end where the field above them does whether or not there's a bar beside them.
  private var inner: CGFloat { Self.width - gutter - barGutter }

  var body: some View {
    let filter = m.window.filter.settled(for: m.rows)
    let rows = filter.apply(m.rows)
    let hidden = filter.hiddenNeeds(m.rows)
    let open = m.windowAgent?.id
    VStack(alignment: .leading, spacing: Rhythm.near) {
      Group {
        HStack(alignment: .lastTextBaseline) {
          Text("Agents").font(Pixel.heading).foregroundStyle(Palette.white).accessibilityAddTraits(.isHeader)
          Spacer(minLength: Rhythm.near)
          Text(filter.isOn ? "\(rows.count) of \(m.rows.count)" : "\(m.rows.count)").font(Pixel.small).foregroundStyle(Palette.muted)
            .accessibilityLabel(filter.isOn ? "\(rows.count) of \(m.rows.count) shown" : "\(m.rows.count) agents")
        }
        .frame(height: 40, alignment: .bottom)
        .padding(.bottom, Rhythm.section - Rhythm.near)
        FilterField(text: Binding(get: { m.window.filter.text }, set: { m.window.filter.text = $0 }))
        HStack(spacing: Rhythm.near) {
          stateMenu(filter)
          let kinds = AgentFilter.harnesses(m.rows)
          if !kinds.isEmpty { kindMenu(filter, kinds) }
        }
        if hidden > 0 {
          // As the board says when an agent on another tab wants you: a filter never hides that.
          Button {
            m.window.filter = AgentFilter()
          } label: {
            Caps("\(hidden) more need\(hidden == 1 ? "s" : "") you: show all", color: Palette.black)
              .frame(maxWidth: .infinity, minHeight: 26)
              .pixelBox(Palette.orange)
          }
          .buttonStyle(PixelPress())
        }
      }
      .frame(width: inner)
      .padding(.leading, gutter)
      ScrollView(.vertical) {
        LazyVStack(spacing: Rhythm.near) {
          ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            AgentCard(row: row, seed: index, chosen: row.id == open)
          }
          if rows.isEmpty, filter.isOn, !m.rows.isEmpty {
            VStack(alignment: .leading, spacing: Rhythm.near) {
              Text("No agents like that right now.").font(Pixel.small).foregroundStyle(Palette.muted)
              PixelButton(title: "Show all") { m.window.filter = AgentFilter() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .frame(width: inner)
        .padding(.leading, gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Rhythm.apart)
        .pixelScroller()
      }
      .padding(.top, Rhythm.near)
    }
    .padding(.top, Rhythm.page)
    .frame(width: Self.width, alignment: .leading)
    .frame(maxHeight: .infinity, alignment: .top)
    .background(Palette.black.opacity(0.35))
  }

  /// Which state to list: each says how many there are, among the kind of agent chosen.
  private func stateMenu(_ filter: AgentFilter) -> some View {
    let tally = AgentTally(AgentFilter(harness: filter.harness).apply(m.rows))
    let names: [(AgentFilter.State, String, Int)] = [
      (.needs, "Need you", tally.needs), (.working, "Working", tally.working), (.done, "Done", tally.done), (.idle, "Idle", tally.idle),
    ]
    return PopUp(name: "Status", value: names.first { $0.0 == filter.state }?.1 ?? "All", on: filter.state != nil) {
      Picker("Status", selection: Binding(get: { m.window.filter.state }, set: { m.window.filter.state = $0 })) {
        Text("All").tag(AgentFilter.State?.none)
        Divider()
        ForEach(names, id: \.0) { state, name, count in
          Text("\(name) (\(count))").tag(AgentFilter.State?.some(state))
        }
      }
      .pickerStyle(.inline).labelsHidden()
    }
  }

  private func kindMenu(_ filter: AgentFilter, _ kinds: [AgentFilter.Harness]) -> some View {
    PopUp(name: "Agent", value: kinds.first { $0.id == filter.harness }?.name ?? "All", on: filter.harness != nil) {
      Picker("Agent", selection: Binding(get: { filter.harness }, set: { m.window.filter.harness = $0 })) {
        Text("All").tag(String?.none)
        Divider()
        ForEach(kinds) { kind in
          Text("\(kind.name) (\(kind.count))").tag(String?.some(kind.id))
        }
      }
      .pickerStyle(.inline).labelsHidden()
    }
  }
}

/// A pop-up button: what it chooses, the choice made, and the Mac's own menu when clicked.
private struct PopUp<Items: View>: View {
  let name: String
  let value: String
  let on: Bool  // something other than all of them is chosen
  @ViewBuilder let items: Items

  var body: some View {
    Menu {
      items
    } label: {
      HStack(spacing: Rhythm.near) {
        Caps(name, color: Palette.muted2)
        Text(value).font(Pixel.small).foregroundStyle(on ? Palette.orange : Palette.white).lineLimit(1)
        Spacer(minLength: 0)
        PixelIcon(rows: PixelIcon.down, scale: 1, color: Palette.muted)
      }
      .padding(.horizontal, Rhythm.near + 2)
      .frame(maxWidth: .infinity, minHeight: 28)
      .pixelBox(Palette.card, border: on ? Palette.orange : Palette.line)
      .contentShape(Rectangle())
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .accessibilityLabel("\(name): \(value)")
  }
}

/// The field a list is filtered by typing in, as in any Mac sidebar.
private struct FilterField: View {
  @Binding var text: String

  var body: some View {
    HStack(spacing: Rhythm.near) {
      PixelIcon(rows: PixelIcon.find, scale: 1, color: Palette.muted)
      TextField("", text: $text, prompt: Text("Filter").foregroundStyle(Palette.faint))
        .textFieldStyle(.plain)
        .font(Pixel.body)
        .foregroundStyle(Palette.white)
        .accessibilityLabel("Filter agents by name")
      if !text.isEmpty {
        Button {
          text = ""
        } label: {
          PixelIcon(rows: PixelIcon.cross, scale: 1, color: Palette.muted).frame(width: 16, height: 16).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear the filter")
      }
    }
    .padding(.horizontal, Rhythm.near + 2)
    .frame(height: 28)
    .pixelBox(Palette.code, border: text.isEmpty ? Palette.line : Palette.orange)
  }
}

/// How many agents are in each state. No side effects.
struct AgentTally: Equatable {
  var needs = 0, working = 0, done = 0, idle = 0

  var total: Int { needs + working + done + idle }

  /// How many of `cells` each state gets, in the order needs, working, done, idle. Every state that has
  /// an agent gets at least one, and they add up to `cells`: a meter never shows a state that isn't there,
  /// nor hides one that is.
  func cells(_ cells: Int) -> [Int] {
    let counts = [needs, working, done, idle]
    guard total > 0, cells >= counts.filter({ $0 > 0 }).count else { return [0, 0, 0, 0] }
    var out = counts.map { $0 == 0 ? 0 : max(1, $0 * cells / total) }
    // What rounding left over or took too much goes to, or comes from, the largest.
    while out.reduce(0, +) != cells {
      let step = out.reduce(0, +) < cells ? 1 : -1
      let at = out.indices.filter { out[$0] + step >= 1 }.max { out[$0] < out[$1] } ?? 0
      out[at] += step
    }
    return out
  }

  init(_ rows: [AgentRow]) {
    for row in rows {
      switch row.s {
      case "blocked", "error": needs += 1
      case "working": working += 1
      case "done": done += 1
      default: idle += 1
      }
    }
  }
}

/// One agent: who it is, where, and what it's doing. A click opens it beside the list.
struct AgentCard: View {
  @EnvironmentObject var m: TTYCatModel
  @State private var hovering = false
  let row: AgentRow
  let seed: Int
  var chosen = false  // it's the one open beside the list

  private var tone: Color {
    switch row.s {
    case "blocked", "error": Palette.orange
    case "done": Palette.green
    default: Palette.line
    }
  }

  /// Only what needs you is framed: a finished one has its green dot, and that's enough.
  private var border: Color {
    row.needsYou ? Palette.orange : chosen ? Palette.white : hovering && row.canOpen ? Palette.muted2 : Palette.line
  }

  private var state: String {
    switch row.s {
    case "blocked": "needs you"
    case "error": "error"
    case "done": "done"
    case "working": "working"
    default: "idle"
    }
  }

  private var counts: AgentCounts { AgentCounts(row) }

  var body: some View {
    Button {
      m.select(row, inWindow: true)  // a row that's the one shown only by being first becomes the one chosen
    } label: {
      VStack(alignment: .leading, spacing: 9) {
        HStack(alignment: .top, spacing: 10) {
          BitView(pose: row.s == "working" ? .work : row.s == "done" ? .happy : row.needsYou ? .alert : .idle,
                  dot: 2, seed: seed, dimmed: row.s == "idle")
            .frame(width: 36, height: 34)
          VStack(alignment: .leading, spacing: 3) {
            Text(row.p ?? "").font(Pixel.title).foregroundStyle(Palette.white).lineLimit(1)
            HStack(spacing: 6) {
              Caps(row.n ?? "Agent", color: Palette.muted2)
              if let host = row.host { Caps(host, color: Palette.white) }
            }
          }
          Spacer(minLength: 0)
          CountsView(counts: counts)
        }
        Text(row.d ?? " ").font(Pixel.small).foregroundStyle(Palette.muted).lineLimit(2, reservesSpace: true)
          .multilineTextAlignment(.leading)
        HStack(spacing: 6) {
          Dot(row.s == "idle" ? Palette.faint : row.s == "working" ? Palette.white : tone)
          Caps(state, color: row.s == "idle" ? Palette.faint : row.s == "working" ? Palette.white : tone)
          Spacer(minLength: 4)
          // What an extension has to say of it: Extensions.cardNotes.
          if let note = Extensions.cardNote(row) {
            Text(note).font(Pixel.small).foregroundStyle(Palette.muted2).lineLimit(1)
          }
          Text(ageText(row.age)).font(Pixel.small).foregroundStyle(Palette.muted)
          // Room for the way to its newest request, which sits over the card: a button can't hold another.
          if let link = row.prs?.first { PullChip(link: link).hidden() }
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .pixelBox(chosen ? Palette.tile : Palette.card, border: border)
    }
    .buttonStyle(PixelPress())
    .disabled(!row.canOpen)
    .onHover { hovering = $0 }
    .accessibilityElement(children: .ignore)
    .overlay(alignment: .bottomTrailing) {
      if let link = row.prs?.first { PullChip(link: link).padding(12) }
    }
    .accessibilityLabel("\(row.p ?? "agent"), \(row.n ?? ""), \(state)\(counts.isEmpty ? "" : ", " + counts.spoken)\(Extensions.cardNote(row).map { ", " + $0 } ?? "")")
    .accessibilityAddTraits(chosen ? .isSelected : [])
  }
}

/// What an agent has started and not finished: subagents, and shells left open.
struct CountsView: View {
  let counts: AgentCounts

  var body: some View {
    if !counts.isEmpty {
      HStack(spacing: Rhythm.near) {
        if let c = counts.subagents { one(PixelIcon.branch, c) }
        if let c = counts.shells { one(PixelIcon.shell, c) }
      }
      .help(counts.spoken)
    }
  }

  private func one(_ icon: [UInt8], _ count: AgentCounts.Count) -> some View {
    HStack(spacing: Rhythm.tight) {
      PixelIcon(rows: icon, scale: 2, color: Palette.muted2)
      Text(count.text).font(Pixel.small).foregroundStyle(Palette.white)
    }
  }
}
