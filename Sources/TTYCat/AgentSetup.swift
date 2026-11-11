// What ttycat can add to each agent's own setup: a hook, say. The daemon knows what there is and is the
// only thing that writes any of it (daemon/integrations.py); this is what's shown, and when to ask.
// Nothing is ever added without a click on the one thing it names.
import SwiftUI

struct SetupAddition: Decodable, Equatable, Identifiable {
  let id: String
  let title: String
  let detail: String
  let writes: String  // what it changes of yours, and where: shown before you say yes
  let state: String   // missing | installed | broken | unreadable

  var isOn: Bool { state == "installed" }
}

struct AgentSetup: Decodable, Equatable, Identifiable {
  let id: String
  let name: String
  let found: Bool       // it's on this Mac
  let shows: [String]   // what ttycat shows of it with nothing added
  let adds: [SetupAddition]
  var can: [String: String]?  // the same as a table: state, sub, sh -> exact | estimated; missing: it can't tell
}

/// One thing ttycat can or can't show of an agent, for the table in Settings > Agents.
struct Capability: Equatable, Identifiable {
  enum Level: Equatable { case yes, estimate, no }
  let id: String
  let name: String
  let word: String
  let level: Level

  /// What it shows as it is, then whether its prompts can be answered here: that one is the only thing
  /// that ever needs adding, so it says where its switch is.
  static func all(_ agent: AgentSetup) -> [Capability] {
    let counted = { (id: String, name: String) -> Capability in
      switch agent.can?[id] {
      case "exact": Capability(id: id, name: name, word: "Counted", level: .yes)
      case "estimated": Capability(id: id, name: name, word: "Estimated", level: .estimate)
      default: Capability(id: id, name: name, word: "Not shown", level: .no)
      }
    }
    let prompts: Capability
    if agent.adds.isEmpty {
      prompts = Capability(id: "ask", name: "Prompts", word: "In terminal", level: .no)
    } else if agent.adds.contains(where: \.isOn) {
      prompts = Capability(id: "ask", name: "Prompts", word: "In ttycat", level: .yes)
    } else {
      prompts = Capability(id: "ask", name: "Prompts", word: "Off", level: .no)
    }
    return [
      Capability(id: "state", name: "Activity", word: "Shown", level: .yes),
      counted("sub", "Subagents"), counted("sh", "Open shells"), prompts,
    ]
  }
}

struct SetupList: Decodable {
  let agents: [AgentSetup]
}

struct SetupReply: Decodable {
  let ok: Bool
  var msg: String?
}

/// Something to ask about once: an agent is on this Mac and there's a thing ttycat could add to it.
struct SetupOffer: Equatable, Identifiable {
  let agent: String
  let addition: SetupAddition
  var id: String { addition.id }
}

enum SetupOffers {
  /// What hasn't been asked about yet. One that's installed needs no asking, and one whose agent isn't
  /// here waits until it is: that's how an agent installed later gets its turn.
  static func make(_ agents: [AgentSetup], seen: Set<String>) -> [SetupOffer] {
    agents.filter(\.found).flatMap { agent in
      agent.adds.filter { $0.state == "missing" && !seen.contains($0.id) }.map { SetupOffer(agent: agent.name, addition: $0) }
    }
  }

  /// What counts as asked already. The first time this is known on a Mac that has been through the
  /// welcome, everything there now was offered there, or passed over: none of it is asked again.
  static func seen(stored: [String]?, welcomed: Bool, agents: [AgentSetup]) -> Set<String> {
    if let stored { return Set(stored) }
    return welcomed ? Set(agents.filter(\.found).flatMap { $0.adds.map(\.id) }) : []
  }

  /// One that was there and whose program has gone, as after the app was moved. Yours already: said, not asked.
  static func broken(_ agents: [AgentSetup]) -> [SetupOffer] {
    agents.flatMap { agent in agent.adds.filter { $0.state == "broken" }.map { SetupOffer(agent: agent.name, addition: $0) } }
  }

  static func stateWord(_ state: String) -> String {
    switch state {
    case "installed": "on"
    case "broken": "needs repair"
    case "unreadable": "settings can't be read"
    default: "off"
    }
  }
}

/// What the welcome says about agents: the ones here, and a line about the ones that aren't.
struct WelcomeSetup: Equatable {
  let found: [AgentSetup]
  let later: String?

  init(_ agents: [AgentSetup]) {
    found = agents.filter(\.found)
    let missing = agents.filter { !$0.found }.map(\.name)
    later = missing.isEmpty || agents.isEmpty ? nil
      : "Not on this Mac: \(missing.joined(separator: ", ")). If you install one later, ttycat finds it, and asks before adding anything to it."
  }

  /// "What it's doing, Subagents" as the end of a sentence.
  static func words(_ shows: [String]) -> String { shows.joined(separator: ", ").lowercased() }
}

/// Settings > Agents: every agent ttycat knows, as a card: whether it's here, what's shown of it, and the
/// switches for what can be added. One that isn't on this Mac is there too, dimmed: it's what you'd get.
struct AgentSetupPane: View {
  @EnvironmentObject var m: TTYCatModel

