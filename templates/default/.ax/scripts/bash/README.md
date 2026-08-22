# `.ax/scripts/bash/` — goax 결정론적 작업 스크립트 

> 핵심 사상: **결정론적인 일은 스크립트가, 판단·인터랙션은 LLM이.**
> SDD 원칙(scripts 분리 + `--json` 출력으로 결정론·재현성 확보). 모든 스크립트가 --json/--dry-run/--help 표준을 따라요.

## 스크립트 목록

| 스크립트 | 용도 | 호출하는 skill |
|---|---|---|
| `common.sh` | 공통 함수 (find_project_root, json_output, [goax] log) | (sourced by all) |
| `next-spec-num.sh` | 다음 spec NNN / ADR NNNN 번호 계산 (`--kind spec\|adr`) | `spec`, `adr` |
| `tier-from-state.sh` | current-task.json + config.yml → tier 결정 (`--reset` 는 `reset-task.sh` 경유) | `spec` |
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
| `update-state.sh` | `.ax/` 실측 → `.ax/state.json` (layers/cross_cut/sensors_mode) 갱신 | `up`, `onboarding`, `audit`, `doctor`, `hud`, `mistake` |
| `triage-search.sh` | KEYWORDS 로 6 군데(specs/adrs/mistakes/rules/modules/imported) 검색 + 동의어 확장 + 매칭수 랭킹 + 스니펫 + 도메인 boost | `triage` |
| `build-memory.sh` | `.ax/` 상태 → `.ax/MEMORY.md` 한 줄 포인터 인덱스 재생성 (triage 가 먼저 read) | `triage` |
| `build-index.sh` | 역색인 `.ax/.search-index` 빌드 + BM25 query (대형 코퍼스 tier, 재생성 캐시) | `triage-search` |

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

- `set -u` 만: `build-index.sh`, `build-memory.sh`, `update-state.sh`
- `set -uo pipefail`: `check-rule-enforcement.sh`, `check-sensor-liveness.sh`, `init-mistake-file.sh`, `install-git-hooks.sh`

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
