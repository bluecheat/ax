# `goax up` — Brownfield 도입

> 이미 운영 중인 프로젝트에 goax를 점진적으로 도입할 때 사용해요.
> Greenfield(빈 프로젝트)는 `goax init`으로 충분.

## 한 줄 요약

```bash
goax up
```

→ 4 phase 자동 진행: **Discover → Plan(결정 4개) → Apply → Next**.

## 4 phase

### Phase 1 — Discover (자동, 변경 0)

기존 자산을 스캔해서 보고:
- 레포 형태 (모노레포/싱글)
- 모듈 개수·이름
- CLAUDE.md 줄 수·룰 추정
- 외부 spec 프로젝트 (`../commerce-spec` 같은)
- 활성 hooks (husky / pre-commit / lint-staged)
- AI 리뷰 (CodeRabbit / Cursor 등)
- Stack 추정
- 도메인 키워드

### Phase 2 — Plan (결정 4개, plan-mode 스타일)

| Q | 항목 | 권장 |
|---|---|---|
| Q1 | CLAUDE.md 룰 처리 | a) 자동 분류 + adoption-plan.md PR |
| Q2 | domain_risk 매트릭스 | a) 추정값 채택 |
| Q3 | hooks 강도 | a) warning-only |
| Q4 | 외부 spec 처리 | a) 링크만 |

각 Q에 a/b/c 중 하나로 응답. `--auto a,a,a,a`로 비대화 가능.

### Phase 3 — Apply

선택된 결정대로 변경 적용. 기존 파일은 보존 (`.goax/*.suggested`로).

### Phase 4 — Next steps

다음 단계 자동 안내 + commit/PR 명령 출력.

## 옵션

```bash
goax up                          # interactive
goax up --dry-run                # plan만, Apply 안 함
goax up --auto a,a,a,a           # 자동 응답 (CI)
```

## 자동 분류 휴리스틱 (Q1:a)

LLM 호출 없이 키워드 grep으로 분류:

| 키워드 | 카테고리 |
|---|---|
| secret / api_key / password / 보안 | `security.md` |
| naming / kebab / camel / 네이밍 | `naming.md` |
| test / @Tag / 테스트 | `testing.md` |
| commit / PR / 리뷰 | `pr.md` |
| throw / catch / 예외 | `error-handling.md` |
| race / lock / 동시성 | `concurrency.md` |
| log / metric / 관측 | `observability.md` |
| dependency / module / 의존 | `architecture.md` |
| ddl / migration / 스키마 | `data.md` |
| (그 외) | `uncategorized.md` |

→ 정확도 \~80%. **사용자가 PR에서 검수**.

## 점진 강화 — `goax up --enforce <category>`

도입 후 1\~2주 데이터 모인 뒤, 카테고리별로 fail 모드 승격:

```bash
goax up --enforce security    # security 카테고리만 fail
goax up --enforce naming      # naming도 fail로
```

(v0.4.1 예정)

## 안티 패턴

- 첫날 fail 모드 → 기존 PR 다 막힘 → 팀 반발 → 도입 실패
- 자동 분류 결과를 검토 없이 머지 → 잘못된 카테고리 누적
- 외부 spec을 무리하게 흡수 → 다른 팀 워크플로우 깨짐

## 도그푸딩 사례

(작성 예정 — commerce-monorepo 적용 후 회고)
