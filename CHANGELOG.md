# Changelog

## v0.1.1 — goax up brownfield 재설계

### 핵심 변화

- **bash 휴리스틱 제거** — 기존 `goax up` brownfield 흐름의 "Q1\~Q4" 인터랙티브 + 도메인 정규식 추정은 noise(`ad`, `ba` 같은 prefix)만 만들어내고 모듈 의존을 못 읽었어요. 이를 **Claude에게 위임**으로 바꿨어요.
- **임시 onboarding skill** — brownfield 감지 시 `goax up`이 `.claude/skills/global/goax-onboarding/`에 skill을 임시 설치하고 `.ax/.onboarding-pending` 마커를 남겨요. 사용자가 Claude Code에서 `"goax 도입 마무리해줘"` 한 줄을 입력하면 skill이 발동해서 코드를 실제로 읽고 도메인·위험도·룰 분류를 사용자와 대화하며 진행해요. 끝나면 **skill 자체와 마커를 자가 삭제** — 프로젝트 트리에 잔재 0.
- **greenfield 영향 0** — 빈/신규 프로젝트는 onboarding skill이 설치되지 않아요.
- **CLI 비주얼 개선** — 박스 헤더, 색상, 구분선, 단계별 ✓ 표기. heredoc escape 버그 수정.

### Spirit §8 — 하네스 자가 점수

응답 prefix에 4계층 반영도를 표시해요: 😑(Layer 1↓) / 😀(2) / 🥰(3) / 🥳(4 + cross-cut).
`templates/default/.ax/spirit/values.md`와 `tone.md`에 룰 + 평가 항목 명시.

### Smoke 갱신

섹션 8을 새 흐름(brownfield 마커·skill 설치, greenfield 영향 0)에 맞게 재작성. 모두 통과.

---

## v0.1.0 — Initial release

> **AI 에이전트의 결과 일관성을 *환경*으로 통제하는 4-Layer 하네스 프레임워크.**
> bash + 마크다운만으로, 어떤 프로젝트에든 1분 안에 도입 가능해요.

기존 `ax-first` 프로토타입을 정리하고 `goax`라는 이름으로 첫 정식 릴리스를 냈어요.

### 4-Layer + 2 Cross-cut

- **Layer 0 — Triage** — 새 작업 진입 시 30초 안에 Size×Risk 분류. 자연어 매칭으로 Claude Code에서 자동 발동
- **Layer 1 — Constitution** — `CLAUDE.md` 비협상 룰 3~5개 (CRITICAL / MANDATORY / CONVENTION 시그널)
- **Layer 2 — Module Rules** — 모노레포의 모듈별 sub-CLAUDE.md
- **Layer 3 — Spec / ADR** — SSOT 기반 SDD 워크플로우 + 결정 근거 ADR
- **Cross-cut Spirit** — `.ax/spirit/{values, tone, rules}` — 모든 sub-agent 공통 태도
- **Cross-cut Mistake Loop** — `.ax/mistakes/` 캡처 → audit → 룰 승격 (코드 대신 환경 수정)

### 명령 — 메인 3개

```bash
goax up        # greenfield/brownfield 자동 감지 + 한 명령 셋업
goax doctor    # 상태 진단 + 다음 단계 안내
goax update    # goax 자체 업데이트
```

설치 후 Claude Code에서 평소처럼 자연어로 일하면 Triage skill이 자동 매칭돼요. Triage가 spirit · 룰 · 페르소나를 자동 주입해요.

### Advanced — `doctor`가 안내하는 명령

```
goax triage <설명>             Size×Risk 수동 분류
goax spec [new|check|list]    SDD — Spec-Driven Development (SSOT)
goax spirit [add|lint|status] Spirit 디렉토리 관리
goax rules [옵션]              룰 인덱스/검색 (토큰 기반)
goax find <token>             ID로 룰 1개 + 본문 + ADR 링크
goax audit                    .ax/mistakes/ 심사 + 룰 승격 후보
```

### 주요 기능

#### Spec-Driven Development (SDD)

