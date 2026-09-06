# `.ax/scripts/bash/` — goax 결정론적 작업 스크립트 

> 핵심 사상: **결정론적인 일은 스크립트가, 판단·인터랙션은 LLM이.**
> SDD 원칙(scripts 분리 + `--json` 출력으로 결정론·재현성 확보). 모든 스크립트가 --json/--dry-run/--help 표준을 따라요.

## 스크립트 목록

| 스크립트 | 용도 | 호출하는 skill |
|---|---|---|
| `common.sh` | 공통 함수 (find_project_root, json_output, [goax] log) | (sourced by all) |
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
| `doctor-scan.sh` | doctor 의 인라인 진단 셋 — 마이그레이션 잔재 · template 기준 hook 등록 · 문서↔실제 메커니즘 · **도달 지도**(룰 소스별 배관 생사) | `doctor` |
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
| `zero-ablation.sh` | 산문 룰 전체를 끄고 무엇이 깨지는지 재는 ablation (`--off/--on/--status`) — 6개월 주기 | `zero` |
| `zero-guard-bash.sh` | **(`.ax/hooks/pre-bash/` 에 설치 — 이 디렉터리 밖)** pre-bash 가드: `git add -A` 차단(exit 2) · 검증 명령 파이프 경고. hook 규약이라 `--json` 표준 밖이에요 | (hook) |

## 표준 (모든 스크립트 공통)

- shebang: `#!/usr/bin/env bash`
- `set -euo pipefail`
- 옵션: `--json` (기계 출력), `--dry-run` (해당 시), `--help/-h`
- stderr: `[goax]` prefix 로그·경고
- stdout: `--json` 시 JSON, 아니면 사용자 친화 텍스트
- exit code: `0` ok, `1` error, `2` skipped (graceful degradation)

### 의도적 편차 (documented deviation)

아래 스크립트는 `-e`(errexit) 를 뺐어요 — grep 이 매칭 0건일 때 exit 1 을 반환하는 파이프라인에
의존(`... | grep ... | wc -l` 류)하고 있어서, `-e` 를 켜면 "매칭 없음"이 스크립트 조기 종료로
오작동해요. 각 자리에서 `|| true` 로 개별 guard 하는 대신 스크립트 전체에서 `-e` 를 뺀 선택:

- `set -u` 만: `build-memory.sh`, `update-state.sh`
- `set -uo pipefail`: `check-rule-enforcement.sh`, `check-sensor-liveness.sh`, `init-mistake-file.sh`, `install-git-hooks.sh`, `spirit-lint.sh`, `rules-index.sh`, `doctor-scan.sh`

나머지 스크립트는 모두 `set -euo pipefail`.

## `--json` 출력 스키마

```json
{
 "status": "ok" | "error" | "skipped",
 "result": { ... },
 "next_step": "string (사용자에게 보여줄 다음 액션)",
 "warnings": ["string", ...],
 "errors": ["string", ...]
}
```

LLM(SKILL.md)이 이 JSON을 받아 사용자에게 ✓ 메시지 출력. 결정론 부분(번호, 경로, sha)은 LLM이 재해석하지 않음 — script가 SSOT.

## graceful degradation

외부 도구(jq, shasum 등)가 없어도 스크립트는 죽지 않고 `--json`이면 `status:skipped`로 응답해요. caller가 fallback 처리.

## 설계 원칙 (왜 이렇게 만들었나)

1. **LLM 선의 의존 제거**까지 마크다운에 박힌 bash를 LLM이 매번 재해석. 동일 작업이 매번 다르게 실행될 위험. 스크립트로 분리 = 결정론
2. **데이터 흐름 SSOT** — `.ax/current-task.json`이 triage→spec→audit 사이 컨텍스트 전달
3. **빠른 실행** — bash 한 번 호출이 LLM 재추론보다 100× 빠름
4. **테스트 가능** — `tests/smoke.sh`가 `bash -n` + `--help` + `--json` syntax 검증
5. **단일 OS** — bash만, PowerShell pair 없음 (Linux/macOS only)
