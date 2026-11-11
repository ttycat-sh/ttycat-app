// The board's look: its palette, its four pixel fonts, its stepped-corner boxes and 5x5 icons.
import AppKit
import CoreText
import SwiftUI

extension Color {
  init(hex: UInt32) {
    self.init(
      .sRGB, red: Double(hex >> 16 & 255) / 255, green: Double(hex >> 8 & 255) / 255,
      blue: Double(hex & 255) / 255)
  }
}

// The board's colours: the same values as ttycat-firmware's main/ui.c.
enum Palette {
  static let black = Color(hex: 0x000000)
  static let tile = Color(hex: 0x0C0C0C)
  static let line = Color(hex: 0x262626)
  static let dotOff = Color(hex: 0x1C1C1C)
  static let card = Color(hex: 0x161616)
  static let code = Color(hex: 0x0B0B0B)
  static let muted = Color(hex: 0x9A9A9A)
  static let muted2 = Color(hex: 0x8C8C8C)
  static let faint = Color(hex: 0x505050)
  static let white = Color(hex: 0xFFFFFF)
  static var orange: Color { Color(hex: Look.accentValue) }  // the accent: orange unless you've chosen otherwise
  static var bitBody: Color { Color(hex: Look.skin.body) }
  static var bitShade: Color { Color(hex: Look.skin.shade) }
  static let green = Color(hex: 0x3FD38A)
  static let laptop = Color(hex: 0xC4C4C4)
  static let laptopEdge = Color(hex: 0x7A7A7A)
  static let ink = Color(hex: 0x0B0B0B)
}

/// Type. Headlines are the board's pixel faces: Press Start 2P for the one big word, Pixelify Sans for the
/// names of things, Silkscreen for labels and buttons. What's read at length is Geist Mono: a terminal's
/// face, drawn for a Mac's screen.
enum Pixel {
  static func registerFonts() {
    for name in ["Silkscreen-Bold", "PressStart2P-Regular", "VT323-Regular", "PixelifySans-wght", "GeistMono-wght"] {
      guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
      CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
  }

  static let label = Font.custom("Silkscreen-Bold", fixedSize: 8)
  static let button = Font.custom("Silkscreen-Bold", fixedSize: 8)
  static let windowLabel = Font.custom("Silkscreen-Bold", fixedSize: 10)  // the window is read from further off than the panel
  static let hero = Font.custom("PressStart2P-Regular", fixedSize: 16)
  static let display = Font.custom("PressStart2P-Regular", fixedSize: 24)  // a number worth the room, in the window
  static let body = Font.custom("Geist Mono", fixedSize: 12)
  static let small = Font.custom("Geist Mono", fixedSize: 10.5)
  static let code = Font.custom("Geist Mono", fixedSize: 12)
  // A name that must be read letter for letter: Pixelify's capital C passes for an O.
  static let name = Font.custom("Geist Mono", fixedSize: 15).weight(.semibold)

  // A variable font: the board draws Pixelify Sans at weight 700.
  static var title: Font { pixelify(16) }
  static var heading: Font { pixelify(20) }   // a part of a pane, in the window
  static var headline: Font { pixelify(32) }  // a pane's name, in the window

  private static func pixelify(_ size: CGFloat) -> Font {
    let wght = 0x7767_6874  // 'wght'
    let base = NSFontDescriptor(name: "PixelifySans-Regular", size: size)
    // No ligatures: its "fi" is one glyph that reads as another letter at this size.
    let noLigatures: [NSFontDescriptor.FeatureKey: Int] = [.typeIdentifier: kLigaturesType, .selectorIdentifier: kCommonLigaturesOffSelector]
    let bold = base.addingAttributes([
      .variation: [NSNumber(value: wght): NSNumber(value: 700)], .featureSettings: [noLigatures],
    ])
    return NSFont(descriptor: bold, size: size).map { Font($0) } ?? .custom("PixelifySans-Regular", fixedSize: size)
  }
}

/// The window's spacing: everything sits on a grid of 8, so what's stacked keeps one beat.
enum Rhythm {
  static let tight: CGFloat = 4    // a line and the one that explains it
  static let near: CGFloat = 8     // things that belong together
  static let apart: CGFloat = 16   // one thing and the next; the inside of a box
  static let section: CGFloat = 24 // a title and what's under it
  static let page: CGFloat = 32    // the edge of a pane; one part of it and the next
}

/// Whether a view is in the window, where there's room and controls take only the width they need, or in
/// the panel, where they fill it.
private struct InWindowKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
  var inWindow: Bool {
    get { self[InWindowKey.self] }
    set { self[InWindowKey.self] = newValue }
  }
}