- `docs/spec/_templates/` — **9종 템플릿** (`spec.md` / `plan.md` / `tasks.md` / `research.md` / `data-model.md` / `quickstart.md` + `checklists/requirements.md` + `contracts/api.yaml` + `contracts/events.md`)
- **SSOT** — `spec.md`가 단일 진실, `plan` / `tasks`는 spec을 *입력*으로 받음
- **NEEDS CLARIFICATION 게이팅** — 마커 1개라도 남으면 `goax spec check` fail
- Triage가 size=L+ 또는 risk=L2+ 분류 시 spec 우선 권장 흐름으로 안내

#### Spirit (행동 정체성)

- `values.md` — 핵심 가치 default 7개 (긍정 편향 금지 · 비판적 사고 · 결과→근거→다음 액션 · 추측 대신 질문 · 작은 단위 · 자가 점검 · 안전 우선) + 자가 점수 1개
- `tone.md` — `~해요 체` 강제 + 안티패턴
- `rules/<카테고리>.md` — 1 파일 = 1 카테고리 (security / naming / pr / testing / observability / concurrency / error-handling)
- Triage가 `spirit_context`로 자동 주입 — 누락 시 작업 차단 (fail)

#### Brownfield 도입

- `goax up` 한 명령으로 4-phase: **discover → plan(결정 4개) → apply → next**
- 기존 자산 자동 스캔 — CLAUDE.md / 외부 spec / hooks / AI 리뷰 / stack / 도메인
- `adoption-plan.md` 자동 생성 — 휴리스틱 기반 룰 분류 (CLAUDE.md → spirit 카테고리)
- `warning` 모드 시작 → 카테고리별 `fail` 점진 승격

#### Sensors / Hooks

- `pre-bash/block-destructive.sh` *(default)* — `rm -rf` 등 파괴적 명령 자동 차단
- `pre-edit/check-protected-paths.sh` *(default)* — 보호 경로 변경 감지
- `pre-commit/critical-rule-grep.sh` *(default)* — CRITICAL 룰 정적 검출
- `post-edit/lint-changed.sh` *(starter)* — 변경 파일 lint
- `pre-edit/spirit-check.sh` *(starter)* — Spirit 변경 + 적용 룰 알림

#### 룰 토큰 (사람과 grep 둘 다 1초)

- **Constitution** — `<scope>:<LEVEL>:<id>` (예: `AX:CRITICAL:001`)
- **Spirit** — `SP-<CATEGORY>-<id>` (예: `SP-SEC-001`)

### 디렉토리

```
your-project/
├── CLAUDE.md                       # Layer 1
├── docs/
│   ├── adr/                        # Layer 3 — 결정 근거
│   └── spec/
│       ├── _templates/             # SDD 템플릿 9종
│       └── feature/NNN-<name>/     # 피처별 spec
├── .claude/                        # Claude Code 표준 (자동 로드)
│   ├── skills/global/              # triage · critical-rules · steering-loop
│   ├── skills/personas/            # engineer-generalist (default)
│   ├── skills/workflows/           # adr-write
│   ├── skills/meta/                # skill-audit · skill-creator
│   ├── agents/evaluator.md         # default
│   └── settings.json               # hooks entry point
└── .ax/                            # goax 자체 자산
    ├── spirit/{values, tone, rules/}
    ├── hooks/
    ├── mistakes/
    ├── config.yml
    └── version
```

### ADR 4건 신설

- [`0001`](docs/adr/0001-four-layer-harness.md) — Four-layer harness 채택
- [`0002`](docs/adr/0002-claude-vs-ax-directory-split.md) — `.claude` vs `.ax` 디렉토리 분리
- [`0003`](docs/adr/0003-spirit-as-cross-cutting-layer.md) — Spirit을 cross-cutting 레이어로
- [`0004`](docs/adr/0004-rules-token-convention.md) — 룰 토큰 컨벤션

### 검토 중 (정식 약속 X)

- 카테고리별 `goax up --enforce <category>` — warning → fail 점진 승격
- `adoption-plan.md` 머지 후 `spirit/rules` 자동 이동
- `goax spec` ↔ `goax triage` 출력 연동 (size=L+ 자동 spec 권장)
- 패키징 옵션 (Homebrew tap / Claude Code plugin 등)
- Spirit drift 정량 측정 (EMA + 코사인 유사도 — SAFi 패턴)
