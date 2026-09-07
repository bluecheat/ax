# `.ax/scripts/bash/` — goax 결정론적 작업 스크립트 

> 핵심 사상: **결정론적인 일은 스크립트가, 판단·인터랙션은 LLM이.**
> SDD 원칙(scripts 분리 + `--json` 출력으로 결정론·재현성 확보). 모든 스크립트가 --json/--dry-run/--help 표준을 따라요.

## 스크립트 목록

| 스크립트 | 용도 | 호출하는 skill |
|---|---|---|
| `common.sh` | 공통 함수 (find_project_root, json_output, [goax] log, `goax_inject_fresh` 세션 내 중복 주입 제거, `goax_lock`/`goax_unlock`/`goax_unlock_all` 원장 락, `goax_resolve_spec` `--spec` 축약 해석, `goax_secret_rules`/`goax_secret_patterns`/`redact_secrets` 시크릿 패턴 SSOT — 검출과 마스킹이 같은 표에서 나와요) | (sourced by all) |
| `detect-model.sh` | 지금 돌고 있는 모델 식별 — override → `$GOAX_MODEL` → transcript 스캔 → unknown | (진단·로깅용) |
| `next-spec-num.sh` | 다음 spec NNN / ADR NNNN 번호 계산 (`--kind spec\|adr`) | `spec`, `adr` |
| `tier-from-state.sh` | current-task.json + config.yml → tier 결정 + evaluator 필수 여부 + spec_review 필수 여부(Size 축만) (`--reset` 는 `reset-task.sh` 경유) | `spec`, `tasks-gate.sh`, `spec-review.sh`, `update-state.sh` |
| `init-spec-dir.sh` | tier별 selective spec 디렉토리 생성 | `spec` |
| `add-spec-files.sh` | 기존 spec에 tasks/research 등 점진 추가 | `spec-tasks`, `spec --add` |
| `slug-from-text.sh` | 영문 텍스트 → kebab-case 정규화·검증 | `spec` |
| `check-templates-drift.sh` | `_templates/.origin` ↔ 현재 sha 비교 | `doctor` |
| `check-manifest-install.sh` | MANIFEST 출고분 ↔ 사용자 프로젝트 파일 단위 비교 (missing + drift) | `doctor` |
| `check-rule-enforcement.sh` | 룰의 `enforced_by`/`enforced_kind` invariant(I1~I6) 검증 | `doctor` |
| `check-sensor-liveness.sh` | Sensors 장치 생사 검증 (C1 grep 스캐폴드 · C2 git hook · C3 차단 능력 0 · C4 세션 루트 이탈) | `doctor` |
| `check-spec-clarity.sh` | spec.md 명료성 게이팅(NEEDS CLARIFICATION/placeholder/빈 섹션) + tasks·AC 진행률 visibility | `spec-validate` |
| `promote-mistake.sh` | mistake → spirit rule 승격 (후보·적용·archive) | `audit` |
| `init-mistake-file.sh` | mistake 파일 skeleton 생성 (template cp + frontmatter 치환) | `mistake`, `audit` |
| `install-git-hooks.sh` | `.ax/hooks/pre-commit/*.sh` chain 을 git pre-commit wrapper 로 설치 (모든 환경 기본 — 사람 터미널 커밋 커버) | `up`, `onboarding` |
| `register-spirit-hook.sh` | `.claude/settings.json` 에 spirit-rules-inject hook idempotent 등록 | `doctor` |
| `reset-task.sh` | 작업 완료 후 `current-task.json` → phase=idle 리셋 (`tier-from-state.sh --reset` 위임) | `spec-implement` |
| `update-state.sh` | `.ax/` 실측 → `.ax/state.json` (layers/cross_cut/sensors_mode + HUD 캐시 `hud.{plugin_version,review_required,cached_at}`) 갱신 | `up`, `onboarding`, `audit`, `doctor`, `hud`, `mistake`, `spec-validate`, `spec-implement` |
| `triage-search.sh` | KEYWORDS 로 6 군데(specs/adrs/mistakes/rules/modules/imported) 검색 + 동의어 확장 + 매칭수 랭킹 + 스니펫 + 도메인 boost | `triage` |
| `build-memory.sh` | `.ax/` 상태 → `.ax/MEMORY.md` 한 줄 포인터 인덱스 재생성 (triage 가 먼저 read) | `triage` |
| `status-note.sh` | 세션 간 인계 노트 `.ax/docs/STATUS.md` — `--show/--init/--add/--done/--set <now|next|open|renamed>`. 형식 고정 · 40줄 상한 · 끝난 항목은 지움 | `triage`(읽기), `spec-implement`, `zero`, `onboarding` |
| `spirit-lint.sh` | Spirit 무결성 — 필수 파일 · frontmatter · `## SP-CAT-NNN:` 헤더 형식 · 토큰 중복(spirit ↔ modules) · placeholder. 자동 수정 없음 | `doctor` ("spirit 점검") |
| `rules-index.sh` | 룰 통합 인덱스 — Constitution(🔴/🟡/🔵 시그널 라인) + Spirit + Module 의 `SP-*` 를 한 목록으로. `--level/--source/--category/--find` | `doctor` ("rules 보여줘"), `/goax` |
| `doctor-scan.sh` | doctor 의 인라인 진단 셋 — 마이그레이션 잔재 · template 기준 hook 등록(파일 + **이벤트 키**) · 문서↔실제 메커니즘 · **도달 지도**(룰 소스별 배관 생사) · **인계 노트 기한**(STATUS.md `- [ ] YYYY-MM-DD`, I3 규칙) | `doctor` |
| `constitution-apply.sh` | onboarding Q5 의 Constitution 블록 적용 — `--block` prepend(기존 본문 `---` 아래 보존) · `--scan-duplicates` · `--drop-exact`(사용자 [a] 뒤에만) · `--append-index` | `onboarding` |
| `tasks-plan.sh` | tasks.md → ready / blocked / parallel + `[P]` 파일 겹침 violations. 항목별 승격 — wave(배리어) 없음, 자동 실행 없음 | `lane`, `spec-implement` |
| `tasks-gate.sh` | spec 완료 게이트 G1~G6 — 미완료 · AC 커버리지 · orphan · 유실 · 레인 원장 · evaluator verdict(`review.md`) | `spec-implement`, `lane`, pre-commit hook |
| `lanes-hotfiles.sh` | tasks.md 에서 핫 파일(여러 미완료 task 가 쓰는 파일) + `files:` 누락 task 추출 | `lane` |
| `spec-review.sh` | spec 합의 리뷰 원장 — `--snapshot`(sha 고정·라운드) / `--status`(리뷰어별 `review-spec.{architect,evaluator}.md` 의 verdict·sha 집계 → pass) / `--merge`(합본). 필수 여부는 Size 축만 | `spec-validate` |
| `lanes-dispatch.sh` | 레인 디스패치 원장 — `--assign / --dispatch / --report / --status`. tasks.md 의 `레인:`·`디스패치:`·`보고:` 필드를 쓰고, 파일 소유 충돌이면 dispatch 거부 | `lane`, `spec-implement` |
| `zero-init.sh` | 0→1 첫날 팩 설치 (룰은 라이브 `spirit/rules/`, 템플릿은 `_templates/zero/`) — 덮어쓰지 않고 SP 토큰 충돌만 경고 | `zero` |
| `zero-domain-risk.sh` | `config.yml` 의 `domain_risk` 블록 통째 교체 (`--show/--set/--default`) — 출고 예시 키가 남으면 triage 가 영원히 default_risk 로 흘러요 | `zero` |
| `zero-probe.sh` | 네거티브 프로브 — 일부러 위반을 만들어 차단이 실제로 도는지 확인 | `zero` |
| `zero-verify.sh` | `config.yml commands` 를 파이프 없이 실행하고 증거 블록 생성 — 안 돌린 게이트도 보고 (하나도 안 돌면 exit 2) | `zero` |
| `zero-ablation.sh` | 산문 룰 전체를 끄고 무엇이 깨지는지 재는 ablation (`--off/--on/--status`) — `--on` 이 회차를 기록하고 다음 기한(+180일)을 STATUS.md 에 체크박스로 (doctor 가 추적) | `zero`, `doctor` |
| `zero-guard-bash.sh` | **(`.ax/hooks/pre-bash/` 에 설치 — 이 디렉터리 밖)** pre-bash 가드: `git add -A` 차단(exit 2) · 검증 명령 파이프 경고. hook 규약이라 `--json` 표준 밖이에요 | (hook) |
| `vendor-skills.sh` | goax skill/command/agent 를 저장소에 동봉(`--plugin-dir` cp) — 모노레포처럼 ADE 루트 ≠ 프로젝트 루트일 때 `.goax-root` 포인터도 씀. `--check` 로 동봉본 ↔ plugin 버전 비교만 | `vendor`, `doctor` |