  var body: some View {
    if m.setups.isEmpty {
      Section(title: "Agents") {
        Text(m.status == nil ? "The daemon isn't running, so this can't be read yet." : "Looking at what's on this Mac.")
          .font(Pixel.body).foregroundStyle(Palette.muted)
      }
    }
    ForEach(m.setups.filter(\.found) + m.setups.filter { !$0.found }) { agent in
      AgentSetupCard(agent: agent)
    }
    if !m.setups.isEmpty {
      Text("Counted comes from the agent's own records. Estimated is worked out from the processes it has running. An agent with no switch needs nothing added.")
        .font(Pixel.small).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
    }
    Color.clear.frame(height: 0).onAppear {
      m.refreshSetups()
      m.sawSetupOffers()
    }
  }
}

private struct AgentSetupCard: View {
  let agent: AgentSetup

  var body: some View {
    VStack(alignment: .leading, spacing: Rhythm.apart) {
      HStack(alignment: .firstTextBaseline, spacing: Rhythm.near) {
        Text(agent.name).font(Pixel.name).foregroundStyle(agent.found ? Palette.white : Palette.muted)
        Spacer(minLength: Rhythm.near)
        Dot(agent.found ? Palette.green : Palette.faint)
        Caps(agent.found ? "On this Mac" : "Not found", color: agent.found ? Palette.green : Palette.faint)
      }
      .accessibilityElement(children: .combine)
      // All four in a row where there's room for the words, else two and two: never one long column.
      ViewThatFits(in: .horizontal) {
        cells(across: 4)
        cells(across: 2)
      }
      ForEach(agent.adds) { addition in
        RowLine()
        AdditionRow(addition: addition, agentFound: agent.found)
      }
    }
    .padding(Rhythm.apart)
    .frame(maxWidth: .infinity, alignment: .leading)
    .pixelBox(Palette.card, border: Palette.line)
  }

  private func cells(across: Int) -> some View {
    let column = GridItem(.flexible(minimum: 118), spacing: Rhythm.near)
    return LazyVGrid(columns: Array(repeating: column, count: across), alignment: .leading, spacing: Rhythm.near) {
      ForEach(Capability.all(agent)) { CapabilityCell(capability: $0, dimmed: !agent.found) }
    }
  }
}

private struct CapabilityCell: View {
  let capability: Capability
  let dimmed: Bool

  private var tone: Color {
    if dimmed { return Palette.faint }
    switch capability.level {
    case .yes: return Palette.green
    case .estimate: return Palette.white
    case .no: return Palette.faint
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Rhythm.near) {
      Caps(capability.name, color: Palette.muted2)
      HStack(spacing: Rhythm.near) {
        switch capability.level {
        case .yes: PixelIcon(rows: PixelIcon.check, scale: 2, color: tone)
        case .estimate: Text("~").font(Pixel.body).foregroundStyle(tone).frame(width: 10)
        case .no: PixelIcon(rows: PixelIcon.dash, scale: 2, color: tone)
        }
        Text(capability.word).font(Pixel.small).lineLimit(1).minimumScaleFactor(0.8)
          .foregroundStyle(dimmed || capability.level == .no ? Palette.muted : Palette.white)
      }
    }
    .padding(Rhythm.near + Rhythm.tight)
    .frame(maxWidth: .infinity, alignment: .leading)
    .pixelBox(Palette.tile, border: Palette.line)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(capability.name): \(capability.word)")
  }
}

struct AdditionRow: View {
  @EnvironmentObject var m: TTYCatModel
  let addition: SetupAddition
  let agentFound: Bool

  private var detail: String {
    switch addition.state {
    case "broken": "It's in the settings, but the program it runs has gone, as after ttycat was moved. Repair points it at this app."
    case "unreadable": "The settings file can't be read, so ttycat won't touch it."
    default: "\(addition.detail) \(addition.writes)"
    }
  }

  var body: some View {
    if addition.state == "broken" {
      ActionRow(title: addition.title, detail: detail, button: "Repair", loud: true, enabled: !m.setupBusy) {
        m.changeSetup(addition.id, install: true)
      }
    } else {
      Toggled(
        title: addition.title, on: addition.isOn, detail: detail,
        enabled: addition.state != "unreadable" && !m.setupBusy && (agentFound || addition.isOn)
      ) { m.changeSetup(addition.id, install: !addition.isOn) }
    }
  }
}

/// On the Agents pane: an agent is here that ttycat could do more for. Asked once; "Not now" is an answer.
struct SetupNotice: View {
  @EnvironmentObject var m: TTYCatModel
  let offers: [SetupOffer]

  var body: some View {
    VStack(alignment: .leading, spacing: Rhythm.near) {
      ForEach(offers) { offer in
        ActionRow(
          title: "\(offer.agent): \(offer.addition.title.lowercasedFirst)",
          detail: "\(offer.addition.detail) \(offer.addition.writes)",
          button: "Turn on", loud: true, enabled: !m.setupBusy
        ) { m.changeSetup(offer.addition.id, install: true) }
      }
      HStack {
        Text("You can change this any time in Settings, under Agents.").font(Pixel.small).foregroundStyle(Palette.muted)
        Spacer(minLength: Rhythm.near)
        PixelButton(title: "Not now") { m.sawSetupOffers() }.fixedSize()
      }
    }
    .padding(Rhythm.apart)
    .frame(maxWidth: .infinity, alignment: .leading)
    .pixelBox(Palette.card, border: Palette.orange)
  }
}

extension String {
  var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
