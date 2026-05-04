# `.ax/state.json` — file ownership

`.ax/state.json`은 statusline·doctor·hud가 공유하는 *render cache* SSOT.
사용자가 직접 편집하는 파일이 아님. skill이 jq로 in-place update.

## Schema (canonical)

`templates/default/.ax/hud/state.json.template`가 정본.
schema 변경 시 반드시 `statusline.sh`가 읽는 path와 이 문서를 같이 갱신 (3-way sync).

## Ownership 표

| 키 | create | update | read |
|---|---|---|---|
| `goax_version` | installer (template cp) | release만 (불변) | doctor |
| `updated_at` | installer | 모든 skill 종료 시 | doctor, hud |
| `hud_preset` | installer | `/hud preset <name>` | statusline |
| `layers.L0_triage.active` | installer | onboarding Q5, doctor | statusline |
| `layers.L1_constitution.active` | installer | onboarding Q5, doctor | statusline |
| `layers.L2_module.active` | installer | onboarding Q5, doctor | statusline |
| `layers.L3_spec_adr.active` | installer | onboarding Q5, doctor | statusline |
| `layers.L*.{rules,specs,adrs,...}` | installer | doctor (실측) | statusline |
| `cross_cut.spirit.active` | installer | doctor (`rules_count > 0` 이면 true) | statusline |
| `cross_cut.spirit.{rules_count,values_filled}` | installer | doctor (실측) | statusline |
| `cross_cut.mistakes.active` | installer | doctor (`count > 0` 이면 true) | statusline |
| `cross_cut.mistakes.{count,last_audit,due_in_days}` | installer | audit, doctor | statusline |
| `current_task` | null | triage skill | statusline |
| `last_skill` | null | 모든 skill 종료 시 | doctor |
| `skill_calls` | 0 | 모든 skill 종료 시 (`+= 1`) | doctor |

## 규칙

1. **create는 installer만** — template를 *단순 cp*. 이후 모든 skill은 update만 (`jq ... > tmp && mv`).
2. **`statusline.sh`는 read-only** — 어떤 경우에도 state.json을 쓰지 않음. side-effect-free.
3. **schema 변경 = 3-way 동기화** — `state.json.template` + `statusline.sh` + 이 표 동시 갱신.
4. **누락 필드 안전 처리** — `statusline.sh`는 `// false`, `// 0`, `// "—"` 같은 jq fallback으로 graceful degrade. 단 표에 *등록되지 않은* 새 필드는 statusline에 표시 X.

## derived value 정의

read-only로 보이지만 의미 있는 *파생값*. doctor가 update 시 계산:

- `cross_cut.spirit.active` ⇐ `cross_cut.spirit.rules_count > 0` 또는 `cross_cut.spirit.values_filled == true`
- `cross_cut.mistakes.active` ⇐ `cross_cut.mistakes.count > 0` 또는 `cross_cut.mistakes.last_audit != null`
- 4계층 `layers.L*.active` ⇐ 사람이 결정 (onboarding Q5에서 채택). 자동 derived 아님.

## 변경 이력

- 2026-05-03: `cross_cut.{spirit,mistakes}.active` 신설. 그전 statusline.sh가 이 path를 읽었지만 template에 필드 없어 항상 false로 표시되던 버그 해소.
