<div align="center">

# goax

**AI 에이전트의 결과 일관성을 *환경*으로 통제하는 4-Layer 하네스 프레임워크**

같은 모델이라도 환경(룰·검증·실수 차단)에 따라 결과가 달라져요.
goax는 그 환경을 **bash + 마크다운**만으로 어떤 프로젝트에든 1분 안에 깔아요.

[Quick Start](#-quick-start) • [Concepts](CONCEPTS.md) • [SDD](docs/sdd.md) • [Spirit](docs/spirit.md) • [CLI](docs/spec/cli.md) • [ADR](docs/adr/)

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![GitHub release](https://img.shields.io/github/v/release/bluecheat/ax?include_prereleases&label=release)](https://github.com/bluecheat/ax/releases)
[![Bash 4+](https://img.shields.io/badge/bash-4%2B-blue.svg)](#-호환성)
[![Zero deps](https://img.shields.io/badge/dependencies-zero-brightgreen.svg)](#-호환성)
[![Made for Claude Code](https://img.shields.io/badge/made%20for-Claude%20Code-7c3aed.svg)](https://docs.claude.com/en/docs/claude-code)

</div>

---

## 🎯 무엇을 푸는가

> **명제** — *"AI 결과 품질 차이는 Model이 아니라 Harness(환경)에서 나온다."*

`Agent = Model(두뇌) + Harness(환경)`. 우리가 통제할 수 있는 건 환경뿐이에요. goax는 그 환경을 5가지 표준 부품으로 만들어요.

| 부품 | 역할 | 어디 |
|---|---|---|
| **Triage** | 새 작업 진입 시 30초 안에 Size×Risk 분류 | `.claude/skills/global/triage/` |
| **Constitution** | 비협상 룰 3~5개 (자동 차단/사람 승인/일반 가이드) | `CLAUDE.md` |
| **Module Rules** | 모듈/도메인별 sub-CLAUDE.md (모노레포) | `<module>/CLAUDE.md` |
| **Spec / ADR** | SDD 워크플로우 + 결정 근거 | `docs/spec/`, `docs/adr/` |
| **Spirit** | 모든 sub-agent 공통 태도 (values/tone/rules) | `.ax/spirit/` |
| **Mistake Loop** | 같은 실수 반복 차단 — 코드 대신 환경을 고침 | `.ax/mistakes/` |

---

## 🚀 Quick Start

```bash
# 1) 설치 — 한 줄
curl -fsSL https://raw.githubusercontent.com/bluecheat/ax/main/install.sh | bash

# 2) 프로젝트로 들어가서 한 명령
cd ~/your-project
goax up                # greenfield → 즉시 골격 설치
                       # brownfield → 골격 + Claude Code 자연어 onboarding 위임

# 3) 상태 확인
goax doctor            # 결손 진단 + 다음 단계 체크리스트
```

> **이게 끝이에요.** 그 다음은 평소처럼 Claude Code에서 자연어로 일하면 돼요.
> Triage skill이 자연어 매칭으로 자동 발동하고, Spirit 컨텍스트도 자동 주입돼요.

---

## 🏗️ 4 Layer + 2 Cross-cut

```
┌──────────────────────────────────────────────────────────────────────┐
│ Layer 0  ⚡ Triage         새 작업 진입 시 30초 Size×Risk 라우팅       │
├──────────────────────────────────────────────────────────────────────┤
│ Layer 1  📜 Constitution    CLAUDE.md — 비협상 룰 3~5개               │
├──────────────────────────────────────────────────────────────────────┤
│ Layer 2  📦 Module Rules    <module>/CLAUDE.md — 모듈/도메인별 룰      │
├──────────────────────────────────────────────────────────────────────┤
│ Layer 3  📝 Spec / ADR      docs/spec, docs/adr — SSOT + 결정 근거    │
└──────────────────────────────────────────────────────────────────────┘
        ▲                                                ▲
   ┌────┴───────────────┐                ┌──────────────┴──────────────┐
   │ ✋ Mistake Loop     │                │ 🌟 Spirit                    │
   │  같은 실수 반복 차단  │                │  values · tone · rules       │
   │  코드 대신 환경 수정  │                │  모든 sub-agent 공통 태도     │
   └─────────────────────┘                └─────────────────────────────┘
```

**왜 5개로 쪼갰나** — 책임이 다르기 때문에.

- **Layer 0**은 *라우팅* — 작은 일에 큰 컨텍스트 안 주기
- **Layer 1**은 *비협상* — 절대 위반 안 됨, 짧고 검출 가능
- **Layer 2**는 *지역 룰* — 그 모듈 안에서만 유효
- **Layer 3**은 *결정 근거* — 왜 X 대신 Y인가
- **Spirit**은 *공통 태도* — 모든 persona가 같은 톤
- **Mistake Loop**은 *환경 자가 진화* — 같은 실수면 환경을 고침

→ 자세히는 [`CONCEPTS.md`](CONCEPTS.md) ⭐

---

## 🔑 명령은 3개만 외워요

```bash
goax up        # 프로젝트에 깔기 (greenfield/brownfield 자동 감지)
goax doctor    # 상태 진단 + 다음 단계 안내
goax update    # goax 자체 업데이트
```

그 외는 **자연어**로 — Claude Code 안에서 평소처럼 말하면 돼요.

```
"결제 환불 윈도우를 7일에서 14일로 바꾸는 작업 계획 세워줘"
   ↓
Claude Code가 triage skill 자동 매칭
   ↓
- .ax/spirit/{values, tone, rules} 자동 주입
- domain_risk 매트릭스로 결제 = L3 자동 분류
- size=L, risk=L3 → SPEC 우선 작성 권장 흐름으로 안내
   ↓
"결제 도메인이라 L3예요. 먼저 spec 작성이 안전해요. 같이 채울까요?"
```

> **Note:** 명시적 `goax triage` / `goax spec` 호출은 거의 안 써도 돼요. 필요할 때 `goax doctor` 한 번 돌리면 어떤 명령을 써야 할지 알려줘요.

### Advanced — `doctor`가 안내하는 명령들

| 명령 | 역할 |
|---|---|
| `goax triage <설명>` | Size×Risk 수동 분류 + 권장 경로 출력 |
| `goax spec [new\|check\|list]` | SDD — Spec-Driven Development (SSOT) |
| `goax spirit [add\|lint\|status]` | Spirit 디렉토리 관리 |
| `goax rules [옵션]` | 룰 인덱스/검색 (Constitution + Spirit 토큰) |
| `goax find <token>` | ID로 룰 1개 + 본문 + 관련 ADR |
| `goax audit` | `.ax/mistakes/` 심사 + 룰 승격 후보 |

전체 CLI: [`docs/spec/cli.md`](docs/spec/cli.md)

---

## 📂 디렉토리 한 화면

```
your-project/
├── CLAUDE.md                       # Layer 1 — 핵심 비협상 룰 3~5개
├── docs/
│   ├── adr/                        # Layer 3 — 결정 근거
│   └── spec/
│       ├── _templates/             # SDD 템플릿 9종 (자동 깔림)
│       └── feature/NNN-<name>/     # 피처별 spec.md/plan.md/tasks.md
├── .claude/                        # Claude Code 표준 (자동 로드)
│   ├── skills/
│   │   ├── global/                 # triage · critical-rules · steering-loop
│   │   ├── personas/               # engineer-generalist + 사용자 추가
│   │   ├── workflows/              # adr-write
│   │   └── meta/                   # skill-audit · skill-creator
│   ├── agents/                     # evaluator (default)
│   └── settings.json               # hooks entry point
└── .ax/                            # goax 자체 자산
    ├── spirit/                     # cross-cutting 행동 정체성
    │   ├── values.md / tone.md
    │   └── rules/<category>.md
    ├── hooks/                      # Sensors 자동화
    ├── mistakes/                   # Mistake Loop 캡처
    ├── config.yml                  # domain_risk · sensors · commands
    └── version
```

> **`.claude/`** = Claude Code 표준 위치 (자동 로드 — slash command 매칭, sub-agent 인식)
> **`.ax/`** = goax 자체 자산 (Claude Code 표준 외 — spirit, hooks 스크립트, mistakes, config)
> 결정 근거: [ADR-0002](docs/adr/0002-claude-vs-ax-directory-split.md)

---

## ✨ 주요 기능

### 📋 Spec-Driven Development (SDD)

> **코드보다 명세를 먼저.** spec.md = 단일 진실, plan/tasks는 spec을 입력으로 받아요.

- `docs/spec/_templates/` — **9종 템플릿** (spec/plan/tasks/research/data-model/quickstart + checklists/requirements + contracts/api + contracts/events)
- `goax spec new <name>` — 새 피처 디렉토리 + 필수 4종(spec/plan/tasks/checklists) 자동 복사
- `goax spec check` — `NEEDS CLARIFICATION` 마커 1개라도 남으면 fail (게이팅)
- `goax spec list` — 모든 spec 상태별 목록 (🔵 NEEDS / 🟡 SPEC만 / 🟢 READY)

자세히: [`docs/sdd.md`](docs/sdd.md)

### 🌟 Spirit — 행동 정체성 레이어

> **여러 sub-agent가 다른 역할을 맡아도, 결과물은 한 팀에서 나온 것처럼.**

- `values.md` — 핵심 가치 7개 (긍정 편향 금지·비판적 사고·자가 점검 등)
- `tone.md` — `~해요 체` 강제 + 안티패턴
- `rules/<카테고리>.md` — 1 파일 = 1 카테고리 (security/naming/pr/testing/...)
- Triage가 `spirit_context`로 자동 주입 — 누락 시 작업 차단

자세히: [`docs/spirit.md`](docs/spirit.md)

### 🌱 Brownfield 도입 (한 명령)

> **이미 운영 중인 프로젝트에도 점진적으로 도입할 수 있어요.**

- `goax up` 한 명령으로 4-phase: **discover → plan(Q1~Q4) → apply → next**
- 기존 자산 자동 스캔 — CLAUDE.md, 외부 spec, hooks, AI 리뷰, stack, 도메인
- `adoption-plan.md` 자동 생성 — 휴리스틱 기반 룰 분류
- `warning` 모드부터 시작 → 카테고리별 `fail` 점진 승격

자세히: [`docs/up.md`](docs/up.md)

### 🛡️ Sensors / Hooks

| Hook | 시점 | 기본 |
|---|---|---|
| `pre-bash/block-destructive.sh` | bash 호출 전 | `rm -rf` 등 파괴적 명령 차단 |
| `pre-edit/check-protected-paths.sh` | edit 전 | 보호 경로 변경 감지 |
| `pre-commit/critical-rule-grep.sh` | commit 전 | CRITICAL 룰 정적 검출 |
| `post-edit/lint-changed.sh` *(starter)* | edit 후 | 변경 파일 lint |
| `pre-edit/spirit-check.sh` *(starter)* | edit 전 | Spirit 적용 룰 알림 |

### 🏷️ 룰 토큰 — 사람과 grep 둘 다 1초

```
🔴 `AX:CRITICAL:001`     ← Constitution (CLAUDE.md, <scope>:<LEVEL>:<id>)
🟡 `payment:MANDATORY:003`
🔵 `AX:CONVENTION:008`

SP-SEC-001               ← Spirit (rules/<category>.md, SP-<CAT>-<id>)
SP-NAMING-007
SP-PR-002
```

`goax rules` / `goax find <token>` 으로 통합 인덱싱·검색.

---

## 🎓 학습 경로

| 시간 | 무엇을 |
|---|---|
| **5분** | 이 README + [`CONCEPTS.md`](CONCEPTS.md) §0~§1 (다이어그램) |
| **30분** | 위 + 실제 `goax up` 실행 + `goax doctor`가 알려주는 체크리스트 따라가기 |
| **1시간** | + [`docs/sdd.md`](docs/sdd.md) (SDD) + [`docs/spirit.md`](docs/spirit.md) (Spirit 작성법) |
| **깊이** | [`docs/reference/*`](docs/reference/) + [`docs/adr/*`](docs/adr/) |

---

## 📦 Distribution Modes

`install.sh`은 두 가지 모드를 지원해요:

| 모드 | 설명 |
|---|---|
| **standalone** *(default)* | `~/.goax/`에 클론 + `~/.local/bin/goax` symlink. 어떤 프로젝트에서든 명령 사용 |
| **submodule** | 프로젝트 안에 `.goax-tool/`로 버전 고정 |

```bash
# standalone
curl -fsSL https://raw.githubusercontent.com/bluecheat/ax/main/install.sh | bash

# submodule
curl -fsSL https://raw.githubusercontent.com/bluecheat/ax/main/install.sh | bash -s -- --mode submodule
```

업데이트는 `goax update` 또는 `git submodule update --remote`.

---

## 🎨 Presets

| Preset | 설명 |
|---|---|
| `default` | 빈 프레임워크. 핵심 자리만 비워두고 사용자가 채움 |
| `starter` | 모든 프로젝트에 공통적으로 유용한 최소 가이드 (Spirit 7개 카테고리, architect agent, post-edit lint) |

> **Note:** Preset은 마이그레이션이 아니라 *overlay*. 기본 위에 덮어 써요. 자기 팀의 preset도 `templates/presets/<name>/`에 직접 추가 가능해요.

---

## 🔧 호환성

- **Claude Code** — first-class. `.claude/skills/` 자동 매칭, `.claude/agents/` 인식, hooks entry point 표준 사용
- **OS** — macOS / Linux (bash 4+). Windows는 WSL
- **의존성** — bash + git만. Node / Python / Docker 의존성 0
- **CI** — GitHub Actions (`.github/workflows/test.yml` 예시 포함)

---

## 🗺️ Roadmap

본 v0.1.0 정식 릴리스 이후 검토 중인 항목:

- 카테고리별 `goax up --enforce <category>` — warning → fail 점진 승격
- `adoption-plan.md` 머지 후 `spirit/rules` 자동 이동
- `goax spec` ↔ `goax triage` 출력 연동 (size=L+ 자동 spec 권장)
- 패키징 옵션 검토 (Homebrew tap / Claude Code plugin 등)
- Spirit drift 정량 측정 (EMA + 코사인 유사도 — SAFi 패턴)

세부는 [CHANGELOG.md](CHANGELOG.md) 참조.

---

## 📚 References

goax는 다음 자료의 *개념*을 차용·통합·확장한 결과예요. 본 레포에 원문이 포함된 것은 없고, 모두 [`CONCEPTS.md §5`](CONCEPTS.md)에 발췌·재구성돼 있어요.

- *Custom Harness Architectures for AI-Assisted Development* (사내 엔지니어링 표준 자료, 4페이지 PDF)
- [github/spec-kit](https://github.com/github/spec-kit) — `.specify/` 파일 구조 패턴
- [Karpathy skills](https://github.com/forrestchang/andrej-karpathy-skills) — "한 폴더 = 한 의도" persona 패턴
- Project ANIMA — SOUL/BRAIN/SPIRIT 3분법
- SAFi (Self-Alignment Framework Interface) — Spirit drift 수학적 측정 개념

---

## License

MIT — [`LICENSE`](LICENSE)

<div align="center">

Made with ⚡ for AI-assisted development

</div>
