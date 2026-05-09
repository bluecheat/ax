# `.ax/scripts/bash/` — goax 결정론적 작업 스크립트 

> 핵심 사상: **결정론적인 일은 스크립트가, 판단·인터랙션은 LLM이.**
> SDD 원칙(scripts 분리 + `--json` 출력으로 결정론·재현성 확보). 모든 스크립트가 --json/--dry-run/--help 표준을 따라요.

## 스크립트 목록

| 스크립트 | 용도 | 호출하는 skill |
|---|---|---|
| `common.sh` | 공통 함수 (find_project_root, json_output, [goax] log) | (sourced by all) |
| `next-spec-num.sh` | 다음 spec NNN 계산 | `spec` |
| `tier-from-state.sh` | current-task.json + config.yml → tier 결정 | `spec` |
| `init-spec-dir.sh` | tier별 selective spec 디렉토리 생성 | `spec` |
| `add-spec-files.sh` | 기존 spec에 plan/tasks/research 점진 추가 | `spec-{plan,tasks,implement}`, `spec --add` |
| `slug-from-text.sh` | 영문 텍스트 → kebab-case 정규화·검증 | `spec` |
| `check-templates-drift.sh` | `_templates/.origin` ↔ 현재 sha 비교 | `doctor` |
| `check-manifest-install.sh` | MANIFEST 출고분 ↔ 사용자 프로젝트 파일 단위 비교 (missing + drift) | `doctor` |
| `promote-mistake.sh` | mistake → CLAUDE.md 룰 승격 (후보·적용) | `audit` |

## 표준 (모든 스크립트 공통)

- shebang: `#!/usr/bin/env bash`
- `set -euo pipefail`
- 옵션: `--json` (기계 출력), `--dry-run` (해당 시), `--help/-h`
- stderr: `[goax]` prefix 로그·경고
- stdout: `--json` 시 JSON, 아니면 사용자 친화 텍스트
- exit code: `0` ok, `1` error, `2` skipped (graceful degradation)

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
