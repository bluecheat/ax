---
name: goax-release
description: "goax 플러그인 **이 저장소(goax repo)** 를 새 버전으로 배포하는 메인테이너 자동화 — 버전 3중(4곳) 동기화 bump → changelog → smoke 게이트 → Conventional Commits 형식(feat(scope): …) commit·브랜치 → PR → squash 머지 → vX.Y.Z 태그 → GitHub Release 를 한 번에. 사용자가 'goax 릴리즈', 'plugin 릴리즈', '버전 올려/bump', '패치/마이너/메이저 올려', '다음 버전 릴리즈', '0.2.3 릴리즈해줘', '이번 변경 배포해줘', '/goax-release' 처럼 **goax 자체의 버전업·배포**를 요청하면 반드시 이 스킬을 써요. 단 goax repo 루트에서만 — 사용자 프로젝트 릴리즈나 oh-my-claudecode 릴리즈는 대상 아님."
---

# goax-release — 플러그인 릴리즈 자동화

> ⚠️ **메인테이너 전용, goax repo 한정.** 이 스킬은 `.claude/skills/` 에 있어 사용자 프로젝트엔 안 실려요(`templates/default` 가 아님). goax plugin **자체**를 릴리즈할 때만 발동해요.

## 발동 트리거
- `/goax-release`, "goax 릴리즈", "plugin 릴리즈", "다음 버전 릴리즈", "버전 올려", "패치 올려"
- "0.2.3 릴리즈" 처럼 버전을 명시하거나, "패치/마이너/메이저" 로 증가분만 말해도 돼요.

## 전제 점검 (시작 전)
1. **goax repo 루트** 인지 — `VERSION`, `.claude-plugin/plugin.json`, `tests/smoke.sh` 존재 확인.
2. **gh 인증** — `gh auth status` (PR·release 에 필요).
3. **릴리즈 대상 변경**이 이미 있는지 — 보통 직전 작업이 워킹트리/브랜치에 있어요. 없으면 "무엇을 릴리즈하나요?" 확인.
4. 버전 인자 파싱 — 명시 버전(`0.2.3`) 또는 증가분(`patch|minor|major`). 둘 다 없으면 사용자에게 물어요(기본 제안: patch).

## 흐름

### 1. 버전 결정 + 3중 동기화 bump (결정론)

`bump-version.sh` 가 4곳(VERSION · plugin.json · marketplace.json top + plugins[0])을 targeted sed 로 일괄 변경하고 일치를 재검증해요. jq rewrite 안 함 → formatting 보존.

```bash
# 명시 버전
bash .claude/skills/goax-release/bump-version.sh 0.2.3 --json
# 또는 증가분
bash .claude/skills/goax-release/bump-version.sh --next patch --json
# (미리보기) --dry-run / (검증만) --check
```

`--json` 의 `result.new` 를 이후 단계의 `<VERSION>` 으로 써요. 실패(불일치/형식오류) 면 **halt**.

### 2. changelog 작성 — `changelog/<VERSION>.md`

직전 작업의 **실제 변경 내용만** 담아요. 이전 changelog 파일(`changelog/<직전버전>.md`) 의 포맷·톤을 따라요.

- ✅ 무엇이 바뀌었나(파일·동작), 검증 방법
- ❌ **검토 과정·기각한 대안·"왜 X 가 아닌가" 같은 deliberation 금지** — changelog 는 결과만 (0.2.1 교훈).
- ❌ 버전 마커(`(NEW 0.x+)`) 본문에 박지 않기.

첫 줄은 `# <VERSION> — <한 줄 요약>`.

### 3. smoke 게이트

```bash
bash tests/smoke.sh
```
버전 4곳 일치 + 구조 계약을 강제해요. **실패 시 즉시 halt + 보고** (커밋·PR 진행 금지).

### 4. commit — Conventional Commits 형식

브랜치·커밋·PR 제목은 **`<type>(<scope>): <한글 요약>`** 템플릿을 따라요. squash 머지하면 PR 제목이 main 의 커밋 제목이 되니, main 히스토리가 곧 이 형식이에요.

**type** — 이번 릴리즈의 *주된* 변경으로 하나만 골라요:

| type | 언제 |
|---|---|
| `feat` | 사용자 프로젝트에 새 동작이 생김 (훅·스크립트·스킬·게이트 추가) |
| `fix` | 잘못 동작하던 걸 고침 (오탐·누락·크래시·포터빌리티) |
| `refactor` | 동작 그대로, 구조만 |
| `docs` | 문서·changelog 만 |
| `test` | smoke·evals 만 |
| `chore` | 그 밖 — 순수 버전 bump 는 `chore(release)` |

