# Changelog

## v0.1.0 — Initial release (이름: goax)

> AI 에이전트의 결과 일관성을 *환경*으로 통제하는 4-layer 하네스 프레임워크예요.
> bash + 마크다운만으로, 어떤 프로젝트에든 1분 안에 도입 가능해요.

### 4-Layer 모델

- **Layer 0 — Triage**: 새 작업 진입 시 30초 안에 Size×Risk 분류 → 자연어 매칭으로 자동 발동
- **Layer 1 — Constitution**: `CLAUDE.md` 비협상 룰 3\~5개 (CRITICAL/MANDATORY/CONVENTION 시그널)
- **Layer 2 — Module Rules**: 모노레포에서 모듈별 sub-CLAUDE.md
- **Layer 3 — Spec / ADR**: SSOT 기반 SDD 워크플로우 + 결정 근거 ADR
- **Cross-cut Spirit**: `.ax/spirit/{values, tone, rules}` — 모든 sub-agent 공통 태도
- **Cross-cut Mistake Loop**: `.ax/mistakes/` 캡처 → audit → 룰 승격 (코드 아니라 환경 고침)

### 명령어 — 메인 3개

```bash
goax up        # greenfield/brownfield 자동 감지 + 한 명령으로 셋업
goax doctor    # 상태 진단 + 다음 단계 친절히 안내
goax update    # goax 자체 업데이트
```

자연어 우선:
- 설치 후 Claude Code에서 "X 구현해줘", "Y 작업 계획" 등 평소처럼 말하면 triage skill이 자동 매칭
- spirit·룰·페르소나가 자동 주입

### Advanced (필요할 때 — doctor가 안내)

```bash
goax triage <설명>           Size×Risk 수동 분류
goax spec [new|check|list]   SDD — Spec-Driven Development (SSOT)
goax spirit [add|lint|status] Spirit 디렉토리 관리
goax rules [옵션]            룰 인덱스/검색 (토큰 기반)
goax find <token>            ID로 룰 + ADR 링크
goax audit                   mistakes 심사
```

### 주요 기능

#### Spec-Driven Development (SDD)

- `docs/spec/_templates/` — 10종 템플릿 (spec/plan/tasks/research/data-model/contracts/quickstart/checklists)
- **SSOT**: spec.md를 단일 진실로, plan/tasks가 spec을 *입력*으로 공유
- **NEEDS CLARIFICATION 게이팅**: 미해소 시 `spec check` fail
- Triage가 size=L+ 또는 risk=L2+ 분류 시 spec 우선 권장

#### Spirit (행동 정체성)

- `values.md` — 핵심 가치 (긍정 편향 금지·비판적 사고·자가 점검 등 default 7개)
- `tone.md` — `~해요 체` 강제 + 안티패턴
- `rules/<카테고리>.md` — 1 파일 = 1 카테고리 (security/naming/pr/testing/...)
- Triage가 spirit_context로 자동 주입

#### Brownfield 도입

- `goax up` 한 명령으로 4-phase: discover → plan(결정 4개) → apply → next
- 기존 자산(CLAUDE.md / 외부 spec / hooks / AI 리뷰) 자동 스캔
- adoption-plan.md 자동 생성 (휴리스틱 기반 룰 분류)
- warning 모드 시작 → 점진 fail 승격

#### Sensors / Hooks

- `pre-bash/block-destructive.sh` — `rm -rf` 등 파괴적 명령 자동 차단 (default)
- `pre-edit/check-protected-paths.sh` — 보호 경로 변경 감지 (default)
- `pre-commit/critical-rule-grep.sh` — CRITICAL 룰 정적 검출 (default)
- `post-edit/lint-changed.sh` — 변경 파일 lint (starter)
- `pre-edit/spirit-check.sh` — Spirit 변경 + 적용 룰 알림 (starter)

#### 룰 토큰 (사람과 grep 둘 다 1초)

- Constitution: `<scope>:<LEVEL>:<id>` (예: `AX:CRITICAL:001`)
- Spirit: `SP-<CATEGORY>-<id>` (예: `SP-SEC-001`)

### 디렉토리

```
your-project/
├── CLAUDE.md                       # Layer 1
├── docs/
│   ├── adr/                        # Layer 3 — 결정 근거
│   └── spec/
│       ├── _templates/             # 10 SDD 템플릿
│       └── feature/NNN-<name>/     # 피처별 spec
├── .claude/                        # Claude Code 표준 (자동 로드)
│   ├── skills/global/              # triage·critical-rules·steering-loop
│   ├── skills/personas/            # engineer-generalist (default)
│   ├── skills/workflows/           # adr-write
│   ├── skills/meta/                # skill-audit·skill-creator
│   ├── agents/evaluator.md         # default
│   └── settings.json               # hooks entry point
└── .ax/                            # goax 자체 자산
    ├── spirit/{values,tone,rules}/
    ├── hooks/
    ├── mistakes/
    ├── config.yml
    └── version
```

### Roadmap

- v0.2: `goax up --enforce <category>` 카테고리별 fail 승격
- v0.3: adoption-plan.md 머지 후 spirit/rules 자동 이동
- v0.4: Homebrew tap (Mac 친화) + Claude Code plugin 패키징
- v0.5: Spirit drift 정량 측정 (EMA + 코사인 유사도)