## 표준 (모든 스크립트 공통)

- shebang: `#!/usr/bin/env bash`
- `set -euo pipefail`
- 옵션: `--json` (기계 출력), `--dry-run` (해당 시), `--help/-h`
- stderr: `[goax]` prefix 로그·경고
- stdout: `--json` 시 JSON, 아니면 사용자 친화 텍스트
- exit code: `0` ok(경고 있어도 ok), `1` error(`--strict` 위반 포함), `2` skipped (대상 없음 · graceful degradation)

### 의도적 편차 (documented deviation)

아래 스크립트는 `-e`(errexit) 를 뺐어요 — grep 이 매칭 0건일 때 exit 1 을 반환하는 파이프라인에
의존(`... | grep ... | wc -l` 류)하고 있어서, `-e` 를 켜면 "매칭 없음"이 스크립트 조기 종료로
오작동해요. 각 자리에서 `|| true` 로 개별 guard 하는 대신 스크립트 전체에서 `-e` 를 뺀 선택:

- `set -u` 만: `build-memory.sh`, `update-state.sh`
- `set -uo pipefail`: `check-rule-enforcement.sh`, `check-sensor-liveness.sh`, `detect-model.sh`, `doctor-scan.sh`, `init-mistake-file.sh`, `install-git-hooks.sh`, `rules-index.sh`, `spirit-lint.sh`, `tasks-gate.sh`, `vendor-skills.sh`, `zero-probe.sh`, `zero-verify.sh`

