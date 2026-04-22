# Implementation Log

> QAFixMac 구현 세션 기록. 각 Step별로 작성한 파일, 빌드 검증, 남긴 결정.

작업 시작일: 2026-04-17
작업 완료일: 2026-04-22 (Phase 1 완료 2026-04-21, Phase 2-A/B/C 추가 2026-04-22)
Claude 모델: Opus 4.7 (1M context)
워킹 디렉터리: `~/Desktop/QAFixMac/`

---

## Step 0-1 · 프로젝트 스캐폴드

**목표**: XcodeGen 기반 macOS 앱 프로젝트 뼈대 생성.

**작성한 파일**:
- `project.yml` — 3개 타겟 정의 (`QAFixMac` / `QAFixMacTests` / `CLISpike`).
  `ENABLE_APP_SANDBOX: YES`, `ENABLE_HARDENED_RUNTIME: YES` 기본값.
- `QAFixMac/Info.plist` — XcodeGen이 일부 키를 자동 주입 (xcodegen이 직접
  수정함).
- `QAFixMac/Resources/QAFixMac.entitlements` —
  - `com.apple.security.app-sandbox: true`
  - `com.apple.security.files.user-selected.read-write: true`
  - `com.apple.security.files.bookmarks.app-scope: true`
  - `com.apple.security.network.client: true`
  - `com.apple.security.inherit: false`
  (원래 합의 계획의 `process.exec`는 `files.user-selected.rw`로 대체.
  App Sandbox 상태로 subprocess + bookmark 조합 검증 필요.)
- `QAFixMac/Resources/Assets.xcassets/{Contents,AppIcon,AccentColor}.json`
- `QAFixMac/Resources/CRITICAL.md` / `SECURITY.md` / `UIKit-CRITICAL.md` —
  internal-ios-repo의 ios-code-review-guide에서 복사.
- `README.md`, `.gitignore`
- 최소 스텁: `QAFixMacApp.swift`, `ContentView.swift`, `SettingsView.swift`(placeholder),
  `CLISpike/main.swift`(placeholder), `QAFixMacTests/PlaceholderTests.swift`

**빌드 검증**: `xcodebuild -scheme QAFixMac build` → `** BUILD SUCCEEDED **`.

**결정**: xcodeproj는 git ignore. project.yml만 보관하고 `xcodegen generate`
재실행으로 복원.

---

## Step 1 · Settings / Keychain / Bookmark / MCP Config

**목표**: 설정 화면과 보안 저장소. Claude Code CLI 감지. MCP 설정 자동 생성.

**작성한 파일**:
- `Models/Settings.swift` — `AppSettings` struct, `AnthropicModel` enum
  (sonnet4, sonnet46, opus47, haiku45), `SettingsStoreKey` 상수.
- `Utilities/KeychainManager.swift` — `kSecAttrAccessibleAfterFirstUnlock`
  기반 save/load/delete. `KeychainKey.notionToken` 만 사용 중.
- `Utilities/BookmarkManager.swift` — `NSOpenPanel`로 디렉터리 선택 →
  `URL.bookmarkData(.withSecurityScope)`. resolve 시 `isStale` 무시
  (향후 stale 처리 필요).
- `Services/MCP/MCPConfigManager.swift` — `~/Library/Application Support/QAFixMac/mcp.json`
  생성. Notion MCP만 포함 (`npx -y @notionhq/notion-mcp-server`, 토큰은
  `OPENAPI_MCP_HEADERS` 환경변수로 주입).
- `Services/Claude/ClaudeCodeVersionProbe.swift` — 후보 경로 3종(homebrew /
  /usr/local / nvm) + `which claude` fallback. `claude --version` 출력에서
  `N.N.N` 파싱. `isSupported`는 major>=2 && minor>=1.
