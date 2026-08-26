---
name: mistake
description: "실수·결함을 사용자 의도대로 **1건 캡처** 하는 skill (write-only, capture phase). 트리거: '/mistake', '실수 기록해줘', '실수 남겨줘', 'mistake 캡처', 'mistake 박아줘', '이번 실수 적어줘', '방금 거 mistake 로 박아'. 사용자 인터뷰 (category/severity/detected_by/context_link/ONE_LINE) → init-mistake-file.sh 가 frontmatter 채움 → LLM 이 본문 (5 Whys / 영향 / audit 액션) Edit 으로 채움. **'기록'·'캡처'·'남겨'·'박기'·'적어' 같은 capture 의도 키워드만 매칭** — '회고'·'심사'·'룰 승격' 같은 review 의도는 audit skill 이 담당. 사용자가 capture 의도 표현 즉시 자동 발동."
---

# Mistake Capture Skill

> 응급실 차트처럼, 1건의 실수를 시점·맥락·근본원인까지 깔끔히 한 파일에 박아요.

## 시작 전 필수

`.ax/spirit/values.md`, `tone.md` 따라요. 이 두 파일이 없으면 mistake skill 자체가 fail (작업 시작 거부).

## 발동 시점

- 사용자가 "실수 기록해줘", "mistake 남겨줘", "/mistake" 등 명시 호출
- 사용자가 "이번 실수 캡처" 같이 의도를 표현하면 자동 발동
- 코드 리뷰·PR 후속에서 사용자가 "이거 mistake 로 박아줘" 라고 할 때

**audit skill 과의 분리**:
- `mistake` (이 skill) = 1건 캡처 — frontmatter + 본문 작성. 새 파일 생성 또는 idempotent append.
- `audit` skill = 누적된 mistakes 회고 + 카테고리 패턴 분석 + 룰 승격 후보 제시. capture 하지 않음.

순차 흐름: `mistake` 로 1건씩 누적 → 주기적 (config.yml `audit_cadence_days` 기준) `audit` 로 회고.

## 핵심 원칙 — 사용자 의도적 캡처만

> hook 자동 capture 는 폐기 — 위반이 mistake 로 자동 박히면 일상 작업이 자기 자신을 신고하는 잡음 루프가 되고, 본문 quality 가 placeholder. 사용자가 "이건 진짜 실수다" 라고 의도적으로 capture 한 1건만 누적되어야 audit 시 의미있는 패턴 추출 가능.

## 1. 인터뷰 — 5가지 받기

사용자에게 한 번에 묻거나 (사용자 이미 다 줬으면 추론), 부족하면 짧게 follow-up:

| 항목 | 값 enum / 형식 | LLM 추론 가능? |
|---|---|---|
| `ONE_LINE` | 한 줄 요약 (10~80자) | ✓ 사용자 메시지에서 추출 |
| `category` | dependency-direction · hydration · n+1 · secrets-in-code · testing · pr · error-handling · concurrency · observability · architecture · naming · data · ... | ✓ 메시지 내용 보고 매핑 |
| `severity` | `low` · `medium` · `high` | △ 영향 범위 보고 추론, 모호하면 묻기 |
| `detected_by` | `claude` · `reviewer` · `ci` · `self` · `user` | ✓ 컨텍스트 보고 (사용자가 발견하면 user, claude 가 발견하면 claude) |
| `context_link` | PR URL 또는 commit SHA (선택) | △ 알면 박고 모르면 빈 채로 |

**기본값 정책**:
- 모호하면 medium / claude / 빈 context_link 로 진행 (사용자 confirm 받기 전에 묻지 말기 — 빠른 capture 우선)
- 사용자가 명시 거부 (예: "내가 발견한 거야") 하면 그 값으로 강제

**SLUG 결정** — `ONE_LINE` 의 핵심 명사구 2-4단어 영문으로. 예: "PG key hardcoded" / "n+1 in user list api". 사용자가 명시하면 그대로.

## 2. bash 위임 — `init-mistake-file.sh`

결정론 부분 (파일명·frontmatter sed·idempotent 체크) 은 모두 스크립트:

```bash
RESULT=$(bash .ax/scripts/bash/init-mistake-file.sh \
    --json \
    --category "$CATEGORY" \
    --slug "$SLUG" \
    --severity "$SEVERITY" \
    --detected-by "$DETECTED_BY" \
    --source skill \
    ${CONTEXT_LINK:+--context-link "$CONTEXT_LINK"} \
    --one-line "$ONE_LINE")

STATUS=$(echo "$RESULT" | jq -r '.status')
ACTION=$(echo "$RESULT" | jq -r '.result.action')   # created | appended
FILE=$(echo "$RESULT"   | jq -r '.result.file_path')

if [ "$STATUS" != "ok" ]; then
    echo "$RESULT" | jq -r '.errors | join("\n")'
    # 사용자에게 에러 보고
    exit 1
fi
```

`init-mistake-file.sh` 가 알아서:
- 파일명 (`${DATE}-${EPOCH}-${RAND4}-${CATEGORY}-${SLUG}.md`) 생성
- `_templates/mistakes/mistake.md` 의 `{{...}}` placeholder sed 치환 (frontmatter)
- **idempotent**: 같은 (DATE, CATEGORY, SLUG) 파일 있으면 본문 재생성 X, `## 이력` 에 재발 라인만 append → `action: appended`
- `--one-line` 받으면 `# 무엇이 일어났나` 섹션도 자동 채움

## 3. 본문 작성 — Edit tool 로 LLM 직접 **(필수, 스킵 금지)**

`action: created` 일 때만 (appended 면 본문 이미 있음 — 사용자에게 기존 파일 검토 권장).

