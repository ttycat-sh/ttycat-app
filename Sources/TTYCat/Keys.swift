// The panel from the keyboard: moving between agents, opening one, going back, Deny, and Cmd-, for the
// window. Never Allow:
// that takes a click, on a prompt that's been read. No side effects: all testable.
import AppKit

enum PanelKey: Equatable {
  case close, up, down, open, back, deny, settings
}

enum PanelKeys {
  private static let escape: UInt16 = 53, `return`: UInt16 = 36, enter: UInt16 = 76
  private static let left: UInt16 = 123, down: UInt16 = 125, up: UInt16 = 126

  /// `typing`: a text field has the keyboard, so every key but Esc is its own.
  /// `repeating`: the key is being held. Only moving repeats: nothing is opened or answered by a held key.
  static func key(code: UInt16, characters: String?, flags: NSEvent.ModifierFlags, typing: Bool, repeating: Bool = false) -> PanelKey? {
    if code == escape { return .close }
    // The Mac's own key for it, wherever the keyboard is.
    if characters == ",", flags.intersection([.command, .option, .control, .shift]) == .command, !repeating { return .settings }
    guard !typing, flags.intersection([.command, .option, .control]).isEmpty else { return nil }
    switch code {
    case up: return .up
    case down: return .down
    default: break
    }
    guard !repeating else { return nil }
    switch code {
    case `return`, enter: return .open
    case left: return .back
    default: return characters?.lowercased() == "d" ? .deny : nil
    }
  }

  /// The row the highlight moves to. From nowhere, down starts at the top and up at the bottom; it
  /// stops at either end, and a row that has gone counts as nowhere.
  static func moved(from current: String?, by step: Int, in ids: [String]) -> String? {
    guard !ids.isEmpty else { return nil }
    guard let current, let at = ids.firstIndex(of: current) else { return step > 0 ? ids.first : ids.last }
    return ids[min(max(at + step, 0), ids.count - 1)]
  }
}