- `Views/Settings/SettingsView.swift` (전면 개편) —
  - `@Observable final class SettingsViewModel` (macOS 14+ Observation)
  - Notion token SecureField, database_id 검증 버튼, 레포 NSOpenPanel,
    CLI 버전 상태, 모델 Picker, Budget TextField, Save 버튼.
  - Save 시 Keychain + UserDefaults + `MCPConfigManager.writeNotionConfig`
    호출.

**빌드 검증**: `** BUILD SUCCEEDED **`.

**결정**:
- `SettingsViewModel`은 `@MainActor @Observable`. 앱 전역 표준.
- `database_id`는 UserDefaults (민감도 낮음), Notion token만 Keychain.
- MCP config는 사용자에게 보여주는 경로 (`mcpConfigPath`)만 노출, 편집 UI
  없음 → Phase 2에서 개방 여부 판단.

---

## Step 2 · Notion 연동 + 티켓 리스트/상세

**목표**: Notion REST API로 Opened iOS 티켓 조회, 위험도 정렬, 버전 필터,
댓글/본문 이미지 hydrate, 429 rate limit 대응.

**작성한 파일**:
- `Utilities/RetryPolicy.swift` —
  - `maxAttempts: 5`, 시퀀스 `1→2→4→8→16s`, `maxDelay: 16s`, `jitter: 0.2`.
  - `shouldRetry(status:)` → 408/425/429/500/502/503/504/529.
  - `delay(forAttempt:retryAfterSeconds:)` — Retry-After 헤더가 있으면
    계산값보다 큰 값을 선택.
  - `actor ConcurrencyLimiter(limit: Int)` — 동시 요청 제한 (Notion 댓글
    병렬 조회에 limit=3).
- `Services/Notion/NotionModels.swift` — `NotionQueryResponse`,
  `NotionPage`, `NotionProperty` (enum + 커스텀 Decodable:
  title / rich_text / select / multi_select / people / unique_id / files),
  `NotionCommentsResponse`, `NotionBlocksResponse`.
- `Services/Notion/NotionService.swift` — protocol + `NotionError`.
- `Services/Notion/NotionAPIClient.swift` —
  - `fetchOpenedTickets(databaseID:version:)` — POST
    `/databases/{id}/query` with filter.and = [상태=Opened, 검증 프로젝트
    태그 contains `iOS {VERSION}`]. 결과를 `Ticket.build`로 변환 후
    Severity 오름차순 정렬.
  - `fetchComments`, `fetchImageBlocks`, `patchStatus`.
  - `perform` 메서드에 `RetryPolicy` 적용 + `ConcurrencyLimiter` acquire/release.
- `Models/Ticket.swift` — `Ticket`, `Severity`, `TicketAttachment`,
  `TicketComment`, `NotionPropertyHelper` (enum extract helper).
- `ViewModels/TicketListViewModel.swift` — refresh, version filter, 댓글 병렬
  hydrate (TaskGroup).
- `Views/Tickets/TicketRowView.swift` — Row + `SeverityBadge`.
- `Views/Tickets/TicketDetailView.swift` — ScrollView (header, 재현절차/결과,
  첨부 이미지 AsyncImage, 댓글 타임라인).
- `Views/Tickets/TicketListView.swift` — NavigationSplitView 사이드바에
  version Picker + refresh 버튼 + 티켓 List.

**빌드 검증**: `** BUILD SUCCEEDED **`.

**결정**:
- Severity 정렬 순서: Critical < Major < Minor < Trivial < unknown (enum
  rank map 기반).
- 댓글 hydrate는 `withTaskGroup(of: (String, [TicketComment]).self)`로 병렬,
  limiter=3이 전역 concurrency를 제한.
- TicketListView detail은 Step 5에서 `FixSessionView`로 교체됨.

---

## Step 2.5 · CLI Prototype Spike

**목표**: `--verbose --bare --output-format stream-json` 조합이 정말 동작하는지
로컬에서 검증할 수 있는 소형 실행 파일.

