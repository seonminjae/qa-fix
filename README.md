# QAFixMac

iOS QA 결함을 **Claude Code 에이전트**로 수정하는 macOS 네이티브 앱입니다.
원래 `.claude/commands/qa-fix.md` 슬래시 커맨드로 돌아가던 워크플로우를
SwiftUI 앱으로 재구현했으며, 에이전트 실행은 로컬의 **Claude Code CLI**
서브프로세스에 위임합니다.

앱이 담당하는 일:
- Notion 데이터베이스에서 Opened 티켓 조회 (버전 필터 · 위험도 정렬)
- 티켓 상세 표시 (담당자 / 디바이스 / 재현 절차·결과)
- Claude Code CLI 에이전트 실행 (debugger ↔ verifier 루프)
- 스트리밍 로그 표시 + `[질문 필요]` 대화형 질의 응답
- diff 미리보기 → 유저 승인 → git commit + Notion 상태 `In progress` 전환
- git stash 안전망 (Start Fix 시 자동 stash, Cancel 시 원복)
- 세션별 토큰/비용 집계 (CostDashboard)

---

## 1. 사전 준비

### 1-1. 도구 설치

```bash
# macOS 14+, Xcode 16+ 필수
brew install xcodegen      # project.yml → .xcodeproj 생성기
```

그리고 **Claude Code CLI** 2.1.0 이상이 설치돼 있어야 합니다. 없으면:
<https://docs.claude.com/en/docs/agents/claude-code>

### 1-2. Claude Code 로그인 (필수)

앱은 Claude Code CLI의 로그인 상태를 그대로 재사용합니다. 터미널에서 한 번만:

```bash
claude           # 인터랙티브 세션 진입
> /login         # 브라우저가 열리고 OAuth 진행
> /exit
```

로그인된 상태인지 확인:
```bash
claude
> /status        # "Login method: Claude Max account" 등이 찍히면 OK
```

> 앱이 띄우는 `claude -p` subprocess가 이 로그인을 그대로 씁니다. `ANTHROPIC_API_KEY`를
> 따로 입력할 필요 없습니다.

### 1-3. Notion 사전 세팅

Notion에서 **Integration Token**을 발급하고 QA 티켓이 담긴 데이터베이스에
integration을 connect 해 주세요:

1. <https://www.notion.so/profile/integrations> → **New integration** →
   Internal 타입으로 생성 → **Internal Integration Secret** 복사
   (`secret_xxxx…` 형식)
2. QA 티켓 데이터베이스 페이지 → 우측 상단 `···` → **Connections** →
   방금 만든 integration 추가
3. 데이터베이스 URL에서 **32자리 Database ID**를 복사
   (예: `https://www.notion.so/workspace/abcdef1234…?v=…` 의 `abcdef1234…`)

---

## 2. 앱 빌드 & 실행

```bash
cd ~/Desktop/QAFixMac
xcodegen generate                  # project.yml → QAFixMac.xcodeproj
open QAFixMac.xcodeproj            # Xcode에서 Cmd+R
```

또는 커맨드라인에서 Release 빌드:
```bash
xcodebuild -project QAFixMac.xcodeproj -scheme QAFixMac \
  -destination 'platform=macOS' -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/QAFixMac-*/Build/Products/Debug/QAFixMac.app
```

---

## 3. 최초 설정 (Settings 탭)

왼쪽 사이드바 → **Settings** 에서 다음을 차례로 입력합니다.

### Notion

| 필드 | 설명 |
|---|---|
| Integration Token | 1-3단계에서 복사한 `secret_xxxx…` (Keychain에 암호화 저장) |
| Database ID | QA 데이터베이스 32자리 ID |

입력 후 **Validate Database ID** 버튼을 눌러 `OK (HTTP 200)`이 뜨는지 확인하세요.
아래에 `MCP config → /Users/…/mcp.json` 경로가 표시되면 Notion MCP 설정 파일도
자동으로 생성된 상태입니다.

### Repository

**Choose…** 로 iOS 레포지토리 루트 디렉터리를 선택합니다. 선택 경로는
Security-Scoped Bookmark로 저장되므로 앱 재실행 후에도 접근이 유지됩니다.

### Claude Code CLI

