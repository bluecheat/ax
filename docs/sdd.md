# SDD — Spec-Driven Development

> **코드보다 명세를 먼저.**
> goax의 Layer 3가 채택한 워크플로우예요. spec이 곧 *Single Source of Truth*.

---

## 왜 SDD인가

AI 에이전트한테 "결제 환불 정책을 7일에서 14일로 바꿔줘" 라고 던지면 위험해요:

- 모델이 임의로 해석해서 코드부터 만지기 시작
- 엣지 케이스(환불 진행 중인 주문은? 정산 영향은?)를 *작업 시작 후*에 발견
- 결정 근거가 없어서 다음 사람이 똑같이 고민

→ **spec.md를 먼저 채우면** 작업 시작 *전*에 모호함을 다 잡아요. 그리고 그 spec 이 tasks.md / 구현 단계의 *유일한 입력*이 돼요. 설계 결정의 *근거* 는 별도 ADR (`.ax/docs/adr/NNNN-*.md`) 가 담당해요.

---

## SSOT — Single Source of Truth

**spec.md = 진실의 출처**

```
spec.md (WHAT/WHY + Technical Context §7.5)
   ↓ 입력 (+ 관련 ADR — 설계 결정 근거)
tasks.md (작업 분해)
   ↓ 입력
구현 (코드)
```

이 흐름의 핵심 규칙:
- spec 과 코드가 다르면 → **spec 이 맞다고 가정**, 코드를 spec 에 맞춰요
- spec 이 바뀌면 → tasks 갱신 *필수*
- spec 없이 코드부터 짜는 건 → L 등급 이상 작업에서 차단
- 설계 결정 (왜 X 대신 Y) → ADR — spec 안에 우겨넣지 않아요 (0.1.16 plan.md 폐기 이후)

---

## NEEDS CLARIFICATION 게이팅

spec.md 안에 모호한 지점이 있으면 이렇게 적어둬요:

```markdown
## 1.3 MVP 경계
- [x] 포함: 7일 → 14일 환불 윈도우 변경
- [ ] **NEEDS CLARIFICATION**: 진행 중인 환불 요청은 새 윈도우 적용?
- [ ] **NEEDS CLARIFICATION**: 정산 배치 영향 범위?
- [ ] 제외: 부분 환불 정책 (별도 spec)
```

→ `goax spec check` 실행하면:
```
✗ 001-payment-refund-window
  ✗ NEEDS CLARIFICATION 미해소: 2건
  → 1개 오류 — implement 단계 차단
```

**모든 NEEDS CLARIFICATION + placeholder + 필수 섹션이 채워져야** tasks 단계로 (`check-spec-clarity.sh`).

---

## 흐름

### 1. Triage가 spec 권장

평소처럼 Claude Code에서 말하면:

```
"결제 환불 윈도우 7→14일로 바꾸는 작업 계획 세워줘"
```

triage가 자동으로:
- size=L, risk=L3 분류
- 📋 *"SPEC 우선 작성 권장"* 출력

### 2. spec 디렉토리 생성

```bash
goax spec new payment-refund-window
```

자동 생성 (tier=standard):
```
docs/spec/001-payment-refund-window/
├── spec.md      # 필수 — WHAT/WHY (SSOT) + Technical Context §7.5
└── tasks.md     # 필수 — 작업 분해 (acceptance ↔ task 매핑)
```

full tier 면 추가:
- `research.md` — 깊이 분석
- `data-model.md` — 데이터 스키마
- `contracts/api.yaml` / `contracts/events.md` — API/이벤트 spec
- `quickstart.md` — 사용 가이드
- ADR `.ax/docs/adr/NNNN-*.md` — 설계 결정 정규 기록 (full tier 권장)

lazy 추가:
- `checklists/requirements.md` — `add-spec-files.sh --add checklists`

### 3. spec.md 채우기

`_templates/spec.md`의 9개 섹션:

