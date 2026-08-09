# GOAX

<p align="center">
  <img src="goax_img.png" alt="GOAX — AX 4-Layer 하네스" width="640">
</p>

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)
[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-Plugin-D97757?logo=anthropic)](https://github.com/bluecheat/ax)
[![OpenCode Compatible](https://img.shields.io/badge/OpenCode-Compatible-blue)](https://opencode.ai/)
[![Lang](https://img.shields.io/badge/lang-English-blue.svg)](README.md)

> **AI 결과 일관성을 *환경*으로 통제해요.**
> 4계층 하네스 — Triage · Constitution · Module · Spec/ADR. Cross-cut — Spirit · Mistake Loop.

**프롬프트 말고 환경을 갖춰요.** plugin 설치 →  5분 onboarding 대화로 하네스 환경이 설치돼요. 단, *자동 마법*은 약속하지 않아요.

> **요구사항** — Claude Code CLI · OpenCode (Hybrid 호환). 호환 매트릭스는 [Multi-CLI 호환](#multi-cli-호환) 참고.

[Quick Start](#quick-start) · [Architecture](#architecture--at-a-glance) · [Spec Workflow](#spec-workflow--two-paths) · [Commands](#commands) · [Principles](#core-principles) · [More](#further-reading)

---

## Quick Start

**1. 설치** — Claude Code 안에서 두 줄:

```
/plugin marketplace add https://github.com/bluecheat/ax
/plugin install goax
```

**2. 도입** — 자연어로 호출해요:

```
"goax 도입해줘"
```

→ `up` 이 프로젝트를 분석하고 동의(Y/n) 를 받은 뒤 `.ax/` 를 설치해요 (~30초). 기존 자산이 있는 프로젝트면 5분짜리 onboarding 대화 (Q1–Q5) 가 이어져요. 자세한 흐름은 [`docs/up.md`](docs/up.md) 참고.

**3. 일상 사용** — 작업 의도를 자연어로 전달하면 모든 작업이 같은 진입점·같은 관문을 거쳐요:

```
"결제 환불 정책 변경 작업 계획 세워줘"
   → triage → spec tier 권장 → spirit·룰·페르소나 컨텍스트 주입
```

> OpenCode 사용자는 [Multi-CLI 호환](#multi-cli-호환) 참고.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Layer 0  Triage         작업 진입 시 의도 인터뷰 + Size × Risk 자동 분류 │
│                          + UserPromptSubmit nudge (idle 시 reminder) │
├─────────────────────────────────────────────────────────────────┤
│ Layer 1  Constitution    CLAUDE.md (root) — 간결                   │
│                          ## META (가드레일 4) + 시그널 + 비협상 룰   │
│                          🔴 CRITICAL / 🟡 MANDATORY / 🔵 CONVENTION │
├─────────────────────────────────────────────────────────────────┤
│ Layer 2  Module Rules    .ax/modules/<n>/rules.md                  │
│                          keywords frontmatter → triage 자동 grep 매칭 │
├─────────────────────────────────────────────────────────────────┤
│ Layer 3  Spec / ADR     .ax/docs/{spec, adr}/                     │
│                          SSOT, NEEDS CLARIFICATION 게이팅           │
└─────────────────────────────────────────────────────────────────┘
       ▲                                       ▲
       │ Cross-cut: Spirit                     │ Cross-cut: Mistake Loop
       │ .ax/spirit/{values, tone, rules}      │ .ax/mistakes/ — 수동 캡처 (mistake skill)
       │ → 모든 sub-agent 공통 태도              │ → /audit 심사 → 룰 승격

Sensors (결정론적):  .ax/hooks/{user-prompt, pre-bash, pre-edit, post-edit, pre-commit}/*.sh
Scripts (결정론적):   .ax/scripts/bash/*.sh — --json 표준
```

### Universal vs Project-Specific

GOAX 가 깔아주는 자산은 두 결로 나뉘어요:

| 결 | 사전 등록 (universal) | 사용자 동의 (project-specific) |
|---|---|---|
| **META** (사고 가드) | 핵심 가드레일 4원칙 — 모든 프로젝트 동일 | — |
| **CRITICAL hooks** | 파괴 명령 / 보호 경로 / Secrets / Hydration / Entity·SQL / Kotlin var | DDL 컨벤션·모듈 의존·테스트 프레임워크 → onboarding이 [지금 hook / 나중 TODO / 강등] 묻기 |
| **Behavioral** (Spirit) | `_templates/spirit/ops.md` SP-OPS-001–007 — opt-in 템플릿 (사용자가 명시적으로 `spirit/rules/` 으로 복사 후 활성화) | 카테고리별 추가 룰 |
| **Module rules** | — | `.ax/modules/<n>/rules.md` (Q2 매핑된 L2/L3 도메인만 stub) |

원칙: **검증된 universal best practice 는 사전 등록하고, 프로젝트 판단이 필요한 항목은 onboarding 에서 명시적으로 물어봐요.**

자세한 컨셉: [`CONCEPTS.md`](CONCEPTS.md)

---

## Spec Workflow — Two Paths

`spec` 스킬은 처음부터 모든 산출물을 다 만들지 않아요. triage 결과로 *딱 필요한 만큼*만 생성해요.

### Tier Matrix

| Tier | 산출물 | 적용 size × risk |
|---|---|---|
| **standard** | `spec.md` + `tasks.md` (2) | S/M/L × L0–L2 |
| **full** | + `research / data-model / quickstart / contracts` + ADR 동반 | L × L3 / XL × * |

### Fast Path — 한 번에

```
"spec 만들어줘 payment-refund — 풀패키지"
```

### Stepwise Path — 단계별로

```
"spec 만들어줘 payment-refund"   → spec.md + tasks.md
"tasks 분해"                      → tasks 분해 ([P] 병렬 마커)
"구현 시작"                       → tasks.md 순차 실행 + - [x] 마킹
# 설계 결정은 ADR (.ax/docs/adr/NNNN-*.md) 로
```

자연어 tier 변경: `"간단"` / `"tasks 까지"` → standard · `"풀패키지"` → full. 설계 결정은 별도 plan 파일 없이 ADR (`.ax/docs/adr/NNNN-*.md`) 에 기록해요.

---

## Commands

**모든 기능을 자연어로 호출해요.** 얇은 slash 래퍼들은 폐기됐고 `/goax` 인덱스 하나만 발견용 진입점으로 남아요. SKILL.md frontmatter 의 `description:` 키워드를 Claude Code · OpenCode 양쪽이 자동 라우팅으로 잡아줘요.

| 자연어 | 발동 skill |
|---|---|
| `/goax` | 인덱스 — 모든 트리거 한눈에 (유일하게 남은 slash 명령) |
| "goax 도입" / "goax 설치" | up → brownfield 면 자동 onboarding |
| "진단해줘" / "goax doctor" | doctor — 결손·drift 점검 |
| "rules 보여줘" | rules — Constitution + Spirit + Module 통합 인덱스 |
| "spec 만들어줘 — <slug>" | spec — tier-aware spec 디렉토리 생성 |
| "tasks 분해" | spec-tasks |
| "구현 시작" / "tasks 실행" | spec-implement |
| "spec 확인" | spec-validate — NEEDS CLARIFICATION 게이팅 |
| "구현해줘" / "고쳐줘" / "리팩토링" | triage — Size × Risk 30 초 분류 |
| "ADR 작성" / "결정 기록" | adr — 새 ADR 파일 |
| "spirit 점검" | spirit — frontmatter + 토큰 무결성 |
| "실수 기록해줘" / "mistake 박아줘" | mistake — 1 건 capture |
| "audit" / "실수 회고" | audit — Mistake Loop 심사·룰 승격 후보 |
| "/hud setup" / "statusline 활성화" | hud — Claude Code statusline (OpenCode 어댑터 추후) |

자동 라우팅이 안 잡히면 `/goax` 인덱스의 키워드를 그대로 쓰거나, Claude 가 `Skill goax:<name>` 으로 명시 호출하면 돼요.

---

## Core Principles

> **결정론적인 일은 스크립트가, 판단·인터랙션은 LLM이.**

- **결정론 bash 스크립트** (`.ax/scripts/bash/`) — `--json --dry-run --help` 표준, `[goax]` stderr prefix, exit 0/1/2 (graceful degradation). 전체 카탈로그는 [`templates/default/.ax/scripts/bash/README.md`](templates/default/.ax/scripts/bash/README.md) 참조.
- **`current-task.json`** — triage → spec → audit 사이 작업 컨텍스트 SSOT (LLM 재추론 X)
- **`_templates/.origin`** — 사용자 수정 vs plugin 출고본 sha 비교, drift는 doctor가 알려줘요. 자동 덮어쓰기 절대 X
- **얇은 wrapper SKILL.md** — 결정론 부분은 스크립트에 위임하고 SKILL 은 트리거·인터랙션·JSON 파싱만 담당해요

---

## What Gets Installed

`up` skill 이 사용자 프로젝트에 (동의 후):

```
your-project/
├── AGENTS.md                              # Layer 1 SSOT — multi-CLI Constitution
├── CLAUDE.md                              # @AGENTS.md alias — Claude Code 자동 인식
├── opencode.json                          # OpenCode config (OpenCode 환경 감지 시만)
├── .ax/
│   ├── spirit/{values, tone, README}.md   # Cross-cut Spirit (출고되는 3종; rules/ 는 사용자 큐레이션, ops.md 는 _templates/spirit/ 를 통한 opt-in)
│   ├── modules/                           # Layer 2 — 모듈별 도메인 룰 (인스턴스만)
│   │   ├── README.md
│   │   └── <module-name>/rules.md         # onboarding Q5가 L2/L3 도메인만 stub
│   ├── hooks/                             # Sensors (결정론)
│   │   ├── user-prompt/triage-nudge.sh    # idle phase 시 reminder (Claude Code 전용)
│   │   ├── pre-bash/{block-destructive,grep-on-commit}.sh
│   │   ├── pre-edit/{check-protected-paths,spirit-check,spirit-rules-inject}.sh
│   │   ├── pre-commit/{critical-rule-grep,check-mistake-secrets}.sh
│   │   └── post-edit/lint-changed.sh
│   ├── scripts/bash/*.sh                  # 결정론 도구 (--json 표준)
│   │   └── install-git-hooks.sh           # OpenCode mode — git pre-commit chain 설치
│   ├── _templates/                        # Layer 3 — 모든 template 한 곳
│   │   ├── adr/0000-template.md
│   │   └── spec/{spec, tasks, ...}.md  + .origin (drift sha)
│   ├── current-task.json                  # 작업 컨텍스트 SSOT
│   ├── config.yml                         # 도메인 위험도 + sensors.mode
│   ├── mistakes/                          # Cross-cut Mistake Loop
│   ├── version
│   └── docs/
│       ├── adr/                           # 실제 ADR (onboarding이 0001-goax-adoption.md 자동 생성)
│       ├── spec/                          # 실제 spec 디렉토리 (NNN-<slug>/)
│       └── reference/                     # 읽기 전용 reference 문서 7개 (plugin docs/reference/ 에서 복사)
└── .claude/
    └── settings.json                      # hooks 등록 (Claude Code 전용 — UserPromptSubmit + PreToolUse + PostToolUse)
```

**프로젝트 트리에 추가되는 건 위가 전부예요.** Claude Code 에서는 플러그인이 skills · commands · agents 를 자동으로 로드하고, OpenCode 에서는 `opencode.json` 의 `instructions:` 가 마크다운 자산을 system prompt 로 병합해요.

---

## Multi-CLI 호환

GOAX 는 Claude Code 플러그인으로 배포되지만, Hybrid 호환 레이어를 통해 OpenCode 환경도 함께 지원해요.

| 자산 | Claude Code | OpenCode | 비고 |
|---|---|---|---|
| `AGENTS.md` (Constitution SSOT) | ✅ `@AGENTS.md` import 체인 | ✅ 직접 인식 (우선순위 1) | multi-CLI SSOT |
| `CLAUDE.md` (alias) | ✅ 자동 | ✅ fallback | 1줄 `@AGENTS.md` import |
| Skills (`.claude/skills/*/SKILL.md`) | ✅ autorouting | ✅ 인식 ([docs](https://opencode.ai/docs/skills/)) | OpenCode [Issue #6177](https://github.com/sst/opencode/issues/6177) plural/singular 미스매치 잔존 |
| 결정론 bash (`.ax/scripts/bash/`) | ✅ Claude Code 호출 | ✅ `GOAX_PROJECT_DIR=$pwd` standalone | `--json --dry-run --help` CLI 무관 |
| Hooks — PreToolUse / PostToolUse | ✅ `.claude/settings.json` | ❌ 미지원 | OpenCode 는 TypeScript in-process plugin SDK 만 |
| Hooks — pre-commit | ✅ `grep-on-commit.sh` chain | ⚠️ `install-git-hooks.sh` (git native) | CATASTROPHIC + secrets 검출은 commit 시점에 보전 |
| Slash commands | ✅ `/goax` 인덱스 | ❌ `.claude/commands/` 미지원 ([Issue #6985](https://github.com/anomalyco/opencode/issues/6985)) | slash 래퍼 폐기 — 자연어만 |
| Mistake auto-capture (hook) | ✅ deprecated → 수동 | ❌ 수동만 | 두 CLI 모두 `/mistake` 사용자 호출 |
| HUD statusline | ✅ Claude Code spec | ⚠️ 어댑터 추후 | 현재 Claude Code 전용 |

### OpenCode 설치

OpenCode 에는 `/plugin` marketplace 가 없어서 vendoring 방식이에요:

```bash
git clone https://github.com/bluecheat/ax .ax-source && \
  cp -r .ax-source/templates/default/* . && \
  rm -rf .ax-source

bash .ax/scripts/bash/install-git-hooks.sh
```

`opencode.json.template` → `opencode.json` 으로 이름 바꾸면 OpenCode 가 `AGENTS.md` 를 system prompt 로 자동 병합해요.

### OpenCode 환경 노트

- Claude Code plugin 으로 깔았다면 `up` skill 이 `OPENCODE_CONFIG_DIR`, `.opencode/`, `~/.config/opencode/`, `command -v opencode` 로 자동 감지해서 위 vendoring 을 대신해줘요.
- `OPENCODE_DISABLE_CLAUDE_CODE=1` 등 모두 지원 — AGENTS.md 가 SSOT 라 어느 기본값이든 안전.
- Path-scoped Spirit rule inject (`spirit-rules-inject.sh`) 는 Claude Code 전용이에요. OpenCode 에서는 `AGENTS.md` 의 CONVENTION 섹션에 `@import` 으로 묶어서 universal 화해요.

전체 호환 디테일·트러블슈팅·TypeScript plugin 로드맵: [`docs/reference/opencode-compat.md`](docs/reference/opencode-compat.md).

---

## HUD — One-line Layer Status (fact-based)

statusline은 **단일 디자인** (preset 없음). 핵심 신호 셋만 한 줄로:

```
triage: M×L3 | harness: 🪐 | ☄3       ← task 있음
harness: 🪐 | ☄3                       ← task 없음 (idle)
```

### 신호 1 — `triage: <Size>×<Risk>` (color matrix)

현재 작업의 size·risk 를 색상으로 즉시 읽어낼 수 있어요:

- **Size**: S=dim · M=cyan · L=yellow · XL=red
- **Risk**: L0=dim · L1=green · L2=yellow · L3=red

16 개 매트릭스 조합 색이 모두 달라요.

### 신호 2 — `harness: <evolution>` (4계층 종합)

플러그인 4 계층의 활성도를 *우주 진화* 단계로 보여줘요:

| 활성 | 이모지 | 의미 | 색 |
|---|---|---|---|
| 0/4 | `·` | 특이점 (시작점) | dim |
| 1/4 | `✦` | 별 첫 빛 | yellow |
| 2/4 | `⭐` | 항성 형성 | yellow |
| 3/4 | `🌟` | 빛나는 별 | green |
| 4/4 | `🪐` | 우아한 행성 (완성) | cyan |

### 신호 3 — `☄<n>` (mistakes count)

mistakes 누적 개수예요. 우주 메타포를 유지해요 (혜성 = 충돌 사건):

- 0=dim · 1–4=plain · 5–9=yellow · 10+=red

### Live Refresh

statusline 은 *어시스턴트 메시지 직후* 에 자동으로 갱신돼요 (Claude Code 사양). idle 중에도 주기적 갱신을 원하면 `.claude/settings.json` 에 `refreshInterval` 을 추가해요:

```json
{
  "statusLine": {
    "type": "command",
    "command": ".ax/hud/statusline.sh",
    "refreshInterval": 5
  }
}
```

5 초마다 재실행해서 백그라운드 작업이 spec/tasks 진척을 갱신할 때 바로 반영돼요.

### How to Activate

```
/hud setup
```

또는 `.claude/settings.json` 에 `statusLine` 을 직접 추가해요. 다른 플러그인의 statusLine 과 충돌하면 `setup` 이 합치기 옵션을 제안해요.

---

## Updates

```
/plugin marketplace update goax
/plugin install goax
```

이게 다예요. 항상 최신 쓰면 돼요.

---

## Further Reading

- [`CONCEPTS.md`](CONCEPTS.md) — 설계 사상, 왜 이렇게 만들었나
- [`docs/sdd.md`](docs/sdd.md) — Spec-Driven Development
- [`docs/spirit.md`](docs/spirit.md) — Spirit 운영 가이드
- [`docs/skill-routing.md`](docs/skill-routing.md) — skill 라우팅 매트릭스
- [`docs/up.md`](docs/up.md) — Brownfield 도입 흐름
- [`changelog/0.1.0.md`](changelog/0.1.0.md) "설계 결정" — 거부된 대안 + 채택 이유 (옛 docs/adr/ 6건 통합)
- [`templates/default/.ax/scripts/bash/README.md`](templates/default/.ax/scripts/bash/README.md) — 결정론 스크립트 카탈로그 + `--json` 표준
- [`changelog/`](changelog/README.md) — 릴리스 기록 (사용자는 굳이 X)

---

## License

MIT License. See [`LICENSE`](LICENSE) for the full text.
