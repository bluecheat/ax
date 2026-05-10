# Tasks — <피처 이름>

> spec.md (WHAT/WHY) 를 받아 *어떻게* 만들지 dependency-ordered 체크리스트로 분해해요.
> 각 task 는 1\~3 파일 변경, 1\~3 시간. 의존성 정렬되어 순차/병렬 실행 가능.
> 설계 결정의 *근거* 는 별도 ADR (`.ax/docs/adr/NNNN-*.md`) 로 기록.

---

## 0. 입력
- [`spec.md`](spec.md) — SSOT (What/Why + Technical Context §7.5)
- 관련 ADR (있으면): `docs/adr/NNNN-*.md`

---

## 1. Task 목록

체크박스 + 태그(파일 경로) + 추정.

### Phase 1: <이름>

- [ ] **T001** — <한 줄 task>
  - 파일: `path/to/file.kt`
  - 의존: 없음
  - 추정: 1h
  - 검증: <어떻게>

- [ ] **T002** — ...
  - 파일: ...
  - 의존: T001
  - 추정: ...

### Phase 2: ...

---

## 2. 병렬 실행 가능

같은 Phase 안에서 의존성 없는 task는 병렬:

```
T001 ─ T003 ─ T005
T002 ─ T004 ─ T006
```

---

## 3. 진행 상황

- 완료: <체크된 task 수> / <전체>
- 차단됨 (block): <task ID + 사유>

> 워크플로우 안내 (다음 단계) 는 `/spec-implement` skill 출력의 `📍 다음` 으로 제공돼요.
> 환경 검증·배포는 이 문서 범위 밖 — 별도 운영 채널.
