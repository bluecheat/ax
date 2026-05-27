# Reference — OpenCode 호환 매트릭스 (0.2.0+)

> goax 는 Claude Code plugin 으로 출고되지만, 0.2.0 부터 **OpenCode** 환경도 Hybrid 호환으로 지원해요. 이 문서는 어떤 자산이 어디서 동작하고, 어떤 한계가 있고, 어떻게 우회하는지 정리한 SSOT 예요.

## 1. 호환 매트릭스

| 자산 / 메커니즘 | Claude Code | OpenCode | 비고 |
|---|---|---|---|
| `AGENTS.md` (Constitution SSOT) | ✅ `@AGENTS.md` import 체인 | ✅ 직접 인식 (우선순위 1) | 0.2.0 부터 SSOT |
| `CLAUDE.md` (alias) | ✅ 자동 인식 | ✅ fallback (AGENTS.md 부재 시) | 본문은 1줄 `@AGENTS.md` import |
| `.claude/skills/*/SKILL.md` | ✅ frontmatter autorouting | ✅ frontmatter 인식 ([공식](https://opencode.ai/docs/skills/)) | OpenCode [Issue #6177](https://github.com/sst/opencode/issues/6177) plural/singular 미스매치 잔존 — 영향 시 `.opencode/skills/` 도 동시 배치 |
| `.claude/settings.json` (hooks) | ✅ PreToolUse/PostToolUse 자동 | ❌ 인식 안 함 | OpenCode 는 `opencode.json` + TypeScript plugin |
| `.claude/commands/` | (0.1.20 폐기) | ❌ 인식 안 함 ([Issue #6985](https://github.com/anomalyco/opencode/issues/6985)) | 영향 없음 — `commands/goax.md` 인덱스만 유지 |
| `.ax/hooks/pre-bash/*.sh` | ✅ PreToolUse:Bash matcher | ❌ bash subprocess hook 미지원 | OpenCode 는 `@opencode-ai/plugin` TypeScript in-process 만 |
| `.ax/hooks/pre-edit/*.sh` | ✅ PreToolUse:Edit/Write/MultiEdit | ❌ 동일 | path-scoped rule inject 도 Claude Code 전용 |
| `.ax/hooks/post-edit/*.sh` | ✅ PostToolUse:Edit/Write/MultiEdit | ❌ 동일 | lint-changed 등 후처리 |
| `.ax/hooks/pre-commit/*.sh` | ✅ `grep-on-commit.sh` chain | ⚠️ git pre-commit 으로 보전 | `install-git-hooks.sh` 안내 |
| `.ax/hooks/user-prompt/*.sh` | ✅ UserPromptSubmit | ❌ 미지원 | triage-nudge 등 — OpenCode 는 system prompt 정적 주입만 |
| `.ax/scripts/bash/*.sh` (결정론) | ✅ Claude Code 가 호출 | ✅ `GOAX_PROJECT_DIR=$pwd` 로 standalone 호출 가능 (0.1.20+ fallback) | `--json --dry-run --help` 인터페이스 CLI 무관 |
| `.ax/spirit/{values,tone,rules}` 마크다운 | ✅ `@import` | ✅ `instructions:` 또는 수동 `@import` | OpenCode 는 path-scoped 자동 inject 안 됨 → 수동 |
| `.ax/_templates/{spec,adr,module}/` | ✅ skill 안에서 cp | ✅ 동일 | 마크다운 자산, CLI 무관 |
| Mistake auto-capture (hook) | ✅ Claude Code 자동 | ❌ 사용자 명시 호출만 | `/mistake` 또는 "실수 기록해줘" |
| Mistake secrets 재검증 (pre-commit) | ✅ Claude Code mode | ✅ git pre-commit (install-git-hooks 후) | `check-mistake-secrets.sh` |
| HUD statusline | ✅ Claude Code statusline | ⚠️ OpenCode statusline schema 다름 | 추후 어댑터 — 현재는 Claude Code 전용 |

## 2. OpenCode 환경에서 hook 시스템 보전

OpenCode 는 `PreToolUse` 같은 도구 호출 전후 차단 hook 이 없어요. 대신 **commit 시점** 에 `.ax/hooks/pre-commit/*.sh` 를 git native pre-commit 으로 등록해서 핵심 가드레일 (CATASTROPHIC 차단·secrets 검출·CRITICAL 룰 grep) 을 보전할 수 있어요.

### 설치

```bash
# goax 가 깔린 프로젝트 루트에서
bash .ax/scripts/bash/install-git-hooks.sh

# 출력 (정상):
# ✓ installed → .git/hooks/pre-commit
#   .ax/hooks/pre-commit/*.sh 가 git commit 시 자동 chain 됩니다.

# 재실행 (idempotent — 이미 등록됐으면 skipped)
bash .ax/scripts/bash/install-git-hooks.sh
# ✓ 이미 goax wrapper 등록됨: .git/hooks/pre-commit (재설치는 --force)
```

### 동작

설치된 wrapper 가 git commit 시 `.ax/hooks/pre-commit/` 의 모든 `*.sh` 를 사전순으로 chain 실행:
- `critical-rule-grep.sh` — staged 파일에서 CRITICAL 룰 패턴 grep + CATASTROPHIC 명령 차단
- `check-mistake-secrets.sh` (0.1.20+) — staged `.ax/mistakes/*.md` 에서 시크릿 추정 패턴 재검증

첫 exit 2 (fail) 에서 commit 차단. mode 는 `.ax/config.yml` 의 `sensors.mode` 따라요 (warning / fail / off).

### 기존 pre-commit 이 있을 때

`.git/hooks/pre-commit` 이 이미 있고 goax marker 가 없으면 install 이 거부돼요. `--force` 로 강제 시 기존 hook 은 `.bak.<timestamp>` 로 백업:

```bash
bash .ax/scripts/bash/install-git-hooks.sh --force
# ✓ replaced → .git/hooks/pre-commit (백업: .git/hooks/pre-commit.bak.20260527-153012)
```

`pre-commit-framework` 같은 도구와 함께 쓰려면 `.pre-commit-config.yaml` 의 `repos:` 에 goax hook 을 local 로 추가하는 방식이 더 깔끔해요 — 현재 자동화는 안 되어 있으니 수동 통합 필요.

## 3. OpenCode 환경변수

[공식 문서](https://opencode.ai/docs/) 기준:

| 변수 | 효과 |
|---|---|
| `OPENCODE_CONFIG_DIR` | opencode.json·skills·agents·plugins 검색 디렉토리 override |
| `OPENCODE_DISABLE_CLAUDE_CODE=1` | `.claude/` 와 `~/.claude/` 호환 레이어 전체 끄기 |
| `OPENCODE_DISABLE_CLAUDE_CODE_PROMPT=1` | `~/.claude/CLAUDE.md` 만 끄기 (AGENTS.md 우선 보장에 유용) |
| `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1` | `.claude/skills/` 호환만 끄기 — `.opencode/skills/` 만 인식 |

goax 사용자 권장: 기본값 그대로 (`.claude/` 호환 켜둠). AGENTS.md 가 우선이라 CLAUDE.md 도 동시에 있어도 SSOT 충돌 없음.

## 4. opencode.json 설정

`up` skill 이 OpenCode 환경 감지 시 `opencode.json` 을 자동 설치:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "instructions": [
    "AGENTS.md",
    ".ax/docs/reference/rules-tokens.md",
    ".ax/docs/reference/rule-enforcement.md",
    ".ax/docs/reference/triage-matrix.md",
    ".ax/docs/reference/critical-rules.md",
    ".ax/docs/reference/opencode-compat.md"
  ],
  "plugins": []
}
```

- **`instructions:`** — OpenCode 가 system prompt 에 병합. 사용자 `AGENTS.md` 가 customize 영역, `.ax/docs/reference/*` 는 plugin 출고 SSOT 룰 문서.
- **`plugins:`** — 비워둠. 향후 TypeScript plugin (block-destructive 등 bash hook 의 TS 포팅) 도입 시 채움 (Full 옵션, 0.2.x 후속).

## 5. 알려진 한계 및 회피

### 5.1 Skill autorouting 정확도
OpenCode 의 frontmatter 매칭 알고리즘이 Claude Code 와 다를 수 있어요. autorouting 실패 시:
1. `/goax` 인덱스를 보고 자연어 키워드 직접 사용
2. 그래도 안 되면 `Skill goax:<name>` 명시 호출 (claude 가 직접)

### 5.2 Path-scoped rule injection
Claude Code 의 `.ax/hooks/pre-edit/spirit-rules-inject.sh` 는 OpenCode 에서 안 돌아요. spirit rule 본문이 `paths:` frontmatter 를 가져도 OpenCode 는 자동 inject 안 함.

**회피:**
- spirit rule 본문을 카테고리별로 묶고, `AGENTS.md` 의 CONVENTION 섹션에 `@.ax/spirit/rules/<category>.md` 로 모두 import (universal 화). 토큰 비용 ↑ 하지만 안전.
- 또는 spec / 작업 컨텍스트에서 사용자가 명시적으로 룰 import.

### 5.3 Mistake auto-capture 미지원
Claude Code 는 hook 으로 위반 시 mistake 자동 캡처 가능 (현재는 폐기 — 사용자 명시 호출만 — 0.1.x 부터). 따라서 OpenCode 와 Claude Code 모두 mistake 캡처는 사용자 `/mistake` skill 명시 호출로 통일됨.

### 5.4 HUD statusline
`.ax/hud/statusline.sh` 는 Claude Code statusline 사양 (stdin JSON `workspace.current_dir`) 에 맞춰 작성. OpenCode statusline 어댑터는 추후 작업.

### 5.5 OpenCode skill discovery 버그
[Issue #6177](https://github.com/sst/opencode/issues/6177) — `.claude/skills/` 호환이 실제로 인식 안 되는 케이스 보고됨 (plural/singular 미스매치). 영향받으면:
- 임시: `.opencode/skills/` 에 같은 자산 cp (실제 사용자 프로젝트에서 — plugin shipping 은 아님)
- 또는 OpenCode 업데이트 대기

## 6. 트러블슈팅

### `bash .ax/scripts/bash/triage-search.sh` 가 실패해요
```bash
[goax] no .ax/ found in any ancestor of $PWD (GOAX_PROJECT_DIR=unset, CLAUDE_PROJECT_DIR=unset)
```
→ OpenCode 환경에선 `GOAX_PROJECT_DIR` 을 명시:
```bash
GOAX_PROJECT_DIR=$(pwd) bash .ax/scripts/bash/triage-search.sh --keywords "payment"
```

### `AGENTS.md` 가 인식 안 돼요
- AGENTS.md 파일이 프로젝트 루트에 있는지 확인 (`ls -la AGENTS.md`)
- OpenCode 가 ancestor 탐색 — git worktree root 가 OpenCode 가 보는 범위인지 확인
- `OPENCODE_DISABLE_CLAUDE_CODE_PROMPT=1` 설정 후 `~/.claude/CLAUDE.md` 가 충돌하는지 확인

### git pre-commit hook 이 안 돌아요
```bash
# wrapper 가 있는지
cat .git/hooks/pre-commit

# 실행권한
ls -l .git/hooks/pre-commit

# .ax/hooks/pre-commit 에 *.sh 있는지
ls .ax/hooks/pre-commit/
```

`grep -q goax-pre-commit-chain .git/hooks/pre-commit` 가 마커 검출에 사용돼요.

## 관련 룰

- `rules-tokens.md` — 룰 토큰 컨벤션
- `rule-enforcement.md` — `enforced_by` invariant (I1, I2, I5)
- `triage-matrix.md` — Size × Risk 매트릭스 + L3 정의
- `critical-rules.md` — universal CRITICAL 룰 목록
