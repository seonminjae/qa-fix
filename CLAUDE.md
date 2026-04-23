# CLAUDE.md — QAFixMac

> 이 파일은 Claude Code가 이 프로젝트에서 작업할 때 먼저 읽어야 하는 컨텍스트입니다.
> 프로젝트 전반의 의도, 현재 상태, 미완성 항목, 설계 결정을 모두 요약합니다.

---

## 1. 프로젝트 한 줄 요약

`.claude/commands/qa-fix.md` (internal-ios-repo 저장소의 iOS QA 결함 수정
워크플로우)를 macOS 네이티브 SwiftUI 앱으로 재구현한 것. 에이전트 실행은 사용자
머신의 Claude Code CLI (`claude -p --verbose --bare --output-format stream-json`)
서브프로세스에 위임하고, 앱은 Notion 조회·이슈 선택·diff 리뷰·커밋·Notion 상태
업데이트 UI를 담당.

원본 슬래시 커맨드: `<internal-ios-repo>/.claude/commands/qa-fix.md`
합의 계획 (v3, Planner/Architect/Critic APPROVE):
`<internal-ios-repo>/photocard/.omc/plans/qa-fix-mac-app.md`

---

## 2. 아키텍처 선택 (ADR 요약)

**Decision**: Option C — SwiftUI UI + Claude Code CLI Headless Subprocess 하이브리드.

**Why**:
- Workflow Fidelity 최상 (Claude Code의 Read/Edit/Grep/Glob/Bash/Agent 도구 + 기존
  Notion MCP + `/commit` 커맨드를 그대로 상속).
- Anthropic Messages API + tool_use를 Swift에서 직접 구현하는 대비 약 40% 코드 감소.
- `edit_file` uniqueness 검사 등 Claude Code가 이미 해결한 문제를 재구현할 필요 없음.

**Alternatives considered**:
- Option A (URLSession으로 Anthropic Messages API 직접): ~2,500 LOC 추가 + `/commit`
  재구현 필요 — 기각 (가중 6.15 vs Option C 9.10).
- Option B (Electron): 사용자가 "macOS 네이티브" 명시 요구 — 무효화.

**Consequences**:
- Claude Code CLI 사전 설치 필수 (현재 검증된 버전: 2.1.112).
- `com.apple.security.process.exec` 엔타이틀먼트 필요 → **App Store 배포 불가**,
  Developer ID + Notarization 전용.
- stream-json 포맷 breaking change 리스크 → `ClaudeStreamEvent.unknown(rawJSON:)`
  fallback과 `NDJSONLineBuffer`로 방어.

---

## 3. 표준 CLI 호출 템플릿

**`--verbose`는 필수. `--bare`는 절대 쓰지 마세요.**

- `--verbose` 없이 `--output-format stream-json`을 쓰면 CLI가 하드 에러로 즉시
  종료합니다 (2.1.112 기준 `Error: When using --print, --output-format=stream-json
  requires --verbose`).
- `--bare`를 붙이면 **Claude Max OAuth 인증이 깨져서** 모든 요청이 `Not logged in ·
  Please run /login`으로 실패합니다 (2.1.112에서 2026-04-23 live 검증 완료).
  `apiKeySource: "none"` + exit 1 + ~80ms duration이 증상. 플러그인/훅 격리가
  필요할 경우 `--bare` 대신 `HOME` 또는 `CLAUDE_HOME` 환경변수로 격리된 `.claude/`
  디렉터리를 가리키는 방식을 써야 합니다 (후속 스파이크 필요).

```
claude -p \
  --verbose \
  --output-format stream-json \
  --include-partial-messages \
  --permission-mode bypassPermissions \
  --model {MODEL} \
  --max-budget-usd {BUDGET} \
  --system-prompt "{SYSTEM_PROMPT}" \
  --mcp-config "{MCP_CONFIG_PATH}" \
  --add-dir "{REPO_PATH}"
```

구현 위치: `QAFixMac/Services/Claude/ClaudeCodeService.swift` 의
`ClaudeInvocation.command(binary:)`. 변경 시 `CLISpike/main.swift`와
`SettingsView.verifyLogin`도 함께 업데이트하세요.

