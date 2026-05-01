# goax

**AI 에이전트의 결과 일관성을 *환경*으로 통제하는 4-layer 하네스 프레임워크예요.**

같은 모델이라도 환경(룰·검증·실수 차단)에 따라 결과가 들쭉날쭉해요.
goax는 그 환경을 **4 Layer + 2 Cross-cut**으로 표준화해서 어떤 프로젝트에든 1분 안에 깔아요.

---

## 🏗️ goax의 핵심 — 4 Layer 모델

```
┌──────────────────────────────────────────────────────────────────────┐
│ Layer 0  ⚡ Triage         새 작업 진입 시 30초 안에 Size × Risk 라우팅 │
│                            → 자연어 매칭으로 자동 발동                 │
├──────────────────────────────────────────────────────────────────────┤
│ Layer 1  📜 Constitution    CLAUDE.md — 비협상 룰 (3~5개 핵심만)        │
│                            → 자동 차단 / 사람 승인 / 일반 가이드 3등급   │
├──────────────────────────────────────────────────────────────────────┤
│ Layer 2  📦 Module Rules    <module>/CLAUDE.md — 모듈/도메인별 룰       │
│                            → 모노레포에서 root 비대화 방지              │
├──────────────────────────────────────────────────────────────────────┤
│ Layer 3  📝 Spec / ADR      docs/spec/, docs/adr/ — SSOT 단일 진실      │
│                            → 결정 근거 + 거부된 대안 기록               │
└──────────────────────────────────────────────────────────────────────┘
        ▲                                                ▲
   ┌────┴────────────────┐                ┌──────────────┴────────────┐
   │ Cross-cut  Mistake  │                │ Cross-cut  Spirit          │
   │  Loop                │                │  .ax/spirit/{values,tone,  │
   │  같은 실수 반복 차단    │                │     rules}                 │
   │  코드가 아니라 환경 고침 │                │  모든 sub-agent 공통 태도   │
   └─────────────────────┘                └───────────────────────────┘
```

**왜 4 Layer로 나눴나** — Layer마다 *책임이 다르기 때문*.
- Layer 0은 *라우팅* (작은 일에 큰 컨텍스트 안 주기)
- Layer 1은 *비협상* (절대 위반 안 됨, 짧고 검출 가능)
- Layer 2는 *지역 룰* (그 모듈 안에서만)
- Layer 3은 *결정 근거* (왜 X 대신 Y인가)
- Cross-cut Spirit은 *공통 태도* (모든 persona가 같은 톤)
- Cross-cut Mistake Loop는 *환경 자가 진화* (같은 실수면 환경 고침)

→ 자세히: [`CONCEPTS.md`](CONCEPTS.md) ⭐

---

## 설치

```bash
curl -fsSL https://raw.githubusercontent.com/bluecheat/ax/main/install.sh | bash
```

→ `~/.goax/`에 클론, `~/.local/bin/goax` symlink. 어떤 프로젝트에서든 `goax` 명령 사용 가능.

---

## 사용 — 명령은 3개만 외워요

```bash
goax up        # 프로젝트에 깔기 (greenfield/brownfield 자동 감지)
goax doctor    # 상태 진단 + 다음 단계 친절히 안내 (어떤 템플릿으로 채울지)
goax update    # goax 자체 업데이트
```

그 외는 **자연어**로:

```
[Claude Code 안에서, 평소처럼]
"결제 환불 윈도우 7→14일로 바꾸는 작업 계획 세워줘"
   ↓
Claude Code가 triage skill을 자동 매칭
   ↓
- .ax/spirit/{values, tone, rules} 자동 주입
- domain_risk 매트릭스로 결제 = L3 자동 분류
- size=L, risk=L3 → 📋 SPEC 우선 작성 권장
   ↓
"결제 도메인이라 L3예요. 먼저 spec 작성이 안전해요. 같이 채울까요?"
```

→ 명시적 `goax triage`/`goax spec` 같은 명령은 거의 안 써도 돼요. doctor가 필요할 때 알아서 안내해요.

---

## 첫 30분 흐름

```bash
# 1) 설치
curl -fsSL https://raw.githubusercontent.com/bluecheat/ax/main/install.sh | bash

# 2) 프로젝트로 들어가서 한 번
cd ~/your-project
goax up                         # 자동 감지 + 4-phase
goax doctor                     # 다음 단계 안내

# 3) doctor가 알려주는 우선순위 따라가며 채우기:
#    - .ax/spirit/values.md (예시 그대로 OK, 우리 팀 가치 추가)
#    - CLAUDE.md 의 CRITICAL 룰 3~5개
#    - 첫 ADR 1개 (docs/adr/0001-*.md)
#    - 도메인 persona 1~2개

# 4) Claude Code 켜고 평소처럼 말하면 끝
#    "결제 환불 정책 변경 작업 계획 세워줘"
```

---

## 디렉토리 한 화면

```
your-project/
├── CLAUDE.md                       # Layer 1 — 핵심 비협상 룰 3~5개
├── docs/
│   ├── adr/                        # Layer 3 — 결정 근거
│   └── spec/
│       ├── _templates/             # SDD 템플릿 10종 (자동 깔림)
│       └── feature/NNN-<name>/     # 피처별 spec.md/plan.md/tasks.md
├── .claude/                        # Claude Code 표준 (자동 로드)
│   ├── skills/
│   │   ├── global/                 # triage·critical-rules·steering-loop
│   │   ├── personas/               # engineer-generalist + 사용자 추가
│   │   ├── workflows/              # adr-write
│   │   └── meta/                   # skill-audit·skill-creator
│   ├── agents/                     # evaluator(default) + architect(starter)
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

---

## SDD — Spec-Driven Development

**Triage가 size=L 이상 또는 risk=L2 이상으로 분류하면 spec 우선 작성 권장돼요.**

자세한 흐름: [`docs/sdd.md`](docs/sdd.md)

---

## 학습 경로

| 시간 | 무엇 |
|---|---|
| 5분 | 이 README + [`CONCEPTS.md`](CONCEPTS.md) §0\~§1 |
| 30분 | 위 + 실제 `goax up` 실행 + `goax doctor` 가이드 따라가기 |
| 1시간 | + [`docs/sdd.md`](docs/sdd.md) (SDD) + [`docs/spirit.md`](docs/spirit.md) |
| 깊이 | [`docs/reference/*`](docs/reference/) + [`docs/adr/*`](docs/adr/) |

---

## 호환성

- **Claude Code**: ✅ first-class — `.claude/skills/` 자동 매칭, `.claude/agents/` 인식
- **OS**: macOS / Linux (bash 4+). Windows는 WSL
- **의존성**: bash + git만. Node/Python/Docker 의존성 0
- **CI**: GitHub Actions (`.github/workflows/test.yml` 예시 포함)

---

## License

MIT — [`LICENSE`](LICENSE)