나머지 스크립트는 모두 `set -euo pipefail`. (목록이 실제와 갈리면 신뢰할 수 없으니, 바뀔 때마다
`grep -l '^set -[a-z]*$' *.sh` 로 재확인하고 이 목록을 갱신해요.)

## `--json` 출력 스키마

```json
{
 "status": "ok" | "warning" | "error" | "skipped",
 "result": { ... },
 "next_step": "string (사용자에게 보여줄 다음 액션)",
 "warnings": ["string", ...],
 "errors": ["string", ...]
}
```

`warning` — 대상은 정상 처리됐지만 사용자가 봐야 할 게 있을 때(예: `check-rule-enforcement.sh`
위반 존재, `spec-review.sh` 라운드 상한 초과, `lanes-dispatch.sh` 원장 불일치). `error`/`skipped` 와
달리 **exit code 는 `0`** 이에요 — caller 가 exit 만 보고 넘어가면 이 신호를 놓쳐요, `status` 를
같이 봐야 해요. `warning` 을 emit 하는 스크립트: `check-manifest-install.sh`, `check-rule-enforcement.sh`,
`check-sensor-liveness.sh`, `constitution-apply.sh`, `doctor-scan.sh`, `lanes-dispatch.sh`,
`lanes-hotfiles.sh`, `rules-index.sh`, `spec-review.sh`, `spirit-lint.sh`, `status-note.sh`,
`tasks-gate.sh`, `tasks-plan.sh`, `zero-ablation.sh`.

