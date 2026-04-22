import Foundation

enum PromptTemplates {
    static let debuggerSystemPrompt = """
    You are an iOS QA defect debugging specialist. You analyze reproduction steps and \
    symptoms, identify root causes, and implement the minimal code fix.

    ## Constraints
    - Keep fix scope minimal. Do not mix refactoring.
    - Follow the existing MVVM + Clean Architecture conventions in the repository.
    - If ambiguous, do NOT guess. Output `[질문 필요]` followed by a numbered question list.
    - After completing a fix, output `[수정 완료]` followed by: root cause analysis, \
      changed files, change summary, and verification points for the verifier.

    ## Available Tools
    You have access to Read, Edit, Grep, Glob, Bash (git/swift only), and the Notion MCP.

    ## Output Format
    The first line must be exactly one of:
    - `[질문 필요]`
    - `[수정 완료]`
    """

    static let verifierSystemPrompt = """
    You are an iOS QA fix verification specialist. You review the debugger's code changes \
    to confirm they resolve the defect without side effects.

    ## Criteria
    1. Does the fix correctly resolve the issue?
    2. Are there potential side effects?
    3. Are there missing edge cases?
    4. Are there iOS-specific issues (memory leaks, retain cycles)?

    ## Constraints
    - Verification only — do not modify code.
    - When requesting re-fix, provide specific problems AND concrete fix direction.
    - After 3 re-fix attempts, report the current state as-is.

    ## Output Format
    The first line must be exactly one of:
    - `[통과]`
    - `[재수정 필요]`
    """

    static func debuggerUserPrompt(ticket: Ticket, previousFeedback: String? = nil) -> String {
        var lines: [String] = []
        lines.append("[QA 결함 수정 - \(ticket.displayID)]")
        lines.append("")
        lines.append("- 티켓: \(ticket.displayID) / \(ticket.title) / 위험도 \(ticket.severity.rawValue)")
        lines.append("- 재현 절차: \(ticket.reproduceSteps.isEmpty ? "(없음)" : ticket.reproduceSteps)")
        lines.append("- 재현 결과: \(ticket.reproduceResult.isEmpty ? "(없음)" : ticket.reproduceResult)")
        lines.append("- 발생 버전: \(ticket.affectedVersion)")
        lines.append("- Notion Page ID: \(ticket.pageID)")
        if !ticket.attachments.isEmpty {
            lines.append("- 첨부 이미지:")
            for a in ticket.attachments { lines.append("    - \(a.url)") }
        }
        if !ticket.comments.isEmpty {
            lines.append("- QA 댓글:")
            for c in ticket.comments {
                lines.append("    - [\(c.createdTime) \(c.author)] \(c.text)")
            }
        }
        if let feedback = previousFeedback, !feedback.isEmpty {
            lines.append("")
            lines.append("## Verifier 피드백")
            lines.append(feedback)
        }
        lines.append("")
        lines.append("1. 재현 절차를 분석하여 관련 코드를 탐색하세요.")
        lines.append("2. 근본 원인을 파악하세요.")
        lines.append("3. 모호하면 [질문 필요]로 반환하세요.")
        lines.append("4. 확실하면 최소 범위로 수정 후 [수정 완료]로 반환하세요.")
        return lines.joined(separator: "\n")
    }

    static func verifierUserPrompt(ticket: Ticket, debuggerOutput: String, gitDiff: String) -> String {
        """
        [검증 - \(ticket.displayID)]

        - 티켓: \(ticket.displayID)
        - 제목: \(ticket.title)
        - 재현 절차: \(ticket.reproduceSteps)
        - 재현 결과: \(ticket.reproduceResult)

        ## debugger 수정 결과
        \(debuggerOutput)

        ## git diff
        \(gitDiff)

        위 수정이 이슈를 올바르게 해결하는지 검증하세요.
        """
    }

    static func commitSystemPrompt(bundle: Bundle = .main) -> String {
        let critical = loadBundled("CRITICAL", ext: "md", bundle: bundle)
        let security = loadBundled("SECURITY", ext: "md", bundle: bundle)
        let uikit = loadBundled("UIKit-CRITICAL", ext: "md", bundle: bundle)
        return """
        You are a commit reviewer + generator, reproducing the behavior of Claude Code's `/commit` command.

        1. Run `git status` and `git diff --cached` (via Bash tool) to inspect staged changes.
        2. Perform a P0 code review using the guides below. Block the commit if any CRITICAL/SECURITY issue is unresolved.
        3. Generate a commit message with an analytical prefix (Feature / Fix / Refactor / Chore / Docs / Style).
        4. Create the commit via `git commit -m "..."`.
        5. Output `[COMMIT OK] <sha> <subject>` on success, or `[COMMIT BLOCKED] <reason>` on block.

        ## CRITICAL.md
        \(critical)

        ## SECURITY.md
        \(security)

        ## UIKit-CRITICAL.md
        \(uikit)
        """
    }

    private static func loadBundled(_ resource: String, ext: String, bundle: Bundle) -> String {
        guard let url = bundle.url(forResource: resource, withExtension: ext),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return "(\(resource).\(ext) not found in bundle)"
        }
        return content
    }
}
