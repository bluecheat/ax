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
| **META** (사고 가드) | Triage First (lean — 일반 행동 원칙은 opt-in `_templates/spirit/behavioral-baseline.md`) | — |
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
"구현 시작"                       → tasks.md 실행: 순차, 또는 레인 배정이 있으면 코디네이터 모드
                                  (lanes-dispatch.sh 원장) → 완료 게이트 G1~G6
                                  (L · M×L3 은 새 컨텍스트 evaluator 필수)
"레인 나눠줘"                     → lane — 가를 수 있는 일인지부터 판정
# 설계 결정은 ADR (.ax/docs/adr/NNNN-*.md) 로
```

자연어 tier 변경: `"간단"` / `"tasks 까지"` → standard · `"풀패키지"` → full. 설계 결정은 별도 plan 파일 없이 ADR (`.ax/docs/adr/NNNN-*.md`) 에 기록해요.

---

## Commands

**모든 기능을 자연어로 호출해요.** 얇은 slash 래퍼들은 폐기됐고 `/goax` 인덱스 하나만 발견용 진입점으로 남아요. SKILL.md frontmatter 의 `description:` 키워드를 Claude Code · OpenCode 양쪽이 자동 라우팅으로 잡아줘요.

| 자연어 | 발동 skill |
|---|---|
| `/goax` | 인덱스 — 모든 트리거 한눈에 (유일하게 남은 slash 명령) |
| "goax 도입" / "goax 설치" | up → brownfield 면 onboarding, greenfield 면 zero |
| "새 프로젝트 시작" / "0에서 만들자" | zero — 0→1 진입: 제품·비즈니스·ADR·집행 배관 |
| "goax 동봉" | vendor — plugin 없이 저장소에 동봉 |
| "진단해줘" / "goax doctor" | doctor — 결손·drift 점검 |
| "rules 보여줘" / "CRITICAL 룰만" | doctor → `rules-index.sh` — Constitution + Spirit + Module 통합 인덱스 |
| "spec 만들어줘 — <slug>" | spec — tier-aware spec 디렉토리 생성 |
| "tasks 분해" | spec-tasks |
| "병렬로 돌리자" / "레인 나눠줘" | lane — 가를 수 있는 일인지부터 판정 |
| "구현 시작" / "tasks 실행" | spec-implement |
| "spec 확인" | spec-validate — NEEDS CLARIFICATION 게이팅 |
| "구현해줘" / "고쳐줘" / "리팩토링" | triage — Size × Risk 30 초 분류 |
| "ADR 작성" / "결정 기록" | adr — 새 ADR 파일 |
| "spirit 점검" | doctor → `spirit-lint.sh` — 헤더 형식 · 토큰 중복 · placeholder |
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
- **축적 대신 재베이스라인** — 행동 스캐폴딩은 모델 세대마다 재베이스라인해요: frontier 모델은 lean 기본 (`model_tier: frontier`), 경량·타사 모델은 `.ax/_templates/spirit/behavioral-baseline.md` opt-in. 지시 복원은 실패가 실제로 재발할 때 항목 단위로만 (ablation 원칙) — 결정론(Sensors · Mistake Loop)은 이 감가상각의 예외예요

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

## HUD — 하네스 위치만 한 줄

statusline 은 **하네스 안에서 지금 어디인지**만 보여줘요. 모델·ctx%·에이전트 수·todo 는 OMC HUD 몫이고, 레인·게이트·경보는 skill 출력과 `doctor` 가 보여줘요.

```
[goax#0.5.1] | M×L2 · payment | spec ✓ › tasks ✓ › impl ● [######----]7/12 › review ○ | mistakes:3
```

| 조각 | 뜻 |
|---|---|
| `[goax#0.5.1]` | 설치된 버전. plugin 이 더 새로우면 `[goax#0.5.1] -> 0.5.2 goax up` |
| `M×L2 · payment` | triage 결과 (Size×Risk, 도메인). 활성 작업이 없으면 `idle` |
| `spec ✓ › tasks ✓ › impl ● 7/12 › review ○` | M 이상의 워크플로 체인. `✓` 완료 · `●` 진행 중 · `○` 남음. S 는 `즉시 작업`. full tier 는 `adr` 이 끼고, `review` 는 evaluator 가 필수일 때만 |
| `mistakes:3` | 실수 누적 수 (5 이상 노랑, 10 이상 빨강) |

프리셋은 OMC HUD 와 같은 이름이에요 — `minimal` / `focused`(기본) / `full`, `.ax/config.yml` 의 `hud.preset`. 스크립트는 파일만 읽어요(스크립트 호출 없음) — statusline 의 300ms 디바운스 안에 끝나요. 무거운 값은 `update-state.sh` 가 캐시하고 30분이 지나면 `(stale)` 을 붙여요.

활성화:

```
/hud setup
```

다른 statusline(예: OMC)이 이미 있으면 `setup` 이 stdin 을 **양쪽에** 먹이는 합성 스크립트를 제안해요 — 명령 두 개를 이어 붙이면 앞 명령이 stdin 을 다 먹어서 안 돼요.

## Updates

```
/plugin marketplace update goax
/plugin install goax
```

이게 다예요. 항상 최신 쓰면 돼요.

---

## 보안 모델

goax 는 **셸 스크립트를 저장소에 설치**하고 Claude Code hook 으로 등록해요. 여기서 두 가지가 따라오는데, 도입 전에 알고 계시는 게 좋아요.

**1. 훅은 안전망이지 보안 경계가 아니에요.**

훅들 (`block-destructive.sh`, `check-protected-paths.sh`, pre-commit chain) 은 bash 패턴 매칭이에요. **사고**를 잡으려고 만들었어요 — 에이전트나 사람이 실수로 파괴적인 일을 하는 상황이요. 우회하려는 상대를 막으려고 만든 게 **아니고**, 만들 수도 없어요. 셸 명령 문자열은 같은 동작을 무한히 다르게 쓸 수 있고, 훅이 보지 않는 경로 (`Edit` 대신 `sed -i`, `git commit --no-verify`, IDE 직접 편집) 로는 어떤 훅이든 비껴갈 수 있으니까요.

그래서 🔴 CRITICAL 은 *"사고로는 통과 못 함"* 으로 읽어야지 *"우회 불가"* 로 읽으면 안 돼요. 진짜 신뢰 경계가 필요하면 — 신뢰할 수 없는 코드 실행, 크레덴셜 격리 같은 — 훅이 아니라 샌드박스·권한 분리·CI 게이트로 해결하세요. goax 는 그걸 대체하지 않아요. 전체 계약은 [`docs/reference/rule-enforcement.md`](docs/reference/rule-enforcement.md) 에 있어요.

**2. `.ax/` 는 저장소를 따라다니는 실행 가능한 코드예요.**

`.ax/hooks/**/*.sh`, `.ax/scripts/bash/*.sh`, `.claude/settings.json` 은 커밋되는 걸 전제로 해요 — 그래야 팀 전체에서 하네스가 일관되니까요. 대신 이런 결과가 따라와요: **goax 를 쓰는 저장소를 clone 해서 Claude Code 로 열면, 그 저장소가 제공한 셸 스크립트가 실행돼요.** Claude Code 자체의 신뢰 프롬프트가 1차 관문이지만, 남의 `.ax/` 는 내가 안 쓴 저장소의 다른 실행 가능한 내용물과 똑같이 다루세요 — 신뢰하기 전에 읽어보시고요.

내 저장소에선 이게 바로 의도한 바예요. 하네스가 자기가 관장하는 코드와 같이 버전 관리되니까요. 외부에서 받은 저장소라면 diff 에서 `.ax/hooks/` 와 `.claude/settings.json` 을 확인하세요.

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
