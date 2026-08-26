---
name: adr
description: "ADR (Architecture Decision Record) 작성 워크플로우. 새 결정을 .ax/docs/adr/NNNN-<slug>.md로 기록. 트리거: '/adr', 'ADR 작성', 'adr', '결정 기록', '아키텍처 결정', 'rationale', '선택의 근거'."
---

# adr — ADR 작성 워크플로우

> ADR는 4기둥 docs 모델(PRD·Architecture·ADR·UI) 중 가장 중요 — 거부된 패턴을 기록함으로써 AI의 context drift를 막아요.

## 시작 전 필수
`.ax/spirit/values.md`, `tone.md` 따라요.

## SSOT 템플릿

ADR는 항상 `.ax/_templates/adr/0000-template.md`를 base로 만들어요.
인라인 템플릿 사용 금지 — `onboarding`의 Q5 자동 ADR도 동일 template 사용해서 포맷 일관성 보장.

template 구조 (요약):
1. 메타 표 (ADR ID·작성일·작성자·상태·관련 spec)
2. 컨텍스트 (현재 상태 / 트리거 / 제약)
3. 검토된 대안 (Pros / Cons / 결과)
4. 결정 (무엇을 / 왜 / trade-off)
5. 결과 (단기 / 장기 / 후속 / 측정)
6. 참고
7. 변경 이력

## 발동 트리거

- L 등급 이상 작업 시작 직전 (Layer 0 Triage가 spec과 함께 권장)
- Constitution/MANDATORY 변경 PR
- 외부 패턴 제안을 거부할 때 (재제안 방지)
- "ADR 작성", "0006 ADR 만들어줘", `adr payment-refund-strategy`

## 1. bash 사전 검색 — 큰 프로젝트 대비

```bash
# 같은 도메인 ADR이 이미 있나
KEYWORDS="payment refund"
grep -rilE "($KEYWORDS)" .ax/docs/adr 2>/dev/null

# 다음 번호 *미리보기* (NNNN 4자리 zero-pad) — 아직 확정 아니에요.
# 확정은 §3 생성 시점의 --reserve 가 해요. 여기서 예약하면 사용자가 취소한
# ADR 번호가 원장에 남아 영구히 비어요.
NEXT=$(bash .ax/scripts/bash/next-spec-num.sh --kind adr --json | jq -r '.result.next')
echo "다음 ADR 번호(예정): $NEXT"

# 폐기·대체된 ADR 확인 (재제안 차단)
grep -lE "^\| 상태 \|.*폐기|superseded" .ax/docs/adr/*.md 2>/dev/null
```

## 2. 출력

```
📝 ADR Write (slug: payment-refund-strategy, 다음 번호: 0006)

 📍 발견
  기존 관련 ADR 0002-pg-multi-provider.md
      0004-rules-token-convention.md
  도메인 매칭 payment → L3 (config.yml)
  기반 spec  .ax/docs/spec/005-payment-refund-window/ (있으면)

 🎯 목표 결정·검토 대안·trade-off를 0000-template.md 양식으로 기록

 ─ 옵션 ──────────────────────────────────────────

 [a] ✓ 다음으로 0006 ADR 작성      [권장]
  생성 .ax/docs/adr/0006-payment-refund-strategy.md
    (0000-template.md 복사 + 메타 채움)
  다음 사용자가 컨텍스트·검토된 대안·결정 본문 작성
    완료 시 spec.md 메타에 ADR 링크 추가

 [b] 다른 slug로
  → 정확한 slug를 알려주세요 (예: refund-window-extension)

 [c] 기존 ADR 갱신 (대체 / 폐기)
  → 어느 ADR을 대체하나요? (예: 0002 폐기, 새 결정으로)

 ▸ 답해주세요 [a] / [b] (slug 같이) / [c] (대상 ADR 번호 같이)
```

## 3. 적용

[a] 응답 시:
```bash
# 번호를 원자적으로 예약 + 실물 생성. 경합하면 다음 번호로 물러나므로
# **반환된 번호를 써야 해요** — §1 의 미리보기 값을 그대로 쓰면 안 돼요.
SLUG="payment-refund-strategy"
RES=$(bash .ax/scripts/bash/next-spec-num.sh --kind adr --reserve --slug "$SLUG" --json)
[ "$(echo "$RES" | jq -r '.status')" = "ok" ] || { echo "$RES" | jq -r '.errors|join("\n")'; exit 1; }
NUM=$(echo "$RES" | jq -r '.result.next')
DEST=$(echo "$RES" | jq -r '.result.path')
echo "$RES" | jq -r '.warnings[]?'        # 경합 시 "0006 대신 0007 로 예약" 안내

cp .ax/_templates/adr/0000-template.md "$DEST"

# 메타 자동 채움 (tmp-mv — BSD/GNU sed 모두 호환)
sed \
 -e "s/| ADR ID | NNNN |/| ADR ID | $NUM |/" \
 -e "s/| 작성일 | YYYY-MM-DD |/| 작성일 | $(date +%Y-%m-%d) |/" \
 -e "s/<한 줄 결정>/Payment Refund Strategy/" \
 "$DEST" > "$DEST.tmp" && mv "$DEST.tmp" "$DEST"
```

✓ 메시지:
```
✓ ADR 0006 — .ax/docs/adr/0006-payment-refund-strategy.md (template 복사, 메타 채움)

다음 단계
 1. 컨텍스트 작성 — 현재 상태 / 트리거 / 제약
 2. 검토된 대안 N개 작성 — Pros/Cons/결과 (거부도 충실히)
 3. 결정 + trade-off 명시
 4. 결과 (단기/장기/후속/측정)
 5. PR로 단독 제출 (코드와 분리)
```

## 4. onboarding Q5와 일관

`onboarding`이 Q5에서 자동 생성하는 `0001-goax-adoption.md`도 **이 template (0000-template.md)을 사용**해요. 즉:
- onboarding이 만든 ADR과 사용자가 `adr`로 만든 ADR이 같은 양식
- 후속 ADR (0002, 0003, ...)도 동일 — 가독성·자동 통계 가능

## 절대 금지

- 인라인 template 사용 X — 항상 `0000-template.md`를 cp
- "검토된 대안" 누락 → 미래 AI가 거부된 대안 재제안
- "결과 / 측정" 누락 → 후속 작업 분실
- 코드 PR 안에 ADR 끼워넣기 → 결정이 묻힘
- 사용자 도메인 결정을 자동 채움 X — 본문은 사용자가 작성