- **Version**: 자동으로 `2.1.xxx ✓` (녹색) 이 표시되면 사용 가능.
- **Test `claude -p hi`**: 실제로 subprocess를 띄워 인증 상태를 확인합니다.
  `✓ 로그인 OK` 가 나와야 합니다. `❌ Not logged in` 이면 터미널에서 `claude`
  → `/login` 실행.

### Agent

- **Model**: Claude Sonnet 4 / 4.6 / Opus 4.7 / Haiku 4.5 중 선택.
  기본은 Sonnet 4.
- **Max budget (USD)**: 단일 세션 최대 비용. CLI의 `--max-budget-usd` 로 전달됩니다.
  기본 5.0. 초과하면 CLI가 자동 중단.

입력 후 우측 하단 **Save** 버튼을 눌러야 저장됩니다.

---

## 4. 한 티켓 수정 워크플로우

### Tickets 탭 구조

```
[ 사이드바 ]                    [ 메인 패널 ]
Version: [iOS 1.41.0 ▾] 🔄     
━━━━━━━━━━━━━━━━━━━━━━━━━━━━    Severity · 환경 · FANPLUSQA-XXXX · [Start Fix]
┌──────────────────────────┐    ──────────────────────────────────────────────
│ Major  Web               │    타이틀
│ [Home] 홈 배너 랜딩 안됨 │    담당자 · 디바이스 · 발생 버전
│ 🧑 현성 최               │    재현 절차 / 재현 결과
│                          │    ──────────────────────────────────────────────
│ [재현 절차] ...          │    Agent Log            |    Diff
│ [재현 결과] ...          │    (스트리밍 중)        |    (수정 후 채워짐)
│ FANPLUSQA-2334           │
└──────────────────────────┘
```

### 1단계 — 버전 필터 & 티켓 선택

1. 사이드바 상단 **Version** 드롭다운에서 수정하고자 하는 버전 선택
   (예: `iOS 1.41.0`). `All` 선택 시 전체 Opened 티켓.
2. 🔄 (Refresh) 버튼으로 최신 상태로 갱신 가능.
3. 카드 하나를 클릭하면 우측 메인 패널에 상세가 뜹니다.

> 위험도(Critical → Major → Minor → Trivial) 순서로 자동 정렬됩니다.

### 2단계 — Start Fix

우측 상단의 **▶ Start Fix** 버튼을 누르면:

1. 현재 체크아웃된 브랜치에서 `git stash push`로 작업 상태 백업 (메시지:
   `QAFixMac-FANPLUSQA-XXXX-<타임스탬프>`)
2. `fix/<현재-브랜치>` 브랜치로 이동/생성
3. Claude Code 에이전트가 debugger 모드로 실행 → 티켓 본문을 읽고 코드 수정 시도
4. verifier가 결과 검증 → 필요 시 재수정 (최대 3회)

### 3단계 — Agent Log 모니터링

**Agent Log** 패널에서 실시간으로:
- `DEBUGGER` / `VERIFIER` / `TOOL_USE` / `TOOL_RESULT` / `SYSTEM` / `USER` / `ERROR`
  소스별로 색상 구분된 로그
- 하단의 **Copy All** 로 전체 로그를 클립보드에 복사 (버그 리포트 시 유용)

### 4단계 — 대화형 질문 처리 (선택)

에이전트가 `[질문 필요]`를 감지하면 하단에 **Question View**가 나타납니다.
질문에 답을 입력하고 **Submit** 하면 에이전트가 이어서 작업합니다.
**Cancel**을 누르면 변경사항을 폐기하고 원상복구합니다.

### 5단계 — Diff 검토 & 결정

에이전트가 `[수정 완료]` → `[통과]`로 마무리하면 **Diff** 패널에 변경사항이
표시되고 하단 **Action Bar**가 활성화됩니다:

| 버튼 | 동작 |
|---|---|
| ✅ **Commit** (⌘S) | `git add -A` → Claude가 `/commit` 가이드를 따라 커밋 메시지 작성 → Notion 상태를 **In progress**로 전환 |
| 🔁 **Re-fix** | 추가 수정 방향을 입력 받아 에이전트를 다시 실행 |
| ❌ **Discard** | `git checkout --` → `git stash pop`으로 완전 원복 |

### 6단계 — 중단 (Stop)

에이전트 실행 중에는 **Start Fix** 자리에 빨간색 **■ Stop** 버튼이 뜹니다.
누르면 subprocess를 SIGINT → SIGTERM → SIGKILL 순으로 정리하고 stash를
되돌려 깨끗한 상태로 복귀합니다.

