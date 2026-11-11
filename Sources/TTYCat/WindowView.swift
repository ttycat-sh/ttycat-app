// The window: a sidebar of panes, and the one that's chosen, in the board's look. Its shape is a Mac
// window's; everything drawn in it is the board's: black, the accent, pixel type for what's named, and
// boxes with stepped corners.
import SwiftUI

struct WindowView: View {
  @EnvironmentObject var m: TTYCatModel

  var body: some View {
    let groups = m.panes
    let shown = WindowPanes.shown(m.window.pane, in: groups)
    let settings = WindowPanes.settingsList(groups)
    let inSettings = settings.contains { $0.id == shown?.id }
    let inAgents = shown?.id == WindowPanes.agents
    HStack(spacing: 0) {
      Sidebar(groups: WindowPanes.sidebar(groups), shown: inSettings ? WindowPanes.settings : shown?.id) { id in
        m.window.pane = id == WindowPanes.settings ? WindowPanes.setting(m.window.setting, in: settings) ?? id : id
      }
      // The pane sits in a box of its own, inset from the window's edge. Settings bring their list with them.
      HStack(spacing: 0) {
        if inSettings {
          SettingsList(panes: settings, shown: shown?.id)
          Rectangle().fill(Palette.line).frame(width: 1)
        }
        if inAgents {
          // The agents bring theirs too: the list stays while one of them is open beside it.
          AgentsList()
          Rectangle().fill(Palette.line).frame(width: 1)
        }
        GeometryReader { room in
        ScrollView(.vertical) {
          VStack(alignment: .leading, spacing: Rhythm.section) {
            if let shown {
              if !inAgents { PaneTitle(pane: shown) }  // the list has the name; the agent open has its own
              PaneBody(id: shown.id)
            }
            if let toast = m.toast {
              Text(toast).font(Pixel.body).foregroundStyle(Palette.orange).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          .padding(Rhythm.page)
          // An agent's page fills the pane and scrolls only its log; the pane scrolls when even that doesn't fit.
          .frame(maxWidth: .infinity, minHeight: inAgents ? room.size.height : nil, alignment: .topLeading)
          .pixelScroller()
        }
        }
        .id(inAgents ? "agent-\(m.windowAgent?.id ?? "")" : shown?.id)  // each pane, and each agent, opens at its top
      }
      .background(Palette.tile)
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
      .padding([.top, .trailing, .bottom], 8)
    }
    .background(Palette.black)
    .ignoresSafeArea()
    .environment(\.inWindow, true)
    .environment(\.colorScheme, .dark)
    .onChange(of: shown?.id, initial: true) { _, id in
      if let id, inSettings { m.window.setting = id }  // Settings opens where it was left
    }
  }
}

/// A row of a list of panes: the sidebar's, and the settings' own.
private struct PaneRow: View {
  let pane: PaneItem
  let chosen: Bool
  var badge = 0
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        PixelIcon(rows: pane.icon, scale: 2, color: chosen ? Palette.orange : Palette.muted2)
          .frame(width: 14, height: 14)
        Caps(pane.title, color: chosen ? Palette.white : Palette.muted)
        Spacer(minLength: 4)
        if badge > 0 {
          Text("\(badge)").font(Pixel.label).foregroundStyle(Palette.black)
            .padding(.horizontal, 5).frame(height: 14).background(Palette.orange)
        }
      }
      .padding(.horizontal, 10)
      .frame(height: 32)
      .frame(maxWidth: .infinity)
      .pixelBox(chosen ? Palette.card : Color.clear, border: chosen ? Palette.line : nil)
    }
    .buttonStyle(PixelPress())
    .accessibilityLabel(pane.title)
    .accessibilityAddTraits(chosen ? .isSelected : [])
  }
}

/// Every setting there is, in one list beside the one that's open.
private struct SettingsList: View {
  @EnvironmentObject var m: TTYCatModel
  let panes: [PaneItem]
  let shown: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("Settings").font(Pixel.heading).foregroundStyle(Palette.white)
        .frame(height: 40, alignment: .bottomLeading)  // on the line of the pane's own name
        .padding(.horizontal, 10).padding(.bottom, Rhythm.section)
        .accessibilityAddTraits(.isHeader)
      ForEach(panes) { pane in
        PaneRow(pane: pane, chosen: pane.id == shown) { m.window.pane = pane.id }
      }
    }
    .padding(.horizontal, 8)
    .padding(.top, Rhythm.page)
    .frame(width: 184, alignment: .leading)
    .frame(maxHeight: .infinity, alignment: .top)
    .background(Palette.black.opacity(0.35))
  }
}

