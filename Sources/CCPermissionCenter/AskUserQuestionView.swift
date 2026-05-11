import SwiftUI

struct AUQOption: Identifiable {
    let id = UUID()
    let index: Int        // 1-based numeric index Claude uses
    let label: String
    let description: String
}

struct AUQQuestion {
    let header: String
    let multiSelect: Bool
    let options: [AUQOption]
}

struct AskUserQuestionView: View {
    let projectLabel: String
    let terminalDisplay: String?
    let question: AUQQuestion
    let onSelect: (AUQOption) -> Void
    let onJump: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            VStack(alignment: .leading, spacing: 8) {
                ForEach(question.options) { option in
                    OptionRow(option: option) { onSelect(option) }
                }
            }
            HStack(spacing: 8) {
                Spacer()
                bottomButton(title: "Dismiss", hint: "⌃⌥R", prominent: false, action: onDismiss)
                bottomButton(title: "Jump", hint: "⌃⌥J", prominent: false, action: onJump)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 600)
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
            VStack(alignment: .leading, spacing: 2) {
                Text(question.header.isEmpty ? "Claude is asking" : question.header)
                    .font(.headline)
                HStack(spacing: 6) {
                    Text(projectLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let term = terminalDisplay {
                        Text("·").foregroundStyle(.secondary)
                        Text(term)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func bottomButton(title: String, hint: String,
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

private struct OptionRow: View {
    let option: AUQOption
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(option.index)")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.bold)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentColor)
                    )
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    if !option.description.isEmpty {
                        Text(option.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .opacity(hovering ? 1.0 : 0.4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(hovering
                      ? Color.accentColor.opacity(0.12)
                      : Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(hovering ? Color.accentColor : Color.secondary.opacity(0.25),
                        lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { hovering = $0 }
    }
}
