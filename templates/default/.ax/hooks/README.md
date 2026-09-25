# .ax/hooks — Sensors

AI 에이전트의 결과를 *작업 후* 자동 검증하는 sensor 4종(Computational/Inferential/Structural/Functional)을 hooks로 자동화해요.

| 위치 | 시점 | 역할 |
|---|---|---|
| session-start/ | 세션 시작·재개·compact 직후 | `session-brief.sh` — 인계 노트 · 설치본 버전 지연 · 밀린 audit · 같은 종류 실수 재발을 짧게 (알릴 게 없으면 출력 없음). compact 직후엔 압축 직전 스냅샷을 맨 앞에 |
| pre-compact/ | 컨텍스트 압축 직전 | `snapshot.sh` — 브랜치·HEAD · 커밋 안 된 파일 · 진행 중 spec 의 tasks 진행률을 `.ax/.session/<sid>/precompact.txt` 에 (LLM 요약 아님, 압축을 막지 않음) |
| user-prompt/ | 사용자 메시지 도착 직후 | Triage 미실행(phase=idle) + 구현 의도 감지 시 reminder 주입 |
| pre-bash/ | bash 도구 호출 직전 | 파괴적 명령 차단 · git 훅 우회(`--no-verify` 등) 차단 · 프로젝트 안 되돌리기 어려운 명령은 사실 확인 · `git commit` 감지 시 pre-commit 체인 위임 |
| pre-edit/ | Edit/Write 직전 | 보호 경로 변경 확인 + spirit 룰 점검 · 룰 경로 주입 · 이 파일에 걸린 룰을 안 읽었으면 편집 차단(`rule-read-gate`) · 품질 설정 수정은 이유 먼저(`quality-config-gate`) |
| post-edit/ | Edit/Write 직후 | `commands.lint_file` 로 편집한 파일 하나를 검사, 실패하면 출력을 모델에게 (막지 않음 · 비어 있으면 아무것도 안 함) |
| pre-commit/ | git commit 직전 | CRITICAL 룰 정적 검출 (위반 시 차단/경고만 — 자동 캡처는 폐기, §"Mistake 캡처" 참고) |
| subagent-start/ | 서브에이전트가 뜨는 순간 | Constitution·Spirit·현재 spec·인계 노트 **경로**를 additionalContext 로 — 하네스가 메인 세션 밖으로 닿게 (goax 자기 에이전트는 제외) |
| stop/ | 턴이 끝나려는 순간 | 활성 spec(implementing·review)이 완료 게이트 미통과면 **한 번** 멈춰 세우고 "마저 하기 · 보류 표기 · 인계 노트" 셋 중 하나를 시켜요 |

## 끄기 · 프로필 — 게이트마다 탈출구

모든 등록 훅은 `common.sh` 의 `goax_hook_enabled <훅 ID> <minimal|standard>` 를 거쳐요. 훅 ID 는 파일 이름에서 `.sh` 를 뺀 것.

- `.ax/config.yml` `sensors.disabled_hooks: [rule-read-gate]` — 그 훅만 꺼요. 한 세션만이면 `GOAX_DISABLED_HOOKS=rule-read-gate`.
- `sensors.hook_profile: minimal` — 안전망만 남겨요 (`block-destructive` · `block-hook-bypass` · `check-protected-paths` · `grep-on-commit`). 주입·게이트는 `standard`(기본)에서만.
- `block-destructive.sh` 의 CATASTROPHIC(루트·시스템 경로 삭제 등)은 이 스위치 **앞**에서 끝나요 — 끌 수 있는 안전망이 아니에요.
- `sensors.mode: off` 는 예전처럼 모든 훅이 아무것도 출력하지 않아요.

## 사실을 요구하는 게이트 — "정말요?" 대신

"확실해요?" 라고 물으면 모델은 늘 "네" 라고 해요. 그래서 이 게이트들은 **사실**을 요구하고, 사실이 채워지면 통과시켜요
(ECC GateGuard 의 fact-forcing 방식). 모두 `sensors.mode` 가 `warning` 이어도 막아요 — 통과하는 데 드는 수고가 작아서예요.