// The board's `.n` box: a fill, an optional 2 px border, and steps cut from the corners.
struct SteppedRect: Shape {
  var step: CGFloat = 2
  func path(in r: CGRect) -> Path {
    Path { p in
      p.move(to: CGPoint(x: r.minX + step, y: r.minY))
      p.addLine(to: CGPoint(x: r.maxX - step, y: r.minY))
      p.addLine(to: CGPoint(x: r.maxX - step, y: r.minY + step))
      p.addLine(to: CGPoint(x: r.maxX, y: r.minY + step))
      p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - step))
      p.addLine(to: CGPoint(x: r.maxX - step, y: r.maxY - step))
      p.addLine(to: CGPoint(x: r.maxX - step, y: r.maxY))
      p.addLine(to: CGPoint(x: r.minX + step, y: r.maxY))
      p.addLine(to: CGPoint(x: r.minX + step, y: r.maxY - step))
      p.addLine(to: CGPoint(x: r.minX, y: r.maxY - step))
      p.addLine(to: CGPoint(x: r.minX, y: r.minY + step))
      p.addLine(to: CGPoint(x: r.minX + step, y: r.minY + step))
      p.closeSubpath()
    }
  }
}

extension View {
  func pixelBox(_ fill: Color, border: Color? = nil) -> some View {
    background(
      ZStack {
        SteppedRect().fill(border ?? fill)
        if border != nil { SteppedRect(step: 2).fill(fill).padding(2) }
      })
  }
}

/// A pixel icon, one byte per row, MSB on the left: the firmware's format. 5 wide for what sits beside
/// text, 7 wide for the window's sidebar.
struct PixelIcon: View {
  static let bang: [UInt8] = [0x04, 0x04, 0x04, 0x00, 0x04]
  static let cross: [UInt8] = [0x11, 0x0A, 0x04, 0x0A, 0x11]
  static let check: [UInt8] = [0x01, 0x03, 0x16, 0x1C, 0x08]
  static let dash: [UInt8] = [0x00, 0x00, 0x0E, 0x00, 0x00]
  static let right: [UInt8] = [0x08, 0x04, 0x02, 0x04, 0x08]
  static let left: [UInt8] = [0x02, 0x04, 0x08, 0x04, 0x02]
  static let plus: [UInt8] = [0x04, 0x04, 0x1F, 0x04, 0x04]
  static let gear: [UInt8] = [0x15, 0x0E, 0x1B, 0x0E, 0x15]
  static let down: [UInt8] = [0x00, 0x11, 0x0A, 0x04, 0x00]
  // 7 x 7: a glass, for a field that finds things.
  static let find: [UInt8] = [0x38, 0x44, 0x44, 0x44, 0x38, 0x04, 0x02]
  static let branch: [UInt8] = [0x04, 0x04, 0x1F, 0x11, 0x11]  // one becoming two: subagents
  static let shell: [UInt8] = [0x10, 0x08, 0x10, 0x00, 0x07]   // >_
  static let out: [UInt8] = [0x0F, 0x03, 0x05, 0x09, 0x10]     // an arrow up and out: it opens somewhere else