**작성한 파일**: `CLISpike/main.swift` — 독립 실행 가능한 Swift 툴.
- claude 바이너리 후보 경로 + `/usr/bin/which` fallback으로 탐색.
- Process spawn, stdin에 prompt, stdout에서 NDJSON 라인 읽기,
  JSONSerialization으로 파싱해 type별 간단 출력.
- stderr는 별도로 dump.
- 마지막에 `[spike] exit={code} events={N} unknown={N} sawResult={bool}`
  리포트.

**빌드 검증**: `xcodebuild -scheme CLISpike build` → `** BUILD SUCCEEDED **`.

**수동 검증 (READMe에 가이드 추가)**: 비용 발생 때문에 live smoke test는
사용자 판단에 맡김.

---

## Step 3 · ClaudeCodeCLIClient + StreamJSONParser

**목표**: 앱 내부에서 Claude Code CLI 세션을 실행·파싱·취소할 수 있는 계층.

**작성한 파일**:
- `Models/ClaudeStreamEvent.swift` — enum with cases
  `.system / .assistantText / .toolUse / .toolResult / .result / .rateLimit /
  .error / .unknown(rawJSON: String)`. `ClaudeUsage` struct 포함 — `totalCostUSD`,
  `durationMS`, tokens.
- `Services/Claude/ClaudeCodeService.swift` —
  - `protocol ClaudeCodeService` (runAgent / stderrStream / cancelCurrentSession).
  - `struct ClaudeInvocation` with `command(binary:)` → **모든 subprocess
    호출 템플릿은 여기서 한 번 정의**. v3 합의 플래그 (`--verbose --bare`
    `--output-format stream-json` `--include-partial-messages`
    `--permission-mode bypassPermissions` `--model` `--add-dir`
    `--system-prompt` `--mcp-config` `--max-budget-usd`) 전부 포함.
- `Services/Claude/StreamJSONParser.swift` —
  - `parseLine(_:)` 정적 메서드. type 별 분기:
    - `assistant`: content 블록에서 text/tool_use 추출.
    - `user`: content 블록에서 tool_result 추출.
    - `system`: `.system(subtype:, raw:)`.
    - `rate_limit_event`: `.rateLimit(raw:)`.
    - `result`: `total_cost_usd` + usage 토큰 + `duration_ms` 파싱.
      subtype `error_during_execution` / `error_max_turns` 는 `.error`로 매핑.
    - `error`: message 추출.
    - 그 외: `.unknown(rawJSON:)`.
  - JSON 파싱 실패 시에도 `.unknown` 으로 안전하게 fallthrough.
  - `class NDJSONLineBuffer` — 바이너리 스트림에서 `\n`으로 라인 분리.
- `Services/Claude/ClaudeCodeCLIClient.swift` —
  - `AsyncThrowingStream<ClaudeStreamEvent, Error>` 반환.
  - stdout/stderr Pipe 분리, stdout은 `NDJSONLineBuffer` → `StreamJSONParser`
    → stream yield. stderr는 별도 `AsyncStream<String>`.
  - `cancelCurrentSession` — SIGINT → 2s → SIGTERM → 3s → SIGKILL 체인
    (DispatchQueue asyncAfter).
  - `continuation.onTermination` 에서 cancel 연계.
  - `terminationHandler` 에서 마지막 버퍼 flush.

**빌드 검증**: `** BUILD SUCCEEDED **`.

**결정**:
- tool_use 입력은 JSON 직렬화 후 최대 200자 prefix만 로그에 남김 (컨텍스트
  오염 방지).
- `.assistantText` 이벤트는 content 배열의 text 블록을 하나로 합쳐 반환.
  partial_message 스트리밍은 현재 그대로 yield.

---

## Step 4 · AgentOrchestrator + AgentLogView + QuestionView

**목표**: debugger ↔ verifier 루프를 앱 내부에서 구동. 질문/재수정 플로우 UI.

