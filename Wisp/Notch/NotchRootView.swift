import SwiftUI

/// Root of the notch window: a black shape that grows from the notch into the panel.
struct NotchRootView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var prefs: Preferences

    var body: some View {
        let size = model.shapeSize
        let shape = NotchShape(bottomRadius: model.bottomRadius)

        ZStack(alignment: .top) {
            shape.fill(Theme.panel)

            if model.isExpanded {
                ExpandedPanel(model: model)
                    .frame(width: Theme.panelWidth, height: Theme.panelHeight)
                    .transition(.opacity.animation(.easeOut(duration: 0.18).delay(0.08)))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture {
            if !model.isExpanded { model.onTapCollapsed() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .tint(prefs.accent.color)
        .preferredColorScheme(.dark)
    }
}

/// Square top edge (flush with the screen), rounded bottom corners.
struct NotchShape: Shape {
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(bottomRadius, rect.width / 2, rect.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Tab bar on top, one fixed-height content area below. Tabs never grow the panel:
/// lists scroll inside the content area instead.
struct ExpandedPanel: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        VStack(spacing: Theme.tabBarGap) {
            TabBar(model: model)
                .frame(height: Theme.tabBarHeight)

            TabContent(tab: model.tab, openSettings: model.onOpenSettings)
                .frame(height: Theme.contentHeight)
                .id(model.tab)
                .transition(.opacity)
        }
        .padding(.top, Theme.panelTopInset)
        .padding(.horizontal, Theme.panelInset)
        .padding(.bottom, Theme.panelInset)
        .foregroundStyle(Theme.textPrimary)
    }
}
