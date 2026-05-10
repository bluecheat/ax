# Requirements Checklist — <피처 이름>

> spec → tasks → implement 단계 진입 전 자가 검증.
> 모든 항목 체크 + NEEDS CLARIFICATION 0건 + placeholder 0건 → `/spec-validate` 통과.

---

## Spec 단계

- [ ] 1️⃣.1 한 줄 정의 작성됨
- [ ] 1️⃣.2 사용자 가치 명확
- [ ] 1️⃣.3 MVP 경계 (포함/NEEDS/제외) 분리
- [ ] 1️⃣.3 모든 NEEDS CLARIFICATION 해소
- [ ] 2️⃣ Why (문제 / 안 만들면 / 대안 — 채택·거부 결정 근거는 ADR 로)
- [ ] 3️⃣ 성공 기준 측정 가능한 형태
- [ ] 3️⃣ 비기능 요구 4종 (성능·가용성·보안·호환성)
- [ ] 4️⃣ 사용자 시나리오 ≥3개 (성공/엣지/실패)
- [ ] 7️⃣ 의존성·영향 범위
- [ ] 7️⃣.5 Technical Context (스택·영향 모듈·적용 룰·진입 ADR)
- [ ] 8️⃣ Open Questions 모두 해소

## ADR (full tier 또는 L≥2 도메인)

- [ ] 핵심 설계 결정마다 ADR 1 건 — 채택 / 거부 / Trade-offs
- [ ] CRITICAL 룰 접촉 결정은 ADR 의무

## Tasks 단계

- [ ] 모든 task 1\~3 파일 변경 단위
- [ ] 의존성 명시
- [ ] 추정 시간
- [ ] Phase 별 acceptance criteria 매핑 (spec.md §3 ↔ task)

## Implement 단계 (위 모두 통과 후)

- [ ] 모든 task 완료
- [ ] 모든 acceptance criteria 통과
- [ ] hooks (lint·structural·security) 통과
- [ ] PR description: spec.md + 관련 ADR 링크 첨부
- [ ] (risk≥L2) traffic estimation 첨부
