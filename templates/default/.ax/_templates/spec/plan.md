# Plan — <피처 이름>

> spec.md(WHAT/WHY)를 받아 *어떻게* 만들지 기술 계획을 세워요.
> 이 문서는 spec.md를 *유일한 입력*으로 가정해요. spec이 바뀌면 plan도 갱신.

---

## 0. 입력

- **Spec**: [`spec.md`](spec.md) (vNNN — 마지막 갱신일)
- **관련 ADR**: docs/adr/NNNN-*.md
- **Constitution 영향**: <CRITICAL 룰 중 이 작업에 적용되는 것 ID 나열 — 예: `AX:CRITICAL:001`>

---

## 1. 아키텍처 결정

### 1.1 시스템 위치
<어느 모듈/서비스에서 작동? 신규? 기존 확장?>

### 1.2 핵심 패턴
- **데이터 흐름**: <Request → A → B → DB → Response>
- **레이어 위치**: <Application / Adapter / Domain — Clean Arch면>
- **트랜잭션 경계**: <어디서 트랜잭션 시작/종료>

### 1.3 거부된 패턴
spec.md 2️⃣.3에서 거부된 대안 + 그 이유. ADR-NNNN로 기록.

---

## 2. 구현 단계 (Phases)

큰 작업은 단계로 분할 — 각 단계는 독립 PR + 테스트 통과:

### Phase 1: <단계 이름>
- 변경 파일: <files>
- 추가 의존성: <libs>
- 테스트: <unit/integration/e2e>
- 위험: <낮음/중간/높음>

### Phase 2: ...

---

## 3. 데이터 변경

### 3.1 스키마 변경
- DDL: `migrations/V<UTC>__*.sql`
- 마이그레이션 전략: <inline / 백필 / dual-write>
- 롤백: <롤백 가능 여부 + 절차>

### 3.2 데이터 백필
<있다면 — batch / streaming / 온라인>

---

## 4. 검증 전략

- [ ] **단위 테스트**: <어디>
- [ ] **통합 테스트**: <어디> (Spring `@SpringBootTest` 류는 `@Tag("integration")` 필수)
- [ ] **E2E**: <필요하면>
- [ ] **부하 테스트**: <risk≥L2 시 traffic estimation>
- [ ] **수동 QA**: <필요하면>

`acceptance criteria` (spec.md 3️⃣) 의 각 항목이 어느 테스트로 검증되는지 매핑.

---

## 5. 롤아웃

- [ ] **feature flag**: <쓰는가>
- [ ] **점진 노출**: <0% → 1% → 10% → 100%>
- [ ] **모니터링**: <어떤 메트릭/알람>
- [ ] **롤백 트리거**: <메트릭 임계치>

---

## 6. 의존성·인터페이스 외부 변경

- **다른 팀에 영향**: <있다면>
- **breaking change**: <있다면 ADR 필수>
- **버전·deprecation**: <필요하면>

---

## 7. 추정·일정

| 단계 | 추정 | 완료 기준 |
|---|---|---|
| Phase 1 | <Nd> | <criteria> |
| Phase 2 | <Nd> | ... |

---

## 8. 위험·완화

| 위험 | 영향 | 완화 |
|---|---|---|
| ... | high/med/low | ... |

---

## 다음 단계

- [ ] 검토자 승인
- [ ] [`tasks.md`](tasks.md) — 단계를 더 잘게 분해
- [ ] (선택) [`research.md`](research.md) — 깊이 분석 필요 시
- [ ] (선택) [`data-model.md`](data-model.md) / [`contracts/`](contracts/)