- `pre-edit/rule-read-gate.sh` — 편집 대상에 걸린 룰 파일(spirit `paths:` · module `paths:`+`applies_to: code`)을 이번 세션에
  **Read 도구로** 읽었는지 `.ax/.session/<sid>/rules-read.log` 로 확인해요 (compaction 이 일어나면 SessionStart 훅이 이 기록을 지워서 다시 읽게 해요). 안 읽었으면 목록을 주고 막아요. CLAUDE.md·AGENTS.md 가
  `@` 로 import 한 룰은 이미 컨텍스트에 있어서 빼요. 경로 예외는 `sensors.rule_gate_exempt`. 매칭 함수는 주입 훅과 같아요
  (`goax_rules_matching` · `goax_module_rules_matching`) — 둘이 어긋나면 "주입은 했는데 게이트는 안 거는" 룰이 생겨요.
  실측(commerce): mistakes 22건 중 20건을 사용자가 잡았고 절반이 "고치기 전에 조사 안 함" — 그중 하나는 "hook 이 읽으라 지시한 룰 파일을 건너뛰고".
- `pre-bash/destructive-facts.sh` — 프로젝트 안 재귀 rm · `git clean -f` · `git checkout -- <경로>` · `git restore` · `git reset --hard` ·
  `git stash drop|clear` · `git branch -D` · `find -delete` 를 세션에서 처음 볼 때 한 번 막고 "지워질 파일 목록 · 되돌리는 절차 ·
  사용자 지시 원문" 을 요구해요. 같은 명령을 다시 실행하면 통과. 재생성 디렉토리(여러 생태계의 흔한 이름을 기본값으로 — build·target·node_modules·
  .next·__pycache__·Pods·.terraform …)와 프로젝트 밖 경로(`git -C <다른 리포>` 포함)는 안 봐요. 스택을 가정하지 않으려고 그 밖의 경로는
  프로젝트가 `sensors.regenerable_paths` 글롭으로 선언해요.
  실측(commerce): 되돌리려고 `rm -rf` 로 디렉토리째 지웠다가 추적 안 되던 운영 파일까지 사라졌어요.
- `pre-edit/quality-config-gate.sh` — **이미 있는** lint·format·타입 검사·커버리지·git 훅 설정 파일(`.eslintrc*` · `.editorconfig` ·
  `tsconfig*.json` · `detekt*.yml` · `ruff.toml` · `.golangci.yml` · `.rubocop.yml` · `.husky/` · `.pre-commit-config.yaml` … 생태계 공통 이름)을
  세션에서 처음 고칠 때 한 번 막고 "완화인지 강화인지 · 사용자 지시 원문" 을 요구해요. 같은 파일을 다시 고치면 통과, 새로 만드는 건 안 막아요.
  다른 설정이 섞인 파일(`package.json` · `pyproject.toml` · `build.gradle`)은 기본값이 아니에요 — 필요하면 `sensors.quality_configs` 글롭으로.
  검사가 실패할 때 코드 대신 규칙을 끄는 쪽으로 가는 걸 막으려고요 (ECC config-protection).