**작성한 파일**:
- `Services/Agent/PromptTemplates.swift` —
  - `debuggerSystemPrompt`, `verifierSystemPrompt` (한국어 키워드 규칙
    `[질문 필요]/[수정 완료]/[통과]/[재수정 필요]` 유지).
  - `debuggerUserPrompt(ticket:previousFeedback:)` — 티켓 전체 필드 +
    이전 verifier 피드백 포함.
  - `verifierUserPrompt(ticket:debuggerOutput:gitDiff:)`.
  - `commitSystemPrompt(bundle:)` — 앱 번들에서 CRITICAL.md / SECURITY.md
    / UIKit-CRITICAL.md 를 읽어 system prompt에 주입. 원본 `/commit` 커맨드
    동치 동작 지시.
- `Services/Git/GitService.swift` — `GitCLIClient`:
  `run(_:at:)` 공통 래퍼 + `diff`, `diffNameOnly`, `status`, `commit`,
  `checkoutAll`, `stashPush/List/Pop`, `headSHA`.
- `Services/Agent/AgentOrchestrator.swift` —
  - `@Observable final class AgentOrchestrator`.
  - phase: `.idle / .debuggerRunning / .verifierRunning / .waitingForQuestion
    / .finished / .failed`.
  - `run(ticket:workingDirectory:)` → `runDebugger` → 키워드 파싱:
    `.question` → phase=.waitingForQuestion;
    `.fixed` → `runVerifier`;
    `.inconclusive` → .failed.
  - `runVerifier`: `GitCLIClient.diff` 주입 → `.pass` / `.refix(최대 3회)` /
    `.inconclusive`.
  - `consume(invocation:source:)` — `AsyncThrowingStream` 이벤트 루프,
    `accumulated` text, tool_use/result/result/error/rateLimit 로그.
  - `log: [AgentLogEntry]`, cumulative cost/tokens 추적.
- `Views/Agent/AgentLogView.swift` — LazyVStack + source별 색상 + auto-scroll
  on log.count change.
- `Views/Agent/QuestionView.swift` — ScrollView(question) + TextEditor(answer)
  + Submit/Cancel.

**빌드 검증**: `** BUILD SUCCEEDED **`.

**결정**:
- 재수정 루프 한도는 `maxRefix: Int = 3`. 초과 시 phase=.finished 로
  전환하고 로그에만 경고.
- `parseDebugger`/`parseVerifier`는 첫 줄만 본다. 원본 qa-fix.md의 "첫 줄에
  키워드" 규칙을 그대로 준수.

---

## Step 5 · DiffView + ActionBar + Commit + git stash

**목표**: 수정 결과 diff 미리보기, Commit/재수정/취소 액션, `/commit` 동치
호출, Notion 상태 PATCH, 워킹트리 안전망.

**작성한 파일**:
- `Utilities/DiffParser.swift` — unified diff → `[DiffFile]` (hunks → lines
  with kind: addition/deletion/context/meta).
- `Views/Diff/DiffFileView.swift` — 파일 단위 라인 표시, addition/deletion
  배경색.
- `Views/Diff/DiffView.swift` — NavigationSplitView(파일 리스트 + 선택된
  파일 내용).
- `Views/Action/ActionBarView.swift` — Commit/Re-fix/Discard 버튼 + 진행
  인디케이터.
- `ViewModels/DiffViewModel.swift` — `refresh(repo:)` → `GitCLIClient.diff`
  → `DiffParser.parse`.
- `ViewModels/AgentViewModel.swift` —
  - `stage: FixSessionStage` (ready / stashCreated / agentRunning /
    awaitingUser / readyToCommit / committing / completed / failed).
  - `start(ticket:repo:)` → stash push → `orchestrator.run` → 완료 시 phase
    에 따라 stage 전환.
  - `submitAnswer(ticket:repo:)` — QuestionView 응답을 debugger에게 재투입.
  - `cancel(ticket:repo:)` — `orchestrator.cancel` + `git checkout --` +
    `git stash pop`.
  - `requestRefix(ticket:repo:feedback:)` — 유저 피드백을 debugger에 재주입.
  - `commit(ticket:repo:)` — `git add -A` → ClaudeCodeService로
    `PromptTemplates.commitSystemPrompt()` 주입된 invocation 실행 →
    `git rev-parse --short HEAD` → `NotionAPIClient.patchStatus(
    pageID:, "In progress")`.
