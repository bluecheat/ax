# Skill Index

> Triage가 작업 분류 후 어떤 skill/agent를 호출할지 결정할 때 참조하는 라우팅 표.

## 그룹

| 그룹 | 용도 | 예 |
|---|---|---|
| `global/` | 전역 — 모든 작업 진입점 | triage, critical-rules, steering-loop |
| `personas/` | 도메인/역할 페르소나 | engineer-generalist, code-reviewer, bug-hunter, refactorer, (자기 도메인 추가) |
| `workflows/` | 일상 작업 절차 | adr-write |
| `meta/` | skill 자체를 다루는 도구 | skill-audit, skill-creator |
| `vendor/` | 외부 빌려온 룰셋 (자기 프로젝트로 추가, skills-lock.json 관리) | — |

## 라우팅 매트릭스

| 작업 유형 | 첫 호출 | 이어서 |
|---|---|---|
| 새 작업 (모든 시작) | **`triage`** | (분류 결과에 따라 다음 단계) |
| 한 줄 수정 (S, L0~L1) | `engineer-generalist` | (직접) → commit |
| 신규 기능 (M, L0~L1) | 도메인 persona OR `engineer-generalist` | tester(있으면) → commit |
| 버그 수정 | **`bug-hunter`** | (재현 → 가드 테스트 → fix) → commit |
| 리팩토링 | **`refactorer`** | (단계 분할) → commit |
| PR 리뷰만 | **`code-reviewer`** | (코드 작성 X, 비평만) |
| Cross-domain (L) | task-machine 류 → 다중 persona | adr-write → evaluator → commit |
| Cross-domain + 고위험 (L+L3) | adr-write 먼저 | task-machine → architect 게이트 → tester → evaluator → commit |
| 신규 도메인 부트스트랩 (XL) | adr-write | 단계 분할 → 단계당 PR |
| Skill 정리 | `meta/skill-audit` | (분기 1회) |
| 새 Skill 생성 | `meta/skill-creator` | (가이드 따라) |

## 한 폴더 = 한 의도 패턴 — 한 폴더 = 한 의도

각 SKILL.md의 `description`은 **트리거 키워드 5\~10개**를 포함. 다른 skill과 트리거 중복 검사.

큰 skill은 `<skill>/references/<topic>.md`로 분리 (현재: `triage/`, `steering-loop/`).

## 자기 프로젝트 맞춤화

1. **personas/** 에 자기 도메인 추가 — `payment-engineer`, `frontend-engineer` 등
2. **vendor/** 에 외부 룰셋 추가 (예: vercel-react-best-practices) → `skills-lock.json`로 잠금
3. **새 skill 만들 때** `meta/skill-creator/SKILL.md` 가이드 따르기

## v0.3 예고 — Spirit (`.ax/sp/`)

`.ax/sp/rules/` 디렉토리에 cross-cutting 공통 룰을 파일 단위로 던져넣으면 모든 skill/agent가 자동 로드. 자세히는 [`docs/spirit.md`](../../docs/spirit.md) 초안 참조.
