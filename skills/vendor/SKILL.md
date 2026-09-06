---
name: vendor
description: "goax skill·command·agent 를 저장소에 동봉해서 plugin 설치 없이 팀 전체가 쓰게 만들어요. 모노레포처럼 ADE 루트(.claude/)와 프로젝트 루트(.ax/)가 다른 경우를 자동 처리. 트리거: '/vendor', 'goax 동봉', '플러그인 없이', '팀에 배포', 'vendoring', '스킬 복사', 'goax vendor'."
---

# vendor — 저장소에 goax 동봉

## 시작 전 필수

`.ax/spirit/values.md`, `tone.md` 를 읽고 따라요.

## 언제 쓰나

goax 를 쓰는 방법은 두 가지예요.

| | plugin 설치 | **동봉 (vendor)** |
|---|---|---|
| 설치 | 팀원 각자 `/plugin install goax` | 없음 — clone 하면 끝 |
| 갱신 | 각자 `/plugin marketplace update` | `/vendor` 재실행 후 커밋 |
| 버전 | 사람마다 다를 수 있음 | 저장소가 고정 |
| 적합 | 개인·소수 | **팀 전체, CI, 온보딩 마찰 제거** |

동봉을 고르는 이유는 보통 하나예요 — **팀원이 아무것도 설치하지 않아도 되게.**

## 두 개의 루트 — 이 skill 의 핵심

```
ADE 루트        에이전트가 스킬을 찾는 곳.  .claude/skills/ 가 여기 있어야 해요.
프로젝트 루트    코드와 하네스가 있는 곳.    .ax/ 가 여기 있어요.
```

단일 저장소면 둘이 같아요. **모노레포면 갈라져요:**

```
commerce-monorepo/          ← ADE 루트 (.claude/ 가 여기)
├─ .claude/skills/          ← 에이전트는 여기서 스킬을 찾아요
├─ .goax-root               ← "하네스는 projects/commerce 에 있다"
└─ projects/
   └─ commerce/             ← 프로젝트 루트
      └─ .ax/               ← 하네스는 여기
```

갈라지면 문제가 생겨요. 스킬은 `.ax/scripts/bash/…` 를 부르는데, 세션이
저장소 루트에서 시작하면 `.ax/` 가 **하위**에 있어서 조상 탐색으로는 영영
못 찾아요. 그래서 이 skill 이 `.goax-root` 포인터를 남겨요 —
`common.sh` 의 `find_project_root` 가 그걸 읽어서 하네스를 찾아가요.

> 단일 저장소면 포인터를 만들지 않아요. 불필요한 파일을 남기지 않으려고요.

## 1. 현재 상태 확인

```bash
PLUGIN_ROOT="${CLAUDE_SKILL_DIR}/../.."
RES=$(bash .ax/scripts/bash/vendor-skills.sh --check --plugin-dir "$PLUGIN_ROOT" --json)
echo "$RES" | jq -r '.result | "vendored=\(.vendored) v\(.vendored_version) plugin=v\(.plugin_version) stale=\(.stale) split=\(.split)"'
```

## 2. 무엇을 할지 보여주기 — `--dry-run`

동봉은 저장소에 파일을 추가하는 일이라, 먼저 계획을 보여주고 동의를 받아요.

```bash
bash .ax/scripts/bash/vendor-skills.sh --plugin-dir "$PLUGIN_ROOT" --dry-run --json
```

출력 형태:

```
📦 goax 동봉 (v0.4.0)

 📍 루트
  ADE 루트      commerce-monorepo/            (.claude/ 가 여기)
  프로젝트 루트  commerce-monorepo/projects/commerce/  (.ax/ 가 여기)
  → 갈라져 있어요. .goax-root 포인터를 만들게요.

 📂 동봉 대상 — 20개
  .claude/skills/    15개  (up, onboarding, zero, triage, spec, lane, adr, …)
  .claude/commands/   1개  (goax)
  .claude/agents/     4개  (architect, evaluator, lane-scout, lane-worker)

 ⚠ 기존 파일
  같은 이름의 goax 자산만 덮어써요. 직접 만드신 스킬은 건드리지 않아요.

 ▸ 진행할까요? [y/n]
```

## 3. 적용

```bash
RESULT=$(bash .ax/scripts/bash/vendor-skills.sh --plugin-dir "$PLUGIN_ROOT" --json)
[ "$(echo "$RESULT" | jq -r '.status')" = "ok" ] || { echo "$RESULT" | jq -r '.errors|join("\n")'; exit 1; }
echo "$RESULT" | jq -r '.result | "\(.count)개 동봉 (v\(.version)), 포인터=\(.pointer_written)"'
```

완료 후 안내:

```
✓ 동봉 완료 — v0.4.0, 20개

다음 단계
 1. 커밋하세요 — .claude/ 와 .goax-root 가 저장소에 들어가야 팀원에게 닿아요
      git add .claude .goax-root && git commit -m "chore: goax 0.4.0 동봉"
 2. 팀원은 clone 후 바로 사용 — plugin 설치 불필요
 3. plugin 갱신 시 /vendor 재실행 → 커밋 (doctor 가 stale 을 알려줘요)
```

## 4. 갱신 — 동봉본이 낡았을 때

동봉본은 **저장소에 고정된 사본**이라 plugin 을 올려도 자동으로 안 따라와요.
`doctor` 가 `.claude/.goax-vendored` 와 plugin VERSION 을 비교해 알려줘요.

낡았으면 §3 을 그대로 다시 돌리면 돼요 (idempotent).

> 실제로 이게 방치되면 어떻게 되는지 사례가 있어요 — 어떤 프로젝트는 3개월 전
> 버전의 복사본으로 돌고 있었어요. 그동안의 버그 수정이 하나도 닿지 않았고요.
> 동봉을 고르면 **갱신은 사람의 일**이 돼요. doctor 를 주기적으로 도세요.

## 5. plugin 과 동봉이 함께 있을 때

같은 이름의 스킬이 두 곳에 있으면 어느 쪽이 발동할지 예측하기 어려워요.
goax 는 이 상황을 중재하지 않아요 — **어느 쪽으로 갈지는 프로젝트가 정해요.**
doctor 가 중복을 사실대로 보고할 뿐이에요.

권장: 동봉을 택한 저장소에서 작업할 땐 plugin 을 비활성화하세요.

## 절대 금지

- 사용자가 직접 만든 `.claude/skills/*` 를 덮어쓰거나 지우기
  — goax 가 출고한 이름만 건드려요
- 동의 없이 `.claude/` 에 쓰기 — §2 dry-run 과 [y/n] 을 건너뛰지 마세요
- 단일 저장소에 `.goax-root` 만들기 — 불필요한 파일이에요
- `--plugin-dir` 을 추측해서 넣기 — `${CLAUDE_SKILL_DIR}/../..` 로만 도출해요

## state.json 갱신

이 skill 은 `.ax/state.json` 을 건드리지 않아요. 동봉은 하네스의 *배포* 문제이지
작업 사이클 상태가 아니에요.