예외: `update-state.sh --json` 은 이 envelope 을 따르지 않아요 — 호출자가 `.status`/`.result` 를
파싱하지 않고 그냥 실행만 하는 fire-and-forget 스크립트라서예요 (모든 SKILL.md 가 `>/dev/null 2>&1 || true` 로 호출).

LLM(SKILL.md)이 이 JSON을 받아 사용자에게 ✓ 메시지 출력. 결정론 부분(번호, 경로, sha)은 LLM이 재해석하지 않음 — script가 SSOT.

## 쓰기 규약 — 여러 세션이 같은 파일을 건드릴 때

`tasks.md`·`state.json`·`STATUS.md`·`.claude/settings.json`·`AGENTS.md`·`.ax/config.yml` 처럼 여러
스크립트·여러 세션이 같은 파일을 `read → 가공 → tmp.$$ → mv` 하는 자리는 **락 없이는 동시 쓰기에서
갱신이 유실돼요** (읽은 뒤 서로를 못 보고 덮어써요). `common.sh` 의 헬퍼로 감싸요:

```bash
LOCK="<대상 절대경로>.lock"
goax_lock "$LOCK" "${GOAX_LOCK_TIMEOUT:-10}" || fail "다른 프로세스가 <대상> 을 쓰는 중이에요 — 잠시 뒤 다시 해요"
# ... 멱등 프로브 · 읽고 바꾸고 tmp 에 쓰고 mv ...
goax_unlock "$LOCK"
```

**락 창은 `mv` 가 아니라 "이 실행이 파일을 바꿀지 말지를 정하는 첫 읽기" 부터예요.** 멱등
`grep -q`(이미 등록됐나 · 이미 적용됐나)를 락 밖에 두면 두 프로세스가 둘 다 "아직 없다" 를 읽고
둘 다 써요 — 실측: `zero-init.sh` 5개 동시 실행이 같은 훅을 3번 등록했어요.

**락 단위는 스크립트가 아니라 대상 파일이에요.** `constitution-apply.sh` 는 prepend·drop·
`--append-index` 세 모드가 같은 `<대상>.lock` 을 잡아요. `state.json`(`update-state.sh` ↔
`tasks-gate.sh`) · `.claude/settings.json`(`register-spirit-hook.sh` ↔ `zero-init.sh`) 처럼 두
스크립트가 같은 파일을 쓰면 락 경로 문자열을 **글자 그대로 맞춰야** 서로를 막아요 — 다른 이름이면
락이 두 개가 돼서 무의미해요. 경로는 **절대경로**여야 해요 — 프로젝트 루트로 `cd` 한 스크립트는
대상이 상대 경로라 `goax_normalize_path "$TARGET" "$PROJECT_ROOT"` 로 절대화해요.

**`--dry-run` 은 락을 안 잡고 아무것도 안 써요.** 락 디렉토리 자체가 부작용이에요. dry-run 분기
*앞에서* `ensure_file` 같은 헬퍼를 부르면 dry-run 이 여전히 파일을 만들어요 — 그런 호출은 분기
뒤로 옮겨요.

`goax_lock` 은 `mkdir` 원자성으로 락을 잡고(0.05→0.2s 폴링, 2번째 인자가 타임아웃 · 기본 10s),
기록된 PID 가 죽었으면(5초 뒤부터), 또는 PID 파일이 없는 락이 `GOAX_LOCK_STALE`(60초)을 넘겼으면 stale 로 보고 회수해요. **살아 있는 홀더는 아무리 오래 잡고 있어도 안 뺏어요** — 대기자는 타임아웃(`GOAX_LOCK_TIMEOUT`, 기본 10초)까지 기다리다 exit 1 이에요. 대기가 길어 곤란한 자리
(테스트 등)는 `GOAX_LOCK_TIMEOUT=1` 로 줄여요. 획득 실패는 무한 대기가 아니라 exit 1 +
`--json` 이면 `{"status":"error"}` 봉투예요. `EXIT`/`INT`/`TERM` trap 으로 자동 해제돼요
— **단, 스크립트가 이미 자기 trap 을 걸어뒀으면 그 trap 이 덮어써져요.** 그런 스크립트
(`check-spec-clarity.sh`, `check-rule-enforcement.sh`, `promote-mistake.sh` 처럼 `trap ... EXIT` 가
있는 경우)는 자기 trap 안에서 `goax_unlock_all` 을 같이 호출해요.

