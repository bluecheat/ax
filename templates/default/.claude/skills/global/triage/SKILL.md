---
name: triage
description: "사용자가 새 작업·기능·수정·리팩토링·버그 fix를 요청할 때 가장 먼저 자동 매칭되는 skill. Size × Risk로 30초 안에 분류하고 spirit·룰·페르소나를 자동 주입. 트리거: '구현해줘', '만들어줘', '작업 계획', '어떻게 만들지', '고쳐줘', '추가해줘', '바꿔줘', '리팩토링', '리팩터링', 'fix', '버그', '기능 추가', 'PR 만들어', '작업하자', '/triage', 'classify', 새 대화 첫 메시지에서 작업 의도가 보이면 자동 발동."
---

# Triage Skill

> 응급실 트리아지처럼, 들어온 작업을 30초 안에 분류하고 권장 경로를 제시한다.

## When to use

- 사용자가 새 작업을 요청한 첫 메시지
- 사용자가 명시적으로 `/triage <설명>` 호출
- 작업 도중 스코프가 커져서 재분류가 필요할 때

## Output 포맷

```yaml
size: <S|M|L|XL>
risk: <L0|L1|L2|L3>
domain: <매칭된 키워드>
suggested_path: <즉시작업 | task-machine | speckit | 단계분할>
required_specs: [<docs/adr/... | spec/...>]
required_sensors: [<lint, structural-check, traffic, integration-tag, ...>]
critical_rules_to_check: [<해당 CRITICAL 토큰들 — 'AX:CRITICAL:001' 형식>]
suggested_persona: <code-reviewer | bug-hunter | refactorer | engineer-generalist | <도메인>-engineer>
spirit_context:                        # ★ v0.3 — 모든 persona에 자동 주입
  values: .ax/spirit/values.md         # 항상
  tone: .ax/spirit/tone.md             # 항상
  rules: [.ax/spirit/rules/<applies_to 매칭>.md]
human_gate: <true|false>
```

**Spirit 강제**: `.ax/spirit/values.md` 또는 `tone.md`가 누락되면 triage 자체가 fail (옵션 4-B). 작업 시작 자체가 거부됨.

## Workflow

1. 입력에서 키워드 추출 → `.ax/config.yml`의 `domain_risk` 매트릭스와 매칭
2. 변경 범위 추정 → Size 결정
3. **상세 분류 표는** [`references/risk-matrix.md`](references/risk-matrix.md) 참조
4. 사용자에게 출력 + OK 받으면 다음 단계 진행
5. 분류 오차 발견 시 `.ax/mistakes/`에 캡처

## CLI 매핑

```bash
goax triage "<설명>"            # 자동 분류
goax rules --level critical     # 매칭된 CRITICAL 룰만 보기
```

## 상세

- Size × Risk 매트릭스, 도메인 매칭 키워드, 호출 순서: **`references/risk-matrix.md`**
