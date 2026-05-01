# ax-first

> **AI Agent Harness Framework** — Guides + Sensors + Loop, packaged as a drop-in scaffold.
> Built by **당근 AX 플랫폼팀**. Inspired by `github/spec-kit` and the Anthropic *Custom Harness Architectures* paper.

---

> Repo: [`bluecheat/ax`](https://github.com/bluecheat/ax) · Framework name: `ax-first` (실행 파일 `ax-first`)

## TL;DR

```bash
# 1. 어떤 프로젝트에서든:
curl -fsSL https://raw.githubusercontent.com/bluecheat/ax/main/install.sh | bash

# 2. 적용:
ax-first init                  # 빈 프레임워크
ax-first init --preset ax      # 당근 AX팀 9 CRITICAL 룰 + 한국어 컨벤션 내장

# 3. 일상 사용 (Claude Code 안에서):
/triage 사용자 알림 비활성화 옵션 추가
/steering-audit
/adr-write payment-refund-window-extension
```

---

## 무엇이 들어가는가

`ax-first init`은 너의 프로젝트에 다음을 깔아준다:

```
your-project/
├── CLAUDE.md                         # Layer 1 Constitution (덮어쓰지 않음 — 병합 안내)
├── .claude/
│   ├── skills/
│   │   ├── _index.md                 # 작업 → skill 라우팅 표
│   │   └── global/
│   │       ├── triage/               # /triage Size×Risk 분류
│   │       ├── critical-rules/       # CRITICAL/MANDATORY/CONVENTION 시그널
│   │       └── steering-loop/        # /steering-audit
│   ├── agents/
│   │   ├── architect.md              # 아키텍처 위반 검토 sub-agent
│   │   └── evaluator.md              # PR 이전 인페런셜 리뷰
│   ├── hooks/                        # Sensors 자동화 (warning-only 시작)
│   │   ├── pre-bash/                 # rm -rf 등 파괴적 명령 차단
│   │   ├── pre-edit/                 # 보호 경로 검사
│   │   ├── post-edit/                # 변경 파일 lint
│   │   └── pre-commit/               # CRITICAL 룰 정적 검출
│   └── settings.json                 # hooks 등록
├── docs/adr/0000-template.md         # ADR 템플릿
└── .ax-first/
    ├── config.yml                    # 도메인 위험도 매트릭스 등 프로젝트 설정
    └── mistakes/                     # Mistake Loop 캡처 슬롯
```

---

## 4계층 모델 (한 화면)

```
Layer 0  Triage         /triage         작업 진입 시 Size×Risk 라우팅
Layer 1  Constitution   CLAUDE.md       비협상 룰 — CRITICAL/MANDATORY/CONVENTION
Layer 2  Module Rules   <module>/CLAUDE.md  도메인별 룰
Layer 3  Spec/ADR       docs/adr + spec/    결정 근거 + 도메인 진실
─ Cross  Mistake Loop   .ax-first/mistakes/ → /steering-audit → 룰 승격
```

자세히: [docs/concepts.md](docs/concepts.md)

---

## 명령어

| 명령 | 역할 |
|---|---|
| `ax-first init [--preset <name>]` | 현재 디렉토리에 하네스 골격 설치 |
| `ax-first triage <설명>` | 작업을 Size×Risk로 분류, 권장 경로 출력 |
| `ax-first audit` | `.ax-first/mistakes/`를 스캔해 룰 승격 후보 제시 |
| `ax-first doctor` | 현재 프로젝트의 하네스 상태 진단 (결손 항목 리포트) |
| `ax-first update` | submodule로 가져온 ax-first를 최신화 |

---

## Quick Win Checklist (init 후 첫날)

- [ ] `CLAUDE.md`의 CRITICAL 9개 중 우리 팀에 맞지 않는 것 삭제·교체
- [ ] `.ax-first/config.yml`의 `domain_risk` 매트릭스를 우리 도메인으로 갱신
- [ ] `.claude/hooks/`의 lint 명령을 우리 스택(ktlint? eslint? rustfmt?)에 맞춤
- [ ] `docs/adr/0001-*.md`로 첫 ADR 작성
- [ ] Claude Code에서 `/triage <첫 작업>`을 호출해 동작 검증

---

## Distribution Model — Bash + git submodule

`install.sh`은 두 가지 모드를 지원한다:

1. **standalone**: `~/.ax-first/`에 클론 후 `~/.local/bin/ax-first` symlink. 어떤 프로젝트에서든 `ax-first` 명령 사용 가능.
2. **submodule**: `git submodule add git@github.com:bluecheat/ax.git .ax-first-tool` — 프로젝트와 함께 ax-first 버전을 고정.

업데이트는 `ax-first update` 또는 `git submodule update --remote` 한 줄.

---

## Preset

| Preset | 설명 |
|---|---|
| `default` | 빈 프레임워크. CRITICAL/MANDATORY 자리만 비워둠 |
| `ax` | 당근 AX팀 권장 9 CRITICAL + 한국어 commit/PR 컨벤션 + ktlint·eslint·tsc 호환 hooks |

Preset은 마이그레이션이 아니라 overlay 방식 — 기본 템플릿 위에 preset 디렉토리를 덮어 쓴다.

---

## Status

- **v0.1** (2026-05-01) — init / triage / audit / doctor + default·ax preset
- **v0.2 (계획)** — `/steering-audit` 자동 룰 승격 PR 작성
- **v0.3 (계획)** — `evaluator` agent의 별도 Claude 세션 호출
- **v0.4 (계획)** — Tidy fail 모드 자동 전환 + 통계 대시보드

자세한 변경: [CHANGELOG.md](CHANGELOG.md)

---

## License

당근마켓 사내 사용 (Internal). 문의: AX 플랫폼팀 (stone@daangn.com).
