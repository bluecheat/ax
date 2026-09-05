---
name: hud
description: "goax HUD(statusline) 관리 — 'HUD 활성화', 'statusline 설정', 'HUD 갱신', 'hud preset', 'HUD 미리보기', 'HUD 끄기', '/hud'. 하네스 위치만 한 줄로 보여줘요: 설치 버전 · triage Size×Risk · M 이상의 spec › tasks › impl › review 진행 단계 · 실수 누적. OMC HUD 와 같은 문법(프리셋 minimal/focused/full · ASCII 바)이고, 다른 statusline 과 합칠 땐 stdin 을 양쪽에 먹이는 합성 스크립트를 써요. 슬래시로도 호출 가능: '/hud'."
---

# hud — 하네스 위치 한 줄

## 시작 전 필수
`.ax/spirit/values.md`, `tone.md` 따라요.

## 무엇을 보여주는가

```
[goax#0.5.1] | M×L2 · payment | spec ✓ › tasks ✓ › impl ● [######----]7/12 › review ○ | mistakes:3
```

| 조각 | 뜻 | 어디서 읽나 |
|---|---|---|
| `[goax#0.5.1]` | 설치된 goax 버전. plugin 이 더 새로우면 `[goax#0.5.1] -> 0.5.2 goax up` (노랑) | `.ax/version` + `state.json.hud.plugin_version` |
| `M×L2 · payment` | triage 가 정한 Size×Risk 와 도메인. idle 이면 `idle` | `current-task.json` |
| `spec ✓ › tasks ✓ › impl ● 7/12 › review ○` | M 이상의 워크플로 체인. `✓` 완료 · `●` 진행 중 · `○` 남음. S 는 `즉시 작업 — spec 불필요`. full tier 는 `adr` 단계가 끼고, `review` 는 evaluator 가 필수일 때만 | `current-task.json` phase + tier, `tasks.md`, `state.json.hud.review_required` |
| `mistakes:3` | `.ax/mistakes/` 누적 수 (README·archive 제외). 5 이상 노랑, 10 이상 빨강 | `.ax/mistakes/` |
| `(stale)` | HUD 캐시가 30분 넘게 오래됐을 때 — 거짓 초록을 안 만들려고 | `state.json.hud.cached_at` |

**안 보여주는 것**: 모델·ctx%·에이전트 수·todo 는 OMC HUD 몫이에요. 레인·게이트·경보는 skill 출력과
doctor 가 물을 때 보여줘요 — 상태 표시줄엔 하네스 위치만 둬요.

**왜 이렇게 바꿨나**: 이전 HUD 의 세 조각(행성 이모지 · S×R · 혜성)은 작업 중에 안 변했어요. 상태
표시줄인데 상태가 안 움직였어요. 지금은 phase 가 바뀔 때마다 체인이 움직여요 — `spec-implement` 가
진입 시 `implementing`, evaluator 대기 시 `review` 를 써요.

## 프리셋 — `.ax/config.yml` `hud.preset`

OMC HUD 와 같은 이름이에요. 키가 없으면 focused.

```
minimal   [goax#0.5.1] | M×L2 | impl ● 7/12 | mistakes:3
focused   [goax#0.5.1] | M×L2 · payment | spec ✓ › tasks ✓ › impl ● [######----]7/12 › review ○ | mistakes:3
full      focused
          014-payment-refund · tier standard · 다음: spec-implement
```

`hud.bars: ascii | unicode` — 바 문자 (`#-` 또는 `█░`). 기본 ascii.

폭이 모자라면 ` | ` 경계에서 뒤부터 잘라요 (`COLUMNS` 기준). 출력은 항상 개행으로 끝나요.

## subcommand

### `/hud setup` — 활성화 (★ 충돌 안전)

1. `.claude/settings.json` 존재 확인
2. **기존 statusLine 검사** — 있으면 절대 자동 덮어쓰지 않아요. 단 command 가 *부재 파일*을 가리키는
   깨진 상태(예: 이전 설치 잔재 `statusline-combined.sh` 가 없음)면 [a-fix] 를 권장으로 표시.
   검사: command 문자열에서 `bash <path>` 의 path 추출 → `[ -f "$path" ]`.
3. 옵션 제시:

