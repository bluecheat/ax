# Data Model — <피처 이름>

> 데이터 모델이 복잡할 때만. 단순하면 spec.md §5에 통합 가능.

---

## 1. ERD

```
[Entity A] ──< [Entity B] >── [Entity C]
```

## 2. Entity 정의

### 2.1 <Entity A>
| 필드 | 타입 | 제약 | 의미 |
|---|---|---|---|
| id | bigint | PK | ... |
| ... | ... | ... | ... |

불변량 (Invariants):
- <항상 성립해야 하는 조건>

### 2.2 <Entity B>
...

## 3. 인덱스
- `idx_<table>_<columns>` (사유)

## 4. 제약·트랜잭션
- FK·unique·check
- 트랜잭션 경계

## 5. 마이그레이션
DDL 파일 위치 + 백필 전략은 plan.md §3 참조.