**트레이드오프 (현재 상태)**: `--bare` 없이 실행하므로 사용자의 hooks / plugins /
MCP (OMC, swift-lsp, figma 등)가 subprocess에 자동 로드됩니다. 3~5초 startup
오버헤드 + system-reminder 토큰 낭비 + debugger/verifier 에이전트가 의도치 않게
외부 skill을 호출할 위험이 있습니다. Phase 2의 후속 과제에서 격리 대책(`HOME`
override 또는 claude-code의 공식 isolation 플래그)을 탐색해야 합니다.

---

## 4. 빌드 · 테스트

```bash
cd ~/Desktop/QAFixMac

# 프로젝트 재생성 (project.yml 수정 시 반드시 실행)
xcodegen generate

# 앱 빌드
xcodebuild -project QAFixMac.xcodeproj -scheme QAFixMac \
  -destination 'platform=macOS' -configuration Debug build

# 단위 테스트 (StreamJSONParser, DiffParser, RetryPolicy, MCPConfigManager)
xcodebuild -project QAFixMac.xcodeproj -scheme QAFixMac \
  -destination 'platform=macOS' test

# CLI Prototype Spike 실행 (subprocess 동작 sanity check)
xcodebuild -project QAFixMac.xcodeproj -scheme CLISpike \
  -destination 'platform=macOS' build
~/Library/Developer/Xcode/DerivedData/QAFixMac-*/Build/Products/Debug/CLISpike \
  "Reply with the word PONG and nothing else." ~/Desktop/QAFixMac
```

**요구 도구**: Xcode 16+, XcodeGen (`brew install xcodegen`), macOS 14+,
Claude Code CLI 2.1.0+.

---

## 5. 디렉터리 레이아웃

