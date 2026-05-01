---
name: adr-write
description: "ADR (Architecture Decision Record) 작성 워크플로우. 새 결정을 docs/adr/NNN-<slug>.md로 기록. 트리거: 'ADR', 'adr', '결정 기록', '아키텍처 결정', 'rationale', '선택의 근거'."
---

# ADR Write Workflow

ADR는 4기둥 docs 모델(PRD·Architecture·ADR·UI) 중 가장 중요 — 거부된 패턴을 기록함으로써 AI의 context drift를 막는다.

## When to use

- L 등급 이상 작업 시작 직전
- Constitution/MANDATORY 변경 PR
- 외부 패턴 제안을 거부할 때 (재제안 방지)

## 파일 위치 / 명명

```
docs/adr/NNN-<short-slug>.md
```

NNN은 4자리 0-padded. 기존 가장 큰 번호 + 1.

## 템플릿

```markdown
# ADR NNNN: <한 줄 결정>

## 상태
- 제안 (YYYY-MM-DD)
- 승인 (YYYY-MM-DD)

## 컨텍스트
이 결정을 강제하는 사실 / 제약 / 영향 범위.

## 검토된 대안
### A. <옵션>
- Pros / Cons / 결과 (채택 / 기각 + 사유)

## 결정
한 단락 + 핵심 trade-off.

## 결과
- 단기 / 장기 / 후속 작업

## 참고
관련 PR / 선·후행 ADR / spec
```

## Workflow

1. `ls docs/adr/` — 다음 번호 파악
2. 위 템플릿으로 초안
3. PR 단독 (코드와 분리)
4. 검토자 ≥ 1인 승인
5. 승인 후 코드 PR 시작

## 안티 패턴

- "검토된 대안" 누락 → 미래 AI가 그 대안을 다시 제안
- "결과" 누락 → 후속 작업 분실
- 코드 PR 안에 ADR 끼워넣기 → 결정을 사람들이 못 봄
