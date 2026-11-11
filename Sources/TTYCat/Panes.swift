// The window's panes: everything about the app that isn't an agent needing you right now. Laid out for a
// window: what a thing is on the left, what to do about it on the right.
import AppKit
import ServiceManagement
import SwiftUI

/// The first time: what it's for, and the things it needs your click for. Each is asked here once, says
/// why, starts off, and can be changed later in the panes below. What makes the app worth having comes first.
struct WelcomePane: View {
  @EnvironmentObject var m: TTYCatModel

  var body: some View {
    HStack(alignment: .center, spacing: 16) {
      BitView(pose: .happy, dot: 5).frame(width: 90, height: 80).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 6) {
        Text("Your agents, in the menu bar").font(Pixel.heading).foregroundStyle(Palette.white)
        Text("Every agent running in a terminal on this Mac shows up under Bit, by itself. When one stops to ask, you answer it there.")
          .font(Pixel.body).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
      }
    }
    WelcomeAgents()
    Section(title: "Two things need your OK") {
      Toggled(
        title: "Tell me when an agent needs me", on: m.notifyPermission == .authorized,
        detail: m.notifyPermission == .denied ? "Turned off in System Settings." : "And when one finishes. macOS will ask.",
        enabled: m.notifyPermission == .notDetermined
      ) { m.turnOnNotifications() }
      RowLine()
      LoginToggle(detail: "So it's watching before your first agent starts.")
    }
    .onAppear {
      m.refreshSetups()
      m.refreshLogin()
      m.refreshPermission()
    }
    HStack(spacing: 12) {
      Text("All of it can be changed in Settings later. Closing this window leaves ttycat in the menu bar.")
        .font(Pixel.small).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 8)
      PixelButton(title: "Done", loud: true) {
        m.finishWelcome()
        m.window.pane = WindowPanes.agents
      }
      .fixedSize()
    }
  }
}

/// The agents found on this Mac, each with what ttycat shows of it as it is and what it could add. What
/// it adds starts off, and says what it writes. One that isn't here yet is asked about when it turns up.
private struct WelcomeAgents: View {
  @EnvironmentObject var m: TTYCatModel