`--spec` 인자를 받는 스크립트는 축약(`--spec 001`)을 각자 다르게 풀지 말고 `goax_resolve_spec`
(정확 일치 → prefix 1개 → 실패/모호)을 써요. 후보가 여럿이면 `GOAX_SPEC_CANDIDATES` 에 담겨요.

**로케일 — `[a-z]`/`[A-Z]` 브래킷을 새로 쓰지 마세요.** en_US.UTF-8 collation 에서 `[a-z]` 는
정렬 순서(aAbB…zZ) 때문에 대문자까지 삼켜요 — 실측: `case "$x" in [a-z]*)` 가 `Payment` 를
통과시켰어요. `[[:lower:]]`·`[[:upper:]]`·`[[:alnum:]]` 를 쓰거나, 옛 코드를 못 고치는 자리는
`common.sh` 최상단의 `export LC_COLLATE=C` 가 안전망이에요 (이미 있는 export — 새로 추가할 필요
없음, 브래킷을 새로 안 쓰면 충분해요).
- 문자 클래스에 한글 **범위**(`[가-힣]`)를 쓰지 않아요 — GNU grep 은 C.UTF-8 에서 "Invalid collation character" 로 거부해요(BSD grep 은 통과라 리눅스 CI 에서만 드러나요). 부정 클래스(`[^<>]`)나 POSIX 클래스로 써요.
- awk 에서 `substr`/`length` 로 문자열을 직접 자르지 않아요 — macOS 기본 awk(BWK)는 바이트 단위라 한글 한 글자를 반으로 가르고, 다음 정규식이 `towc: multibyte conversion failure` 로 awk 전체를 죽여요(리눅스는 gawk 가 문자 단위, mawk 는 towc 검사가 없어 둘 다 안 죽어요 — macOS 에서만 터지고, 긴 한글 픽스처 없이는 CI 에서도 안 드러나요). `common.sh` 의 `GOAX_AWK_CLIP`(`clip(s, n)`, 낱말 경계로만 자름)을 써요.

**`tasks.md` 를 파싱하는 스크립트는 코드펜스를 건너뛰어요.** `_templates/spec/tasks.md` 자체가
형식 설명 예시(`- [ ] T001 [P] [AC2] …`)를 코드펜스 안에 담고 있어서, 펜스를 안 보면 그 예시 줄이
실제 task 로 세여요. awk 파서는 이 3줄로 펜스를 건너뛰어요:
```awk
/^[[:space:]]*```/ { fence = !fence; next }
fence { next }
```

## graceful degradation

외부 도구(jq, shasum 등)가 없어도 스크립트는 죽지 않고 `--json`이면 `status:skipped`로 응답해요. caller가 fallback 처리.

## 설계 원칙 (왜 이렇게 만들었나)

1. **LLM 선의 의존 제거**까지 마크다운에 박힌 bash를 LLM이 매번 재해석. 동일 작업이 매번 다르게 실행될 위험. 스크립트로 분리 = 결정론
2. **데이터 흐름 SSOT** — `.ax/current-task.json`이 triage→spec→audit 사이 컨텍스트 전달
3. **빠른 실행** — bash 한 번 호출이 LLM 재추론보다 100× 빠름
4. **테스트 가능** — `tests/smoke.sh`가 `bash -n` + `--help` + `--json` syntax 검증
5. **단일 OS** — bash만, PowerShell pair 없음 (Linux/macOS only)
