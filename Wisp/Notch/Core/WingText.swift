import AppKit

/// Text on the closed notch is measured the way it is drawn: 12 pt semibold, every digit
/// equally wide. So a number that counts doesn't resize the notch.
enum WingText {
    static func width(_ text: String) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }
}
