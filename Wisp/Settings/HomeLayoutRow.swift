import SwiftUI

/// Settings → Notch: what Home shows, as a small plan with a way to change it (board 10.1.3).
struct HomeLayoutRow: View {
    @ObservedObject var prefs: Preferences
    @State private var choosing = false

    private var names: String {
        (prefs.homeLayout ?? .standard).items.map(\.shortTitle).joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "house").font(.system(size: 14)).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("Home").font(.system(size: 13.5))
                Text(
                    prefs.homeLayout == nil
                        ? String(localized: "Shows the defaults")
                        : String(localized: "\(prefs.homeLayout?.items.count ?? 0) things: \(names)")
                )
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            }
            Spacer(minLength: 10)
            if let layout = prefs.homeLayout {
                HomeLayoutPlan(layout: layout, showsNames: true)
                    .frame(width: 96, height: 44)
                Button("Edit") { choosing = true }.buttonStyle(.settings)
                    .popover(isPresented: $choosing, arrowEdge: .bottom) { chooser }
            } else {
                Button {
                    choosing = true
                } label: {
                    Label("Choose what Home shows", systemImage: "plus")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 12)
                        .frame(height: Theme.buttonHeight)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                                .strokeBorder(Theme.textFaint, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $choosing, arrowEdge: .bottom) { chooser }
            }
        }
        .padding(.horizontal, 15)
        .frame(height: 62)
    }

    private var chooser: some View {
        HomeLayoutChooser(layout: prefs.homeLayout ?? .standard) { chosen in
            if let chosen { prefs.homeLayout = chosen }
            choosing = false
        }
    }
}

/// The places of a layout, drawn small.
struct HomeLayoutPlan: View {
    let layout: HomeLayout
    var showsNames = false
    var fill = Theme.control

    private static let gap: CGFloat = 3

    var body: some View {
        let items = layout.items
        Group {
            switch items.count {
            case 1:
                place(items[0])
            case 2:
                HStack(spacing: Self.gap) {
                    place(items[0])
                    place(items[1])
                }
            case 3:
                HStack(spacing: Self.gap) {
                    place(items[0])
                    VStack(spacing: Self.gap) {
                        place(items[1])
                        place(items[2])
                    }
                }
            default:
                VStack(spacing: Self.gap) {
                    HStack(spacing: Self.gap) {
                        place(items[0])
                        place(items[1])
                    }
                    HStack(spacing: Self.gap) {
                        place(items[2])
                        place(items[3])
                    }
                }
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: Theme.smallCorner + 1, style: .continuous).fill(Color.black))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.smallCorner + 1, style: .continuous)
                .strokeBorder(Theme.lineStrong, lineWidth: 1)
        )
    }

    private func place(_ item: HomeItem) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(fill)
            .overlay {
                if showsNames {
                    Text(item.shortTitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.textLabel)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
    }
}

/// How many things Home shows, then what goes where.
private struct HomeLayoutChooser: View {
    @State var layout: HomeLayout
    /// `nil` when cancelled.
    let finish: (HomeLayout?) -> Void

    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How many things does Home show?").font(.system(size: 13, weight: .semibold))
            HStack(spacing: 8) {
                ForEach(HomeLayout.counts, id: \.self) { count in
                    countButton(count)
                }
            }
            Text("What goes where").font(.system(size: 13, weight: .semibold))
            VStack(spacing: 8) {
                let names = HomeLayout.placeNames(count: layout.items.count)
                ForEach(Array(layout.items.indices), id: \.self) { index in
                    placeRow(index, name: names[index])
                }
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { finish(nil) }.buttonStyle(SecondaryButtonStyle(height: Theme.windowButtonHeight))
                Button("Done") { finish(layout) }.buttonStyle(AccentButtonStyle(height: Theme.windowButtonHeight))
            }
        }
        .padding(14)
        .frame(width: 330)
        .environment(\.colorScheme, .dark)
    }

    private func countButton(_ count: Int) -> some View {
        let selected = layout.items.count == count
        return Button {
            layout = layout.withCount(count)
        } label: {
            VStack(spacing: 6) {
                HomeLayoutPlan(
                    layout: HomeLayout(items: Array(HomeItem.allCases.prefix(count))),
                    fill: selected ? prefs.accent.color : Theme.trackOff
                )
                .frame(width: 42, height: 26)
                Text(verbatim: "\(count)").font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Theme.buttonCorner + 2, style: .continuous)
                    .fill(selected ? prefs.accent.color.opacity(0.14) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.buttonCorner + 2, style: .continuous)
                    .strokeBorder(selected ? prefs.accent.color : Theme.lineStrong, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "\(count) things"))
    }

    private func placeRow(_ index: Int, name: String) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: "\(index + 1)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(prefs.accent.color))
            Text(name)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 78, alignment: .leading)
            Picker(
                name,
                selection: Binding(
                    get: { layout.items[index] },
                    set: { layout = layout.replacing(at: index, with: $0) })
            ) {
                ForEach(HomeItem.allCases, id: \.self) { item in
                    Text(item.title).tag(item)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity)
        }
    }
}
