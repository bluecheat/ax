#!/usr/bin/env bash
# triage-first scaffold — "goax 가 설치된 프로젝트에서 새 작업 요청이 들어온 첫 턴" 을 실제 설치기로 만들어요.
# `--scaffold` 로만 실행되고, 샌드박스 밖에서 사용자 권한으로 돌아요.
#
# 예전엔 프롬프트가 "AGENTS.md 와 spirit 을 만들고 나서 요청을 처리해" 라고 시켜서 baseline arm 도 같은
# Triage First 문장을 봤어요 — Δ 가 "프롬프트에 적힌 룰을 따르는가" 였지 플러그인이 아니었어요. 이제 룰은
# provision.sh 가 깐 AGENTS.md/CLAUDE.md 에만 있고, `user-prompt/triage-nudge.sh` (UserPromptSubmit) 가
# 구현 의도를 감지해 nudge 를 밀어 넣어요. 픽스처는 요청이 가리키는 결제 모듈 하나예요.
set -euo pipefail

CASE_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(CDPATH="" cd "$CASE_DIR/../.." && pwd)"
[ -f "$PLUGIN_ROOT/.claude-plugin/plugin.json" ] || { printf '[goax eval] plugin root 아님: %s\n' "$PLUGIN_ROOT" >&2; exit 1; }

git init -q
mkdir -p .claude   # Claude Code 환경 표시 — provision 이 settings.json 까지 설치해 실제 `up` 결과와 같은 트리가 돼요
OUT=$(bash "$PLUGIN_ROOT/scripts/provision.sh" --target "$PWD" --json)
printf '%s' "$OUT" | jq -e '.status == "ok" or .status == "warning"' >/dev/null \
    || { printf '[goax eval] provision 실패: %s\n' "$OUT" >&2; exit 1; }
[ -f .ax/hooks/user-prompt/triage-nudge.sh ] || { printf '[goax eval] triage-nudge.sh 가 설치되지 않았어요\n' >&2; exit 1; }

mkdir -p src/payment
cat > src/payment/index.ts <<'TS'
export interface Payment {
  id: string;
  orderId: string;
  amount: number;
  currency: "KRW";
  status: "authorized" | "captured" | "failed";
  capturedAt?: string;
}

const payments = new Map<string, Payment>();

export function authorize(orderId: string, amount: number): Payment {
  if (amount <= 0) throw new Error("amount must be positive");
  const p: Payment = { id: `pay_${Date.now().toString(36)}`, orderId, amount, currency: "KRW", status: "authorized" };
  payments.set(p.id, p);
  return p;
}

export function capture(paymentId: string): Payment {
  const p = payments.get(paymentId);
  if (!p) throw new Error("payment not found");
  if (p.status !== "authorized") throw new Error(`cannot capture ${p.status}`);
  p.status = "captured";
  p.capturedAt = new Date().toISOString();
  return p;
}

export function get(paymentId: string): Payment | undefined {
  return payments.get(paymentId);
}
TS