```
[hud setup]

 📍 발견
  .claude/settings.json: 존재
  statusLine: <없음 / omc / 다른 plugin / 사용자 정의>

 ─ 옵션 ──────────────────────────────────────────

 [a] ✓ 신규 등록         [기존 statusLine 없을 때만 권장]
  수정 .claude/settings.json
    "statusLine": { "type": "command", "command": "bash \"${CLAUDE_PROJECT_DIR}/.ax/hud/statusline.sh\"" }

 [b] ⚠ 기존 statusLine 교체
  경고 omc HUD 등이 사라져요. 되돌리려면 사용자가 직접 settings.json 수정.

 [c] 합치기 — goax 한 줄 + 기존 HUD          [기존 statusLine 있을 때 권장]
  생성 .ax/hud/statusline-combined.sh (런타임 생성물 — template 에 없음, .gitignore 대상)
  수정 .claude/settings.json command 만 → bash "${CLAUDE_PROJECT_DIR}/.ax/hud/statusline-combined.sh"

 [a-fix] ⚡ 깨진 statusLine 1줄 복구   [부재 파일 참조 감지 시에만]

 [d] 취소

 ▸ 답해주세요 [a] / [b] / [c] / [d]
```

**[c] 합성 스크립트는 이 형태여야 해요** — stdin 을 한 번 받아 **양쪽에 각각** 먹여요:

```bash
#!/usr/bin/env bash
# .ax/hud/statusline-combined.sh — goax + 기존 HUD. 런타임 생성물이에요.
EXISTING='node "$HOME/.claude/hud/omc-hud.mjs"'      # 기존 statusLine.command 를 그대로 옮겨요
INPUT=$(cat)
printf '%s' "$INPUT" | bash "${CLAUDE_PROJECT_DIR:-.}/.ax/hud/statusline.sh"
printf '%s' "$INPUT" | eval "$EXISTING"
```

왜: 앞 스크립트가 `cat` 으로 stdin 을 다 먹으면 뒤 스크립트는 빈 입력을 받아요 — OMC 는
ctx%·모델을 못 그려요. 그리고 goax 출력이 개행으로 끝나야 다음 HUD 가 새 줄에서 시작해요.
이전 합치기(두 명령을 그냥 이어 붙인 것)는 둘 다 어겼어요.

**기본 동작**: 기존 statusLine 있으면 [c] 권장. 사용자 명시 동의 없이는 절대 변경 X.

### `/hud preset <minimal|focused|full>`

`.ax/config.yml` 의 `hud.preset` 을 바꿔요 (사용자 동의 후, 키가 없으면 블록을 추가). 바로 다음
렌더부터 반영돼요 — 재시작 필요 없어요.

### `/hud refresh` — 캐시 갱신

```bash
bash .ax/scripts/bash/update-state.sh
```

`hud.plugin_version`(skill 컨텍스트에서만) · `hud.review_required` · `hud.cached_at` 이 갱신돼요.
skill 들이 끝날 때 이미 부르니 보통은 필요 없어요. `(stale)` 이 보이면 이걸로 지워요.

### `/hud disable`

`.claude/settings.json` 은 직접 수정 안 해요 (사용자 권한 영역). 대신 안내:
```
goax statusline 을 끄려면 .claude/settings.json 에서 "statusLine" 필드를 제거하거나
"type": "static" + "value": "" 으로 바꿔주세요. 합치기였다면 기존 명령만 남기세요.
```

### 인자 없음 — 현재 상태 + 미리보기

```bash
printf '{"workspace":{"current_dir":"%s"}}' "$PWD" | COLUMNS="${COLUMNS:-120}" bash .ax/hud/statusline.sh
```

```
🪝 goax HUD

 렌더  [goax#0.5.1] | M×L2 · payment | spec ✓ › tasks ✓ › impl ● [######----]7/12 › review ○ | mistakes:3
 프리셋  focused (.ax/config.yml hud.preset)
 등록  .claude/settings.json statusLine → .ax/hud/statusline.sh (또는 statusline-combined.sh / 미등록)
 캐시  hud.cached_at 12분 전 · plugin_version 0.5.1
```

## 절대 금지

- 사용자 동의 없이 `.claude/settings.json` 수정 X
- 다른 plugin 의 statusLine 을 임의로 덮어쓰지 X
- 합성 스크립트를 "명령 두 개 이어 붙이기" 로 만들기 X — stdin 을 양쪽에 먹여야 해요
- `.ax/state.json` 외 다른 위치에 상태 저장 X
- statusline.sh 에서 스크립트를 호출하기 X — 300ms 디바운스 안에 끝나야 해요. 계산은 `update-state.sh` 가
- HUD 에 레인·게이트·경보 세그먼트 넣기 X — 하네스 위치만
