import SwiftUI

/// A service's letters on a neutral tile (board 0.2): only the letters take its colour.
struct ServiceIcon: View {
    enum Size {
        case small, row, header

        var side: CGFloat {
            switch self {
            case .small: 18
            case .row: 32
            case .header: 44
            }
        }

        var corner: CGFloat {
            switch self {
            case .small: 5
            case .row: Theme.buttonCorner
            case .header: Theme.iconCorner
            }
        }

        var fontSize: CGFloat {
            switch self {
            case .small: 7.5
            case .row: 11
            case .header: 15
            }
        }
    }

    let letters: String
    let color: Color
    var size: Size = .row

    var body: some View {
        RoundedRectangle(cornerRadius: size.corner, style: .continuous)
            .fill(Theme.control)
            .overlay(
                RoundedRectangle(cornerRadius: size.corner, style: .continuous)
                    .strokeBorder(Theme.lineStrong, lineWidth: 1)
            )
            .frame(width: size.side, height: size.side)
            .overlay(
                Text(verbatim: letters)
                    .font(.system(size: size.fontSize, weight: .bold))
                    .foregroundStyle(color)
            )
    }
}