```
QAFixMac/
├── project.yml                        # XcodeGen 설정 (3 target: 앱 / 테스트 / CLI spike)
├── QAFixMac.xcodeproj                 # 생성물 (git ignore)
├── README.md                          # 사용자용 README
├── CLAUDE.md                          # ← 이 파일
├── QAFixMac/
│   ├── QAFixMacApp.swift              # @main
│   ├── ContentView.swift              # NavigationSplitView + 3 tab
│   ├── Models/
│   │   ├── Settings.swift             # AppSettings, AnthropicModel enum
│   │   ├── Ticket.swift               # Ticket, Severity, TicketComment, TicketAttachment, NotionPropertyHelper
│   │   ├── ClaudeStreamEvent.swift    # .assistantText / .toolUse / .result / .unknown(rawJSON:) 등
│   │   └── SessionRecord.swift        # SessionRecord, SessionStatus, CostRecord, SessionStore
│   ├── Views/
│   │   ├── Settings/SettingsView.swift       # API 키 / database_id / 레포 / 모델 / Budget / CLI 버전
│   │   ├── Tickets/{TicketListView,TicketRowView,TicketDetailView}.swift
│   │   ├── Agent/{AgentLogView,QuestionView}.swift
│   │   ├── Diff/{DiffView,DiffFileView}.swift
│   │   ├── Action/ActionBarView.swift
│   │   ├── Cost/CostDashboardView.swift
│   │   └── FixSessionView.swift       # 전체 픽스 세션 컨테이너
│   ├── ViewModels/
│   │   ├── TicketListViewModel.swift  # Notion 조회 + 버전 필터 + 위험도 정렬 + 댓글 hydrate
│   │   ├── AgentViewModel.swift       # stash/agent/diff/commit 오케스트레이션
│   │   ├── DiffViewModel.swift
│   │   └── CostViewModel.swift
│   ├── Services/
│   │   ├── Notion/
│   │   │   ├── NotionService.swift            # protocol + NotionError
│   │   │   ├── NotionAPIClient.swift          # URLSession + RetryPolicy + 동시 3개 throttle
│   │   │   └── NotionModels.swift             # NotionPage, NotionProperty, NotionComment, NotionBlock
│   │   ├── Claude/
│   │   │   ├── ClaudeCodeService.swift        # protocol + ClaudeInvocation + ClaudeClientError
│   │   │   ├── ClaudeCodeCLIClient.swift      # Process 구현 + SIGINT→SIGTERM→SIGKILL
│   │   │   ├── StreamJSONParser.swift         # NDJSON 파서 + .unknown forward compat
│   │   │   └── ClaudeCodeVersionProbe.swift   # `claude --version` 파싱 + 최소 버전 체크
│   │   ├── Git/GitService.swift               # GitCLIClient (diff, commit, stash, checkout, HEAD)
│   │   ├── Agent/
│   │   │   ├── PromptTemplates.swift          # debugger/verifier/commit system prompt + user prompt 빌더
│   │   │   └── AgentOrchestrator.swift        # debugger ↔ verifier 루프, 재수정 최대 3회, 키워드 파싱
│   │   └── MCP/MCPConfigManager.swift         # 앱 내장 Notion MCP config 생성 (~/Library/Application Support/QAFixMac/mcp.json)
│   ├── Utilities/
│   │   ├── KeychainManager.swift      # Notion 토큰 보관
│   │   ├── BookmarkManager.swift      # Security-Scoped Bookmark (NSOpenPanel → bookmarkData)
│   │   ├── RetryPolicy.swift          # exp backoff (1→2→4→8→16s, ±20% jitter) + ConcurrencyLimiter(3)
│   │   ├── DiffParser.swift           # unified diff → DiffFile[]
│   │   └── AppLogger.swift            # OSLog (subprocess, notion, git, agent, ui)
│   ├── Resources/
│   │   ├── QAFixMac.entitlements      # app-sandbox + bookmarks.app-scope + files.user-selected.rw + network.client
│   │   ├── CRITICAL.md                # 앱 번들에 포함되는 P0 리뷰 가이드 (internal-ios-repo에서 복사)
│   │   ├── SECURITY.md
│   │   ├── UIKit-CRITICAL.md
│   │   └── Assets.xcassets
│   └── Info.plist
├── CLISpike/
│   └── main.swift                     # --verbose --bare stream-json 검증 + .unknown 카운트 + result 이벤트 출력
└── QAFixMacTests/
    ├── StreamJSONParserTests.swift    # assistant / toolUse / result(totalCost) / unknown / malformed
    ├── DiffParserTests.swift          # single / multiple files
    ├── RetryPolicyTests.swift         # shouldRetry / Retry-After / exp growth
    ├── MCPConfigManagerTests.swift    # 생성된 mcp.json 스키마 검증
    └── Fixtures/                      # 비어있음, 향후 녹화된 stream-json ndjson 추가 예정
```

---

## 6. 원본 워크플로우 매핑

| 원본 qa-fix.md 단계 | QAFixMac 구현체 |
|---|---|
| Step 1: 버전 선택 (Notion Opened iOS 티켓에서 버전 수집) | `TicketListViewModel.refresh` + 사이드바 version Picker |
| Step 2: 선택 버전의 Opened 티켓 조회 + 댓글/이미지 | `NotionAPIClient.fetchOpenedTickets` + `fetchComments` + `fetchImageBlocks` |
| Step 3: 이슈 선택 (위험도 우선 상위 3개 + Other) | `TicketListView` 사이드바. 현재는 단순 선택(우선 표시 정렬은 Severity Comparable) |
| Step 4: 에이전트 수정 (debugger ↔ verifier) | `AgentOrchestrator` + `ClaudeCodeCLIClient`. OMC 경로 대신 Basic 단일 경로만 지원 (Phase 1) |
| Step 5: 유저 검증 (Commit / 재수정 / 취소) | `ActionBarView` + `QuestionView` + `AgentViewModel.commit`/`cancel`/`requestRefix` |
| Commit 시 Notion 상태 In progress | `AgentViewModel.commit` → `NotionAPIClient.patchStatus(pageID:, "In progress")` |
| git stash 안전망 (v3 추가) | `AgentViewModel.start` 에서 `GitCLIClient.stashPush`, `cancel` 에서 `checkout --` + `stashPop` |