---

## 5. Cost 탭

왼쪽 사이드바 → **Cost** 에서 누적 비용과 과거 세션 목록을 확인합니다:

- 총 비용 (USD), 입력/출력 토큰, 재수정 횟수
- 세션별 Status(pill: completed / cancelled / crashed)
- 수정된 파일 목록, 최종 commit SHA

---

## 6. 크래시 복구

앱이 비정상 종료된 뒤 다시 켜면 완료되지 않은 세션이 있을 경우 자동으로
**Crash Recovery** 시트가 뜹니다:
- 남아있는 stash 확인 후 `stash pop` 으로 복구하거나 폐기 선택 가능.

---

## 7. CLI Spike — 인증 확인용

실제 Claude Code 인증 & stream-json 수신이 정상 동작하는지 별도 바이너리로
빠르게 확인할 수 있습니다 (앱 실행 없이 터미널에서):

```bash
xcodebuild -project QAFixMac.xcodeproj -scheme CLISpike \
  -destination 'platform=macOS' -configuration Debug build

~/Library/Developer/Xcode/DerivedData/QAFixMac-*/Build/Products/Debug/CLISpike \
  "Reply with the word PONG and nothing else." \
  ~/Desktop/QAFixMac
```

성공 예시:
```
[event #1] system
[event #10] assistant
[event #12] result (cost=0.14131400000000002 USD, duration=4112ms)
[spike] exit=0 events=12 unknown=0 sawResult=true
```

`Not logged in · Please run /login`이 뜨면 1-2단계로 돌아가 로그인하세요.

---

## 8. 주요 파일 위치

| 항목 | 경로 |
|---|---|
| Notion Integration Token | macOS Keychain (`com.fanmaum.QAFixMac.notionToken`) |
| MCP 설정 | `~/Library/Application Support/QAFixMac/mcp.json` |
| 세션 기록 | `~/Library/Application Support/QAFixMac/sessions/` |
| 앱 설정 | `UserDefaults` (database ID, 모델, budget, repo bookmark) |

---

## 9. 트러블슈팅

| 증상 | 확인사항 |
|---|---|
| Settings에서 `❌ claude binary not found` | `claude --version`이 터미널에서 되는지. nvm 사용 시 `~/.nvm/current/bin/claude`가 있는지 |
| `❌ Not logged in` | 터미널에서 `claude` → `/login` 재실행. 그 후 **Test** 다시 |
| Notion `HTTP 404` | Database ID 오타, 또는 integration이 해당 DB에 connect 되어있지 않음 |
| 티켓 리스트가 빈 채로 뜸 | Notion DB에 `상태` 속성(select) 값이 `Opened`인 페이지가 있는지, 버전 필터가 맞는지 |
| Agent Log가 잠깐 뜨다 exit=1 | `Test 'claude -p hi'`로 인증 먼저 확인 |
| 창을 줄이면 UI가 깨짐 | 최소 창 크기는 1000×700. 그 이하로는 축소가 불가능하도록 강제돼 있음 |

---

## 10. 배포 / 알려진 제약

- **App Store 배포 불가** — `claude` subprocess를 spawn하기 때문.
  Developer ID 서명 + Notarization 전용으로 가정.
- 현재 App Sandbox는 **OFF** (`QAFixMac.entitlements`의
  `com.apple.security.app-sandbox = false`). 내부 사내 배포 용도이기에
  샌드박스 제약을 풀어 두었습니다.
- 병렬 티켓 처리(OMC 경로)는 아직 미구현. 한 번에 하나의 티켓만.
- 사용자 전역 Claude Code hooks/plugins/MCP가 subprocess에 로드되어
  3~5초 startup 오버헤드가 있습니다 (향후 격리 예정).

---

## 11. 개발자용: 빌드 & 테스트

```bash
# 프로젝트 파일 (재)생성
xcodegen generate

# 앱 빌드
xcodebuild -project QAFixMac.xcodeproj -scheme QAFixMac \
  -destination 'platform=macOS' -configuration Debug build

# 단위 테스트 (StreamJSONParser / DiffParser / RetryPolicy / MCPConfigManager)
xcodebuild -project QAFixMac.xcodeproj -scheme QAFixMac \
  -destination 'platform=macOS' test
```

설계 결정, 원본 슬래시 커맨드 매핑, 구현 상태는 `CLAUDE.md` 참고.