| § | 내용 | 핵심 |
|---|---|---|
| 0 | 메타 | spec ID / 작성자 / 상태 |
| 1 | 무엇 (What) | **MVP 경계** — 포함 / NEEDS CLARIFICATION / 제외 |
| 2 | 왜 (Why) | 문제 / 안 만들면 / 검토된 대안 |
| 3 | 성공 기준 | Given/When/Then 또는 정량 + 비기능 4종 |
| 4 | 사용자 시나리오 | 성공 / 엣지 / 실패 경로 |
| 5 | 도메인·데이터 | 복잡하면 data-model.md로 |
| 6 | 인터페이스 | API 있으면 contracts/로 |
| 7 | 의존성·영향 | 변경 모듈 / 외부 / 호환성 |
| 8 | Open Questions | NEEDS CLARIFICATION 모음 |
| 9 | 변경 이력 | |

### 4. spec check (게이팅 — `check-spec-clarity.sh`)

```bash
goax spec check
```

- ✗ NEEDS CLARIFICATION 1건 이상 → fail
- ✗ placeholder `<...>` 본문 잔존 → fail (표 셀·URL 화이트리스트)
- ✗ 필수 섹션 (§1.1 한 줄 정의 / §3 성공 기준 / §4 사용자 시나리오) 비어있음 → fail
- ✓ 셋 다 통과 → tasks 단계 진행 가능

### 5. tasks.md → 구현 (+ ADR 별도)

spec 이 통과되면:
- 설계 결정 — ADR `.ax/docs/adr/NNNN-*.md` 1 건 이상 (full tier / L≥L2 도메인 의무)
- `tasks.md` — 1\~3 파일 단위 task 분해, acceptance criteria 와 1:1 매핑
- 구현 — task 별 PR (또는 묶음 PR)

---

## ADR과의 차이

| | ADR | Spec |
|---|---|---|
| 무엇을 다루나 | *결정 근거* (왜 X 대신 Y) | *도메인 정의* (X는 무엇) |
| 시제 | 과거형 ("우리는 X를 채택했다") | 현재형 ("X는 Y이다") |
| 변경 빈도 | 낮음 (결정은 이력) | 중간 (도메인 진화) |
| 게이팅 | 없음 (참고 문서) | NEEDS CLARIFICATION 게이팅 |

**결합** (0.1.16):
spec.md 2️⃣ (거부된 대안) 은 *짧은 한 줄 요약* 만 두고, 결정 *근거* + Trade-offs + 거부된 옵션의 *왜* 는 ADR 이 단독으로 담당. plan.md 가 폐기되면서 spec ↔ ADR 의 역할 분리가 더 명확해졌어요.

---

## L 등급 이상에서 spec 우선의 이유

| 작업 | spec 필요? | 이유 |
|---|---|---|
| 한 줄 색상 변경 | ❌ | 모호함 거의 없음, 빠른 fix가 비용보다 큼 |
| 옵션 추가 (단일 도메인) | △ | spec 없이도 OK, 단 ADR로 결정 근거 |
| 결제 도메인 정책 변경 | ✅ | 엣지 케이스 / 정산 영향 / 멱등성 — spec으로 미리 잡기 |
| 신규 도메인 부트스트랩 | ✅ | 경계가 모호 → spec으로 정의 |
| 리팩토링 (P0) | ✅ | 단계 분할 + 회귀 영향 — tasks.md Phase 분해 + ADR 결정 근거 |

→ Triage L+ 자동 권장은 **이 표를 룰화**한 거예요.

---

## 안티 패턴

- spec 없이 코드부터 — 엣지 케이스가 PR 단계에서 발견되면 비용 ↑
- spec.md를 코드 변경 후에 작성 — SSOT 깨짐
- NEEDS CLARIFICATION을 우회하고 implement — 모호함이 코드로 들어감
- 설계 결정의 *근거* 를 spec 에 우겨넣기 — ADR 자리. spec 은 What/Why + Acceptance + Tech Context §7.5 만
- 환경 e2e·배포·모니터링을 tasks 의 정상 phase 에 박기 — 운영 활동은 spec 범위 밖

---

## CLI 빠른 참조

```bash
goax spec new <name>      # 디렉토리 + 4 필수 파일 자동 생성
goax spec check [<id>]    # NEEDS CLARIFICATION 게이팅
goax spec list            # 모든 spec + 상태 (🔵 NEEDS / 🟡 SPEC만 / 🟢 READY)
```

---

## 더

- 템플릿 본문: [`docs/_templates/spec/`](_templates/spec/)
- ADR template: [`docs/_templates/adr/0000-template.md`](_templates/adr/0000-template.md)
- 4 Layer 모델 전체: [`../CONCEPTS.md`](../CONCEPTS.md)
