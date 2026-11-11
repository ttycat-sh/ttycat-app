// The scroll bars, drawn as the rest is: a thin square bar in the board's greys, the accent while it's
// held. A Mac's own scroller underneath, so dragging, paging and the keyboard work as they do everywhere.
import AppKit
import SwiftUI

/// Where a scroller's bar goes, and how it looks. No side effects: all testable.
enum ScrollBar {
  static let width: CGFloat = 12     // the room the scroller takes
  static let thickness: CGFloat = 4  // the bar itself
  static let shortest: CGFloat = 24  // never too small to catch

  /// The bar inside the knob's place: thin, against the outer edge, and inset at its ends.
  static func bar(knob: CGRect, in bounds: CGRect) -> CGRect {
    let height = min(max(knob.height - 4, shortest), bounds.height)
    let top = min(max(knob.midY - height / 2, bounds.minY), bounds.maxY - height)
    return CGRect(x: bounds.maxX - thickness - 4, y: top, width: thickness, height: height)
  }
}

final class PixelScroller: NSScroller {
  private var inside = false
  private var held = false

  override class var isCompatibleWithOverlayScrollers: Bool { true }

  override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
    ScrollBar.width
  }

  // AppKit draws a scroller of its own unless these two are overridden: then it asks here.
  override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}  // no slot: the bar is all there is

  override func drawKnob() {
    let knob = rect(for: .knob)
    guard knob.height > 0 else { return }
    NSColor(held || inside ? Palette.orange : Palette.faint).setFill()
    ScrollBar.bar(knob: knob, in: bounds).fill()
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
  }

  override func mouseEntered(with event: NSEvent) {
    inside = true
    needsDisplay = true
  }

  override func mouseExited(with event: NSEvent) {
    inside = false
    needsDisplay = true
  }

  override func mouseDown(with event: NSEvent) {
    held = true
    needsDisplay = true
    super.mouseDown(with: event)  // returns when the drag ends
    held = false
    needsDisplay = true
  }
}

/// Put behind a scroll view's content, it gives that scroll view the scroller above.
private struct PixelScrollerProbe: NSViewRepresentable {
  final class Probe: NSView {
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      // After this pass: the scroll view is around it only once the content is in place.
      DispatchQueue.main.async { [weak self] in self?.apply() }
    }

    private func apply() {
      guard let scroll = enclosingScrollView, !(scroll.verticalScroller is PixelScroller) else { return }
      let scroller = PixelScroller()
      scroller.controlSize = .small
      scroll.verticalScroller = scroller
      scroll.tile()
    }
  }

  func makeNSView(context: Context) -> Probe { Probe() }
  func updateNSView(_ view: Probe, context: Context) {}
}

extension View {
  /// For what a ScrollView holds: its scroll bar is drawn as the board would.
  func pixelScroller() -> some View {
    background(PixelScrollerProbe().frame(width: 0, height: 0).accessibilityHidden(true))
  }
}
