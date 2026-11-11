// The pieces the panel and the window are both made of: a titled box, a setting that's on or off, a fact
// with its light, a meter, and something to do with its button.
import SwiftUI

// In blocks, like the board's meters.
struct FlashBar: View {
  let pct: Int
  private let cells = 28

  var body: some View {
    HStack(spacing: 2) {
      ForEach(0..<cells, id: \.self) { i in
        Rectangle().fill(i * 100 < pct * cells ? Palette.orange : Palette.line).frame(height: 8)
      }
    }
    .accessibilityElement()
    .accessibilityValue("\(pct) percent")
  }
}

/// A box with its name in it. In the window it has room to breathe.
struct Section<Content: View>: View {
  @Environment(\.inWindow) private var inWindow
  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: inWindow ? Rhythm.apart : 6) {
      Caps(title).accessibilityAddTraits(.isHeader)
      content
    }
    .padding(inWindow ? Rhythm.apart : 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .pixelBox(inWindow ? Palette.card : Palette.tile, border: Palette.line)
  }
}

/// A setting that's on or off. In the panel a tick box leads, as on the board; in the window what it is
/// comes first and a switch sits at the end of the line.
struct Toggled: View {
  @Environment(\.inWindow) private var inWindow
  let title: String
  let on: Bool
  var detail: String?
  var enabled = true
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: inWindow ? 16 : 8) {
        if !inWindow { PixelCheckbox(on: on) }
        VStack(alignment: .leading, spacing: inWindow ? Rhythm.tight : 2) {
          Text(title).font(Pixel.body).foregroundStyle(enabled ? Palette.white : Palette.faint)
            .fixedSize(horizontal: false, vertical: true)
          if let detail {
            Text(detail).font(Pixel.small).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
          }
        }
        .multilineTextAlignment(.leading)
        Spacer(minLength: 0)
        if inWindow { PixelSwitch(on: on, enabled: enabled) }
      }
    }
    .buttonStyle(PixelPress())
    .disabled(!enabled)
    // One thing to VoiceOver, that says what it is and how it stands.
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(detail.map { "\(title), \($0)" } ?? title)
    .accessibilityValue(on ? "on" : "off")
    .accessibilityAddTraits(.isToggle)
  }
}

struct Fact: View {
  let name: String
  let value: String
  let good: Bool

  var body: some View {
    HStack(spacing: 8) {
      Dot(good ? Palette.green : Palette.faint)
      Text(name).font(Pixel.body).foregroundStyle(Palette.white)
      Spacer(minLength: 8)
      Text(value).font(Pixel.small).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
    }
    .accessibilityElement(children: .combine)
  }
}

/// Something to do, with what it does beside it: the words on the left, one button on the right.
struct ActionRow: View {
  let title: String
  var detail: String?
  let button: String
  var loud = false
  var enabled = true
  let action: () -> Void

  var body: some View {
    // Side by side while the words keep a readable width; in a narrow window the button goes under them.
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .center, spacing: Rhythm.apart) {
        words.frame(minWidth: 220, idealWidth: 220, maxWidth: .infinity, alignment: .leading)
        press
      }
      VStack(alignment: .leading, spacing: Rhythm.near + Rhythm.tight) {
        words
        press
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var words: some View {
    VStack(alignment: .leading, spacing: Rhythm.tight) {
      Text(title).font(Pixel.body).foregroundStyle(Palette.white).fixedSize(horizontal: false, vertical: true)
      if let detail {
        Text(detail).font(Pixel.small).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var press: some View {
    PixelButton(title: button, loud: loud, enabled: enabled, action: action).fixedSize()
  }
}

/// A line between two things in one box.
struct RowLine: View {
  var body: some View { Rectangle().fill(Palette.line).frame(height: 2) }
}
