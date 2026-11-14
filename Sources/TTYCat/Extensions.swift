// What an extended build can add to the app. The open-source build adds nothing, and runs fine.
// Everything an extension can reach through here is the contract between the two: change it, and
// bump apiVersion, as with daemon/plugins.py.
import SwiftUI

/// A tab in the panel: for what's about agents right now. `badge`: a word in a box beside its title;
/// nil, none. `link`: while it gives somewhere to go, a click on the tab opens that instead of the page,
/// as for a page that's locked. Both are asked each time the tabs are drawn.
struct ExtraPage {
  let id: String
  let title: String
  var badge: @MainActor () -> String? = { nil }
  var link: @MainActor () -> URL? = { nil }
  let view: @MainActor () -> AnyView
}

/// A pane in the window. `settings`: it's something to set, listed with the app's own settings;
/// otherwise something to look at, listed above them. `icon`: its icon in the sidebar, 7 x 7 pixels in
/// PixelIcon's format. `summary`: a line under its title, saying what's there. `badge`: a word in a box
/// beside its title, wherever it's listed; nil, none. Asked each time the list is drawn.
struct ExtraPane {
  let id: String
  let title: String
  var icon = PixelIcon.navGrid
  var summary: String?
  var settings = true
  var badge: @MainActor () -> String? = { nil }
  let view: @MainActor () -> AnyView
}

@MainActor
enum Extensions {
  /// 2: the window. Setup left the panel, so `setupSections` became `panes`.
  /// 3: `agentFacts` and `cardNotes`, and a row's `ses`.
  /// 4: a tab's `badge` and `link`, and `cardNotes` on the panel's rows too.
  /// 5: a pane's `badge`.
  static let apiVersion = 5
  static var pages: [ExtraPage] = []
  static var panes: [ExtraPane] = []
  /// More tiles on an agent's page in the window, after the app's own: what an extension knows of
  /// that agent. Asked each time the page is drawn, so answer from what's already at hand. `about`
  /// is what the daemon said of the agent, once it has.
  static var agentFacts: [@MainActor (AgentRow, AgentAbout?) -> [AgentFacts.Fact]] = []
  /// A few words on an agent's card in the window, beside how long it's been as it is, and on its row
  /// in the panel. Asked each time either is drawn. nil: nothing to say of this one.
  static var cardNotes: [@MainActor (AgentRow) -> String?] = []

  /// The app's tiles for an agent, then each extension's.
  static func facts(_ row: AgentRow, about: AgentAbout?) -> [AgentFacts.Fact] {
    AgentFacts(row, about: about).facts + agentFacts.flatMap { $0(row, about) }
  }

  /// What extensions say on an agent's card, each one's words apart.
  static func cardNote(_ row: AgentRow) -> String? {
    let notes = cardNotes.compactMap { $0(row) }.filter { !$0.isEmpty }
    return notes.isEmpty ? nil : notes.joined(separator: " \u{00B7} ")
  }
  static var started: [@MainActor (TTYCatModel) -> Void] = []
  static var polled: [@MainActor (TTYCatModel) -> Void] = []  // once a second
  /// Uninstalling: take away what the extension added outside the app. Run before the daemon stops.
  static var uninstalling: [@MainActor (TTYCatModel) -> Void] = []
  static var preview: (@MainActor (String, TTYCatModel) -> Void)?

  /// Called once, before anything starts. A build with extensions compiles its own in.
  static func install() {
    #if TTYCAT_PRO
    ProFeatures.install()
    #endif
  }
}