/// Bit, how things stand, and the panes. The accent glows from the corner Bit sits in.
private struct Sidebar: View {
  @EnvironmentObject var m: TTYCatModel
  let groups: [[PaneItem]]
  let shown: String?
  let pick: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header.padding(.top, 46)  // under the window's own buttons
      VStack(alignment: .leading, spacing: Rhythm.apart) {
        ForEach(groups.indices, id: \.self) { index in
          VStack(spacing: 2) {
            ForEach(groups[index]) { pane in
              PaneRow(pane: pane, chosen: pane.id == shown, badge: pane.id == WindowPanes.agents ? m.needs : 0) { pick(pane.id) }
            }
          }
        }
      }
      .padding(.top, Rhythm.section)
      Spacer(minLength: 12)
      if let pet = m.status?.pet {
        // Bit's level, here too: the panel has the rest.
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 6) {
            Caps(pet.name, color: Palette.white)
            Spacer(minLength: 4)
            Text("LV \(pet.level)").font(Pixel.small).foregroundStyle(Palette.orange)
          }
          LevelBar(pet: pet)
          Text(pet.nextKeepsake).font(Pixel.small).foregroundStyle(Palette.muted).lineLimit(1)
        }
        .padding(10)
        .pixelBox(Palette.tile, border: Palette.line)
        .padding(.bottom, 10)
        .accessibilityElement(children: .combine)
      }
      Text(AppUpdater.version.first?.isNumber == true ? "v\(AppUpdater.version)" : AppUpdater.version).font(Pixel.small).foregroundStyle(Palette.faint).lineLimit(1)
        .padding(.horizontal, 10)
    }
    .padding(.horizontal, 10)
    .padding(.bottom, 16)
    .frame(width: 212, alignment: .leading)
    .frame(maxHeight: .infinity, alignment: .top)
    .background(
      RadialGradient(
        colors: [Palette.orange.opacity(0.28), Palette.orange.opacity(0.06), .clear],
        center: .topLeading, startRadius: 0, endRadius: 420))
  }

  private var header: some View {
    HStack(spacing: 10) {
      BitView(pose: m.status == nil ? .nap : m.needs > 0 ? .alert : m.working > 0 ? .work : .idle, dot: 3,
              dimmed: m.status == nil || (m.needs == 0 && m.working == 0))
        .frame(width: 52, height: 46)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text("ttycat").font(Pixel.heading).foregroundStyle(Palette.white)
        Text(WindowPanes.status(daemonUp: m.status != nil, agents: m.rows.count, needs: m.needs))
          .font(Pixel.small).foregroundStyle(m.needs > 0 ? Palette.orange : Palette.muted).lineLimit(1)
      }
    }
    .padding(.horizontal, 6)
    .accessibilityElement(children: .combine)
  }
}

private struct PaneTitle: View {
  let pane: PaneItem

  var body: some View {
    VStack(alignment: .leading, spacing: Rhythm.near) {
      Text(pane.title).font(Pixel.headline).foregroundStyle(Palette.white)
        .frame(height: 40, alignment: .bottomLeading)
        .accessibilityAddTraits(.isHeader)
      if let summary = pane.summary {
        Text(summary).font(Pixel.body).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

private struct PaneBody: View {
  let id: String

  var body: some View {
    VStack(alignment: .leading, spacing: Rhythm.apart) {
      switch id {
      case WindowPanes.welcome: WelcomePane()
      case WindowPanes.agents: AgentsPane()
      case WindowPanes.general: GeneralPane()
      case WindowPanes.agentSetup: AgentSetupPane()
      case WindowPanes.notifications: NotificationsPane()
      case WindowPanes.board: BoardPane()
      case WindowPanes.advanced: AdvancedPane()
      case WindowPanes.about: AboutPane()
      default: Extensions.panes.first { $0.id == id }?.view()
      }
    }
    .id(id)  // a pane's own state, such as a name half typed, doesn't follow to the next
  }
}
