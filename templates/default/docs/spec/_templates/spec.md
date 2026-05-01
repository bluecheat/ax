# Spec — <피처 이름>

> **이 문서가 SSOT (Single Source of Truth)예요.**
> plan.md / tasks.md / 구현 단계는 이 문서를 입력으로 공유해요.
> 코드와 spec이 다르면 spec이 맞다고 가정 — 코드를 spec에 맞춰요.

---

## 0. 메타

| 필드 | 값 |
|---|---|
| Spec ID | NNN-<slug> |
| 작성자 | <이름> |
| 작성일 | YYYY-MM-DD |
| 상태 | 초안 / 검토 중 / 승인 / 폐기 |
| 관련 ADR | docs/adr/NNNN-*.md (있으면) |
| Triage 결과 | size=L, risk=L2 (`goax triage` 출력 첨부) |

---

## 1. 무엇을 (What)

### 1.1 한 줄 정의
<무엇을 만들거나 바꾸는가 — 한 문장>

### 1.2 사용자 가치
<누가 / 어떤 상황에서 / 무엇을 얻는가>

### 1.3 MVP 경계 (NEEDS CLARIFICATION 마커 사용)
- [ ] 포함: <명확히 들어가는 것>
- [ ] **NEEDS CLARIFICATION**: <불확실한 것 — 결정 필요>
- [ ] 제외 (Out of scope): <이번 버전에서 안 다루는 것>

> NEEDS CLARIFICATION이 1개라도 남아있으면 `goax spec check`가 fail. 모두 해소 후 plan 단계로.

---

## 2. 왜 (Why)

### 2.1 문제
<지금 어떤 문제가 있는가>

### 2.2 안 만들면
<만들지 않을 때의 대가>

### 2.3 다른 대안
- A: <대안 A> — Pros/Cons → 채택 여부
- B: <대안 B> — Pros/Cons → 채택 여부

→ 거부된 대안은 반드시 ADR로 기록해 미래에 재제안 방지.

---

## 3. 성공 기준 (Acceptance Criteria)

측정 가능한 형태로:

- [ ] <기준 1 — Given/When/Then 또는 정량>
- [ ] <기준 2>
- [ ] <기준 3>

### 비기능 요구 (Non-functional)

| 항목 | 기준 |
|---|---|
| 성능 | <응답 시간·처리량> |
| 가용성 | <SLO> |
| 보안 | <인증·권한·데이터 처리> |
| 호환성 | <기존 시스템과의 backward compat> |

---

## 4. 사용자 시나리오 (User Scenarios)

```
시나리오 1: <성공 경로>
  주어진: <초기 상태>
  사용자가: <행동>
  결과: <기대 결과>

시나리오 2: <엣지 케이스>
  ...

시나리오 3: <실패 경로>
  ...
```

---

## 5. 도메인 / 데이터 (선택 — 클 때만)

데이터 모델이 복잡하면 [`data-model.md`](data-model.md)로 분리.

핵심 엔티티만 여기에:
- **<Entity>**: <의미>
- ...

---

## 6. 인터페이스 (선택 — API 있을 때)

API/이벤트가 있으면 [`contracts/`](contracts/) 디렉토리로:
- `contracts/api.yaml` (OpenAPI)
- `contracts/events.md` (이벤트 스키마)

핵심 endpoint만 여기에:
- `POST /v1/<resource>` — <목적>

---

## 7. 의존성 / 영향 범위

- **변경되는 모듈**: <module-a>, <module-b>
- **외부 의존성**: <DB·외부 API·큐 등>
- **호환성 영향**: <기존 사용자에게 미치는 영향>
- **운영 영향**: <인프라·모니터링·롤백>

---

## 8. 보류 (Open Questions)

→ NEEDS CLARIFICATION의 모음. 해소되면 §1.3에서 체크.

- [ ] **NEEDS CLARIFICATION**: <질문 1>
- [ ] **NEEDS CLARIFICATION**: <질문 2>

---

## 9. 변경 이력

| 날짜 | 변경 | 작성자 |
|---|---|---|
| YYYY-MM-DD | 초안 | <이름> |

---

## 다음 단계

- [ ] 모든 NEEDS CLARIFICATION 해소
- [ ] 검토자 승인
- [ ] [`plan.md`](plan.md) 작성 (HOW)
