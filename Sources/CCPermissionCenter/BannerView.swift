import SwiftUI

enum BannerKind {
    case idle
    case finished
    case info

    var iconName: String {
        switch self {
        case .idle:     return "hourglass.circle.fill"
        case .finished: return "checkmark.circle.fill"
        case .info:     return "bell.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .idle:     return .blue
        case .finished: return .green
        case .info:     return .gray
        }
    }
}

struct BannerView: View {
    let title: String
    let subtitle: String?
    let kind: BannerKind
    let onJump: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kind.iconName)
                .foregroundStyle(kind.tint)
                .font(.system(size: 24, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let onJump {
                Button("Jump", action: onJump)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 360)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 10, y: 2)
        )
        .onTapGesture { onDismiss() }
    }
}
