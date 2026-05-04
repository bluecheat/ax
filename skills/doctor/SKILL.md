---
name: doctor
description: "goax 설치 상태 진단 — '/doctor', 'goax doctor', 'goax 진단', '하네스 점검', 'goax 상태' 트리거. 4계층 + cross-cut + sensors 결손을 검사하고 다음 단계를 친절히 안내."
---

# goax doctor — 4계층 결손 진단

## 시작 전 필수
`.ax/spirit/values.md`, `tone.md` 따라요.

## 발동 트리거
- `/doctor`, `goax doctor`, "goax 진단", "하네스 점검", "goax 상태"
- `--strict` 옵션도 인식 (placeholder를 통과로 안 보고 fail 처리)

## 1. PROJECT_ROOT 감지

`.ax/`가 있는 가장 가까운 디렉토리:

1. 자기 + 조상 디렉토리에서 `.ax/` 찾기
2. 자식 디렉토리(2~4단 깊이)에서 `.ax/` 찾기
3. 못 찾으면 → `먼저 'goax 도입해줘'라고 말해주세요` 안내

다른 디렉토리에서 발동되면 알려요:
```
⚠ 현재 디렉토리에 .ax/가 없어요.
 /Users/x/projects/commerce 의 goax 설치를 진단해요.
 정확히 거기서 실행하려면: cd /Users/x/projects/commerce
```

## 2. 빠른 사전 통계 (bash) — 큰 프로젝트 대비

수십 모듈·수백 spec이 있을 때 LLM이 모두 읽기 전 bash로 통계:

```bash
ROOT=$(pwd) # 또는 감지한 PROJECT_ROOT

# 전체 자산 한눈에
echo "Spirit rules: $(ls $ROOT/.ax/spirit/rules/*.md 2>/dev/null | wc -l) 카테고리"
echo "ADR:    $(ls $ROOT/.ax/docs/adr/*.md 2>/dev/null | grep -v 0000-template | wc -l) 건"
echo "Spec:   $(ls -d $ROOT/.ax/docs/spec/[0-9][0-9][0-9]-* 2>/dev/null | wc -l) 건"
echo "Mistakes:  $(ls $ROOT/.ax/mistakes/*.md 2>/dev/null | grep -v README | wc -l) 건"
echo "Module CLAUDE: $(find $ROOT -maxdepth 4 -name CLAUDE.md -not -path "*/.*" -not -path $ROOT/CLAUDE.md 2>/dev/null | wc -l) 건"

# Layer 1 시그널 라벨 카운트
echo "CLAUDE.md 시그널:"
echo " 🔴 CRITICAL $(grep -c '🔴' $ROOT/CLAUDE.md 2>/dev/null)"
echo " 🟡 MANDATORY $(grep -c '🟡' $ROOT/CLAUDE.md 2>/dev/null)"
echo " 🔵 CONVENTION $(grep -c '🔵' $ROOT/CLAUDE.md 2>/dev/null)"

# placeholder 잔재 검색
grep -lE "<여기에 본문|<자기 팀|TODO\(goax\)" \
 $ROOT/.ax/spirit/*.md $ROOT/.ax/spirit/rules/*.md 2>/dev/null

# domain_risk 키 개수
grep -cE "^[[:space:]]+[a-z-]+:" $ROOT/.ax/config.yml 2>/dev/null

# 미승격 mistakes (audit 후보 — 카테고리당 카운트)
grep -h "^category:" $ROOT/.ax/mistakes/*.md 2>/dev/null \
 | awk '{print $2}' | sort | uniq -c | sort -rn
```

이 통계가 곧 진단 결과에 들어가요.

## 3. 4계층 + Cross-cut + Sensors 검사

각 항목 ✓/·/✗ 표시 + 빈 placeholder 검출.

