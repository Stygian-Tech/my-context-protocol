import Foundation

/// Line-oriented diff (simplified unified: ` ` / `-` / `+` prefixes). `nil` when texts are identical.
enum SkillBodyUnifiedDiff {
    /// Max lines per side before using a truncated summary instead of full DP.
    private static let maxLinesForFullDiff = 2_500

    /// Cap total emitted characters (storage and API payload safety).
    private static let maxOutputChars = 60_000

    static func format(
        oldText: String,
        newText: String,
        oldLabel: String = "prior release",
        newLabel: String = "new commit"
    ) -> String? {
        if oldText == newText { return nil }

        let oldLines = lines(from: oldText)
        let newLines = lines(from: newText)

        if oldLines.count > maxLinesForFullDiff || newLines.count > maxLinesForFullDiff {
            return truncatedSummary(oldLines: oldLines, newLines: newLines, oldLabel: oldLabel, newLabel: newLabel)
        }

        let script = editScript(oldLines, newLines)
        var body = ""
        for op in script {
            switch op {
            case let .same(line):
                append(&body, " \(line)\n")
            case let .remove(line):
                append(&body, "-\(line)\n")
            case let .insert(line):
                append(&body, "+\(line)\n")
            }
            if body.count >= maxOutputChars { break }
        }
        if body.count >= maxOutputChars {
            body += "\n… diff truncated …\n"
        }
        return "--- \(oldLabel)\n+++ \(newLabel)\n\(body)"
    }

    private static func append(_ s: inout String, _ chunk: String) {
        if s.count >= maxOutputChars { return }
        s += chunk
    }

    private static func lines(from s: String) -> [String] {
        if s.isEmpty { return [] }
        var out: [String] = []
        s.enumerateLines { line, _ in out.append(String(line)) }
        return out
    }

    private enum LineOp {
        case same(String)
        case remove(String)
        case insert(String)
    }

    /// Hunt LCS backtracking for line arrays.
    private static func editScript(_ a: [String], _ b: [String]) -> [LineOp] {
        let n = a.count
        let m = b.count
        if n == 0 {
            return b.map { .insert($0) }
        }
        if m == 0 {
            return a.map { .remove($0) }
        }

        var dp = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in 0 ..< n {
            for j in 0 ..< m {
                if a[i] == b[j] {
                    dp[i + 1][j + 1] = dp[i][j] + 1
                } else {
                    dp[i + 1][j + 1] = max(dp[i][j + 1], dp[i + 1][j])
                }
            }
        }

        var i = n
        var j = m
        var rev: [LineOp] = []
        while i > 0 || j > 0 {
            if i > 0, j > 0, a[i - 1] == b[j - 1] {
                rev.append(.same(a[i - 1]))
                i -= 1
                j -= 1
            } else if j > 0, (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                rev.append(.insert(b[j - 1]))
                j -= 1
            } else if i > 0 {
                rev.append(.remove(a[i - 1]))
                i -= 1
            } else {
                break
            }
        }
        return rev.reversed()
    }

    private static func truncatedSummary(
        oldLines: [String],
        newLines: [String],
        oldLabel: String,
        newLabel: String
    ) -> String {
        var out = "--- \(oldLabel)\n+++ \(newLabel)\n"
        out += "(Large file: \(oldLines.count) vs \(newLines.count) lines — showing first changes only)\n"
        let limit = 60
        var shown = 0
        let maxPair = max(oldLines.count, newLines.count)
        for idx in 0 ..< maxPair {
            let o = idx < oldLines.count ? oldLines[idx] : ""
            let n = idx < newLines.count ? newLines[idx] : ""
            if o != n {
                out += "-\(o)\n+\(n)\n"
                shown += 1
                if shown >= limit { break }
            }
            if out.count >= maxOutputChars { break }
        }
        if shown >= limit || out.count >= maxOutputChars {
            out += "\n… truncated …\n"
        }
        return out
    }
}