- `Views/FixSessionView.swift` — 티켓 선택 시 우측 detail. 상단 헤더 +
  HSplitView(AgentLog / Diff) + QuestionView 혹은 ActionBarView + 에러/상태
  footer.
- `Views/Tickets/TicketListView.swift` (교체) — detail을 `FixSessionView`로
  교체. `resolvedRepo()`가 Settings bookmark를 풀어서 URL 반환.

**빌드 검증**: `** BUILD SUCCEEDED **`.

**결정**:
- stash 메시지는 `QAFixMac-{displayID}-{unix timestamp}`. 크래시 복구 때
  이 prefix로 찾도록 설계 (현재 복구 UI 미구현).
- Commit flow에서 Notion PATCH 실패해도 commit은 유지. 에러는 `errorMessage`
  에 설정.
- `git add -A` 사용 — 원본 /commit은 staged/unstaged를 세분화하지만 Phase 1
  에서는 전체 stage. Phase 2 TODO.

---

## Step 6 · OSLog + SessionStore + CostDashboard + 테스트

**목표**: 로깅, 세션 기록, 비용 대시보드, 골든/단위 테스트.

**작성한 파일**:
- `Utilities/AppLogger.swift` — `os.Logger` wrapper, 5 카테고리
  (subprocess / notion / git / agent / ui). debug/info/warning/error.
- `Models/SessionRecord.swift` — `SessionRecord` (id, ticket 메타, startedAt,
  endedAt, status, stashMessage, commitSHA, changedFiles, cost),
  `enum SessionStatus` (`inProgress/completed/crashed/cancelled`),
  `CostRecord`, `class SessionStore` (
  `~/Library/Application Support/QAFixMac/sessions/*.json` 저장/조회).
  `crashedSessions()`는 `status == .inProgress`로 필터.
- `ViewModels/CostViewModel.swift` — SessionStore.list() 합산.
- `Views/Cost/CostDashboardView.swift` — Form + LabeledContent.
- `ContentView.swift` 수정 — cost 탭을 `CostDashboardView`로 교체.
- 테스트 4종:
  - `StreamJSONParserTests`: assistant text / tool_use / result(total_cost_usd)
    / unknown / malformed JSON → 5 cases pass.
  - `DiffParserTests`: single / multiple files → 2 cases pass.
  - `RetryPolicyTests`: shouldRetry / Retry-After / exponential growth →
    3 cases pass.
  - `MCPConfigManagerTests`: 생성된 mcp.json 스키마 검증 → 1 case pass.
- `project.yml` 수정: `QAFixMacTests`에 `GENERATE_INFOPLIST_FILE: YES` 추가
  (초기 실행 시 Info.plist 누락 에러 때문).

**테스트 검증**: `xcodebuild clean test` → 11 tests / 4 suites / `** TEST SUCCEEDED **`.

**미완 연결**:
- `AgentViewModel` 은 `SessionRecord` 를 아직 기록하지 않음. CostDashboard
  는 빈 리스트만 본다. (Phase 2 TODO, CLAUDE.md §8 참조)
- stream-json 녹화 픽스처 (Fixtures/ 폴더)는 비어있음. Mock 기반 E2E 테스트
  도 아직.

---

## Phase 2-A · SessionStore 기록 연결 (2026-04-22)

**목표**: `AgentViewModel`에서 `SessionRecord`를 생성·갱신·저장. CostDashboard가
실제 데이터를 집계하도록.

