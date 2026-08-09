---
category: ops
applies_to: [code, pr, commit, review]
# paths: (생략 — universal 룰. CLAUDE.md @import으로 전체 작업에 적용됨)
# path-scoped 예시 (도메인 특화 룰의 경우):
# paths:
#   - "**/domain/**"
#   - "**/*Entity*.kt"
# → generate-rule-shims.sh가 .claude/rules/<name>.md shim 자동 생성
---

# Ops — Universal Action Baseline

> 모든 작업·sub-agent의 공통 행동 룰. 도메인 특화 룰이 아닌 *어떻게 일하는지*의 베이스라인.
> 룰 작성법: `.ax/docs/reference/rules-tokens.md`

<!-- META(Triage First)는 root AGENTS.md ## META 블록에 별도 박힘 (lean — 일반 행동
     원칙은 behavioral-baseline.md opt-in). 본 파일은 그 위에 쌓는 운영 룰. -->

## SP-OPS-001: MANDATORY 룰 위반 가능성 감지 시 작업 중단

🟡 MANDATORY 시그널이 박힌 룰을 위반할 가능성이 보이면 **작업 전 사용자에게 명시 확인**.
"진행해도 될까요?" 한 번 묻고 답을 기다린다. 자동 진행 금지.

✅ "Core 모듈에서 Adapter API를 호출하려 해요 (MANDATORY:002). 진행할까요?"
❌ 묻지 않고 그냥 코드 작성

<!-- 검출 패턴: 사용자 메시지에 "그냥 해줘" 같은 명시적 우회 허가가 없는 한 적용 -->

---

## SP-OPS-002: Generator와 Evaluator는 같은 세션에서 자평하지 않는다

작성한 코드를 같은 호출에서 "검토 끝" 처리하지 않는다. 검증은 별도 lane:
- `code-reviewer` / `verifier` agent에게 위임, 또는
- 결정론 도구 (`lint`, `tsc`, `pytest`) 결과로 대체

self-praise bias 차단. CONCEPTS §5.3.

---

## SP-OPS-003: Hook 경고를 무시하지 않는다 (Mistake Loop 활성)

`[goax hook]` 경고가 stderr에 뜨면:
1. 사용자에게 한 줄 요약 보고
2. `.ax/mistakes/` 에 자동 캡처됨 — 사용자에게 알림
3. 같은 경고가 두 번째 등장하면 `/audit` 권유

침묵 금지. 워닝을 수확 곡선의 데이터 포인트로 본다.

---

## SP-OPS-004: 보호 경로 변경 시 의도 명시

`CLAUDE.md`, `.ax/`, `.github/`, 빌드 설정에 손대기 전 **이유를 한 줄 설명**하고 사용자 확인.
hook이 mode=warning이라 막지 않더라도 명시 동의 없이 진행 X.

---

## SP-OPS-005: Triage 결과 없이 큰 작업 시작 금지

작업이 한 파일·한 함수 수준을 넘으면 (`Size ≥ M` 또는 `Risk ≥ L2` 의심) 먼저 triage.
`.ax/current-task.json` 비어있는 상태에서 `spec` 등 후속 도구를 부르면 SKIP 됨.
순서: triage → spec(필요 시) → 작업.

---

## SP-OPS-006: 결정론 도구 결과를 LLM 추측으로 덮지 않는다

`tier-from-state.sh`, `next-spec-num.sh` 등 스크립트가 값을 반환하면 그 값을 *그대로* 쓴다.
"더 좋아 보이는 다른 값"으로 바꾸지 않는다. 결정론 = 신뢰의 닻.

✅ `NEXT=$(bash .ax/scripts/bash/next-spec-num.sh --json | jq -r '.result.next')`
❌ 스크립트 무시하고 LLM이 직접 다음 번호 계산

---

## SP-OPS-007: 변경 한 줄 한 줄이 요청에 trace 가능해야 한다

PR diff의 모든 줄에 대해 "왜 이 줄이 필요한가?" → 사용자 요청까지 1:1 mapping.
"리팩토링 김에 같이 정리"는 별도 PR. *Surgical Changes* 원칙의 운영 버전.
