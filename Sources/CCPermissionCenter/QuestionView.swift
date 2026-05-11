import SwiftUI

struct QuestionView: View {
    let projectLabel: String
    let terminalDisplay: String?
    let question: String
    let onJump: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ScrollView {
                Text(question)
                    .font(.system(.body, design: .default))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
            }
            .frame(maxHeight: 220)
            HStack(spacing: 8) {
                Spacer()
                actionButton(title: "Dismiss", hint: "⌃⌥R",
                             prominent: false, action: onDismiss)
                actionButton(title: "Jump", hint: "⌃⌥J",
                             prominent: true, action: onJump)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 820)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 16, y: 4)
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.blue)
            Text(projectLabel)
                .font(.headline)
            if let term = terminalDisplay {
                Text("·").foregroundStyle(.secondary)
                Text(term)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Claude is asking")
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.blue.opacity(0.18)))
                .foregroundStyle(.blue)
        }
    }

    @ViewBuilder
    private func actionButton(title: String, hint: String,
                              prominent: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).fontWeight(prominent ? .semibold : .medium)
                Text(hint)
                    .font(.system(.caption2, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(prominent ? 0.18 : 0.0))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.secondary.opacity(0.4),
                                            lineWidth: prominent ? 0 : 1)
                            )
                    )
                    .foregroundStyle(prominent ? .white.opacity(0.85) : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(prominent ? Color.accentColor : Color.secondary.opacity(0.12))
        )
        .foregroundStyle(prominent ? .white : .primary)
    }
}
