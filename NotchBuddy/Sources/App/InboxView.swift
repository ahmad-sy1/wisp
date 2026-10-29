import SwiftUI

// MARK: - Inbox (Gmail) — the tab that replaced the chat

struct InboxView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack(alignment: .topLeading) {
            CardBackground(wash: nil)
            VStack(alignment: .leading, spacing: 0) {
                header
                    .frame(height: 16)
                    .padding(.bottom, 8)
                if !GmailService.shared.isConfigured {
                    notConfigured
                } else if state.gmailMessages.isEmpty {
                    Text(state.gmailError ?? (state.gmailConnected ? "Inbox is empty" : "Connecting…"))
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: state.gmailError != nil ? "#FF8D97" : "#6B7079"))
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 1) {
                            ForEach(state.gmailMessages) { InboxRow(message: $0) }
                        }
                    }
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 8)
            .padding(.leading, 84)
            .padding(.trailing, 10)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle().fill(Color(hex: "#EA4335")).frame(width: 7, height: 7)
            Text("Inbox")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "#F5F6F8"))
            Text(KeychainStore.shared.get(GmailService.addressKey) ?? "Gmail")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#6B7079"))
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            if state.gmailUnread > 0 {
                Text("\(state.gmailUnread) unread")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: "#F4505E"))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color(hex: "#F4505E").opacity(0.14)))
            }
            Button(action: { GmailService.shared.open() }) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .frame(width: 18, height: 18)
                    .background(Color.white.opacity(0.07))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var notConfigured: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Connect Gmail to see your inbox here.")
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "#C5C8CD"))
            Text("Settings → Gmail: your address and an app password.")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#6B7079"))
            Button("Open settings") {
                NotificationCenter.default.post(name: .openFullSettings, object: nil)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Color(hex: "#EA4335").opacity(0.9))
            .buttonStyle(.plain)
        }
    }
}

private struct InboxRow: View {
    let message: GmailMessage
    @State private var hovering = false

    var body: some View {
        Button(action: { GmailService.shared.open(message) }) {
            HStack(spacing: 8) {
                Circle()
                    .fill(message.isRead ? Color.clear : Color(hex: "#3B9EFF"))
                    .frame(width: 6, height: 6)
                MailAvatar(message: message, size: 22)
                Text(message.senderName)
                    .font(.system(size: 12, weight: message.isRead ? .regular : .semibold))
                    .foregroundColor(Color(hex: message.isRead ? "#8E939C" : "#F5F6F8"))
                    .lineLimit(1).truncationMode(.tail)
                    .frame(width: 128, alignment: .leading)
                Text(message.subject)
                    .font(.system(size: 11.5))
                    .foregroundColor(Color(hex: message.isRead ? "#6B7079" : "#C5C8CD"))
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(message.timeLabel)
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundColor(Color(hex: "#6B7079"))
            }
            .padding(.horizontal, 6)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(hovering ? 0.06 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct MailAvatar: View {
    let message: GmailMessage
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Color(hex: message.avatarColor))
            .frame(width: size, height: size)
            .overlay(Text(message.initial)
                .font(.system(size: size * 0.48, weight: .bold))
                .foregroundColor(.black.opacity(0.75)))
    }
}

// MARK: - New-mail banner (closed notch)

enum MailBannerLayout {
    static let height: CGFloat = 50
}

/// iPhone-style notification: the notch grows down and shows who wrote and about what.
/// Clicking it opens the inbox (IslandWindowController.defaultView).
struct MailBannerView: View {
    let banner: MailBanner
    let notchHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)
            HStack(spacing: 10) {
                MailAvatar(message: banner.message, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(banner.message.senderName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                        .lineLimit(1).truncationMode(.tail)
                    Text(banner.message.subject)
                        .font(.system(size: 11.5))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 4)
                if banner.extra > 0 {
                    Text("+\(banner.extra)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: "#8E939C"))
                }
                Image(systemName: "envelope.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#EA4335"))
            }
            .padding(.horizontal, 14)
            .frame(height: MailBannerLayout.height - 6)
            Spacer(minLength: 0)
        }
    }
}
