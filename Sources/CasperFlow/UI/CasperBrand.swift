import AppKit
import SwiftUI

/// Casper wordmark + PyAI endorsement (rounded type, teal accent).
struct CasperLockup: View {
  var compact: Bool = false
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    HStack(alignment: .center, spacing: 10) {
      CasperAppIconView()
        .frame(width: compact ? 32 : 40, height: compact ? 32 : 40)
      VStack(alignment: .leading, spacing: 1) {
        Text("Casper")
          .font(compact ? .system(size: 16, weight: .bold, design: .rounded) : WFTheme.wordmarkFont)
          .foregroundStyle(colorScheme == .dark ? WFTheme.cream : WFTheme.ink)
        HStack(spacing: 6) {
          Text("by PyAI")
            .font(WFTheme.endorsementFont)
            .foregroundStyle(WFTheme.accent)
          if !compact {
            Text("Your friendly voice helper")
              .font(.system(size: 11, weight: .regular, design: .rounded))
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
      }
    }
  }
}

/// Dock-style Casper mark from brand PNG (squircle + ghost).
struct CasperAppIconView: View {
  var body: some View {
    Group {
      if let image = CasperBrandAssets.appIconImage() {
        Image(nsImage: image)
          .resizable()
          .interpolation(.high)
          .aspectRatio(contentMode: .fit)
      } else {
        CasperMark(onDark: true)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

/// Flat ghost fallback if the PNG is missing.
struct CasperMark: View {
  var onDark: Bool

  var body: some View {
    Canvas { context, size in
      let bodyColor = onDark ? WFTheme.cream : WFTheme.ink
      let eyeColor = onDark ? WFTheme.ink : WFTheme.cream
      let w = size.width
      let h = size.height
      var ghost = Path()
      ghost.move(to: CGPoint(x: w * 0.30, y: h * 0.38))
      ghost.addCurve(
        to: CGPoint(x: w * 0.50, y: h * 0.14),
        control1: CGPoint(x: w * 0.30, y: h * 0.20),
        control2: CGPoint(x: w * 0.38, y: h * 0.14)
      )
      ghost.addCurve(
        to: CGPoint(x: w * 0.70, y: h * 0.38),
        control1: CGPoint(x: w * 0.62, y: h * 0.14),
        control2: CGPoint(x: w * 0.70, y: h * 0.20)
      )
      ghost.addLine(to: CGPoint(x: w * 0.70, y: h * 0.62))
      ghost.addCurve(
        to: CGPoint(x: w * 0.50, y: h * 0.82),
        control1: CGPoint(x: w * 0.72, y: h * 0.78),
        control2: CGPoint(x: w * 0.60, y: h * 0.86)
      )
      ghost.addCurve(
        to: CGPoint(x: w * 0.30, y: h * 0.62),
        control1: CGPoint(x: w * 0.40, y: h * 0.86),
        control2: CGPoint(x: w * 0.28, y: h * 0.78)
      )
      ghost.closeSubpath()
      context.fill(ghost, with: .color(bodyColor))

      let eyeW = w * 0.07
      let eyeH = h * 0.13
      let eyeY = h * 0.34
      context.fill(
        RoundedRectangle(cornerRadius: eyeW / 2).path(
          in: CGRect(x: w * 0.38, y: eyeY, width: eyeW, height: eyeH)
        ),
        with: .color(eyeColor)
      )
      context.fill(
        RoundedRectangle(cornerRadius: eyeW / 2).path(
          in: CGRect(x: w * 0.55, y: eyeY, width: eyeW, height: eyeH)
        ),
        with: .color(eyeColor)
      )

      let barW = w * 0.04
      let heights: [CGFloat] = [0.07, 0.10, 0.14, 0.10, 0.07]
      let baseY = h * 0.72
      let total = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * w * 0.025
      var x = (w - total) / 2
      for height in heights {
        let barH = h * height
        context.fill(
          RoundedRectangle(cornerRadius: barW / 2).path(
            in: CGRect(x: x, y: baseY - barH, width: barW, height: barH)
          ),
          with: .color(WFTheme.accent)
        )
        x += barW + w * 0.025
      }
    }
    .accessibilityHidden(true)
  }
}

enum CasperBrandAssets {
  static func appIconImage() -> NSImage? {
    if let url = Bundle.main.url(forResource: "CasperAppIcon", withExtension: "png"),
       let image = NSImage(contentsOf: url) {
      return image
    }
    if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
       let image = NSImage(contentsOf: url) {
      return image
    }
    return NSImage(named: "CasperAppIcon")
  }

  /// Same brand mark as the app sidebar, sized for the menu bar.
  static func menuBarStatusImage() -> NSImage {
    let pointSize = NSSize(width: 18, height: 18)
    let image = NSImage(size: pointSize)
    if let source = appIconImage() {
      for representation in source.representations {
        image.addRepresentation(representation)
      }
    }
    image.size = pointSize
    image.isTemplate = false
    return image
  }
}