---

## 7. 구현 상태 (2026-04-22 기준)

| Task | 상태 | 비고 |
|---|---|---|
| Step 0-1 스캐폴드 (project.yml, entitlements, P0 가이드 번들) | ✅ | xcodegen으로 xcodeproj 생성 |
| Step 1 Settings/Keychain/Bookmark/MCPConfig/CLI 감지 | ✅ | SettingsView에서 database_id 검증 버튼 포함 |
| Step 2 Notion 연동 + 티켓 리스트/상세 | ✅ | 429/Retry-After + 동시 3개 throttle + 댓글 병렬 hydrate + createdTime 오름차순 정렬 |
| Step 2.5 CLI Prototype Spike | ✅ | CLISpike 타겟 빌드 성공. 실제 live smoke test는 사용자 수동 |
| Step 3 ClaudeCodeCLIClient + StreamJSONParser | ✅ | .unknown fallback + stderr 분리 + SIGINT→SIGTERM→SIGKILL |
| Step 4 AgentOrchestrator + AgentLogView + QuestionView | ✅ | 재수정 최대 3회. `[질문 필요]/[수정 완료]/[통과]/[재수정 필요]` 키워드 파싱 |
| Step 5 DiffView + ActionBar + commit + stash | ✅ | `/commit` 동치 flow는 `PromptTemplates.commitSystemPrompt()`로 P0 가이드 주입 |
| Step 6 OSLog + SessionStore + CostDashboard + 테스트 | ✅ | 11/11 테스트 통과 (4 스위트) |
| Phase 2-A SessionStore 기록 연결 | ✅ | `AgentViewModel.start/commit/cancel`에서 `SessionRecord` CRUD |
| Phase 2-B 크래시 복구 UI | ✅ | `CrashRecoveryView` 시트 — `QAFixMacApp.task`에서 `crashedSessions` 조회해 자동 표시 |
| Phase 2-C Security-Scoped Bookmark 수명 관리 | ✅ | `TicketListView`에서 `@State scopedRepo` + `onDisappear` stopAccess |
| Phase 2-D CostDashboard 세션 리스트 노출 | ✅ | `Table` 기반 — Status pill, cost, refix, commit SHA 표시. `CostViewModel.sessions` 추가 |
| Phase 2-E Commit cost를 orchestrator log에 반영 | ✅ | `AgentOrchestrator.append`을 internal로 노출, `AgentViewModel.commit`에서 commit phase 이벤트 forward |

**전체 빌드 & 테스트 (2026-04-22)**: `xcodebuild clean build` + `test` →
`** BUILD SUCCEEDED **` / `** TEST SUCCEEDED **` (11 tests, 4 suites).

---

## 8. 아직 해야 할 일 (Phase 2 잔여)

1. **병렬 이슈 처리**: 원본 qa-fix의 OMC 경로 (복수 티켓 병렬) 지원. 현재는 단일
   이슈 순차만. `AgentViewModel`/`AgentOrchestrator`를 N-세션 관리자로 확장 필요.
2. **녹화된 stream-json 픽스처 6종** (`Fixtures/`): 실제 CLI 출력을 캡처해서
   `MockClaudeCodeService`와 함께 `AgentOrchestratorTests` 작성. 현재 `Fixtures/`
   폴더는 비어있음.
3. **live CLI smoke test**: CLISpike가 실제로 `result` 이벤트와 `total_cost_usd`
   를 받는지 `xcodebuild build && run` 으로 수동 검증 (비용 발생, 사용자 판단).
4. **커밋 메시지 포맷 검증**: `PromptTemplates.commitSystemPrompt()`가 실제
   `/commit` 동치 결과를 생성하는지 live 실행으로 확인. 현재 파일 안에
   CRITICAL.md/SECURITY.md/UIKit-CRITICAL.md 전문을 주입하는 방식.

---

## 9. 주의사항 (Claude가 작업할 때)