- 모두 세션당 3번까지 전체 안내, 그 뒤는 한 줄이에요 — 같은 긴 문구가 컨텍스트에 쌓이면 반복 루프를 부른다는 ECC 실측(#2142)을 따라요.
  세션 id 가 없으면(수동 실행) 추적할 수 없어서 rule-read-gate 는 통과, destructive-facts · quality-config-gate 는 경고로 강등해요.
- 명령 판정은 `goax_shell_scan`(python3 shlex — 따옴표·주석·heredoc·here-string 을 셸처럼)이 해요. python3 가 없거나 **있는데 실패하면**
  (macOS xcrun shim 등 — `goax_py_ok` 가 실제 import 로 확인) 두 Bash 게이트는 따옴표를 뗀 문자열로 간이 판정해요. 판정 못 했다고 통과시키지 않아요.

## git 훅 우회 — `pre-bash/block-hook-bypass.sh`

에이전트가 `--no-verify` · `git commit -n` · `git -c core.hooksPath=…` · `git config core.hooksPath <값>` · `HUSKY=0`/`LEFTHOOK=0` 로
프로젝트의 git 훅을 끄는 걸 막아요 (`sensors.mode` 가 warning 이어도). goax 자체의 pre-commit 체인은 `grep-on-commit.sh` 가 PreToolUse 에서
먼저 돌려서 이 플래그로 안 빠지지만, 프로젝트 훅(`external:*` — husky·lefthook·commit-msg·pre-push)은 사라져요. 판정은 `goax_shell_scan` 이
따옴표·heredoc 을 셸처럼 읽어서 해요 — `git commit -m "fix -n handling"` 의 `-n` 은 안 걸려요. 사람은 `! git commit --no-verify …` 로 직접 할 수 있어요.

## 세션 내 중복 주입 — 같은 포인터는 한 번만

`pre-edit/spirit-rules-inject.sh` 와 `module-rules-inject.sh` 는 편집마다 매칭된 룰 파일 **경로**를 주입해요.
실측(한 프로젝트 한 세션)에서 이게 1,200회 · 529KB 였고, 편집한 파일은 196개였어요 — 같은 룰 경로가 편집마다
다시 들어간 거예요. 그래서 `common.sh` 의 `goax_inject_fresh` 가 세션(`session_id`)마다 마커
(`.ax/.session/<sid>/injected/<key>`)를 두고, 같은 포인터는 4시간(`GOAX_INJECT_TTL`) 안엔 다시 안 줘요.
compaction 뒤엔 4시간 TTL 이 다시 줄 여지를 남겨요. 세션 id 가 stdin 에 없으면(수동 실행) 예전처럼 매번 줘요.

## Stop 게이트 — 멈춰 세우는 건 한 번, 세션당 8회까지

`stop/spec-gate.sh` 는 `current-task.json` 의 phase 가 `implementing`·`review` 이고 `tasks-gate.sh` 가 위반을
보고할 때만 `{"decision":"block","reason":…}` 로 한 턴을 더 줘요. Claude Code 가 재시도할 땐
`stop_hook_active=true` 로 오고 그땐 무조건 통과 — 무한 루프는 공식 계약이 막아요. 인계 노트
(`current-task.json` 의 `handoff.now`)에 그 spec 이 **24시간 안에** 적혀 있으면 멈추는 게 의도라고 보고 잡지 않아요 —
`status-note.sh --set now` 가 `handoff.now_at` 필드에 시각을 적고 게이트가 그 시각을 봐요. 시각이 없는 옛
노트는 인정하지 않아요 (예전엔 spec 이름만 있으면 통과라서 몇 주 전 노트 한 줄이 새 세션의 게이트를 영구히
꺼 버렸어요). 지울 땐 `status-note.sh --clear now`. 이 훅은 실행될 때 `.ax/.session/*` 의 24시간 넘은
디렉토리도 지워요 — 그 청소가 pre-edit 훅에만 있어서 Edit 없는 세션은 아무것도 못 지웠거든요.
세션당 상한은 `GOAX_STOP_GATE_MAX`(기본 8) — `.ax/.session/<sid>/stop-blocks` 카운터. 끄려면 `sensors.mode=off`.

## Secrets 검출 — 패턴의 SSOT 는 `common.sh` 의 표 하나예요

시크릿의 형태를 아는 곳은 `.ax/scripts/bash/common.sh` 의 `goax_secret_rules` 표 **하나** 예요.
`pre-commit/critical-rule-grep.sh` 의 검출은 `goax_secret_patterns`(표의 `use=both|detect` 행)에서,
`redact_secrets` 의 마스킹은 같은 표의 `use=both|mask` 행에서 나와요. 형태를 하나 더할 땐 표에만 행을
넣으세요 — 훅에 패턴을 다시 적으면 그 순간 두 곳이 어긋나요. 실제로 어긋나 있었고(웹훅은 마스킹만,
`pg_key` 는 마스킹만, `passwd`·`access_key` 는 검출만, AWS·Stripe·JWT 는 정량자가 서로 달랐어요),
그래서 같은 파일에 검출과 마스킹이 다른 답을 냈어요.

표는 두 갈래를 담아요. ① 발급처가 형식을 정해둔 토큰 — 대소문자를 그대로 봐야 오탐이 안 늘어요.
② `key=value` — 키 이름의 대소문자는 표가 브래킷으로 담고 있어서 `grep -i` 가 필요 없고, 검출 행과
마스킹 행이 키 목록 조각을 공유해요. `${GITHUB_TOKEN}`·`<from env>` 같은 참조 표기와 `secret: null`·
`token_count = 0` 은 값 첫 글자와 최소 길이로 걸러요. 검출되면 **파일 이름만** 찍어요 — 매칭된 줄을
stderr 로 흘리면 검출한 의미가 없어요.

`common.sh` 가 없으면 검출할 패턴 자체가 없어요. 그때는 조용히 통과하지 않고
`[goax] common.sh 없음 — secrets 안전망 비활성 (.ax/scripts/bash/common.sh 복구 필요)` 를 stderr 에
남기고 통과해요 (아래 jq 규약과 같은 원칙). 이 부재가 가장 흔한 시점은 설치 중간이에요 — `.ax/hooks` 는
이미 있고 `.ax/scripts/bash` 는 아직 없는 창이 실재해서, 무성 통과면 안전망이 꺼진 걸 아무도 몰라요.

## jq 가 없어도 조용히 넘어가지 않아요

`pre-bash/block-destructive.sh` 와 `pre-edit/check-protected-paths.sh` 는 stdin JSON 을 jq 로 파싱해요.
jq 가 PATH 에 없으면 인자를 못 뽑아 그냥 통과(fail-open)하는데, 예전엔 그게 **무성**이라 `rm -rf /etc` 가
아무 출력 없이 exit 0 이고 안전망이 꺼진 걸 아무도 몰랐어요. 이제 `[goax] jq 없음 — 이 안전망이 비활성
상태예요` 를 stderr 에 한 줄 남기고 통과해요 (fail-open 자체는 그대로).

## 설치 시 심볼릭 링크 — 따라가지 않아요

`scripts/provision.sh` 는 대상 경로에 심링크가 한 조각이라도 끼어 있으면 아무것도 쓰지 않고 `warnings` 에
남겨요(`status: warning`). `.ax/hooks` 를 프로젝트 밖으로 걸어 두면 훅 파일이 통째로 밖에 생기고,
`.claude/settings.json` 은 그 경로를 등록하니 이후 세션이 프로젝트 밖 코드를 실행하게 돼요. 댕글링 링크도
같이 막아요 — `[ -e ]` 가 false 라 "없으니 새로 만들자" 로 읽히면 링크가 가리키던 자리에 파일이 생겨요.

## 동작 모드 — `sensors.mode`

`.ax/config.yml`의 `sensors.mode` 값에 따라 hook이 다르게 반응해요:

- `warning` — stderr 메시지만 출력하고 통과 (default, 도입 초기 권장)
- `fail` — Claude Code hook은 **exit 2**로 차단(stderr가 모델에 reroute), git pre-commit은 **exit 1**로 차단
- `off` — 모든 hook 이 출력 없이 통과 (응급용)

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

`UserPromptSubmit`·`SubagentStart`·`Stop` 은 매처 없이 발화해요. `PreToolUse`/`PostToolUse`는 `matcher`(도구 이름)로 필터. 등록해야 할 이벤트·hook 의 SSOT 는 `templates/default/.claude/settings.json.template` — `doctor` 가 이벤트 키와 파일 둘 다 대조해요.

## 프로젝트별 커스터마이즈

- `post-edit/lint-changed.sh` — 훅을 고치지 말고 `.ax/config.yml` `commands.lint_file` 에 `"<글롭> => <명령 {file}>"` 를 적어요 (후보: `detect-stack.sh`, 쓰기: `config-set.sh --add commands.lint_file …`)
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
