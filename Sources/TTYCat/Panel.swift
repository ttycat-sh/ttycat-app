// The panel under the menu bar icon, laid out like the board's screens.
import AppKit
import SwiftUI

let panelWidth: CGFloat = 340
private let panelChrome: CGFloat = 52  // the tabs and padding, which stay put while a page scrolls

struct PanelView: View {
  @EnvironmentObject var m: TTYCatModel

  var body: some View {
    VStack(spacing: 6) {
      TopBar()
      PageScroll(tallest: m.maxPanelHeight - panelChrome) {
        VStack(spacing: 6) {
          switch m.page {
          case .agents: AgentsPage()
          case .pet: PetPage()
          case .extra(let id): Extensions.pages.first { $0.id == id }?.view()
          }
          if let toast = m.toast {
            Text(toast).font(Pixel.body).foregroundStyle(Palette.orange).lineLimit(2)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
    }
    .padding(10)
    .frame(width: panelWidth)
    .background(GeometryReader { Color.clear.preference(key: PanelHeightKey.self, value: $0.size.height) })
    .onPreferenceChange(PanelHeightKey.self) { m.panelHeight = $0 }
    .frame(maxHeight: .infinity, alignment: .top)  // while the window catches up, the top stays put
    .background(Palette.black)
    // The shape of what hangs from the menu bar on a Mac now. The window behind it is clear.
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    .environment(\.colorScheme, .dark)
  }
}

private struct PanelHeightKey: PreferenceKey {
  static let defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct PageHeightKey: PreferenceKey {
  static let defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// A page as tall as it needs, until it would run off the screen: then it scrolls, under the tabs.
private struct PageScroll<Content: View>: View {
  @State private var height: CGFloat = 0
  let tallest: CGFloat
  @ViewBuilder let content: Content

  var body: some View {
    ScrollView(.vertical, showsIndicators: height > tallest) {
      content.background(GeometryReader { Color.clear.preference(key: PageHeightKey.self, value: $0.size.height) }).pixelScroller()
    }
    .frame(height: min(height, tallest))
    .onPreferenceChange(PageHeightKey.self) { height = $0 }
  }
}

// The board's tab bar and its "MAC" link marker, here the other way round.
private struct TopBar: View {
  @EnvironmentObject var m: TTYCatModel

  var body: some View {
    HStack(spacing: 6) {
      tab("Agents", count: m.rows.count, page: .agents)
      tab("Bit", count: nil, page: .pet)
      ForEach(Extensions.pages, id: \.id) { extra in
        tab(extra.title, count: nil, badge: extra.badge(), page: .extra(extra.id), link: extra.link())
      }
      Spacer(minLength: 8)
      if m.boardMatters {
        HStack(spacing: 2) {
          Dot(m.boardConnected ? Palette.green : Palette.faint)
          if Extensions.pages.isEmpty {  // with more tabs, the light says it alone
            Caps(m.boardConnected ? m.status?.board.label ?? "Board" : "Board", color: m.boardConnected ? Palette.muted : Palette.faint)
          }
        }
        .padding(4)  // a light of 6 points is too small to point at
        .contentShape(Rectangle())
        .help(m.boardConnected ? "\(m.boardTitle) is connected" : "\(m.boardTitle) isn't connected")
      }
      // Everything that isn't about an agent right now is in the window.
      Button { m.openSettings() } label: {
        HStack(spacing: 3) {
          PixelIcon(rows: PixelIcon.gear, scale: 2, color: Palette.muted)
          if m.setupMarked { Dot(Palette.orange) }
        }
        .padding(4)
      }
      .buttonStyle(PixelPress())
      .help("Settings (\u{2318},)")
      .accessibilityLabel("Settings")
    }
  }

  /// `link`: the tab goes there instead of to its page, as an extension's locked one does.
  private func tab(_ title: String, count: Int?, badge: String? = nil, page: Page, link: URL? = nil) -> some View {
    let chosen = m.page == page && link == nil
    return Button {
      if let link {
        NSWorkspace.shared.open(link)
        return
      }
      m.page = page
      m.selected = nil
    } label: {
      HStack(spacing: 5) {
        Caps(title, color: chosen ? Palette.white : Palette.muted2)
        if let count, count > 0 {
          Text("\(count)").font(Pixel.small).foregroundStyle(Palette.muted)
        }
        if let badge {
          Caps(badge, color: Palette.black)
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .pixelBox(Palette.orange)
        }
      }
      .fixedSize()  // a name is never cut short to make room
      .padding(.horizontal, 6)
      .frame(height: 24)
      // The line is as wide as the name: a tab doesn't stretch to fill the bar.
      .overlay(alignment: .bottom) { Rectangle().fill(chosen ? Palette.orange : Color.clear).frame(height: 2) }
    }
    .buttonStyle(PixelPress())
    .help(link.map { "\(title): opens \($0.host() ?? "a website")" } ?? "")
    .accessibilityLabel(badge.map { "\(title), \($0)" } ?? title)
    .accessibilityAddTraits(chosen ? .isSelected : link != nil ? .isLink : [])
  }
}

// ---------------------------------------------------------------- agents

private struct AgentsPage: View {
  @EnvironmentObject var m: TTYCatModel

  var body: some View {
    if let row = m.selectedRow {
      AgentPage(row: row)
    } else {
      list
    }
  }

  @ViewBuilder private var list: some View {
    let ask = m.heroAsk
    // A row in the sorted list that isn't blocked is never above one that is.
    let top = m.top
    let below = m.listRows
    let shown = ask == nil ? 6 : 3
    if let ask {
      let asks = m.asks
      AskCard(row: ask, position: (at: (asks.firstIndex { $0.id == ask.id } ?? 0) + 1, of: asks.count)).id(ask.rev)
    } else {
      Hero(top: top)
      if m.hero == .stopped {  // what to do about it, where it's said
        HStack(spacing: 6) {
          PixelButton(title: "Restart", action: m.restartDaemon)
          PixelButton(title: "Open log") { NSWorkspace.shared.open(URL(fileURLWithPath: Supervisor.logPath)) }
        }
      }
    }
    let kinds = AgentFilter.harnesses(m.rows)
    if !kinds.isEmpty {
      HarnessTabs(harnesses: kinds, total: m.rows.count, chosen: m.panelFilter.harness) { m.panelHarness = $0 }
    }
    if !below.isEmpty {
      ScrollViewReader { scroll in
        ScrollView(.vertical, showsIndicators: below.count > shown) {
          VStack(spacing: 3) {
            ForEach(Array(below.enumerated()), id: \.element.id) { index, row in
              AgentRowView(row: row, seed: index, highlighted: row.id == m.highlighted).id(row.id)
            }
          }
          .pixelScroller()
        }
        .onChange(of: m.highlighted) { _, id in
          if let id { scroll.scrollTo(id) }  // the arrow keys can go past what's showing
        }
      }
      .frame(height: CGFloat(min(below.count, shown)) * 40 - 3)
    }
    if let pet = m.status?.pet, ask == nil { PetStrip(pet: pet) }
  }
}

private struct Hero: View {
  @EnvironmentObject var m: TTYCatModel
  let top: AgentRow?

  private struct Look {
    var pose: BitPose
    var label: String
    var word: String
    var suffix = ""
    var detail: String
    var tone: Color = Palette.white
    var border: Color = Palette.line
    var dimmed = false
    var badge: [UInt8]?
    var opens = false
    var lines = 1  // what went wrong is said in full
  }

  private var look: Look {
    let name = "\(top?.n ?? "Agent") \u{B7} \(top?.title ?? "")"
    switch m.hero {
    case .stopped:
      return Look(
        pose: .nap, label: "Daemon", word: "STOPPED",
        detail: m.problem ?? "starting it...", tone: Palette.orange, border: Palette.orange, dimmed: true, lines: 3)
    case .error:
      return Look(
        pose: .alert, label: name, word: "ERROR", suffix: "\(ageText(top?.age)) ago",
        detail: top?.d ?? "", tone: Palette.orange, border: Palette.orange, badge: PixelIcon.cross, opens: top?.canOpen == true,
        lines: 3)
    case .updating:
      return Look(
        pose: .work, label: "Board", word: "UPDATING", detail: "don't unplug it; agents keep running",
        tone: Palette.orange)
    case .done:
      return Look(
        pose: .happy, label: name, word: "DONE", detail: top?.d ?? "", tone: Palette.green, border: Palette.green,
        opens: true)
    case .unplugged:
      return Look(
        pose: .nap, label: "Board", word: "UNPLUGGED", detail: "plug it in over USB; agents still show here",
        tone: Palette.muted, dimmed: true)
    case .ready:
      return Look(pose: .idle, label: "No agents yet", word: "READY", detail: "start one in any terminal")
    case .clear:
      let working = m.working
      return Look(
        pose: working > 0 ? .work : .idle, label: "Nothing needs you", word: "CLEAR",
        detail: "\(working) working \u{B7} \(m.rows.count - working) idle")
    }
  }

  var body: some View {
    let look = self.look
    Button {
      if look.opens, let top { m.select(top) }
    } label: {
      HStack(spacing: 8) {
        ZStack(alignment: .topTrailing) {
          Rectangle().fill(Palette.black).frame(width: 56, height: 52)
          BitView(pose: look.pose, dot: 3, dimmed: look.dimmed)
            .frame(width: 56, height: 52)
          if let badge = look.badge {
            PixelIcon(rows: badge, scale: 2, color: Palette.orange).padding(2)
          }
        }
        VStack(alignment: .leading, spacing: 4) {
          Caps(look.label, color: Palette.muted2)
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(look.word).font(Pixel.hero).foregroundStyle(look.tone).lineLimit(1)
            Text(look.suffix).font(Pixel.small).foregroundStyle(Palette.muted).lineLimit(1)
          }
          Text(look.detail).font(Pixel.body).foregroundStyle(Palette.muted).lineLimit(look.lines)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
        if look.opens { PixelIcon(rows: PixelIcon.right, scale: 1) }
      }
      .padding(8)
      .frame(maxWidth: .infinity)
      .pixelBox(Palette.card, border: look.border)
    }
    .buttonStyle(PixelPress())
    .disabled(!look.opens)
    .help(look.detail)
  }
}

private struct AgentRowView: View {
  @EnvironmentObject var m: TTYCatModel
  @State private var hovering = false
  let row: AgentRow
  let seed: Int
  var highlighted = false  // by the arrow keys

  /// Under the pointer or the arrow keys: it says it opens, as the card at the top does.
  private var pointedAt: Bool { (hovering || highlighted) && row.canOpen }

  var body: some View {
    Button {
      m.select(row)
    } label: {
      HStack(spacing: 7) {
        stateIcon.frame(width: 16, height: 16)
        // Line by line, so the name gives way only to the age, and what it's doing to the rest.
        VStack(alignment: .leading, spacing: 0) {
          HStack(spacing: 4) {
            Text(row.title).font(Pixel.title).foregroundStyle(Palette.white).lineLimit(1)
            Spacer(minLength: 4)
            Text(ageText(row.age)).font(Pixel.small).foregroundStyle(Palette.muted)
          }
          HStack(spacing: 5) {
            if let host = row.host { Text(host).font(Pixel.small).foregroundStyle(Palette.white) }
            Text(row.d ?? "").font(Pixel.small).foregroundStyle(Palette.muted).lineLimit(1)
            Spacer(minLength: 4)
            // What an extension has to say of it, as on its card in the window: Extensions.cardNotes.
            if let note = Extensions.cardNote(row) {
              Text(note).font(Pixel.small).foregroundStyle(Palette.muted2).lineLimit(1).fixedSize()
            }
            Caps(row.a ?? "", color: Palette.muted2)
          }
        }
        // Room for the way to its newest request, which sits over the row: a button can't hold another.
        if let link = row.prs?.first { PullChip(link: link).hidden() }
        PixelIcon(rows: PixelIcon.right, scale: 1, color: Palette.muted).opacity(pointedAt ? 1 : 0)  // always there: no row shifts
      }
      .padding(.horizontal, 8)
      .frame(height: 37)
      .frame(maxWidth: .infinity)
      .pixelBox(Palette.tile, border: row.s == "blocked" || pointedAt ? Palette.orange : Palette.line)
    }
    .buttonStyle(PixelPress())
    .disabled(!row.canOpen)
    .onHover { hovering = $0 && row.canOpen }
    // A right click, as on its card in the window. Renaming opens its page here, where the name is typed.
    .contextMenu {
      if row.canOpen {
        Button("Rename\u{2026}") { m.startRenaming(row) }
        Button("Open in Terminal") { m.open(row) }
      }
    }
    .overlay(alignment: .trailing) {
      if let link = row.prs?.first { PullChip(link: link).padding(.trailing, 20) }  // clear of the arrow
    }
    .help([row.n, row.d].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ": "))  // "CC" is Claude
  }

  // The board's status squares; a working agent is the mascot at its laptop.
  @ViewBuilder private var stateIcon: some View {
    switch row.s {
    case "blocked": square(PixelIcon.bang, fill: Palette.orange, border: Palette.orange, ink: Palette.black)
    case "error": square(PixelIcon.cross, fill: Palette.black, border: Palette.orange, ink: Palette.orange)
    case "done": square(PixelIcon.check, fill: Palette.green, border: Palette.green, ink: Palette.black)
    case "working": BitView(pose: .work, dot: 1, seed: seed)
    default: square(PixelIcon.dash, fill: Palette.tile, border: Palette.line, ink: Palette.faint)
    }
  }

  private func square(_ icon: [UInt8], fill: Color, border: Color, ink: Color) -> some View {
    ZStack {
      SteppedRect().fill(border)
      Rectangle().fill(fill).padding(2)
      PixelIcon(rows: icon, scale: 2, color: ink)
    }
  }
}

// The board's Detail screen: what this agent has been doing, and its way to the terminal.
struct AgentPage: View {
  @EnvironmentObject var m: TTYCatModel
  @Environment(\.inWindow) private var inWindow  // which of the two it's open in: each has its own
  let row: AgentRow

  var body: some View {
    VStack(spacing: 6) {
      HStack(spacing: 6) {
        Button {
          m.closeAgent(inWindow: inWindow)
        } label: {
          HStack(spacing: 5) {
            PixelIcon(rows: PixelIcon.left, scale: 1)
            Caps("Back", color: Palette.white)
          }
          .padding(.vertical, 4)
        }
        .buttonStyle(PixelPress())
        Spacer(minLength: 4)
        if let link = row.prs?.first { PullChip(link: link) }  // what it put up for review lately
        Text("\(stateWord) \(ageText(row.age))").font(Pixel.small).foregroundStyle(stateColor)
      }
      if renaming {
        // Over whatever else is here: a prompt stays where it is, and can still be answered.
        AgentNameField(row: row)
          .padding(8)
          .frame(maxWidth: .infinity, alignment: .leading)
          .pixelBox(Palette.card, border: Palette.line)
      }
      if row.s == "blocked" {
        AskCard(row: row).id(row.rev)
      } else if !renaming {
        title
      }
      recent
      HStack(spacing: 6) {
        if !renaming {
          PixelButton(title: "Rename") { m.startRenaming(row, inWindow: inWindow) }.fixedSize()
            .help("Give it a name of your own, so it can be told from the others in \(row.folder ?? row.p ?? "its folder")")
        }
        PixelButton(title: "Open in terminal") { m.open(row) }
      }
    }
  }

  private var renaming: Bool { m.isRenaming(row, inWindow: inWindow) }

  private var stateWord: String {
    switch row.s {
    case "blocked": "needs you"
    case "error": "error"
    case "done": "done"
    case "working": "working"
    default: "idle"
    }
  }

  private var stateColor: Color {
    switch row.s {
    case "blocked", "error": Palette.orange
    case "done": Palette.green
    default: Palette.muted
    }
  }

  private var title: some View {
    HStack(spacing: 8) {
      BitView(pose: row.s == "working" ? .work : row.s == "done" ? .happy : row.s == "error" ? .alert : .idle, dot: 2)
        .frame(width: 36, height: 34)
      VStack(alignment: .leading, spacing: 2) {
        Text(row.title).font(Pixel.title).foregroundStyle(Palette.white).lineLimit(1)
        HStack(spacing: 5) {
          Caps(row.n ?? "Agent", color: Palette.muted2)
          if let host = row.host { Text(host).font(Pixel.small).foregroundStyle(Palette.muted2) }
          if let folder = row.folderBesideName { Text(folder).font(Pixel.small).foregroundStyle(Palette.muted2).lineLimit(1) }
        }
      }
      Spacer(minLength: 0)
    }
    .padding(8)
    .frame(maxWidth: .infinity)
    .pixelBox(Palette.card, border: Palette.line)
  }

  private var recent: some View {
    let activity = m.activity(inWindow: inWindow)
    return VStack(alignment: .leading, spacing: 6) {
      Caps("Recent")
      if activity.isEmpty {
        Text(row.d ?? "nothing yet").font(Pixel.body).foregroundStyle(Palette.faint)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        FitScroll(tallest: row.s == "blocked" ? 110 : 260) {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(activity.enumerated()), id: \.offset) { index, item in
              HStack(alignment: .top, spacing: 6) {
                Text(item.shownAge).font(Pixel.small).foregroundStyle(Palette.faint).frame(width: 30, alignment: .trailing)
                Dot(item.tone == 1 ? Palette.orange : item.tone == 2 ? Palette.green : Palette.faint)
                  .padding(.top, 4)
                Text(item.text).font(Pixel.body).foregroundStyle(index == 0 ? Palette.white : Palette.muted)
                  .lineLimit(3)
                  .fixedSize(horizontal: false, vertical: true)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .help(item.text)
              }
            }
          }
        }
      }
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .pixelBox(Palette.tile, border: Palette.line)
  }
}

private struct PetStrip: View {
  @EnvironmentObject var m: TTYCatModel
  let pet: PetInfo

  var body: some View {
    Button { m.page = .pet } label: { strip }
      .buttonStyle(PixelPress())
      .help("See \(pet.name)")
  }

  private var strip: some View {
    // One line: the Bit page has the rest, and the agents keep the room.
    HStack(alignment: .center, spacing: 8) {
      Text(pet.name).font(Pixel.title).foregroundStyle(Palette.white).lineLimit(1)
      Text("LV \(pet.level)").font(Pixel.body).foregroundStyle(Palette.orange).fixedSize()
      LevelBar(pet: pet)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity)
    .pixelBox(Palette.tile, border: Palette.line)
  }
}

func ageText(_ age: Double?) -> String {
  let a = Int(age ?? 0)
  if a < 60 { return "\(a)s" }
  if a < 3600 { return "\(a / 60)m" }
  if a < 86400 { return "\(a / 3600)h" }
  return "\(a / 86400)d"
}
