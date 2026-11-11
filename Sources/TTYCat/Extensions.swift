// What an extended build can add to the app. The open-source build adds nothing, and runs fine.
// Everything an extension can reach through here is the contract between the two: change it, and
// bump apiVersion, as with daemon/plugins.py.
import SwiftUI

/// A tab in the panel: for what's about agents right now.
struct ExtraPage {
  let id: String
  let title: String
  let view: @MainActor () -> AnyView
}

/// A pane in the window. `settings`: it's something to set, listed with the app's own settings;
/// otherwise something to look at, listed above them. `icon`: its icon in the sidebar, 7 x 7 pixels in
/// PixelIcon's format. `summary`: a line under its title, saying what's there.
struct ExtraPane {
  let id: String
  let title: String
  var icon = PixelIcon.navGrid
  var summary: String?
  var settings = true
  let view: @MainActor () -> AnyView
}

@MainActor
enum Extensions {
  /// 2: the window. Setup left the panel, so `setupSections` became `panes`.
  static let apiVersion = 2
  static var pages: [ExtraPage] = []
  static var panes: [ExtraPane] = []
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
