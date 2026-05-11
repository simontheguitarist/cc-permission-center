import SwiftUI

enum DiffKind {
    case context
    case removed
    case added
}

struct DiffLine: Identifiable {
    let id: Int
    let kind: DiffKind
    let text: String
}

enum LineDiff {
    /// Line-level unified diff using LCS. Cheap enough (O(n*m)) for typical
    /// edit-tool payloads; we cap the longer side at 400 lines.
    static func compute(old: String, new: String) -> [DiffLine] {
        let oldRaw = old.components(separatedBy: "\n")
        let newRaw = new.components(separatedBy: "\n")
        let maxLines = 400
        let oldLines = oldRaw.count > maxLines ? Array(oldRaw.prefix(maxLines)) : oldRaw
        let newLines = newRaw.count > maxLines ? Array(newRaw.prefix(maxLines)) : newRaw

        let n = oldLines.count
        let m = newLines.count
        if n == 0 {
            return newLines.enumerated().map { DiffLine(id: $0.offset, kind: .added, text: $0.element) }
        }
        if m == 0 {
            return oldLines.enumerated().map { DiffLine(id: $0.offset, kind: .removed, text: $0.element) }
        }

        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 1...n {
            for j in 1...m {
                if oldLines[i - 1] == newLines[j - 1] {
                    lcs[i][j] = lcs[i - 1][j - 1] + 1
                } else {
                    lcs[i][j] = max(lcs[i - 1][j], lcs[i][j - 1])
                }
            }
        }

        var result: [DiffLine] = []
        var i = n, j = m
        var nextId = 0
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && oldLines[i - 1] == newLines[j - 1] {
                result.append(DiffLine(id: nextId, kind: .context, text: oldLines[i - 1]))
                i -= 1; j -= 1
            } else if j > 0 && (i == 0 || lcs[i][j - 1] >= lcs[i - 1][j]) {
                result.append(DiffLine(id: nextId, kind: .added, text: newLines[j - 1]))
                j -= 1
            } else {
                result.append(DiffLine(id: nextId, kind: .removed, text: oldLines[i - 1]))
                i -= 1
            }
            nextId += 1
        }
        return result.reversed()
    }
}

struct DiffView: View {
    let lines: [DiffLine]
    var maxVisibleLines: Int = 18
    private let rowHeight: CGFloat = 18
    private let verticalPadding: CGFloat = 8

    var body: some View {
        let trimmed = trimContextRuns(lines)
        let visible = min(trimmed.count, maxVisibleLines)
        let height = CGFloat(max(visible, 1)) * rowHeight + verticalPadding

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(trimmed) { line in
                    DiffRow(line: line, fixedHeight: rowHeight)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    /// Collapse long stretches of unchanged context into a single
    /// `... N unchanged lines ...` marker, keeping a few lines around each
    /// change so the diff stays legible.
    private func trimContextRuns(_ lines: [DiffLine]) -> [DiffLine] {
        let contextRadius = 2
        var keep = Set<Int>()
        for (idx, line) in lines.enumerated() where line.kind != .context {
            let lo = max(0, idx - contextRadius)
            let hi = min(lines.count - 1, idx + contextRadius)
            for k in lo...hi { keep.insert(k) }
        }
        // If no changes at all, just show everything (unusual).
        if keep.isEmpty { return lines }
        var out: [DiffLine] = []
        var idx = 0
        var nextId = 1_000_000
        while idx < lines.count {
            if keep.contains(idx) {
                out.append(lines[idx])
                idx += 1
            } else {
                var skipped = 0
                while idx < lines.count, !keep.contains(idx) {
                    skipped += 1
                    idx += 1
                }
                if skipped > 0 {
                    out.append(DiffLine(
                        id: nextId,
                        kind: .context,
                        text: "      … \(skipped) unchanged line\(skipped == 1 ? "" : "s") …"
                    ))
                    nextId += 1
                }
            }
        }
        return out
    }
}

private struct DiffRow: View {
    let line: DiffLine
    let fixedHeight: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            Text(prefix)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 12, alignment: .center)
                .foregroundStyle(prefixColor)
            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 8)
        .frame(height: fixedHeight)
        .background(rowBackground)
    }

    private var prefix: String {
        switch line.kind {
        case .added: return "+"
        case .removed: return "-"
        case .context: return " "
        }
    }

    private var prefixColor: Color {
        switch line.kind {
        case .added: return .green
        case .removed: return .red
        case .context: return .secondary
        }
    }

    private var textColor: Color {
        switch line.kind {
        case .added: return .green
        case .removed: return .red
        case .context: return .secondary
        }
    }

    private var rowBackground: some View {
        Group {
            switch line.kind {
            case .added: Color.green.opacity(0.10)
            case .removed: Color.red.opacity(0.10)
            case .context: Color.clear
            }
        }
    }
}
