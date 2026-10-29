import SwiftUI

extension View {
    /// Liquid Glass on macOS 26 (it reacts to hover and press by itself); on older
    /// systems a frosted material with a thin light edge.
    ///
    /// For small controls only: the panel itself stays pure black.
    @ViewBuilder
    func glass<S: InsettableShape>(in shape: S, tint: Color? = nil) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            glassEffect(Glass.regular.tint(tint).interactive(), in: shape)
        } else {
            frostedGlass(in: shape, tint: tint)
        }
        #else
        frostedGlass(in: shape, tint: tint)
        #endif
    }

    private func frostedGlass<S: InsettableShape>(in shape: S, tint: Color?) -> some View {
        background(shape.fill(.ultraThinMaterial))
            .background(shape.fill(tint ?? .clear))
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.75)
            )
    }
}
