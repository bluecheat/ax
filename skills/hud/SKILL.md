---
name: hud
description: "goax HUD/statusline 관리 — 'HUD 활성화', 'statusline 설정', 'HUD 갱신' 등. statusline은 .ax/hud/statusline.sh가 .ax/state.json을 읽어 한 줄 출력. 기존 statusLine(omc 등)과 충돌 안 나게 안내. 슬래시로도 호출 가능: '/hud'."
---

# hud — 4계층 활성도 시각 신호

## 시작 전 필수
`.ax/spirit/values.md`, `tone.md` 따라요.

## 무엇을 보여주는가

statusline 한 줄 — 매 응답 위에 표시:
```
triage: M×L2 | harness: 🌟 | ☄2
```

| 부분 | 의미 |
|---|---|
| `triage: M×L2` | 현재 작업 Size×Risk (current_task 매칭 시만 표시) |
| `harness: 🌟` | Layer 0/1/2/3 종합 활성도 — 우주 진화 한 글자 (· ✦ ⭐ 🌟 🪐, 0/4~4/4) |
| `☄2` | 미승격 mistakes 수 (색상: 5+ 노랑, 10+ 빨강) |

## subcommand

### `/hud setup` — 활성화 (★ 충돌 안전)

1. `.claude/settings.json` 존재 확인
2. **기존 statusLine 검사** — 있으면 절대 자동 덮어쓰지 않음. 단 statusLine.command가 *부재 파일*을 가리키는 **깨진 상태**(예: 이전 install 잔재로 `statusline-combined.sh`를 호출하지만 그 파일이 없는 경우)면 [a-fix] 옵션을 권장으로 표시.
   - 검사: 현재 command 문자열에서 `bash <path>` 형태의 path 추출 → `[ -f "$path" ]` 확인 → 부재면 broken
3. 옵션 제시:

```
[hud setup]

 📍 발견
  .claude/settings.json: 존재
  statusLine: <현재 상태 — 없음 / omc / 다른 plugin / 사용자 정의>

 ─ 옵션 ──────────────────────────────────────────

 [a] ✓ 신규 등록         [기존 statusLine 없을 때만 권장]
  수정 .claude/settings.json
    "statusLine": { "type": "command", "command": "bash .ax/hud/statusline.sh" }
  영향 매 응답 위에 한 줄 추가

 [b] ⚠ 기존 statusLine 교체
  기존: <현재 statusLine>
  대체: goax statusline
  경고: omc HUD 등이 사라짐. 되돌리려면 사용자가 직접 settings.json 수정.

 [c] 합치기 — 한 줄에 둘 다
  방법 새 합성 스크립트 생성 (런타임 생성물 — template에 없음)
    .ax/hud/statusline-combined.sh:
    bash .ax/hud/statusline.sh
    bash <기존 명령>
  수정 .claude/settings.json command만 → bash .ax/hud/statusline-combined.sh
  장점 goax + omc HUD 공존
  주의 [c]를 선택하지 않았다면 statusline-combined.sh는 *존재하지 않는 게 정상*.
       기존 settings.json이 이 파일을 참조하는 깨진 상태면 [a-fix] 사용.

 [a-fix] ⚡ 깨진 statusLine 1줄 복구  [부재 파일 참조 감지 시에만 표시]
  현재  bash <부재 파일>  ← settings.json이 가리키지만 디스크에 없음
  수정  bash ${CLAUDE_PROJECT_DIR}/.ax/hud/statusline.sh
  영향  .claude/settings.json statusLine.command 한 줄만 수정. 그 외 보존.

 [d] 취소

 ▸ 답해주세요 [a] / [b] / [c] / [d]
```

**기본 동작**: 기존 statusLine 있으면 [a] 추천 안 함, [c] 합치기 추천. 사용자 명시 동의 없이는 절대 변경 X.

### `/hud refresh` — state.json canonical 갱신

```bash
bash .ax/scripts/bash/update-state.sh
```

✓ 메시지: `state.json 갱신 (harness: 🌟, mistakes 3건)`

### `/hud disable`

`.claude/settings.json` 직접 수정 안 함 (사용자 권한 영역). 대신 안내:
```
goax statusline을 끄려면 .claude/settings.json에서 "statusLine" 필드를 제거하거나
"type": "static" + "value": "" 으로 바꿔주세요.

자동 수정 원하면 "/hud setup" → [d] 취소 → 사용자가 직접.
```

### 인자 없음 — 현재 상태

```
🪝 goax HUD 상태

 state.json 존재 (갱신: 2026-05-02 15:30, 35분 전)
 statusline 활성 (.ax/hud/statusline.sh)
 settings  .claude/settings.json에 등록됨

 마지막 갱신 항목: spec-validate (current_task.spec_passed = false)
```

## 절대 금지

- 사용자 동의 없이 `.claude/settings.json` 수정 X
- 다른 plugin의 statusLine을 임의로 덮어쓰지 X
- `.ax/state.json` 외 다른 위치에 상태 저장 X (전역 ~/.ax/ 같은 곳 X)
- statusline.sh가 state.json 못 읽어도 (jq 없거나 등) 무한 대기 X — 100ms 안에 종료