  // 7 x 7, for the sidebar.
  static let navGrid: [UInt8] = [0x77, 0x77, 0x77, 0x00, 0x77, 0x77, 0x77]
  static let navBars: [UInt8] = [0x01, 0x05, 0x05, 0x15, 0x15, 0x55, 0x55]
  static let navLines: [UInt8] = [0x7F, 0x00, 0x7C, 0x00, 0x7F, 0x00, 0x78]
  static let navGear: [UInt8] = [0x2A, 0x3E, 0x77, 0x63, 0x77, 0x3E, 0x2A]
  static let navBell: [UInt8] = [0x08, 0x1C, 0x3E, 0x3E, 0x3E, 0x7F, 0x08]
  static let navChip: [UInt8] = [0x14, 0x3E, 0x7F, 0x3E, 0x7F, 0x3E, 0x14]
  static let navScreen: [UInt8] = [0x7F, 0x41, 0x41, 0x41, 0x7F, 0x08, 0x1C]
  static let navSwatch: [UInt8] = [0x7F, 0x47, 0x47, 0x47, 0x47, 0x47, 0x7F]
  static let navKey: [UInt8] = [0x38, 0x28, 0x38, 0x08, 0x0C, 0x08, 0x0C]
  static let navPrompt: [UInt8] = [0x00, 0x40, 0x20, 0x10, 0x20, 0x47, 0x00]
  static let navInfo: [UInt8] = [0x08, 0x00, 0x18, 0x08, 0x08, 0x08, 0x1C]
  static let navHeart: [UInt8] = [0x36, 0x7F, 0x7F, 0x7F, 0x3E, 0x1C, 0x08]

  let rows: [UInt8]
  var scale: CGFloat = 2
  var color: Color = Palette.white

  private var width: Int { rows.count > 5 ? 7 : 5 }

  var body: some View {
    let width = self.width
    Canvas { ctx, _ in
      for (j, row) in rows.enumerated() {
        for i in 0..<width where row & (UInt8(1) << UInt8(width - 1 - i)) != 0 {
          let r = CGRect(x: CGFloat(i) * scale, y: CGFloat(j) * scale, width: scale, height: scale)
          ctx.fill(Path(r), with: .color(color))
        }
      }
    }
    .frame(width: CGFloat(width) * scale, height: CGFloat(rows.count) * scale)
    .accessibilityHidden(true)  // what it's on says what it is
  }
}

/// A small light: on, off, or a colour that means something. Square, like every pixel here.
struct Dot: View {
  let color: Color
  init(_ color: Color) { self.color = color }
  var body: some View { Rectangle().fill(color).frame(width: 6, height: 6) }
}

// Silkscreen labels are capitals on the board too.
struct Caps: View {
  @Environment(\.inWindow) private var inWindow
  let text: String
  var color: Color = Palette.muted
  init(_ text: String, color: Color = Palette.muted) {
    self.text = text
    self.color = color
  }
  var body: some View {
    Text(text.uppercased()).font(inWindow ? Pixel.windowLabel : Pixel.label).foregroundStyle(color).lineLimit(1)
  }
}

// The board's "pressed" feedback: the box lights up while held.
struct PixelPress: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.brightness(configuration.isPressed ? 0.25 : 0).contentShape(Rectangle())
  }
}

struct PixelButton: View {
  @Environment(\.inWindow) private var inWindow
  let title: String
  var loud = false
  var enabled = true
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Caps(title, color: !enabled ? Palette.faint : loud ? Palette.black : Palette.white)
        .padding(.horizontal, inWindow ? 14 : 8)
        .frame(maxWidth: inWindow ? nil : .infinity, minHeight: inWindow ? 32 : 28)
        .pixelBox(loud && enabled ? Palette.orange : Palette.tile, border: loud && enabled ? nil : Palette.line)
    }
    .buttonStyle(PixelPress())
    .disabled(!enabled)
  }
}

struct PixelCheckbox: View {
  let on: Bool
  var body: some View {
    ZStack {
      Rectangle().fill(on ? Palette.green : Palette.tile)
      Rectangle().strokeBorder(on ? Palette.green : Palette.faint, lineWidth: 2)
      if on { PixelIcon(rows: PixelIcon.check, scale: 2, color: Palette.black) }
    }
    .frame(width: 16, height: 16)
  }
}

/// On or off, as a switch: a square knob in a square track, for the window.
struct PixelSwitch: View {
  let on: Bool
  var enabled = true

  var body: some View {
    ZStack(alignment: on ? .trailing : .leading) {
      Rectangle().fill(on && enabled ? Palette.green : Palette.tile)
      Rectangle().strokeBorder(on && enabled ? Palette.green : Palette.faint, lineWidth: 2)
      Rectangle().fill(on && enabled ? Palette.black : Palette.faint).frame(width: 10, height: 10).padding(4)
    }
    .frame(width: 34, height: 18)
    .animation(.easeOut(duration: 0.1), value: on)
  }
}
