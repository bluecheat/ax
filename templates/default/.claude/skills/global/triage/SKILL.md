---
name: triage
description: "작업 진입 시 Size × Risk로 분류하고 권장 경로/sensors/필수 게이트를 출력. 사용자가 새 작업을 요청할 때마다 가장 먼저 호출되는 skill. 트리거: '/triage', 'triage', 'classify', 새 작업의 첫 메시지."
---

# Triage Skill — 작업 분류 및 라우팅

> 응급실의 트리아지 간호사처럼, 들어온 작업을 30초 안에 분류하고 권장 경로를 제시한다.

## When to use

- 사용자가 새 작업을 요청한 첫 메시지
- 사용자가 명시적으로 `/triage <설명>` 호출
- 작업 도중 스코프가 커져서 재분류가 필요할 때

## How to classify

### Size

| 등급 | 정의 |
|---|---|
| S — Patch | 1~2 파일, 한 도메인, 비즈니스 로직 미변경 |
| M — Feature | 한 모듈/도메인 내 신규 기능, 1~2일 작업 |
| L — Cross-domain / High-risk | 2개 이상 도메인 OR 결제·주문·정산 등 고위험 도메인 |
| XL — Bootstrap / Refactor | 신규 도메인, P0 리팩토링, 1주 이상 |

### Risk (도메인 기반)

`.ax-first/config.yml`의 `domain_risk`를 참조. 매칭 안 되면 `default_risk`.

| 등급 | 의미 |
|---|---|
| L0 | 사용자 직접 영향 미미, 롤백 자유 |
| L1 | 사용자 노출, 캐시 영향 없음 |
| L2 | 노출 + 캐시 OR 결제 외 트랜잭션 |
| L3 | 결제·정산·금액 흐름 — 자동 사람 게이트 |

### 출력 포맷

```yaml
size: <S|M|L|XL>
risk: <L0|L1|L2|L3>
domain: <매칭된 도메인 키워드>
suggested_path: <즉시작업 | task-machine | speckit | 단계분할>
required_specs: [<docs/adr/... | spec/...>]
required_sensors: [<lint, structural-check, traffic, integration-tag, ...>]
critical_rules_to_check: [<CLAUDE.md의 CRITICAL 중 해당 항목>]
human_gate: <true|false>
```

## Workflow

1. 입력에서 키워드 추출 → `.ax-first/config.yml` `domain_risk`와 매칭
2. 변경 범위 추정 → Size 결정
3. 매트릭스에 따라 path / sensors / human_gate 산출
4. 사용자에게 출력 + OK 받으면 다음 단계 진행
5. 분류 오차 발견 시 `.ax-first/mistakes/`에 캡처

## CLI 매핑

```bash
ax-first triage "<설명>"
```

CLI 결과와 본 skill의 분류는 동일한 config.yml을 사용해 일관성 보장.

## 안티 패턴

- 모든 작업을 풀 task-machine으로 처리 → 토큰 낭비
- Size만 보고 Risk 무시 → 한 줄 결제 변경이 무방비
- `human_gate=true`인데 대화 안에서 처리 → 머지 직전에 막힘
