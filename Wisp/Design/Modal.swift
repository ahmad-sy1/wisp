import SwiftUI

/// Dims the window to 60 % black, with a modal in the middle (board 0.2).
struct ModalBackdrop<Content: View>: View {
    let close: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
            content
        }
        .ignoresSafeArea()
    }
}

extension View {
    func modalSurface() -> some View {
        background(RoundedRectangle(cornerRadius: Theme.modalCorner, style: .continuous).fill(Theme.modal))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.modalCorner, style: .continuous)
                    .strokeBorder(Theme.lineStrong, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.modalCorner, style: .continuous))
    }
}