frontmatter + `# 무엇이 일어났나` 는 이미 채워진 상태. **나머지 5섹션 모두 placeholder 를 실제 내용으로 교체:**

| 섹션 | 교체 대상 placeholder | 작성 방법 |
|---|---|---|
| `# 어디서 (파일·모듈)` | `파일/모듈/도메인.` | 사용자 컨텍스트에서 파일 경로·모듈명 추출. 없으면 사용자에게 짧게 묻기 |
| `# 왜 발생 (5 Whys 기법)` | `1. 왜 X? → A` … `5. 왜 D? → 근본 원인` | "왜?" 를 5번까지. 사용자와 같이 깊게 |
| `# 어떻게 막을 수 있나` | `- 사람 리뷰로 막을 수 있나? (No → ...)` 등 가이드 라인 | 사람 리뷰 vs Sensor 자동화 vs 룰 추가 — 어느 메커니즘이 적합한지 LLM 판단 + 사용자 검증 |
| `# 영향 (Cost)` | `<변경 비용 — 예: ...>`, `<예: CI 빌드 / 테스트 실패>` 등 `<...>` 마커 | 즉시 + 잠재 후속 — 변경 비용·후속 PR 비용·silent 영향. 추정값으로 채우되 `<...>` 마커는 모두 제거 |
| `# audit 액션 제안` | (빈 섹션) | 룰 승격 후보 / hook 작성 / 관측 보강 등 1줄 이상 |

**Edit tool 사용** — `init-mistake-file.sh` 가 만든 파일을 Read 후 각 섹션 placeholder 교체. 한 번에 4~5개 Edit 병렬 가능.

**완료 검증 (보고 직전 필수)** — 결과 보고하기 전에 파일을 다시 Read 또는 Grep 으로 다음 placeholder 마커가 모두 0 건인지 확인:
- `파일/모듈/도메인\.` (어디서 미작성)
- `1\. 왜 X\? → A` (5 Whys 미작성)
- `<예: ` 또는 `<변경 비용 — 예:` (영향 미작성)
- `# audit 액션 제안\n\n## 이력` (audit 액션 빈 채로)

**1건이라도 남으면 추가 Edit. 사용자에게 "캡처 완료" 보고 금지** — placeholder 잔재 = 미완성 mistake = audit 시 의미 0.

## 4. 결과 보고 — 사용자 confirm

```
✓ mistake 캡처 — .ax/mistakes/<filename>.md (action: created)

📍 frontmatter
   category=secrets / severity=high / detected_by=reviewer / source=skill

📋 본문 채워진 섹션
   ✓ 무엇이 일어났나 ✓ 어디서 ✓ 왜 발생 (5 Whys) ✓ 어떻게 막을 수 있나
   ✓ 영향 (Cost) ✓ audit 액션 제안

📍 다음 단계
   1. 본문 검토 후 추가/수정 — `<filename>` 직접 편집
   2. 같은 카테고리 N건 누적되면 `goax audit` 로 룰 승격 후보 검토
   3. context_link (PR URL) 늦게 알게 되면 frontmatter 직접 갱신
```

**`appended` 케이스** — 사용자에게 기존 파일 알려주기:

```
↻ 같은 (날짜, category, slug) 기존 mistake 발견 — 재발 라인 append
   .ax/mistakes/<existing-filename>.md
   기존 분석은 그대로 유지. 새 컨텍스트가 있으면 본문 직접 편집 권장.
```

## 5. 에러 처리

- `init-mistake-file.sh` 가 fail (template 부재 / common.sh 부재 / jq 부재 등) → 사용자에게 plugin install 상태 확인 안내 + skill 종료
- 필수 인자 누락 (category/severity 등 미응답) → 다시 묻기. 추측으로 박지 말기.
- redact_secrets 가 ONE_LINE 의 secret 패턴 자동 치환 — 단 caller (LLM) 가 secret 을 ONE_LINE 에 직접 박지 않을 책임. 본문 작성 시 secret 발견하면 별도 처리 (사용자에게 알리고 redact).

## state.json 갱신

```bash
jq --arg file "$FILE" \
   '.last_skill = "mistake"
    | .skill_calls = ((.skill_calls // 0) + 1)
    | .last_mistake_file = $file
    | .updated_at = (now | todate)' \
    .ax/state.json > .ax/state.json.tmp && mv .ax/state.json.tmp .ax/state.json
```

`update-state.sh` 의 mistake count 도 자동 반영 (다음 호출 시).

## 절대 금지

- **자동 capture X** — hook 시점에 이 skill 호출 금지 (LLM 부재). hook 들은 차단/경고만, 사용자가 의도적으로 mistake skill 호출.
- **본문 placeholder 그대로 두지 X (검증 필수)** — `init-mistake-file.sh` 호출 후 Edit 으로 5섹션 (어디서/5 Whys/어떻게 막을 수 있나/영향/audit 액션) 채우고, 보고 직전 placeholder 마커 잔재 0 인지 Grep 검증. placeholder 남은 채로 "캡처 완료" 보고 금지. audit 시 의미 0.
- **사용자 컨텍스트 추측만으로 본문 박지 X** — 5 Whys 의 깊은 원인은 사용자만 알 수 있음. 첫 1-2 단계는 LLM 이 추론, 그 다음은 사용자 인터뷰.
- **secret 을 ONE_LINE 또는 본문에 직접 박지 X** — redact_secrets 가 보호하지만 caller 가 1차 책임.
- **다른 mistake 와 합치지 X** — idempotent 는 같은 (날짜, category, slug) 만. 다른 카테고리는 새 파일.
