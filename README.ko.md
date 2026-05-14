# goax

<p align="center">
  <img src="goax_img.png" alt="goax — AX 4-Layer 하네스" width="640">
</p>

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)
[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-Plugin-D97757?logo=anthropic)](https://github.com/bluecheat/ax)
[![Lang](https://img.shields.io/badge/lang-English-blue.svg)](README.md)

> **AI 결과 일관성을 *환경*으로 통제해요.**
> 4계층 하네스 — Triage · Constitution · Module · Spec/ADR. Cross-cut — Spirit · Mistake Loop.

**프롬프트 말고 환경을 갖춰요.** plugin 설치 →  5분 onboarding 대화로 하네스 환경이 설치돼요. 단, *자동 마법*은 약속하지 않아요.

> **요구사항** — Claude Code CLI 환경

[Quick Start](#quick-start) · [Architecture](#architecture--at-a-glance) · [Spec Workflow](#spec-workflow--two-paths) · [Commands](#commands) · [Principles](#core-principles) · [More](#further-reading)

---

## Quick Start

**Step 1 — 설치**

Claude Code 안에서 *한 줄씩* 입력해요

```
/plugin marketplace add https://github.com/bluecheat/ax

/plugin install goax
```

**Step 2 — 도입**

자연어로 트리거.

```
"goax 도입해줘"
```

→ `up` skill 이 프로젝트를 분석하고 동의 프롬프트(Y/n) 후 `.ax/`를 깔아요(약 30초).
**brownfield**(기존 자산 있는 프로젝트)면 이어서 `onboarding`이 도메인·위험도·hooks 강도·외부 spec·Layer 활성화를 **Q1–Q5 5단계 대화**(체감 5분)로 같이 정리해요. 한 발화에 끝나는 *자동 마법*은 아니에요 — 의식적 결정을 받기 위한 흐름이에요.

**Step 3 — 일상 사용**

```
"결제 환불 정책 변경 작업 계획 세워줘"
   → triage → spec tier 권장 → spirit·룰·페르소나 컨텍스트 주입
```

골격이 갖춰지면 매 작업이 같은 진입점·같은 게이팅을 거쳐요.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Layer 0  Triage         작업 진입 시 의도 인터뷰 + Size × Risk 자동 분류 │
│                          + UserPromptSubmit nudge (idle 시 reminder) │
├─────────────────────────────────────────────────────────────────┤
│ Layer 1  Constitution    CLAUDE.md (root) — 얇음                   │
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
       │ .ax/spirit/{values, tone, rules}      │ .ax/mistakes/ — hook 자동 capture
       │ → 모든 sub-agent 공통 태도              │ → /audit 심사 → 룰 승격

Sensors (결정론적):  .ax/hooks/{user-prompt, pre-bash, pre-edit, post-edit, pre-commit}/*.sh
Scripts (결정론적):   .ax/scripts/bash/*.sh — --json 표준
```

### Universal vs Project-Specific

goax가 깔아주는 것은 두 결로 나뉘어요:

| 결 | 사전 등록 (universal) | 사용자 동의 (project-specific) |
|---|---|---|
| **META** (사고 가드) | 핵심 가드레일 4원칙 — 모든 프로젝트 동일 | — |
| **CRITICAL hooks** | 파괴 명령 / 보호 경로 / Secrets / Hydration / Entity·SQL / Kotlin var | DDL 컨벤션·모듈 의존·테스트 프레임워크 → onboarding이 [지금 hook / 나중 TODO / 강등] 묻기 |
| **Behavioral** (Spirit) | `_templates/spirit/ops.md` SP-OPS-001–007 — opt-in 템플릿 (사용자가 명시적으로 `spirit/rules/` 으로 복사 후 활성화) | 카테고리별 추가 룰 |
| **Module rules** | — | `.ax/modules/<n>/rules.md` (Q2 매핑된 L2/L3 도메인만 stub) |

원칙: **검증된 universal best practice는 사전 등록, 프로젝트 판단이 필요한 것은 onboarding이 명시적으로 묻기.**

자세한 컨셉: [`CONCEPTS.md`](CONCEPTS.md)

---

## Spec Workflow — Two Paths

`spec-new`는 처음부터 9개 파일을 다 만들지 않아요. triage 결과로 *딱 필요한 만큼*.

### Tier Matrix

| Tier | 산출물 | 적용 size × risk |
|---|---|---|
| **standard** | `spec.md` + `tasks.md` (2) | S/M/L × L0–L2 |
| **full** | + `research / data-model / quickstart / contracts` + ADR 동반 | L × L3 / XL × * |

### Fast Path — Single Command

```
/spec --tier full payment-refund
```

### Stepwise Path — Per-stage

```
/spec --tier standard payment-refund  → spec.md + tasks.md
/spec-tasks                                 → tasks 분해 ([P] 병렬 마커)
/spec-implement                             → tasks.md 순차 실행 + - [x] 마킹
# 설계 결정은 ADR (.ax/docs/adr/NNNN-*.md) 로
```

자연어 override: `"간단"` / `"tasks까지"` → standard · `"풀패키지"` → full. 설계 결정은 ADR (`.ax/docs/adr/NNNN-*.md`) 로 — 별도 plan 파일 X.

---

## Commands

### Slash Commands

| Command | 무엇을 | 자연어 별칭 |
|---|---|---|
| `/goax` | 도움말·인덱스 | — |
| `/doctor` | 결손 진단 + `_templates` drift | "진단해줘" |
| `/rules` | Constitution + Spirit + Module 통합 | "rules 보여줘" |
| `/spec` | tier-aware spec 생성 (한 번에) | "spec 만들어줘 — <slug>" |
| `/spec-tasks` | tasks.md 단계 | "tasks 분해" |
| `/spec-implement` | 순차 실행 + 체크리스트 마킹 | "구현 시작" |
| `/spec-validate` | NEEDS CLARIFICATION 게이팅 | "spec 확인" |
| `/audit` | Mistake Loop 캡처·심사·승격 | "audit", "또 그걸" |

### Natural Language Only (no slash command)

| 자연어 | 발동 skill |
|---|---|
| "goax 도입해줘" | up → onboarding (자동 위임) |
| "<작업> 계획 세워줘" | triage → spec-new (tier 자동 권장) |
| "spirit 점검" | spirit-check |
| "ADR 작성" | adr-write |
| "statusline 활성화" | hud setup |
| "실수 기록해줘" / "mistake 캡처" | mistake (audit 와 페어) |

---

## Core Principles

> **결정론적인 일은 스크립트가, 판단·인터랙션은 LLM이.**

- **결정론 bash 스크립트** (`.ax/scripts/bash/`) — `--json --dry-run --help` 표준, `[goax]` stderr prefix, exit 0/1/2 (graceful degradation). 전체 카탈로그는 [`templates/default/.ax/scripts/bash/README.md`](templates/default/.ax/scripts/bash/README.md) 참조.
- **`current-task.json`** — triage → spec → audit 사이 작업 컨텍스트 SSOT (LLM 재추론 X)
- **`_templates/.origin`** — 사용자 수정 vs plugin 출고본 sha 비교, drift는 doctor가 알려줘요. 자동 덮어쓰기 절대 X
- **thin wrapper SKILL.md** — 결정론 부분 스크립트 위임. SKILL은 트리거·인터랙션·JSON 파싱만

---

## What Gets Installed

`up` skill 이 사용자 프로젝트에 (동의 후):

```
your-project/
├── CLAUDE.md                              # Layer 1 (기존 있으면 .suggested)
├── .ax/
│   ├── spirit/{values, tone, rules}/      # Cross-cut Spirit (ops.md 포함)
│   ├── modules/                           # Layer 2 — 모듈별 도메인 룰 (인스턴스만)
│   │   ├── README.md
│   │   └── <module-name>/rules.md         # onboarding Q5가 L2/L3 도메인만 stub
│   ├── hooks/                             # Sensors (결정론)
│   │   ├── user-prompt/triage-nudge.sh    # idle phase 시 reminder
│   │   ├── pre-bash/{block-destructive,grep-on-commit}.sh
│   │   ├── pre-edit/{check-protected-paths,spirit-check,spirit-rules-inject}.sh
│   │   ├── pre-commit/critical-rule-grep.sh
│   │   └── post-edit/lint-changed.sh
│   ├── scripts/bash/*.sh                  # 결정론 도구 (--json 표준)
│   ├── current-task.json                  # 작업 컨텍스트 SSOT
│   ├── config.yml                         # 도메인 위험도 + sensors.mode
│   ├── mistakes/                          # Cross-cut Mistake Loop (hook 자동 capture)
│   ├── version
│   └── docs/
│       ├── _templates/                    # Layer 3 — 모든 template 한 곳
│       │   ├── adr/0000-template.md
│       │   └── spec/{spec, tasks, ...}.md  + .origin (drift sha)
│       ├── adr/                           # 실제 ADR (onboarding이 0001-goax-adoption.md 자동 생성)
│       └── spec/                          # 실제 spec 디렉토리 (NNN-<slug>/)
└── .claude/
    └── settings.json                      # hooks 등록 (UserPromptSubmit + PreToolUse + PostToolUse)
```

**프로젝트 트리에 추가되는 건 위가 전부예요.** skills · commands · agents는 plugin이 자동 로드.

---

## HUD — One-line Layer Status (fact-based)

statusline은 **단일 디자인** (preset 없음). 핵심 신호 셋만 한 줄로:

```
triage: M×L3 | harness: 🪐 | ☄3       ← task 있음
harness: 🪐 | ☄3                       ← task 없음 (idle)
```

### 신호 1 — `triage: <Size>×<Risk>` (color matrix)

현재 작업 size·risk를 색상으로 즉시 인지:

- **Size**: S=dim · M=cyan · L=yellow · XL=red
- **Risk**: L0=dim · L1=green · L2=yellow · L3=red

16개 매트릭스 조합 색이 모두 다름.

### 신호 2 — `harness: <evolution>` (4계층 종합)

plugin 4계층 활성도가 *우주 진화* 단계로:

| 활성 | 이모지 | 의미 | 색 |
|---|---|---|---|
| 0/4 | `·` | 특이점 (시작점) | dim |
| 1/4 | `✦` | 별 첫 빛 | yellow |
| 2/4 | `⭐` | 항성 형성 | yellow |
| 3/4 | `🌟` | 빛나는 별 | green |
| 4/4 | `🪐` | 우아한 행성 (완성) | cyan |

### 신호 3 — `☄<n>` (mistakes count)

mistakes 누적 수. 우주 메타포 일관 (혜성 = 충돌 사건):

- 0=dim · 1–4=plain · 5–9=yellow · 10+=red

### Live Refresh

statusline은 *어시스턴트 메시지 후*에 자동 갱신 (Claude Code 사양). idle 중에도 주기적 갱신 원하면 `.claude/settings.json`에 `refreshInterval` 추가:

```json
{
  "statusLine": {
    "type": "command",
    "command": ".ax/hud/statusline.sh",
    "refreshInterval": 5
  }
}
```

5초마다 재실행 — 백그라운드 작업이 spec/tasks 진척을 갱신할 때 즉시 반영.

### How to Activate

```
/hud setup
```

또는 `.claude/settings.json`에 `statusLine` 직접 추가. 다른 plugin statusLine과 충돌 시 `setup`이 합치기 옵션 제시.

---

## Updates

```
/plugin marketplace update goax
/plugin install goax
```

이게 다예요. 항상 최신 쓰면 돼요.

---

## Further Reading

- [`CONCEPTS.md`](CONCEPTS.md) — 14개 핵심 개념 카드 (왜 이렇게 만들었나)
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
