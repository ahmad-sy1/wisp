import SwiftUI

/// New mail peeking out of the notch (board 8): who, what, and three keys.
struct MailPeek: View {
    let mail: MailMessage
    @ObservedObject var model: NotchModel

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Avatar(initial: mail.initial, seed: mail.senderAddress, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(mail.senderName)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("now")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Text(mail.subject)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textPrimary.opacity(0.85))
                        .lineLimit(1)
                }
            }
            HStack(spacing: 6) {
                Button("Open") {
                    MailStore.shared.open(mail)
                    model.onCollapse()
                }
                .buttonStyle(PeekButtonStyle(primary: true))
                Button("Delete") {
                    MailStore.shared.trash(mail)
                    model.onCollapse()
                }
                .buttonStyle(PeekButtonStyle(primary: false))
                .help("Moves it to the Gmail trash")
                Button("Later") { model.onCollapse() }
                    .buttonStyle(PeekButtonStyle(primary: false))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 38)
        .padding(.bottom, 14)
        .foregroundStyle(Theme.textPrimary)
    }
}

/// Wide 30 pt keys: white for the main one, grey for the others.
private struct PeekButtonStyle: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(primary ? Color.black : Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                .fill(primary ? Color.white : configuration.isPressed ? Theme.activeTab : Theme.control))
            .opacity(configuration.isPressed && primary ? 0.8 : 1)
            .contentShape(Rectangle())
    }
}

/// Unread mail on the closed notch (board 8): an envelope left of the camera, the
/// count right of it.
struct MailWings: View {
    let count: Int
    let height: CGFloat
    let wing: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "envelope")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: wing)
            Spacer(minLength: 0)
            CountBadge(count: count)
                .frame(width: wing)
        }
        .padding(.horizontal, 3)
        .frame(height: height)
    }
}
