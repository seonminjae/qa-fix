# QAFixMac

QA 결함을 Claude Code 에이전트로 수정하는 macOS 네이티브 앱입니다.
Notion 티켓 조회 → Agent 수정 → Diff 검토 → Commit까지 한 창에서 처리합니다.

---

## 1. 사전 준비

### 1-1. 도구 설치

```bash
# macOS 14+, Xcode 16+
brew install tuist     # 또는 `mise install tuist`
```

Claude Code CLI 2.1.0 이상도 필요합니다 → <https://docs.claude.com/en/docs/agents/claude-code>

### 1-2. Claude Code 로그인

앱은 CLI의 로그인을 그대로 재사용합니다.

```bash
claude
> /login
> /exit
```

`/status`에 `Login method: Claude Max account`가 찍히면 OK. 별도 `ANTHROPIC_API_KEY`는 필요 없습니다.

### 1-3. Notion 세팅

1. <https://www.notion.so/profile/integrations> → **New integration** (Internal) → **Internal Integration Secret** 복사
2. QA 티켓 데이터베이스 → `···` → **Connections** → 방금 만든 integration 추가
3. DB URL에서 32자리 **Database ID** 복사

---

## 2. 빌드 & 실행

```bash
cd ~/Desktop/QAFixMac
tuist generate             # QAFixMac.xcworkspace 생성 & Xcode 실행
```

---

## 3. Settings 입력

사이드바 → **Settings** 에서 차례로 입력합니다.

**Notion** — Integration Token(API Key), Database ID. **Validate Database ID**로 `OK (HTTP 200)` 확인.

**Platform** — iOS / Android / backend / Web 중 조회할 환경을 선택. 아무것도 선택하지 않으면 전체 티켓 조회.

**Repository** — **Choose…**로 iOS 레포 루트 선택. Security-Scoped Bookmark로 재실행에도 유지됩니다.

**Claude Code CLI** — Version이 `2.1.xxx ✓`(녹색)인지, **Test `claude -p hi`**가 `✓ 로그인 OK`를 반환하는지 확인.

**Agent** — Model(기본 Opus 4.6)과 Max budget(USD, 기본 5.0) 지정. 설정 후 **Save**.

---

## 4. 티켓 수정 플로우

1. **Tickets** 탭에서 버전을 고르고 티켓을 선택합니다.
2. 우측 상단 **▶ Start Fix**. 현재 변경사항은 자동 stash, `fix/<브랜치>`로 이동 후 debugger ↔ verifier 루프가 실행됩니다 (재수정 최대 3회).
3. 에이전트가 `[질문 필요]`를 감지하면 하단에 입력창이 뜹니다. 답변 후 **Submit**.
4. `[통과]`로 끝나면 **Diff** 패널에 변경 내용이 표시됩니다:
   - **Commit (⌘S)** — `/commit` 가이드대로 커밋 메시지 작성 + Notion 상태 **In progress**
   - **Re-fix** — 추가 지시를 주고 다시 실행
   - **Discard** — `git checkout --` + `stash pop`으로 원복
5. 실행 중 **■ Stop**을 누르면 subprocess를 정리하고 stash를 되돌립니다.

---
