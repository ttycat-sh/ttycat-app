import AppKit
import Testing
@testable import TTYCat

private func key(_ code: UInt16, _ characters: String? = nil, flags: NSEvent.ModifierFlags = [], typing: Bool = false,
                 repeating: Bool = false) -> PanelKey? {
  PanelKeys.key(code: code, characters: characters, flags: flags, typing: typing, repeating: repeating)
}

@Suite struct PanelKeyboard {
  @Test func theKeysThatMoveAroundThePanel() {
    #expect(key(53) == .close)
    #expect(key(126) == .up)
    #expect(key(125) == .down)
    #expect(key(36) == .open)
    #expect(key(76) == .open)  // the number pad's Enter
    #expect(key(123) == .back)
    #expect(key(2, "d") == .deny)
    #expect(key(2, "D", flags: .capsLock) == .deny)
  }

  @Test func noKeyEverAllows() {
    for (code, characters) in [(0, "a"), (16, "y"), (49, " "), (48, "\t"), (124, nil)] as [(UInt16, String?)] {
      #expect(key(code, characters) == nil)
    }
  }

  @Test func aTextFieldKeepsEveryKeyButEsc() {
    #expect(key(2, "d", typing: true) == nil)
    #expect(key(36, typing: true) == nil)
    #expect(key(125, typing: true) == nil)
    #expect(key(53, typing: true) == .close)
  }

  @Test func shortcutsOfTheSystemAreLeftAlone() {
    #expect(key(2, "d", flags: .command) == nil)
    #expect(key(125, flags: .option) == nil)
    #expect(key(36, flags: .control) == nil)
  }

  @Test func aHeldKeyMovesButNeverOpensOrAnswers() {
    #expect(key(125, repeating: true) == .down)
    #expect(key(126, repeating: true) == .up)
    #expect(key(36, repeating: true) == nil)
    #expect(key(2, "d", repeating: true) == nil)
    #expect(key(123, repeating: true) == nil)
  }

  @Test func theHighlightStartsAtAnEndAndStopsAtBoth() {
    let ids = ["a", "b", "c"]
    #expect(PanelKeys.moved(from: nil, by: 1, in: ids) == "a")
    #expect(PanelKeys.moved(from: nil, by: -1, in: ids) == "c")
    #expect(PanelKeys.moved(from: "a", by: 1, in: ids) == "b")
    #expect(PanelKeys.moved(from: "c", by: 1, in: ids) == "c")
    #expect(PanelKeys.moved(from: "a", by: -1, in: ids) == "a")
    #expect(PanelKeys.moved(from: "gone", by: 1, in: ids) == "a")  // its agent ended
    #expect(PanelKeys.moved(from: "a", by: 1, in: []) == nil)
  }
}
