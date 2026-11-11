// The board in the window: its name, what it runs, and what can be done about it. Only ever shown on a
// Mac that has had a board.
import SwiftUI

struct FirmwareSection: View {
  @EnvironmentObject var m: TTYCatModel
  @State private var confirming = false  // an unknown device: asked twice
  @State private var confirmingApprove = false  // so is letting a device say yes

  var body: some View {
    Section(title: "Board") {
      if m.boardConnected {
        NameRow()
        RowLine()
      }
      switch m.firmwarePlan {
      case .noImage:
        note("This build carries no firmware. Build ttycat-firmware, then run build.sh again.")
      case .notConnected:
        Fact(name: "Board", value: "not connected", good: false)
        PixelButton(title: "Forget the board", enabled: !m.flashBusy, action: m.forgetBoard)
        note("For a Mac that won't have it again: nothing here mentions the board until one is plugged in.")
      case .identifying:
        Fact(name: "Board", value: "connecting", good: false)
      case .unknownDevice(let port):
        Fact(name: "Board", value: "not answering", good: false)
        note("\((port as NSString).lastPathComponent) isn't answering. If that's the board, reinstalling fixes it. If it's another device, this would overwrite it.", warn: true)
        if confirming {
          HStack(spacing: 6) {
            PixelButton(title: "Cancel") { confirming = false }
            PixelButton(title: "Overwrite it", loud: true) {
              confirming = false
              m.updateFirmware(unknown: true, port: port)
            }
          }
        } else {
          PixelButton(title: "Reinstall firmware") { confirming = true }
        }
      case .customFirmware(let name, let port, let canReplace, let outdated, let core):
        Fact(name: "Board", value: "\(name), custom firmware", good: !outdated)
        if outdated {
          note(core?.canUpdate == true
               ? "This firmware doesn't match this version of ttycat, so nothing is being sent to it. Updating its core fixes that."
               : "This firmware doesn't match this version of ttycat, so nothing is being sent to it. Rebuild it from the latest source.", warn: true)
        }
        coreChoice(core)
        if !outdated { approveChoice(name) }
        if canReplace {
          if confirming {
            note("This erases \(name) from \(port).", warn: true)
            HStack(spacing: 6) {
              PixelButton(title: "Cancel") { confirming = false }
              PixelButton(title: "Erase it", loud: true, enabled: !m.flashBusy) {
                confirming = false
                m.updateFirmware(unknown: true)
              }
            }
          } else {
            PixelButton(title: "Replace with ttycat firmware") { confirming = true }
          }
        }
      case .upToDate(let version):
        Fact(name: "Board", value: newestLabel(version, updates: m.status?.updates), good: true)
      case .boardNewer(let board, let app):
        Fact(name: "Board", value: "\(board), newer than the app's \(app)", good: true)
      case .update(let from, let to):
        Fact(name: "Firmware", value: "\(from) installed", good: false)
        RowLine()
        ActionRow(
          title: "Firmware \(to) is available",
          detail: "Takes about 10 seconds. Agents keep running; answer prompts in ttycat or the terminal until the board is back.",
          button: "Update board", loud: true, enabled: !m.flashBusy
        ) { m.updateFirmware() }
      case .noTool(let to):
        Fact(name: "Board", value: "\(to) available", good: false)
        note("Updating needs esptool, which comes with ESP-IDF.", warn: true)
      case .writing(let pct, let to):
        Fact(name: "Writing \(to)", value: "\(pct)%", good: true)
        FlashBar(pct: pct)
        note("Don't unplug the board.")
      case .restarting(let to):
        Fact(name: "Written \(to)", value: "waiting for the board", good: true)
        FlashBar(pct: 100)
      case .coreUpdate(let step, let pct, let to):
        switch step {
        case .building:
          Fact(name: "Building core \(to)", value: "\(pct)%", good: true)
          FlashBar(pct: pct)
          note("On this Mac, with your board's own folder. The first build takes a few minutes. The board works as usual until it's written.")
        case .writing:
          Fact(name: "Writing core \(to)", value: "\(pct)%", good: true)
          FlashBar(pct: pct)
          note("Don't unplug the board.")
        case .restarting:
          Fact(name: "Written core \(to)", value: "waiting for the board", good: true)
          FlashBar(pct: 100)
        case .puttingBack:
          Fact(name: "Putting the old build back", value: "\(pct)%", good: false)
          FlashBar(pct: pct)
          note("The new build didn't start. Don't unplug the board.", warn: true)
        }
      case .registering(let pct, let waiting):
        if waiting {
          Fact(name: "Read its firmware", value: "waiting for the board", good: true)
          FlashBar(pct: 100)
        } else {
          Fact(name: "Reading its firmware", value: "\(pct)%", good: true)
          FlashBar(pct: pct)
        }
        note("A copy of what it runs, to put back if an update ever fails. Nothing is written to it.")
      }
      if let flash = m.status?.flash, flash.state == "failed", !m.flashBusy {
        note("Last try failed: \(flash.msg)", warn: true)
      }
    }
  }

