# Requirements Checklist — <피처 이름>

> spec → plan → implement 단계 진입 전 자가 검증.
> 모든 항목 체크 + NEEDS CLARIFICATION 0건 → `goax spec check` 통과.

---

## Spec 단계

- [ ] §1.1 한 줄 정의 작성됨
- [ ] §1.2 사용자 가치 명확
- [ ] §1.3 MVP 경계 (포함/NEEDS/제외) 분리
- [ ] §1.3 모든 NEEDS CLARIFICATION 해소
- [ ] §2 Why (문제 / 안 만들면 / 대안)
- [ ] §3 성공 기준 측정 가능한 형태
- [ ] §3 비기능 요구 4종 (성능·가용성·보안·호환성)
- [ ] §4 사용자 시나리오 ≥3개 (성공/엣지/실패)
- [ ] §7 의존성·영향 범위
- [ ] §8 Open Questions 모두 해소

## Plan 단계 (spec 통과 후)

- [ ] §1 아키텍처 결정 명확
- [ ] §1.3 거부된 패턴 → ADR 작성
- [ ] §2 단계 분할 (Phase 1, 2, ...)
- [ ] §3 데이터 변경 + 롤백 전략
- [ ] §4 검증 전략 (acceptance criteria 매핑)
- [ ] §5 롤아웃 + feature flag
- [ ] §6 외부 영향
- [ ] §8 위험·완화

## Tasks 단계

- [ ] 모든 task 1\~3 파일 변경 단위
- [ ] 의존성 명시
- [ ] 추정 시간

## Implement 단계 (위 모두 통과 후)

- [ ] 모든 task 완료
- [ ] 모든 acceptance criteria 통과
- [ ] hooks (lint·structural·security) 통과
- [ ] PR description: spec.md / plan.md 링크 첨부
- [ ] (risk≥L2) traffic estimation 첨부
