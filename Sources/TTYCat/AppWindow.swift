// The app's window and its menus. A menu bar app has neither until asked: the window opens from the
// panel's gear, Cmd-, or a right click on the icon, and while it's open the app is in the Dock and has
// a menu bar like any other. Closing it puts the app back to being only its icon.
import AppKit
import SwiftUI

@MainActor
final class AppWindow: NSObject, NSWindowDelegate {
  private(set) static var shared: AppWindow?
  static let size = NSSize(width: 900, height: 600)

  private let model: TTYCatModel
  private(set) var window: NSWindow?

  init(model: TTYCatModel) {
    self.model = model
    super.init()
    Self.shared = self
  }

  /// Made the first time it's wanted, and kept: where it was and how big come back with it.
  func show() {
    let window = self.window ?? make()
    self.window = window
    if window.contentViewController == nil {
      window.contentViewController = NSHostingController(rootView: WindowView().environmentObject(model))
    }
    model.window.isOpen = true
    NSApp.setActivationPolicy(.regular)  // in the Dock, with a menu bar, while there's a window to come back to
    NSApp.mainMenu = AppMenu.main()
    NSApp.unhide(nil)  // closing the window hides the app: see windowWillClose
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
  }

  private func make() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: Self.size),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: true)
    window.title = "ttycat"
    window.titleVisibility = .hidden  // the sidebar says whose window it is
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true  // there's no title bar to hold it by
    window.appearance = NSAppearance(named: .darkAqua)  // the board's look has one scheme
    window.backgroundColor = NSColor(Palette.black)
    window.minSize = NSSize(width: 900, height: 460)
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed
    window.delegate = self
    window.center()
    window.setFrameAutosaveName("ttycat.window.900")  // after centring: a saved place wins. Named for its first size
    return window
  }

  func windowWillClose(_ notification: Notification) {
    model.window.isOpen = false
    window?.contentViewController = nil  // built new next time, like the panel: it reads its settings again
    // Not while another window of the app's is up, such as its update's: that would hide it.
    let others = NSApp.windows.contains { $0 !== window && $0.isVisible && $0.styleMask.contains(.titled) }
    guard !others else { return }
    NSApp.setActivationPolicy(.accessory)
    // Still the active app, with nothing to show for it: give the front back to what was there before.
    DispatchQueue.main.async { NSApp.hide(nil) }
  }
}

@MainActor
enum AppMenu {
  /// The menu bar while the window is open: what every Mac app has, and no more.
  static func main() -> NSMenu {
    let bar = NSMenu()
    bar.addItem(submenu("ttycat", [
      item("About ttycat", #selector(Actions.about)),
      item("Check for Updates\u{2026}", #selector(Actions.checkForUpdates)),
      .separator(),
      item("Settings\u{2026}", #selector(Actions.settings), ","),
      .separator(),
      item("Hide ttycat", #selector(NSApplication.hide(_:)), "h", target: NSApp),
      item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option], target: NSApp),
      .separator(),
      item("Quit ttycat", #selector(Actions.quit), "q"),
    ]))
    bar.addItem(submenu("Edit", [
      item("Undo", Selector(("undo:")), "z", target: nil),
      item("Redo", Selector(("redo:")), "z", [.command, .shift], target: nil),
      .separator(),
      item("Cut", #selector(NSText.cut(_:)), "x", target: nil),
      item("Copy", #selector(NSText.copy(_:)), "c", target: nil),
      item("Paste", #selector(NSText.paste(_:)), "v", target: nil),
      item("Select All", #selector(NSText.selectAll(_:)), "a", target: nil),
    ]))
    let window = submenu("Window", [
      item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m", target: nil),
      item("Zoom", #selector(NSWindow.performZoom(_:)), target: nil),
      .separator(),
      item("Close", #selector(NSWindow.performClose(_:)), "w", target: nil),
    ])
    bar.addItem(window)
    NSApp.windowsMenu = window.submenu
    return bar
  }

  /// A right click on the menu bar icon.
  static func statusItem() -> NSMenu {
    let menu = NSMenu()
    menu.addItem(item("Settings\u{2026}", #selector(Actions.settings), ","))
    menu.addItem(item("Check for Updates\u{2026}", #selector(Actions.checkForUpdates)))
    menu.addItem(.separator())
    menu.addItem(item("Quit ttycat", #selector(Actions.quit), "q"))
    return menu
  }

  /// Quitting stops the daemon this app started, and prompts go back to the terminal: worth a word
  /// when agents are running, and silent when none are.
  static func quit() {
    guard let model = Actions.shared.model else { return NSApp.terminate(nil) }
    let count = model.rows.count
    if QuitCheck.asks(ownsDaemon: model.ownsDaemon, agents: count) {
      StatusPanel.shared?.close()
      NSApp.activate()
      let alert = NSAlert()
      alert.messageText = "Quit ttycat?"
      alert.informativeText = QuitCheck.message(agents: count)
      alert.addButton(withTitle: "Quit")
      alert.addButton(withTitle: "Cancel")
      guard alert.runModal() == .alertFirstButtonReturn else { return }
    }
    NSApp.terminate(nil)
  }

  private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
    let menu = NSMenu(title: title)
    items.forEach(menu.addItem)
    let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    holder.submenu = menu
    return holder
  }

  /// `target`: the app's own actions unless said; nil sends it to whatever has the keyboard.
  private static func item(_ title: String, _ action: Selector, _ key: String = "", _ flags: NSEvent.ModifierFlags = .command,
                           target: AnyObject? = Actions.shared) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.keyEquivalentModifierMask = flags
    item.target = target
    return item
  }

  /// What the menus do. An object, because a menu item needs one to send to.
  final class Actions: NSObject, NSMenuItemValidation {
    static let shared = Actions()
    weak var model: TTYCatModel?

    /// A build of your own doesn't update itself: there, the item is grey.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
      guard item.action == #selector(checkForUpdates) else { return true }
      return MainActor.assumeIsolated { model?.appUpdater.isActive ?? false }
    }

    @objc func settings() { MainActor.assumeIsolated { model?.openSettings() } }
    @objc func about() { MainActor.assumeIsolated { model?.showSettings(WindowPanes.about) } }
    @objc func quit() { MainActor.assumeIsolated { AppMenu.quit() } }
    @objc func checkForUpdates() { MainActor.assumeIsolated { model?.appUpdater.check() } }
  }
}

/// Whether quitting is worth a question. No side effects.
enum QuitCheck {
  static func asks(ownsDaemon: Bool, agents: Int) -> Bool { ownsDaemon && agents > 0 }

  static func message(agents: Int) -> String {
    "\(agents) agent\(agents == 1 ? " is" : "s are") running. They keep going, but ttycat stops watching them, and their prompts are answered in the terminal until it's open again."
  }
}