  /// ttycat's new releases, built for a board of the person's own with its own folder. Never their folder in ttycat.
  @ViewBuilder private func coreChoice(_ core: CoreInfo?) -> some View {
    if let core, core.registered {
      if let available = core.available {
        Fact(name: "Built from core", value: core.core ?? "unknown", good: false)
        Fact(name: "Newer core", value: available, good: false)
        if core.blocked.isEmpty {
          PixelButton(title: "Update core to \(available)", loud: true, enabled: !m.flashBusy) { m.updateCore() }
          note("Builds it on this Mac with your board's own folder, then writes it. Takes a few minutes. If the new build doesn't start, the one it runs now goes back on.")
        } else {
          note(core.blocked, warn: true)
        }
      } else if let version = core.core {
        Fact(name: "Built from core", value: newestLabel(version, updates: m.status?.updates), good: true)
      }
      if core.state == "failed", !core.msg.isEmpty, !m.flashBusy {
        note("Last update: \(core.msg)", warn: true)
      }
      if let folder = core.folder, !FileManager.default.fileExists(atPath: folder) {
        if core.available == nil {
          note("Its folder isn't at \(folder) any more.", warn: true)
        }
        PixelButton(title: "Choose its folder again", enabled: !m.flashBusy) { m.chooseBoardFolder() }
        if let refused = m.registerRefused {
          note("That folder wasn't taken: \(refused)", warn: true)
        }
      }
    } else if let core {
      if core.folder != nil {
        note("It runs a build this Mac has no copy of. Choose its folder again, so the one it runs can go back on if an update fails.", warn: true)
      } else {
        note("ttycat's updates are built for this board with its own code. Choose the folder it was built from\(m.status?.board.name.map { ", named \($0)" } ?? ""), and they'll show here. The board's firmware is read, not changed.")
      }
      PixelButton(title: core.folder == nil ? "Choose its folder" : "Choose its folder again", enabled: !m.flashBusy) {
        m.chooseBoardFolder()
      }
      if let refused = m.registerRefused {
        note("That folder wasn't taken: \(refused)", warn: true)
      }
    }
  }

  /// Off unless you turn it on. Only worth turning on for a device that shows the whole prompt.
  @ViewBuilder private func approveChoice(_ name: String) -> some View {
    if m.status?.board.approves == true {
      Toggled(title: "It can approve prompts", on: true, detail: "turn off to allow Deny only") {
        m.setDeviceApproves(name, false)
      }
    } else if confirmingApprove {
      note("Only if it shows you the whole prompt before you say yes. Otherwise you'd be approving what nobody has read.", warn: true)
      HStack(spacing: 6) {
        PixelButton(title: "Cancel") { confirmingApprove = false }
        PixelButton(title: "Let it approve", loud: true) {
          confirmingApprove = false
          m.setDeviceApproves(name, true)
        }
      }
    } else {
      Toggled(title: "It can approve prompts", on: false, detail: "it can only Deny for now") {
        confirmingApprove = true
      }
    }
  }

  private func note(_ text: String, warn: Bool = false) -> some View {
    Text(text).font(Pixel.small).foregroundStyle(warn ? Palette.orange : Palette.muted)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// The board's name, kept on the board and on this Mac. Renaming never changes what it may approve.
struct NameRow: View {
  @EnvironmentObject var m: TTYCatModel
  @State private var editing = false
  @State private var typed = ""

  var body: some View {
    if editing {
      TextField("", text: $typed, prompt: Text("desk cat").foregroundStyle(Palette.faint))
        .textFieldStyle(.plain)
        .font(Pixel.body)
        .foregroundStyle(Palette.white)
        .padding(.horizontal, 6)
        .frame(height: 26)
        .pixelBox(Palette.code, border: Palette.orange)
        .onSubmit(save)
      HStack(spacing: 6) {
        PixelButton(title: "Cancel") { editing = false }
        PixelButton(title: "Save", loud: true, action: save)
      }
    } else {
      HStack(spacing: 6) {
        Fact(name: "Name", value: m.status?.board.label ?? "none yet", good: m.status?.board.label != nil)
        PixelButton(title: "Rename") {
          typed = m.status?.board.label ?? ""
          editing = true
        }
        .fixedSize()
      }
    }
  }

  private func save() {
    editing = false
    m.nameBoard(typed)
  }
}
