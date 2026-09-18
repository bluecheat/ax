# eval-hook-shim — `claude plugin eval` 용 hook 미러

`claude plugin eval` 샌드박스는 프로젝트 `.claude/settings.json` 을 읽지 않아요 (던지기 config 에
cwd 의 trust 기록이 없음 — 실측 2026-09-18: UserPromptSubmit·PreToolUse·Stop 마커 0개). 대신
**플러그인 hook** (`hooks/hooks.json`) 은 로드하고, `${CLAUDE_PROJECT_DIR}` 도 샌드박스 cwd 로
정확히 잡혀요. 그래서 goax 가 사용자 프로젝트에 등록하는 hook 을 여기서 플러그인 hook 으로
한 번 더 등록해 두고, 케이스의 `case.yaml` 이 goax 와 함께 이 shim 을 로드해요:

```yaml
plugins: ["../..", "../../tests/eval-hook-shim"]
```

hook 스크립트 자체는 shim 에 없어요 — 케이스의 `scaffold_script` 가 `scripts/provision.sh` 로
`.ax/` 를 샌드박스에 설치하고, 여기 등록된 `${CLAUDE_PROJECT_DIR}/.ax/hooks/...` 가 그걸 가리켜요.
그래서 eval 이 재는 건 "hook 이 등록되는가" 가 아니라 (그건 smoke §4.1 · doctor 가 봐요)
"등록된 hook 이 그 상황에서 그렇게 행동하는가" 예요.

`hooks.json` 은 템플릿에서 기계적으로 뽑아요 — 손으로 고치지 마세요:

```bash
jq '{hooks: .hooks}' templates/default/.claude/settings.json.template > tests/eval-hook-shim/hooks/hooks.json
```

`tests/smoke.sh` 가 두 파일의 `hooks` 객체가 같은지 검사해요. 배포 대상이 아니에요 (marketplace 에 없음).
