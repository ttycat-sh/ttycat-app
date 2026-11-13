// One agent, in the window, beside the list of them: who it is, how it stands, what it has running, its
// prompt if it's asking, and what it has been doing. The panel's page is the board's Detail screen; this
// one has the room to say more.
import SwiftUI

/// What's said about an agent in the tiles at the top of its page. No side effects.
struct AgentFacts: Equatable {
  struct Fact: Equatable, Identifiable {
    enum Tone: Equatable { case plain, needs, done, quiet }
    let id: String
    let name: String
    let value: String
    var note: String?
    var tone = Tone.plain
  }

  let facts: [Fact]

  init(_ row: AgentRow, about: AgentAbout? = nil) {
    let state: Fact
    switch row.s {
    case "blocked": state = Fact(id: "state", name: "State", value: "Needs you", tone: .needs)
    case "error": state = Fact(id: "state", name: "State", value: "Error", tone: .needs)
    case "done": state = Fact(id: "state", name: "State", value: "Done", tone: .done)
    case "working": state = Fact(id: "state", name: "State", value: "Working")
    default: state = Fact(id: "state", name: "State", value: "Idle", tone: .quiet)
    }
    let since = Fact(id: "since", name: "For", value: row.age == nil ? "-" : ageText(row.age),
                     tone: row.age == nil ? .quiet : .plain)
    // A count that isn't known is said to be that, never none: see daemon/harness.py.
    let counted = { (id: String, name: String, n: Int?, word: String) -> Fact in
      guard let n else { return Fact(id: id, name: name, value: "Not shown", note: "This kind of agent doesn't say.", tone: .quiet) }
      let guessed = row.guess?.contains(id) ?? false
      if n == 0 { return Fact(id: id, name: name, value: "None", tone: .quiet) }
      return Fact(id: id, name: name, value: "\(guessed ? "~" : "")\(n) \(word)", note: guessed ? "An estimate, from its processes." : nil)
    }
    // What only some kinds of agent say is left out for the others, not shown as empty.
    let more: [Fact?] = [
      about?.model.map { Fact(id: "model", name: "Model", value: Self.model($0), note: $0) },
      about?.ctx.map { Fact(id: "ctx", name: "Context", value: "\(Self.tokens($0)) tokens", note: "What its last reply was given to read.") },
      about?.steps.map { Fact(id: "steps", name: "This turn", value: $0 == 1 ? "1 tool" : "\($0) tools", note: "Tools used since your last prompt.",
                              tone: $0 == 0 ? .quiet : .plain) },
      about?.up.map { Fact(id: "up", name: "Started", value: "\(ageText(Double($0))) ago") },
    ]
    facts = [
      state, since,
      counted("sub", "Subagents", row.sub, "running"),
      counted("sh", "Shells", row.sh, "open"),
      Fact(id: "where", name: "Where", value: row.host ?? "This Mac"),
    ] + more.compactMap { $0 }
  }

  /// "claude-opus-5-5-20260301" is said as "opus-5-5": the maker and the date are in the tile's tip.
  static func model(_ id: String) -> String {
    var parts = id.split(separator: "[").first.map(String.init)?.split(separator: "-").map(String.init) ?? []
    if parts.first == "claude" { parts.removeFirst() }
    if let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) { parts.removeLast() }
    return parts.isEmpty ? id : parts.joined(separator: "-")
  }

  static func tokens(_ n: Int) -> String {
    if n < 1000 { return "\(n)" }
    if n < 999_500 { return "\(Int((Double(n) / 1000).rounded()))k" }
    return String(format: "%.1fM", Double(n) / 1_000_000)
  }

  /// A folder under your own is said from there: "~/code/shop".
  static func folder(_ path: String, home: String = NSHomeDirectory()) -> String {
    path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
  }
}

struct AgentDetail: View {
  @EnvironmentObject var m: TTYCatModel
  let row: AgentRow

  private var renaming: Bool { m.isRenaming(row, inWindow: true) }

  private var activity: [ActivityItem] { m.window.activityFor == row.id ? m.window.activity : [] }
  private var about: AgentAbout? { m.window.activityFor == row.id ? m.window.about : nil }

  var body: some View {
    VStack(alignment: .leading, spacing: Rhythm.section) {
      header
      // As many in a row as there's room for.
      ViewThatFits(in: .horizontal) {
        facts(across: 5)
        facts(across: 4)
        facts(across: 3)
        facts(across: 2)
      }
      if row.s == "blocked" {
        // The whole prompt: it can be answered here because it can be read here.
        AskCard(row: row).id(row.rev).frame(maxWidth: 620, alignment: .leading)
      } else {
        now
      }
      recent
    }
  }

