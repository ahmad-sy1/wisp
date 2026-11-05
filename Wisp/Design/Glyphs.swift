import AppKit
import SwiftUI

extension Image {
    /// An SF Symbol, or one of wisp's own glyphs where SF Symbols has no match.
    static func wisp(_ name: String) -> Image {
        name == WispGlyph.pullRequest ? Image(nsImage: WispGlyph.pullRequestImage) : Image(systemName: name)
    }
}

enum WispGlyph {
    /// The pull request mark of design page 3: two nodes joined by a branch.
    static let pullRequest = "wisp.pullrequest"

    static let pullRequestImage: NSImage = {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            NSColor.black.set()
            let line = NSBezierPath()
            line.lineWidth = 1.4
            line.lineCapStyle = .round
            func ring(_ x: CGFloat, _ y: CGFloat) {
                line.appendOval(in: NSRect(x: x - 2, y: y - 2, width: 4, height: 4))
            }
            ring(3.5, 3.5)
            ring(3.5, 12.5)
            ring(12.5, 12.5)
            line.move(to: NSPoint(x: 3.5, y: 5.5))
            line.line(to: NSPoint(x: 3.5, y: 10.5))
            line.move(to: NSPoint(x: 12.5, y: 10.5))
            line.line(to: NSPoint(x: 12.5, y: 6.5))
            line.curve(to: NSPoint(x: 9.5, y: 3.5), controlPoint1: NSPoint(x: 12.5, y: 4.5), controlPoint2: NSPoint(x: 11.5, y: 3.5))
            line.line(to: NSPoint(x: 7, y: 3.5))
            line.move(to: NSPoint(x: 8.8, y: 1.5))
            line.line(to: NSPoint(x: 6.8, y: 3.5))
            line.line(to: NSPoint(x: 8.8, y: 5.5))
            line.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
