<div align="center">

# goax

**AI 에이전트의 결과 일관성을 *환경*으로 통제하는 4-Layer 하네스 프레임워크**

bash + 마크다운만으로, 어떤 프로젝트에든 1분 안에.

[Quick Start](#-quick-start) • [Concepts](CONCEPTS.md) • [SDD](docs/sdd.md) • [Spirit](docs/spirit.md) • [CLI](docs/spec/cli.md)

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![GitHub release](https://img.shields.io/github/v/release/bluecheat/ax?include_prereleases&label=release)](https://github.com/bluecheat/ax/releases)
[![Bash 4+](https://img.shields.io/badge/bash-4%2B-blue.svg)](#-호환성)
[![Zero deps](https://img.shields.io/badge/dependencies-zero-brightgreen.svg)](#-호환성)
[![Made for Claude Code](https://img.shields.io/badge/made%20for-Claude%20Code-7c3aed.svg)](https://docs.claude.com/en/docs/claude-code)

</div>

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
> Triage skill이 자동 매칭하고 Spirit 컨텍스트도 자동 주입돼요.

→ 4-Layer 모델·왜 이렇게 만들었나·출처는 모두 [`CONCEPTS.md`](CONCEPTS.md) 에 있어요.

---

## 🔑 명령

**메인 3개**만 외워도 충분해요.

```bash
goax up        # 프로젝트에 깔기 (greenfield/brownfield 자동 감지)
goax doctor    # 상태 진단 + 다음 단계 안내
goax update    # goax 자체 업데이트
```

그 외는 모두 **자연어**로 — Claude Code 안에서 평소처럼 말하면 Triage skill이 자동 매칭돼요. 명시 호출이 필요할 때 `goax doctor`가 어떤 명령을 쓸지 알려줘요.

| 명령 | 역할 |
|---|---|
| `goax triage <설명>` | Size×Risk 수동 분류 + 권장 경로 |
| `goax spec [new\|check\|list]` | SDD — Spec-Driven Development (SSOT) |
| `goax spirit [add\|lint\|status]` | Spirit 디렉토리 관리 |
| `goax rules [옵션]` | 룰 인덱스/검색 (Constitution + Spirit 토큰) |
| `goax find <token>` | ID로 룰 1개 + 본문 + 관련 ADR |
| `goax audit` | `.ax/mistakes/` 심사 + 룰 승격 후보 |

전체: [`docs/spec/cli.md`](docs/spec/cli.md)

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
    ├── spirit/{values, tone, rules/}    # cross-cutting 행동 정체성
    ├── hooks/                           # Sensors 자동화
    ├── mistakes/                        # Mistake Loop 캡처
    ├── config.yml                       # domain_risk · sensors · commands
    └── version
```

> **`.claude/`** = Claude Code 표준 위치 (자동 로드)
> **`.ax/`** = goax 자체 자산 — 결정 근거: [ADR-0002](docs/adr/0002-claude-vs-ax-directory-split.md)

---

## 📦 Distribution

| 모드 | 설명 |
|---|---|
| **standalone** *(default)* | `~/.goax/`에 클론 + `~/.local/bin/goax` symlink. 어떤 프로젝트에서든 명령 사용 |
| **submodule** | 프로젝트 안에 `.goax-tool/`로 버전 고정 |

```bash
# standalone (default)
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
| `starter` | 최소 가이드 (Spirit 7 카테고리, architect agent, post-edit lint) |

> Preset은 마이그레이션이 아니라 *overlay* — 기본 위에 덮어 써요. 자기 팀의 preset도 `templates/presets/<name>/`에 추가 가능해요.

---

## 🔧 호환성

- **Claude Code** — first-class. `.claude/skills/` 자동 매칭, `.claude/agents/` 인식
- **OS** — macOS / Linux (bash 4+). Windows는 WSL
- **의존성** — bash + git만. Node / Python / Docker 의존성 0
- **CI** — GitHub Actions 예시 포함 (`.github/workflows/test.yml`)

---

## 📖 더 읽기

| 문서 | 무엇 |
|---|---|
| [`CONCEPTS.md`](CONCEPTS.md) ⭐ | 14개 개념 카드 + 출처 + 학습 경로 (마스터 인덱스) |
| [`docs/sdd.md`](docs/sdd.md) | Spec-Driven Development 흐름 |
| [`docs/spirit.md`](docs/spirit.md) | Spirit 작성법 |
| [`docs/up.md`](docs/up.md) | Brownfield 도입 가이드 |
| [`docs/adr/`](docs/adr/) | 결정 근거 (ADR 4건) |
| [`CHANGELOG.md`](CHANGELOG.md) | 버전별 변경 + 검토 중 항목 |

---

## License

MIT — [`LICENSE`](LICENSE)