  /// The way to its terminal beside its name where there's room for the name, else under it.
  private var header: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .center, spacing: Rhythm.apart) {
        identity.frame(minWidth: 300, alignment: .leading)
        Spacer(minLength: Rhythm.near)
        terminal
      }
      VStack(alignment: .leading, spacing: Rhythm.apart) {
        identity
        terminal
      }
    }
  }

  private var terminal: some View {
    HStack(spacing: Rhythm.near) {
      if row.canOpen && !renaming {
        PixelButton(title: "Rename") { m.startRenaming(row, inWindow: true) }
          .help("Give it a name of your own, so it can be told from the others in \(row.folder ?? row.p ?? "its folder")")
      }
      PixelButton(title: "Open in terminal", loud: true, enabled: row.canOpen) { m.open(row) }
    }
    .fixedSize()
  }

  private var identity: some View {
    HStack(alignment: .center, spacing: Rhythm.apart) {
      BitView(pose: row.s == "working" ? .work : row.s == "done" ? .happy : row.needsYou ? .alert : .idle,  // idle is Bit as ever, greyed: asleep is for a daemon that's stopped
              dot: 4, dimmed: row.s == "idle")
        .frame(width: 72, height: 68).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: Rhythm.near) {
        if renaming {
          AgentNameField(row: row)
        } else {
          Text(row.title).font(Pixel.headline).foregroundStyle(Palette.white).lineLimit(1).minimumScaleFactor(0.5)
            .accessibilityAddTraits(.isHeader)
        }
        HStack(spacing: Rhythm.near) {
          Caps(row.n ?? "Agent", color: Palette.muted2)
          if let host = row.host { Caps(host, color: Palette.white) }
          // Where it is, once its name no longer says so.
          if let folder = row.folderBesideName { Caps(folder, color: Palette.faint) }
        }
        if let cwd = about?.cwd {
          // Its folder, cut in the middle: the end of a path says the most.
          Text((row.host == nil ? AgentFacts.folder(cwd) : cwd) + (about?.branch.map { "  on \($0)" } ?? "")).font(Pixel.small).foregroundStyle(Palette.muted)
            .lineLimit(1).truncationMode(.middle).textSelection(.enabled).help(cwd)
        }
        if let made = row.prs, !made.isEmpty {
          // What it has put up for review lately, newest first.
          HStack(spacing: Rhythm.near) { ForEach(made) { PullChip(link: $0) } }.padding(.top, Rhythm.tight)
        }
      }
    }
  }

  private func facts(across: Int) -> some View {
    let column = GridItem(.flexible(minimum: 104), spacing: Rhythm.near)
    return LazyVGrid(columns: Array(repeating: column, count: across), alignment: .leading, spacing: Rhythm.near) {
      ForEach(Extensions.facts(row, about: about)) { FactTile(fact: $0) }
    }
  }

  /// What it's doing, or the last thing it said.
  private var now: some View {
    let said = row.said.flatMap { $0.isEmpty ? nil : $0 }
    return Section(title: row.s == "working" ? "Doing now" : said != nil ? "Last said" : "Now") {
      Text(said ?? row.d ?? "Nothing yet.").font(Pixel.body).foregroundStyle(Palette.white)
        .lineLimit(4).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
    }
  }

  /// The one part of the page that scrolls: it takes what room is left under the rest.
  private var recent: some View {
    Section(title: "Recent") {
      if activity.isEmpty {
        Text(m.window.activityFor == row.id ? "Nothing to show: this kind of agent keeps no log ttycat can read, or it hasn't done anything yet."
          : "Reading what it's been doing.")
          .font(Pixel.small).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
      } else {
        ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: Rhythm.near) {
          ForEach(Array(activity.enumerated()), id: \.offset) { index, item in
            HStack(alignment: .firstTextBaseline, spacing: Rhythm.near) {
              Text(item.shownAge).font(Pixel.small).foregroundStyle(Palette.faint).frame(width: 34, alignment: .trailing)
              Dot(item.tone == 1 ? Palette.orange : item.tone == 2 ? Palette.green : Palette.faint)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
              Text(item.text).font(Pixel.body).foregroundStyle(index == 0 ? Palette.white : Palette.muted)
                .lineLimit(6).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
          }
        }
        .padding(.trailing, Rhythm.section)  // clear of the scroll bar
        .pixelScroller()
        }
        .frame(minHeight: 160, maxHeight: .infinity)
      }
    }
    .frame(maxHeight: activity.isEmpty ? nil : .infinity, alignment: .top)
  }
}

/// A request the agent made, a click from the browser.
struct PullChip: View {
  @State private var hovering = false
  let link: PullLink

  var body: some View {
    Button {
      if let url = link.destination { NSWorkspace.shared.open(url) }
    } label: {
      HStack(spacing: 5) {
        PixelIcon(rows: PixelIcon.out, scale: 1, color: hovering ? Palette.white : Palette.green)
        Text(link.label).font(Pixel.small).foregroundStyle(Palette.white).lineLimit(1)
      }
      .padding(.horizontal, 6)
      .frame(height: 18)
      .pixelBox(Palette.card, border: hovering ? Palette.white : Palette.line)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .fixedSize()
    .onHover { hovering = $0 }
    .help("Open \(link.repo) \(link.label) in your browser")
    .accessibilityLabel("Open \(link.spoken)")
  }
}

private struct FactTile: View {
  let fact: AgentFacts.Fact

  private var ink: Color {
    switch fact.tone {
    case .needs: Palette.orange
    case .done: Palette.green
    case .quiet: Palette.muted
    case .plain: Palette.white
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Rhythm.near) {
      Caps(fact.name, color: Palette.muted2)
      Text(fact.value).font(Pixel.name).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.7)
    }
    .padding(Rhythm.near + Rhythm.tight)
    .frame(maxWidth: .infinity, alignment: .leading)
    .pixelBox(Palette.card, border: fact.tone == .needs ? Palette.orange : Palette.line)
    .help(fact.note ?? "")
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(fact.name): \(fact.value)")
  }
}