**scope** — 가장 많이 바뀐 영역 하나, kebab-case: `hooks` · `spec` · `adr` · `triage` · `doctor` · `lane` · `scripts` · `templates` · `evals` · `release` 등. 여럿이면 사용자 체감이 큰 쪽.

**브랜치** — 괄호는 셸 인용이 번거로워서 브랜치 이름은 `<type>/<scope>-<짧은-slug>` 로 써요 (예: `feat/hooks-fact-gates`, `chore/release-0.7.0`). 이미 작업 브랜치 위에 있으면(기능+릴리즈 번들) 그 브랜치를 그대로 써요. main 이면 먼저 만들어요.

```bash
git checkout -b <type>/<scope>-<slug>   # main 일 때만
git add VERSION .claude-plugin/plugin.json .claude-plugin/marketplace.json changelog/<VERSION>.md [+ 변경 파일]
git commit -F - <<'EOF'
<type>(<scope>): <한글 요약> (v<VERSION>)

<본문: 무엇이 좋아졌는지 → 무엇을 바꿨는지, 한글로>

<세션이 알려준 Co-Authored-By · Claude-Session 줄 — 모델 이름을 손으로 박지 않아요>
EOF
```

예: `feat(hooks): 룰을 읽기 전엔 편집을 막고 파괴 명령은 사실부터 적게 해요 (v0.7.0)` · `fix(spec): --delta 가 1 라운드에서 전부 바뀜이라던 것 (v0.6.3)` · `chore(release): v0.7.1`.
요약은 **한글**, 끝의 `(vX.Y.Z)` 로 main 로그에서 릴리즈 커밋을 찾아요. 작업 중 커밋이 여러 개면 각자 `<type>(<scope>): …` 로 쌓아도 돼요 — squash 가 PR 제목 하나로 합쳐요.

### 5. PR

```bash
git push -u origin <branch>
gh pr create --base main --title "<type>(<scope>): <한글 요약> (v<VERSION>)" --body "<...>"
```
PR 제목 = 4단계 커밋 제목과 같은 템플릿. PR 본문 끝에 `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

### 6. squash 머지

```bash
gh pr merge <PR#> --squash --delete-branch
```
⚠️ **CI 주의** — 이 repo 는 조직 설정상 *GitHub Actions hosted runners 가 비활성*이라 `smoke` 체크가 러너 부재로 2초만에 fail 떠요(코드 문제 아님). **branch protection 이 없어 머지엔 영향 없어요.** 게이트는 **로컬 smoke 통과**. (러너를 켜려면 조직 Settings → Actions.)

### 7. 태그

```bash
git checkout main && git pull origin main
git tag -a v<VERSION> -m "v<VERSION> — <요약>"
git push origin v<VERSION>
```
컨벤션: `vX.Y.Z` (예: `v0.2.2`).

### 8. GitHub Release

```bash
gh release create v<VERSION> --title "v<VERSION> — <요약>" --notes-file changelog/<VERSION>.md --latest
```

## 완료 보고

릴리즈 후 한눈 요약: PR# (머지됨) · main HEAD · VERSION 4곳 일치 · 태그 · Release URL. CI 가 러너 부재로 fail 이면 그 사실(코드 무관)도 명시.

## 주의 (왜 중요한지)
- **버전은 항상 4곳 동시** — `tests/smoke.sh` 가 VERSION·plugin.json·marketplace.json(top+plugins[0]) 이 모두 같은지 강제해요. 한 곳만 손으로 고치면 smoke 가 바로 깨지니, `bump-version.sh` 로만 만지고 `--check` 로 의심될 때 검증해요.
- **changelog 는 실제 변경 내용만** — 사용자가 보는 릴리즈 노트라, 검토 과정·기각한 대안 같은 deliberation 을 넣으면 무엇이 바뀌었는지가 묻혀요 (0.2.1 에서 직접 겪은 교훈).
- **커밋·PR 제목은 `<type>(<scope>): <한글 요약> (vX.Y.Z)`** — Conventional Commits 템플릿, 요약은 한글. 태그·Release 제목은 `vX.Y.Z — <요약>`. 0.6.3 까지의 `release: …` 형식은 더 쓰지 않아요.
- **버전 마커(`(NEW 0.x+)`) 금지** — 금방 낡아서 re-read 를 깨요 (repo CLAUDE.md 룰).
- **smoke 실패 = 릴리즈 중단** — 버전 불일치나 구조 계약 위반을 안고 배포하면 사용자 설치가 깨져요. 고치고 다시.