  var body: some View {
    let welcome = WelcomeSetup(m.setups)
    Section(title: "Your agents") {
      if m.setups.isEmpty {
        Text("Looking for agents on this Mac.").font(Pixel.body).foregroundStyle(Palette.muted)
      } else if welcome.found.isEmpty {
        Text("None found on this Mac yet. Start one in any terminal and it shows up by itself.")
          .font(Pixel.body).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
      }
      ForEach(Array(welcome.found.enumerated()), id: \.element.id) { index, agent in
        if index > 0 { RowLine() }
        VStack(alignment: .leading, spacing: Rhythm.tight) {
          HStack(spacing: Rhythm.near) {
            Dot(Palette.green)
            Text(agent.name).font(Pixel.body).foregroundStyle(Palette.white)
          }
          Text(agent.adds.isEmpty ? "Shown as it is: \(WelcomeSetup.words(agent.shows)). Nothing to turn on."
            : "Shown as it is: \(WelcomeSetup.words(agent.shows)).")
            .font(Pixel.small).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        }
        ForEach(agent.adds) { addition in
          AdditionRow(addition: addition, agentFound: true)
        }
      }
      if let later = welcome.later {
        if !welcome.found.isEmpty { RowLine() }
        Text(later).font(Pixel.small).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

private struct LoginToggle: View {
  @EnvironmentObject var m: TTYCatModel
  var detail: String?

  var body: some View {
    Toggled(
      title: "Start at login", on: m.loginState == .enabled,
      detail: m.loginState == .requiresApproval ? "Needs your OK in System Settings." : detail
    ) {
      if m.loginState == .requiresApproval {
        SMAppService.openSystemSettingsLoginItems()
      } else {
        m.setStartAtLogin(m.loginState != .enabled)
      }
    }
  }
}

struct GeneralPane: View {
  @EnvironmentObject var m: TTYCatModel

  var body: some View {
    Section(title: "On this Mac") {
      LoginToggle(detail: "ttycat is watching before your first agent starts.")
    }
    .onAppear { m.refreshLogin() }
    Section(title: "Quit") {
      ActionRow(
        title: "Quit ttycat",
        detail: m.ownsDaemon ? "Stops the daemon too. Agents keep running; their prompts are answered in the terminal."
          : "A daemon started elsewhere keeps running.",
        button: "Quit", enabled: !m.flashBusy
      ) { AppMenu.quit() }
    }
  }
}

struct NotificationsPane: View {
  @EnvironmentObject var m: TTYCatModel

  var body: some View {
    if m.notifyPermission == .denied {
      Section(title: "Permission") {
        ActionRow(
          title: "Notifications are off for ttycat", detail: "Turned off in System Settings, so nothing below can reach you.",
          button: "Open System Settings", loud: true
        ) {
          let page = "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=sh.ttycat.app"
          if let url = URL(string: page) { NSWorkspace.shared.open(url) }
        }
      }
    } else if m.notifyPermission == .notDetermined {
      Section(title: "Permission") {
        ActionRow(
          title: "Notifications aren't on yet", detail: m.notifyProblem ?? "macOS asks once. Nothing below reaches you until then.",
          button: "Turn on notifications", loud: true, action: m.turnOnNotifications)
      }
    }
    Section(title: "Tell me") {
      Toggled(title: "When an agent needs me", on: m.notifyAsks, detail: "Short ones can be answered right on the notification. Allow never can.") {
        m.setNotify(asks: !m.notifyAsks)
      }
      RowLine()
      Toggled(title: "When an agent finishes", on: m.notifyFinishes, detail: "After 30 seconds or more of work.") {
        m.setNotify(finishes: !m.notifyFinishes)
      }
      RowLine()
      Toggled(title: "Play a sound for prompts", on: m.notifySound, enabled: m.notifyAsks) {
        m.setNotify(sound: !m.notifySound)
      }
    }
    .onAppear { m.refreshPermission() }
    Section(title: "Focus") {
      // macOS doesn't tell an app like this one whether a Focus is on, so this is always here.
      ActionRow(
        title: "A Focus holds notifications back", detail: "Unless ttycat is allowed in it. macOS doesn't say when one is on.",
        button: "Focus settings"
      ) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension") {
          NSWorkspace.shared.open(url)
        }
      }
    }
  }
}

struct BoardPane: View {
  @EnvironmentObject var m: TTYCatModel

  var body: some View {
    FirmwareSection()
    // The daemon only asks about a board's firmware. The app's own updates are under About.
    if let updates = m.status?.updates {
      Section(title: "Updates") {
        Toggled(title: "Check for firmware updates", on: updates.check, detail: updatesDetail(updates)) {
          m.setUpdateCheck(!updates.check)
        }
      }
    }
  }

  /// What's sent stays short in the detail: the board's model and versions, never anything about you.
  private func updatesDetail(_ updates: UpdatesInfo) -> String {
    guard updates.check else { return "Off: nothing is sent to ttycat." }
    if !updates.error.isEmpty { return "Couldn't reach ttycat. It tries again within the hour." }
    return "Sends the board's model and versions, and this app's. Nothing else."
  }
}

struct AdvancedPane: View {
  @EnvironmentObject var m: TTYCatModel

  var body: some View {
    Section(title: "Daemon") {
      Fact(name: "Daemon", value: daemonText, good: m.status != nil)
      if m.boardMatters { Fact(name: "Board", value: boardText, good: m.boardConnected) }
      if let problem = m.problem {
        Text(problem).font(Pixel.small).foregroundStyle(Palette.orange).fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
      }
      RowLine()
      HStack(spacing: 8) {
        Text("It watches your agents and talks to Claude's hook.").font(Pixel.small).foregroundStyle(Palette.muted)
        Spacer(minLength: 8)
        PixelButton(title: "Open log") { NSWorkspace.shared.open(URL(fileURLWithPath: Supervisor.logPath)) }.fixedSize()
        PixelButton(title: "Restart", enabled: !m.flashBusy, action: m.restartDaemon).fixedSize()
      }
    }
    Section(title: "Uninstall") {
      ActionRow(
        title: "Remove ttycat from this Mac",
        detail: "Takes its hook out of Claude's settings and its login item away, then moves the app to the Trash. It asks first.",
        button: "Uninstall\u{2026}", enabled: !m.flashBusy, action: m.uninstall)
    }
  }

  private var daemonText: String {
    guard let status = m.status else { return "not running" }
    return m.ownsDaemon ? "running, pid \(status.pid)" : "running on its own, pid \(status.pid)"
  }

  private var boardText: String {
    guard let board = m.status?.board, board.connected else { return "not connected" }
    let port = board.port.map { ($0 as NSString).lastPathComponent.replacingOccurrences(of: "cu.", with: "") } ?? ""
    let fw = board.fw.map { "fw \($0) \u{B7} \(port)" } ?? port
    return board.label.map { "\($0) \u{B7} \(fw)" } ?? fw
  }
}

struct AboutPane: View {
  @EnvironmentObject var m: TTYCatModel

  var body: some View {
    HStack(alignment: .center, spacing: 16) {
      BitView(pose: .happy, dot: 5).frame(width: 90, height: 80).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text("ttycat").font(Pixel.heading).foregroundStyle(Palette.white)
        Text(AppUpdater.version.first?.isNumber == true ? "Version \(AppUpdater.version)" : "A developer's build").font(Pixel.body).foregroundStyle(Palette.muted).textSelection(.enabled)
        Text("Every coding agent, what it's doing, and Allow or Deny for the ones waiting on you.")
          .font(Pixel.small).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
      }
    }
    .accessibilityElement(children: .combine)
    Section(title: "Updates") {
      if AppMover.shouldOffer {
        ActionRow(
          title: "ttycat isn't in Applications", detail: "It can only update itself from there.",
          button: "Move to Applications", loud: true
        ) { AppMover.move() }
      } else if let ready = m.appUpdateReady {
        ActionRow(
          title: "ttycat \(ready) is ready",
          detail: "Downloads it, checks it's ttycat's, and opens again as the new version. Agents keep running.",
          button: "Install", loud: true, action: m.appUpdater.check)
      } else if m.appUpdater.isActive {
        ActionRow(title: "ttycat updates itself", detail: "It checks on its own. This asks now.", button: "Check now", action: m.appUpdater.check)
      } else {
        Text("A build of your own: it doesn't update itself.").font(Pixel.body).foregroundStyle(Palette.muted)
      }
    }
    Section(title: "Elsewhere") {
      ActionRow(title: "ttycat.sh", detail: "The board, the downloads, and how it all fits together.", button: "Website") {
        if let url = URL(string: "https://ttycat.sh") { NSWorkspace.shared.open(url) }
      }
      RowLine()
      ActionRow(title: "Open source", detail: "The app, the daemon and the firmware are on GitHub, under Apache-2.0.", button: "Source") {
        if let url = URL(string: "https://github.com/ttycat-sh/ttycat-app") { NSWorkspace.shared.open(url) }
      }
    }
  }
}