- **`--verbose`는 필수, `--bare`는 금지.** `--verbose`가 없으면 stream-json
  모드가 즉시 에러. `--bare`를 붙이면 OAuth 인증이 깨져서 `Not logged in` 실패
  (2.1.112 live 검증됨, 2026-04-23).
- **인증은 Claude Max OAuth 재사용 전제.** 내부 사용자는 Terminal에서
  `claude` 한 번 실행 → `/login` 완료 시 Keychain(`Claude Code-credentials`)에
  저장된 토큰을 subprocess가 그대로 읽습니다. 별도 `ANTHROPIC_API_KEY` 입력
  경로는 제거했습니다.
- **App Sandbox는 OFF.** `QAFixMac.entitlements`의 `app-sandbox = false`.
  배포는 회사 내부 클론 빌드 전용이라 App Store 경로는 고려 안 함. Developer ID
  서명도 필수 아님. Sandbox/Bookmark 조합 설계는 남아있지만 현재 비활성.
- **`--mcp-config`가 가리키는 파일은 Notion MCP만 포함.** `~/.claude/settings.json`
  등 사용자 전역 MCP를 덮어쓰지 않습니다. `MCPConfigManager`로만 생성.
  단, `--bare`를 쓸 수 없는 현재 제약상 사용자 전역 MCP/플러그인이 subprocess에
  함께 로드되는 건 피할 수 없습니다 (후속 격리 과제).
- **커밋 플로우는 단일 경로.** `/commit` 슬래시 커맨드 직접 호출은 subprocess에
  의도치 않은 경로라 **삭제되었습니다**. P0 리뷰는 `PromptTemplates
  .commitSystemPrompt()`가 CRITICAL.md 등을 주입해서 수행.
- **`ClaudeStreamEvent.unknown`은 forward compat용.** 새 이벤트 타입이 CLI
  업데이트로 추가되어도 파서가 터지지 않습니다. 무시하지 말고 UI에서 collapsible
  로그로 볼 수 있게 남겨두는 것이 원칙.
- **`@Observable` (macOS 14+).** `ObservableObject`/`@Published`와 혼용하지 마세요.
  프로젝트 전반이 Observation framework로 통일되어 있습니다.
- **모델 하드코딩 금지.** `AnthropicModel` enum을 추가하고 `SettingsView` Picker
  에 노출. `ClaudeInvocation.model`은 Settings 값 경유.

---

## 10. Open Questions (합의 계획 v3에서 잔존)

1. **Security-Scoped Bookmark와 subprocess의 `--add-dir`** 궁합 — Sandbox 내
   resolved URL을 subprocess에 그대로 넘겨서 파일 접근이 되는가? Step 2.5
   스파이크에서 live 검증 필요.
2. **`--max-budget-usd` 의 실제 차단 동작** — tool_use 반복 중 budget을 초과하면
   CLI가 어떤 이벤트를 emit하는지 미검증. `result` 이벤트 subtype 관찰 필요.
3. **동시 Claude Code 세션 충돌** — 사용자 터미널 세션과 앱 subprocess가 동시
   실행될 때 계정 rate limit은 분산되지만 비용은 합산. UI에 "외부 세션 활성" 경고
   필요할 수 있음.

---

## 11. 파일 위치 빠른 참조

- 합의 계획 (정본): `photocard/.omc/plans/qa-fix-mac-app.md`
- 원본 슬래시 커맨드: `internal-ios-repo/.claude/commands/qa-fix.md`
- 원본 `/commit` 커맨드: `internal-ios-repo/.claude/commands/commit.md`
- iOS P0 리뷰 가이드 (번들에 복사됨):
  - `internal-ios-repo/.claude/skills/ios-code-review-guide/CRITICAL.md`
  - `internal-ios-repo/.claude/skills/ios-code-review-guide/SECURITY.md`
  - `internal-ios-repo/.claude/skills/ios-code-review-guide/uikit/CRITICAL.md`
- Claude Code 버전 검증된 빌드: 2.1.112 (nvm Node 22.18.0 기준
  `~/.nvm/versions/node/v22.18.0/bin/claude`).