| Layer | 검사 |
|---|---|
| **Layer 1** | `CLAUDE.md` 존재 + 시그널(🔴/🟡/🔵) 라벨 있는지 + 4계층 인덱스 표 |
| **Layer 0 / 설정** | `.ax/config.yml` (domain_risk 5+ 권장) + `.ax/version` |
| **Cross-cut Spirit** | `values.md`/`tone.md` (placeholder 검사), `rules/<카테고리>.md` 1개+ |
| **Cross-cut Mistake Loop** | `.ax/mistakes/` 디렉토리 존재 |
| **Layer 3 / Spec·ADR** | `.ax/docs/adr/`, ADR 1개+ (0000-template 외), `.ax/docs/_templates/spec/` (`.origin` drift 비교 — 아래 §3.5) |
| **Layer 2 / Module Rules** | (선택) 모듈별 `<module>/CLAUDE.md` 카운트 |
| **Sensors / Hooks** | `.ax/hooks/{pre-bash,pre-edit,post-edit,pre-commit}/` + `.claude/settings.json` |

### 3.5 _templates drift 체크 (script-backed)

스크립트 위임 — 결정론은 `check-templates-drift.sh`에. plugin 컨텍스트에서 실행되면 `${CLAUDE_SKILL_DIR}`(Claude Code 공식 변수)로 plugin root를 도출(`${CLAUDE_SKILL_DIR}/../..`). 사용자가 직접 bash로 호출했다면 비어있을 수 있어요(그때는 plugin_updated 검사가 skip 되고 user_modified만 보고).

> ⚠ **drift 감지 범위 제한**: `check-templates-drift.sh`는 `.ax/docs/_templates/spec/` 만 커버. `.ax/spirit/rules/`, `.ax/docs/_templates/{adr,module,spirit}/` 의 사용자 변경은 *감지 안 됨* — plugin 갱신 시 silently 출고본으로 회귀 가능. 그래서 onboarding 절대 금지 항목에 plugin shipped spirit/rules 직접 append 금지가 박혀있음 — 프로젝트별 룰은 별도 파일(`<project>-<category>.md`) + @import 권장.

```bash
# plugin root 도출 — ${CLAUDE_SKILL_DIR} 우선, ${CLAUDE_PLUGIN_ROOT}는 호환용 fallback
if [ -n "${CLAUDE_SKILL_DIR:-}" ]; then
    PLUGIN_ROOT="$(cd "${CLAUDE_SKILL_DIR}/../.." && pwd)"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT"
else
    PLUGIN_ROOT=""
fi

if [ -n "$PLUGIN_ROOT" ]; then
 RESULT=$(bash .ax/scripts/bash/check-templates-drift.sh --json --plugin-dir "$PLUGIN_ROOT")
else
 RESULT=$(bash .ax/scripts/bash/check-templates-drift.sh --json)
fi
USER_MOD=$(echo "$RESULT" | jq -r '.result.user_modified')
PLUGIN_UPD=$(echo "$RESULT" | jq -r '.result.plugin_updated')
DRIFT_FILES=$(echo "$RESULT" | jq -r '.result.drift_files | join(", ")')
```

상태별 보고:
- `user_modified=false, plugin_updated=false` → `✓ _templates 출고본과 동일`
- `user_modified=true, plugin_updated=false` → `· _templates: 사용자 수정 감지 (정상 — 이게 SSOT). 변경: $DRIFT_FILES`
- `user_modified=*, plugin_updated=true` → `⚠ plugin _templates 갱신됨` + 옵션 제시:
 - [a] ✓ 사용자 수정 유지 (권장 — 도메인 적응 결과)
 - [b] plugin 출고본을 `.ax/docs/_templates/spec.suggested/`로 떨어트려 사용자가 머지
 - [c] ⚠ 사용자 수정 백업(`.ax/docs/_templates/spec.bak/`) 후 plugin으로 덮어쓰기

**원칙**: 사용자 수정은 *절대* 자동 덮어쓰기 X. 머지 결정은 사용자.

## 3. 출력

