# Tasks — <피처 이름>

> spec.md (WHAT/WHY) 를 받아 *어떻게* 만들지 dependency-ordered 체크리스트로 분해해요.
> 각 task 는 1\~3 파일 변경, 1\~3 시간. 의존성 정렬되어 순차/병렬 실행 가능.
> 설계 결정의 *근거* 는 별도 ADR (`.ax/docs/adr/NNNN-*.md`) 로 기록.

---

## 0. 입력
- [`spec.md`](spec.md) — SSOT (What/Why + Technical Context §7.5)
- 관련 ADR (있으면): `.ax/docs/adr/NNNN-*.md`

---

## 1. Task 목록

체크박스 + 태그(파일 경로) + 추정.

**한 줄 형식** — 기계가 읽어요 (`tasks-plan.sh`, `tasks-gate.sh`).

```
- [ ] T001 [P] [AC2] <한 줄 설명> — files: path/a.kt, path/b.kt
      의존: T000
      검증: <어떻게>
```

| 토큰 | 뜻 |
|---|---|
| `T001` | task ID. spec 안에서 sequential |
| `[P]` | **병렬 가능** — 아래 규칙을 만족할 때만 |
| `[AC2]` | 이 task 가 충족하는 spec.md §3 의 수용 기준 |
| `files:` | 건드리는 파일. `[P]` 검증의 근거예요 |

체크박스 상태는 셋이에요: `[ ]` 미완료 · `[x]` 완료 · `[~]` **의도적 보류**.
보류는 사유를 같이 적어요 — 게이트가 "누락" 과 "의도적 보류" 를 구분해야 하니까요.

### `[P]` 규칙 — 기본은 순차예요

`[P]` 는 다음을 **둘 다** 만족할 때만 붙여요:

1. 미완료 의존이 없다
2. 다른 `[P]` task 와 **파일이 겹치지 않는다**

겹치면 `tasks-plan.sh` 가 violation 으로 잡아요. 구현 task 는 대부분 *쓰기*
라서, 읽기와 달리 나란히 돌리면 서로의 암묵적 결정을 못 봐요 — 각자 멀쩡한데
합치면 양립 불가능한 코드가 나와요. 그래서 **증명될 때만 병렬**이에요.

### Phase 1: <이름>

- [ ] T001 [AC1] 리뷰 스코어 계산기 추가 — files: review/Scorer.kt
      의존: 없음
      검증: ScorerTest
- [ ] T002 [P] [AC1] 가중치 설정 외부화 — files: review/Weight.kt
      의존: 없음
      검증: WeightTest
- [ ] T003 [AC2] 스코어를 API 응답에 노출 — files: review/Api.kt
      의존: T001
      검증: ApiTest
- [~] T004 [AC3] 캐시 계층 — files: review/Cache.kt
      의존: T003
      보류: 트래픽 측정 후 결정 (2026-09 재검토)

### Phase 2: ...

---

## 2. 진행 상황

수동으로 세지 마세요 — 손으로 적은 숫자는 반드시 어긋나요.

```bash
bash .ax/scripts/bash/tasks-gate.sh --spec <NNN-slug> --json
```

`[ ]` 미완료 수, AC 커버리지 간극, 매핑 없는 orphan task 를 한 번에 알려줘요.

> 워크플로우 안내 (다음 단계) 는 `/spec-implement` skill 출력의 `📍 다음` 으로 제공돼요.
> 환경 검증·배포는 이 문서 범위 밖 — 별도 운영 채널.
