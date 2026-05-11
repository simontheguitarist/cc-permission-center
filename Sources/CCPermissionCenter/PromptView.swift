import SwiftUI

struct PromptView: View {
    let request: PermissionRequest
    var pendingCount: Int = 0
    let onDecide: (PermissionRequest.Decision) -> Void
    let onJump: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ToolDetailView(
                toolName: request.toolName,
                input: parsedInput,
                fallback: request.toolInput,
                cwd: request.cwd
            )
            buttonRow
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 880)
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
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.orange)
            Text(request.projectLabel)
                .font(.headline)
            if let term = request.terminalDisplay {
                Text("·").foregroundStyle(.secondary)
                Text(term)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if pendingCount > 0 {
                Text("+\(pendingCount) waiting")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color.orange.opacity(0.18))
                    )
                    .foregroundStyle(.orange)
            }
        }
    }

    private var buttonRow: some View {
        HStack(spacing: 8) {
            Spacer()
            ActionButton(title: "Reject", hint: "⌃⌥R", color: .red) {
                onDecide(.deny)
            }
            ActionButton(title: "Jump", hint: "⌃⌥J", color: .gray) {
                onJump()
            }
            ActionButton(title: "Accept", hint: "⌃⌥A",
                         color: .accentColor, prominent: true) {
                onDecide(.approve)
            }
        }
    }

    private var parsedInput: [String: Any] {
        guard let data = request.toolInputJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }
}

// MARK: - Per-tool detail rendering

private struct ToolDetailView: View {
    let toolName: String
    let input: [String: Any]
    let fallback: String
    let cwd: String

    var body: some View {
        switch toolName {
        case "Bash":
            BashDetail(command: stringValue("command"),
                       description: stringValue("description"))
        case "Read":
            ReadDetail(filePath: stringValue("file_path"),
                       offset: input["offset"] as? Int,
                       limit: input["limit"] as? Int,
                       cwd: cwd)
        case "Edit":
            FileEditDetail(filePath: stringValue("file_path"),
                           oldString: stringValue("old_string"),
                           newString: stringValue("new_string"),
                           cwd: cwd)
        case "MultiEdit":
            MultiEditDetail(filePath: stringValue("file_path"),
                            edits: (input["edits"] as? [[String: Any]]) ?? [],
                            cwd: cwd)
        case "Write":
            FileWriteDetail(filePath: stringValue("file_path"),
                            content: stringValue("content"),
                            cwd: cwd)
        case "NotebookEdit":
            FileWriteDetail(filePath: stringValue("notebook_path"),
                            content: stringValue("new_source"),
                            cwd: cwd)
        case "WebFetch":
            WebFetchDetail(url: stringValue("url"),
                           prompt: stringValue("prompt"))
        default:
            GenericDetail(toolName: toolName, fallback: fallback)
        }
    }

    private func stringValue(_ key: String) -> String {
        (input[key] as? String) ?? ""
    }
}

private struct ToolHeader: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

private struct BashDetail: View {
    let command: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ToolHeader(label: description.isEmpty ? "Run command" : description)
            HStack(alignment: .top, spacing: 6) {
                Text("$")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(command)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct FileEditDetail: View {
    let filePath: String
    let oldString: String
    let newString: String
    let cwd: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ToolHeader(label: "Edit file")
            Text(prettyPath(filePath, cwd: cwd))
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            DiffView(lines: LineDiff.compute(old: oldString, new: newString))
        }
    }
}

private struct MultiEditDetail: View {
    let filePath: String
    let edits: [[String: Any]]
    let cwd: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ToolHeader(label: "Edit file (\(edits.count) change\(edits.count == 1 ? "" : "s"))")
            Text(prettyPath(filePath, cwd: cwd))
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            DiffView(lines: combinedDiff)
        }
    }

    private var combinedDiff: [DiffLine] {
        var out: [DiffLine] = []
        var id = 0
        for (idx, edit) in edits.enumerated() {
            let old = edit["old_string"] as? String ?? ""
            let new = edit["new_string"] as? String ?? ""
            let lines = LineDiff.compute(old: old, new: new)
            if idx > 0 {
                out.append(DiffLine(id: id, kind: .context, text: "      — change \(idx + 1) —"))
                id += 1
            }
            for line in lines {
                out.append(DiffLine(id: id, kind: line.kind, text: line.text))
                id += 1
            }
        }
        return out
    }
}

private struct FileWriteDetail: View {
    let filePath: String
    let content: String
    let cwd: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ToolHeader(label: "Write file")
            Text(prettyPath(filePath, cwd: cwd))
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            // Show new file as all-added lines.
            DiffView(lines: LineDiff.compute(old: "", new: content))
        }
    }
}

private struct ReadDetail: View {
    let filePath: String
    let offset: Int?
    let limit: Int?
    let cwd: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ToolHeader(label: "Read file")
            Text(prettyPath(filePath, cwd: cwd))
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            if offset != nil || limit != nil {
                Text("offset \(offset ?? 0) · limit \(limit.map(String.init) ?? "all")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct WebFetchDetail: View {
    let url: String
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ToolHeader(label: "Fetch URL")
            Text(url)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
            if !prompt.isEmpty {
                Text(prompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

private struct GenericDetail: View {
    let toolName: String
    let fallback: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ToolHeader(label: toolName)
            ScrollView {
                Text(fallback)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 200)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.45))
            )
        }
    }
}

private func prettyPath(_ path: String, cwd: String) -> String {
    guard !path.isEmpty else { return "(no path)" }
    if !cwd.isEmpty, path.hasPrefix(cwd + "/") {
        return String(path.dropFirst(cwd.count + 1))
    }
    if let home = ProcessInfo.processInfo.environment["HOME"], path.hasPrefix(home) {
        return "~" + String(path.dropFirst(home.count))
    }
    return path
}

// MARK: - Buttons

private struct ActionButton: View {
    let title: String
    let hint: String
    let color: Color
    var prominent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .fontWeight(prominent ? .semibold : .medium)
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
                .fill(prominent ? color : Color.secondary.opacity(0.12))
        )
        .foregroundStyle(prominent ? .white : .primary)
    }
}