```
🩺 goax doctor — /path/to/your-project
    goax 0.3.0 · preset=default · installed 2026-05-02

 ─ Layer 1 — Constitution ───────────────────────────────
 ✓ CLAUDE.md (62줄, 시그널 라벨 있음, 4계층 인덱스 ✓)

 ─ Layer 0 — Triage / 설정 ───────────────────────────────
 ✓ config.yml (domain_risk 30 keys, default L1)
 ✓ version (goax &lt;version&gt;)

 ─ Cross-cut — Spirit ───────────────────────────────────
 ✓ spirit/values.md (사용자 정의됨)
 · spirit/tone.md → placeholder 그대로
 ✓ spirit/rules/ (4 카테고리: architecture, data, testing, ops)

 ─ Cross-cut — Mistake Loop ─────────────────────────────
 ✓ mistakes/ (3건 누적, 다음 audit: 2026-05-09)

 ─ Layer 3 — Spec / ADR ─────────────────────────────────
 ✓ docs/adr/ (1건: 0001-goax-adoption.md)
 ✓ docs/_templates/spec/
 · docs/spec/NNN-*/ — 작성된 spec 0건 (첫 spec 권장)

 ─ Layer 2 — Module Rules ───────────────────────────────
 ✓ <module>/CLAUDE.md (5/13 모듈 — L2/L3 도메인만, 선택적)

 ─ Sensors — Hooks ──────────────────────────────────────
 ✓ pre-bash, pre-edit, post-edit, pre-commit hooks
 ✓ .claude/settings.json

 ─ 점수 ──────────────────────────────────────────────────
 9/11 (90%)

 ─ 다음 단계 ──────────────────────────────────────────────

 [a] ✓ tone.md 우리 팀 말투로 수정    [추천]
  파일 .ax/spirit/tone.md
  이유 placeholder 그대로 — 모든 sub-agent가 default 톤 사용 중
  방법 ~해요 체 + 우리 팀 안티패턴 추가

 [b] 첫 spec 작성         [권장]
  명령 "새 spec 만들어줘 — <slug>"
  이유 Layer 3은 template만 — 실제 spec이 있어야 game이 시작됨

 [c] audit 실행 — mistakes 3건 회고
  명령 "goax audit"
  이유 3건 누적, 카테고리별 패턴 보일 수 있음

 ▸ 답해주세요 [a] / [b] / [c] / 또는 그냥 보고만
```

**규칙**
- 빈 placeholder는 `·` (warning), 누락은 `✗` (fail)
- 다음 단계 옵션은 결손이 큰 항목부터 우선순위 부여
- `[권장]`/`[추천]` 표시는 점수 기여도 + 안전성 기준
- 문제 없으면 "다음 단계" 섹션에 [a] "spec 1개 작성"·[b] "audit"처럼 발전적 옵션

## 4. --strict 모드

placeholder는 통과로 안 봄. 모든 항목이 사용자 정의 상태여야 score 만점.
사용자가 "엄격하게 진단해줘", "strict mode" 같은 표현 쓰면 자동 적용.

## 절대 금지

- 결손이 있으면 그냥 ✗만 찍지 말고 **구체적 다음 명령**을 제시
- "전부 OK!" 같은 자가 칭찬 금지 (Spirit 1️⃣)
- placeholder를 통과로 위장 X

## state.json 갱신

이 skill이 끝날 때 `.ax/state.json` 갱신 항목:
- 모든 layers + cross_cut (canonical)

갱신 방법: jq로 in-place. 실패해도 skill 본 작업은 영향 X (HUD는 부수효과).
```bash
# canonical 갱신 (layer.active, cross_cut.active, sensors_mode, updated_at) — 결정론 스크립트
bash .ax/scripts/bash/update-state.sh

# 메타데이터 (last_skill, skill_calls)만 별도
jq '.last_skill = "doctor" | .skill_calls = ((.skill_calls // 0) + 1)' \
 .ax/state.json > .ax/state.json.tmp && mv .ax/state.json.tmp .ax/state.json
```
