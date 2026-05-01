# ADR 0004: 룰 식별 토큰 컨벤션

## 상태
승인됨 (v0.2, 2026-05-01)

## 컨텍스트
모노레포에서 룰이 root + 모듈별 + spirit/rules로 분산. "결제 도메인 CRITICAL만 보고 싶다" 같은 1초 쿼리 불가.

## 검토된 대안

### A. ID 없음 — 사람이 grep으로 직접
- Pros: 학습 비용 0
- Cons: 정확도 낮음, 매번 다른 키워드
- 결과: 기각

### B. HTML 메타 코멘트 (`<!-- ax:rule scope=... -->`)
- Pros: 기계 친화
- Cons: 사람 가독성 ↓
- 결과: 기각

### C. `<scope>:<LEVEL>:<id>` + `SP-<CATEGORY>-<id>` (채택)
- Pros: 사람도 grep도 1초
- 예: `AX:CRITICAL:001`, `payment:MANDATORY:003`, `SP-SEC-001`
- 결과: 채택

## 결정
- Constitution 토큰: `<scope>:<LEVEL>:<id>` (3자리 0-padded id)
- Spirit 토큰: `SP-<CATEGORY>-<id>` (3자리)
- 룰 본문은 `## SP-...:` 헤더로 시작 (lint가 헤더만 ID로 인식 — 본문 안 인용은 무시)

## 결과
- v0.2: rules CLI (`goax rules`, `goax find`)
- v0.3: spirit 토큰 통합 + `--source constitution|spirit` 필터