**수정한 파일**:
- `ViewModels/AgentViewModel.swift` —
  - `private let sessionStore: SessionStore?` (`try? SessionStore()`로 초기화).
  - `var currentSession: SessionRecord?` 공개 (디버깅/UI용).
  - `start(ticket:repo:)` 진입 시 `SessionRecord.new(ticket:)` → `stashMessage`
    주입 → `persist`. 오케스트레이터 실행 후 `syncCostFromOrchestrator` +
    `persist`.
  - `handleOrchestratorFinish` — phase에 따라 status 결정. `.finished` 일 때
    `changedFiles`를 `diffFiles.map { $0.path }`로 채움.
  - `commit(ticket:repo:)` — `.result` 이벤트 cost를 `mergeCommitCost`로 세션에
    누적, 성공 시 `finishRecord(status: .completed, commitSHA:, repo:)`. 실패
    시 `.crashed`.
  - `cancel(ticket:repo:)` — `finishRecord(status: .cancelled)`.
- 변경 없음: `Models/SessionRecord.swift`, `ViewModels/CostViewModel.swift`
  (SessionStore.list() 합산은 그대로 동작).

**결정**:
- `changedFiles`는 `.finished` 시점 `diffFiles` path, 실패/crash 시 `git diff
  --name-only` fallback.
- commit invocation은 `orchestrator`를 경유하지 않으므로 별도 cost 변수로 누적
  후 CostRecord에 병합.
- 실패·크래시 루트에서도 `endedAt`을 찍고 저장 (복구 UI가 inProgress로 남은
  기록만 필터링하도록).

---

## Phase 2-B · 크래시 복구 UI (2026-04-22)

**목표**: 앱이 중단되어 `status == inProgress`로 남은 세션을 시작 시 사용자에게
알리고, stash 복원 또는 "resolved" 마킹을 제공.

**작성한 파일**: `Views/CrashRecoveryView.swift`
- `CrashRecoveryViewModel` (`@MainActor @Observable`) — `SessionStore` 소유,
  `reload()`, `markResolved(_:)` (status=cancelled + save), `popStash(for:repo:)`
  (`GitCLIClient.stashPop`).
- `CrashRecoveryView` 시트 —
  - 세션 행마다 ticketDisplayID, title, startedAt, stashMessage(monospace, 선택 가능).
  - `Mark resolved` 버튼 (무조건 노출).
  - `Pop stash` 버튼 (stashMessage + bookmark 모두 있을 때만).
  - 상태 footer + Close 버튼.

**수정한 파일**: `QAFixMacApp.swift` —
- `@State showCrashRecovery: Bool = false`
- `.task { if crashedSessions 있으면 showCrashRecovery = true }`
- `.sheet(isPresented:) { CrashRecoveryView() }`.

**결정**:
- `Pop stash`는 레포 bookmark가 해제된 상태(처음 실행)에서는 버튼 자체를
  렌더하지 않음. Settings 구성 전이어도 "resolved" 처리는 가능.
- `popStash`는 가장 최근 stash만 pop하는 git 기본 동작을 그대로 사용. 특정 stash
  메시지 매칭은 Phase 2 후기로 미룸 (stashMessage를 UI에 노출해 사용자가 직접
  `git stash list`로 대조 가능).

---

## Phase 2-C · Security-Scoped Bookmark 수명 관리 (2026-04-22)

**목표**: `startAccessingSecurityScopedResource`를 body 렌더마다 호출하던 leak
패턴을 제거.

**수정한 파일**: `Views/Tickets/TicketListView.swift` —
- `@State private var scopedRepo: URL?` — 한 번만 열고 유지.
- `.task`에서 `resolveRepoIfNeeded()` 호출 (bookmark resolve → startAccess → 저장).
- `.onDisappear`에서 `releaseRepo()` (stopAccess + nil).
- detail branch는 `scopedRepo`만 사용. `FixSessionView(ticket:repo:)`에 전달.

**결정**:
- body 안에서 `startAccess`를 호출하던 원본 코드는 같은 URL에 대해 여러 번
  startAccess가 쌓일 수 있었음. `@State`+task로 단일 retain을 보장.

---

## 댓글 정렬 (2026-04-22)

