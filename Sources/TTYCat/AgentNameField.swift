// An agent's name, to type over: on its page in the window and on its page in the panel. Return or Save keeps
// it, Esc or Cancel drops it, and empty is no name of its own, so it goes by its folder again. What's typed is
// made a name by AgentName, and kept by the daemon.
import SwiftUI

struct AgentNameField: View {
  @EnvironmentObject var m: TTYCatModel
  @Environment(\.inWindow) private var inWindow  // which of the two it's in: each says for itself whose name is being typed
  let row: AgentRow
  @State private var typed = ""
  @FocusState private var typing: Bool

  private var folder: String { row.folder ?? row.p ?? "" }

  var body: some View {
    VStack(alignment: .leading, spacing: inWindow ? Rhythm.near : 6) {
      TextField("", text: $typed, prompt: Text(folder).foregroundStyle(Palette.faint))
        .textFieldStyle(.plain)
        .font(inWindow ? Pixel.title : Pixel.body)
        .foregroundStyle(Palette.white)
        .padding(.horizontal, inWindow ? 8 : 6)
        .frame(maxWidth: inWindow ? 360 : .infinity, minHeight: inWindow ? 32 : 26)
        .pixelBox(Palette.code, border: Palette.orange)
        .focused($typing)
        .onSubmit(save)
        .onExitCommand(perform: cancel)  // in the window; the panel has Esc first, and does the same: StatusPanel
        .onChange(of: typed) { _, new in
          if new.count > AgentName.longest { typed = String(new.prefix(AgentName.longest)) }
        }
        .accessibilityLabel("Name")
      if inWindow {
        buttons.fixedSize()
      } else {
        buttons
      }
      Text("Leave it empty and it goes by its folder, \(folder).").font(Pixel.small).foregroundStyle(Palette.muted)
        .fixedSize(horizontal: false, vertical: true)
    }
    .onAppear {
      typed = row.name ?? ""
      typing = true
    }
  }

  private var buttons: some View {
    HStack(spacing: inWindow ? Rhythm.near : 6) {
      PixelButton(title: "Cancel", action: cancel)
      PixelButton(title: "Save", loud: true, action: save)
    }
  }

  private func cancel() {
    m.stopRenaming(inWindow: inWindow)
  }

  private func save() {
    m.stopRenaming(inWindow: inWindow)
    m.rename(row, to: typed)
  }
}
