# .ax/hooks — Sensors

AI 에이전트의 결과를 *작업 후* 자동 검증하는 sensor 4종(Computational/Inferential/Structural/Functional)을 hooks로 자동화해요.

| 위치 | 시점 | 역할 |
|---|---|---|
| user-prompt/ | 사용자 메시지 도착 직후 | Triage 미실행(phase=idle) + 구현 의도 감지 시 reminder 주입 |
| pre-bash/ | bash 도구 호출 직전 | 파괴적 명령 차단 + `git commit` 감지 시 critical-rule-grep 위임 |
| pre-edit/ | Edit/Write 직전 | 보호 경로 변경 확인 + spirit 룰 점검 |
| post-edit/ | Edit/Write 직후 | 변경 파일 lint (경고만) |
| pre-commit/ | git commit 직전 | CRITICAL 룰 정적 검출 (위반 시 차단/경고만 — 자동 캡처는 폐기, §"Mistake 캡처" 참고) |

## 동작 모드 — `sensors.mode`

`.ax/config.yml`의 `sensors.mode` 값에 따라 hook이 다르게 반응해요:

- `warning` — stderr 메시지만 출력하고 통과 (default, 도입 초기 권장)
- `fail` — Claude Code hook은 **exit 2**로 차단(stderr가 모델에 reroute), git pre-commit은 **exit 1**로 차단
- `off` — hook 전체 침묵 (응급용)

도입 초기엔 `warning`으로 시작해 팀이 룰을 학습하고, 데이터가 쌓이면 카테고리별로 `fail`로 승격하는 흐름을 권장해요. 모든 hook이 `goax_mode` helper(`.ax/scripts/bash/common.sh`)로 동일한 방식으로 이 값을 읽어요.

## Hook 입출력 규약 (Claude Code)

- **입력**: stdin JSON `{tool_name, tool_input, ...}`. `tool_input.command`(Bash) / `tool_input.file_path`(Edit/Write)을 jq로 파싱.
- **차단**: `exit 2` + stderr 메시지(모델에 보여짐). `exit 1`은 일반 에러 처리되어 차단되지 않아요.
- **경고**: stderr 출력 후 `exit 0`.
- **변수**: `$CLAUDE_PROJECT_DIR`(사용자 프로젝트 루트)는 Claude Code가 자동 주입. plugin 자체 위치는 `${CLAUDE_SKILL_DIR}`(skill 디렉토리, Claude Code 공식 변수)로 도출 — `${CLAUDE_SKILL_DIR}/../..` 가 plugin root. (`$CLAUDE_PLUGIN_ROOT`는 비표준 — 호환용으로 fallback에만 둘 것.)

## settings.json 등록 형식

`.claude/settings.json`의 `hooks`는 PascalCase 이벤트 키 + `hooks:[{type,command}]` 중첩 형태예요:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PROJECT_DIR}/.ax/hooks/user-prompt/triage-nudge.sh\"" }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PROJECT_DIR}/.ax/hooks/pre-bash/block-destructive.sh\"" },
          { "type": "command", "command": "bash \"${CLAUDE_PROJECT_DIR}/.ax/hooks/pre-bash/grep-on-commit.sh\"" }
        ]
      }
    ]
  }
}
```

`UserPromptSubmit`은 매처 없이 모든 사용자 메시지에 발화해요. `PreToolUse`/`PostToolUse`는 `matcher`(도구 이름)로 필터.

## 프로젝트별 커스터마이즈

- `post-edit/lint-changed.sh` — 자기 스택의 lint 명령으로 교체
- `pre-commit/critical-rule-grep.sh` — 자기 CRITICAL 룰의 grep 패턴 추가 (또는 룰별 sensor 신설)
- `user-prompt/triage-nudge.sh` — intent regex가 자기 프로젝트 어휘에 맞지 않으면 조정
- 새 hook 추가 시 위 settings.json 형식 그대로

## Mistake 캡처 — 사용자 명시 skill 만

hook 들 (`pre-edit/check-protected-paths.sh`, `pre-commit/critical-rule-grep.sh`, `pre-bash/block-destructive.sh`) 은 차단/경고만. mistake 자동 capture 는 폐기 — 위반이 mistake 로 자동 박히면 일상 작업이 자기 자신을 신고하는 잡음 루프 + 본문 quality 가 placeholder.

mistake 기록은 사용자 명시 `mistake` skill 호출로만 (`"실수 기록해줘"`, `/mistake`). 사용자가 의도적으로 capture 한 mistake 만 `.ax/mistakes/` 에 누적 → audit 시 의미있는 패턴 추출.

## Claude Code 외 환경

git pre-commit hook으로도 직접 등록할 수 있어요 (이쪽은 exit 1이 차단):

```bash
ln -sf "$(pwd)/.ax/hooks/pre-commit/critical-rule-grep.sh" .git/hooks/pre-commit
```

Claude Code의 `PreToolUse:Bash` 등록(`grep-on-commit.sh` wrapper)과 git symlink 둘 다 두면 어느 경로로 commit하든 검출돼요.