**수정한 파일**: `ViewModels/TicketListViewModel.swift` —
- `hydrateComments` 안에서 `comments.sorted { $0.createdTime < $1.createdTime }`.
  ISO8601 문자열이므로 lexical 정렬이 시간순과 동일.

---

## Phase 2-D · CostDashboard 세션 리스트 (2026-04-22)

**목표**: 합계만 보여주던 대시보드에 최근 세션 행을 추가. Phase 2-A에서 기록
되는 `SessionRecord`가 UI로 드러나게.

**수정한 파일**:
- `ViewModels/CostViewModel.swift` — `var sessions: [SessionRecord] = []`
  추가, `reload()`에서 `store.list()`를 그대로 노출.
- `Views/Cost/CostDashboardView.swift` —
  - 상단: 기존 합계 Form (Cumulative usage).
  - 하단: `Table(viewModel.sessions)` — Ticket(displayID+title), Status pill,
    Started(date+time), Cost, Tokens(in/out), Refix, Commit SHA 7 컬럼.
  - `StatusPill` 뷰 — SessionStatus별 색상 (inProgress=orange, completed=green,
    crashed=red, cancelled=gray).
  - Reload 버튼 (arrow.clockwise) 헤더에 배치.

**결정**:
- `Table`이 macOS 14 기준 SwiftUI로 제공됨. ID는 `SessionRecord: Identifiable`
  (`id: UUID`) 덕에 자동으로 동작.
- Column 폭은 `.width(min:ideal:)` 혹은 고정. 너무 좁으면 로컬에서 re-tune 필요.

---

## Phase 2-E · Commit cost를 orchestrator log에 반영 (2026-04-22)

**목표**: `AgentViewModel.commit`의 subprocess 이벤트가 `AgentLogView`에 전혀
안 나타나던 문제 해결. commit 단계 비용 / tool 사용이 UI에서 보이도록.

**수정한 파일**:
- `Services/Agent/AgentOrchestrator.swift` — `private func append(_:_:)` →
  `func append(_:_:)` (internal 노출. 외부에서 log에 추가 가능).
- `ViewModels/AgentViewModel.swift` `commit(ticket:repo:)` —
  - commit phase 시작 시 `orchestrator.append(.system, "── commit phase started ──")`.
  - stream event loop에 `.toolUse` / `.toolResult` / `.assistantText` /
    `.result(cost)` / `.error` 모두 `orchestrator.append`로 forward.
  - 결과 cost는 이전과 동일하게 `mergeCommitCost`로 `SessionRecord`에도 누적.

**결정**:
- `append`를 public 대신 internal로 열어둔 이유: 같은 모듈(`QAFixMac` app target)
  안에서만 호출. 테스트 bundle이 `@testable import QAFixMac`로 접근 가능.
- system prefix (`── commit phase started ──`)로 로그 스크롤에서 phase 경계가
  눈에 띄게 함. `AgentLogView`는 source별 색상만 구분하므로 텍스트 prefix는
  UX helper.

---

## 최종 빌드/테스트 상태 (2026-04-22)

```
$ xcodebuild -project QAFixMac.xcodeproj -scheme QAFixMac -destination 'platform=macOS' test
...
Test Suite 'DiffParserTests' passed at 2026-04-22 09:26:00.xxx.
Test Suite 'MCPConfigManagerTests' passed at 2026-04-22 09:26:00.xxx.
Test Suite 'RetryPolicyTests' passed at 2026-04-22 09:26:00.958.
Test Suite 'StreamJSONParserTests' passed at 2026-04-22 09:26:01.003.
Test Suite 'QAFixMacTests.xctest' passed at 2026-04-22 09:26:01.003.
Test Suite 'All tests' passed at 2026-04-22 09:26:01.003.
** TEST SUCCEEDED **
```

- Swift 파일 43개 (Phase 2-B에서 `CrashRecoveryView.swift` 추가).
- 3 타겟 (QAFixMac / QAFixMacTests / CLISpike) 모두 빌드 성공.
- 11 unit tests 전부 통과.
