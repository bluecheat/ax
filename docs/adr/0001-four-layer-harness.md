# ADR 0001: 4계층 하네스 모델 채택

## 상태
승인됨 (v0.1, 2026-05-01)

## 컨텍스트
AI 에이전트의 결과 일관성을 *환경* 차원에서 통제할 골격이 필요했다.
선행 모델 검토:
- 하네스 엔지니어링 모델: Agent = Model + Harness 공식 + Guides/Sensors/Loop
- 한 폴더 = 한 의도 패턴: 한 폴더 = 한 페르소나

## 검토된 대안

### A. 단일 파일 (.cursorrules / CLAUDE.md만)
- Pros: 학습 곡선 최소
- Cons: 모노레포 비대화, Triage·Sensors·Loop 부재, 같은 실수 반복 차단 불가
- 결과: 기각

### B. PRD-first 워크플로우 (specify→plan→tasks 표준화)
- Pros: 잘 검증된 워크플로우
- Cons: 우리는 *비협상 룰*과 *행동 정체성*도 다뤄야 함 — PRD-first 모델은 그것들을 다루지 못함
- 결과: 부분 채택 — spec-kit과 병행 사용 가능하지만 goax는 별도 도구

### C. 4계층 + Cross-cutting (채택)
- Layer 0 Triage / Layer 1 Constitution / Layer 2 Module / Layer 3 Spec·ADR
- + Cross-cut Mistake Loop + Cross-cut Spirit (v0.3에서 추가)
- Pros: 책임 분리 명확, 점진 도입 가능, 모노레포·싱글 모두 적용
- Cons: 학습 곡선 약간 ↑
- 결과: 채택

## 결정
4계층 + 2 cross-cut 모델 채택. 자세한 정의는 [`CONCEPTS.md §1`](../../CONCEPTS.md) 참조.

## 결과
- v0.1: Layer 0\~3 + Mistake Loop 골격
- v0.3: Spirit cross-cut 추가
- 후속: 도그푸딩(commerce-monorepo)에서 발견된 페인을 ADR-0005+로 기록
