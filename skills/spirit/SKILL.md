---
name: spirit
description: "Spirit 검증 — 'spirit 점검', 'goax spirit', '가치 룰 lint'. .ax/spirit/{values, tone, rules}의 frontmatter + 토큰 무결성 검사."
---

# goax spirit-check — Spirit 무결성

## 발동
- "spirit 점검", "spirit lint", "goax spirit"

## 검사 항목

### 1. 필수 파일
- `.ax/spirit/values.md` 존재 + non-empty
- `.ax/spirit/tone.md` 존재 + non-empty
- `.ax/spirit/rules/` 디렉토리 존재
- `.ax/docs/_templates/spirit/rule.md` 존재 (rules 작성 템플릿 — 인스턴스 디렉토리와 분리)

### 2. rules/*.md frontmatter
각 rules/<category>.md 파일은 다음 frontmatter 필요:
```yaml
---
category: <name>
description: <one-liner>
---
```

### 3. 토큰 무결성
- 모든 rules/<cat>.md 안의 룰 ID는 `SP-<CAT>-NNN` 형식 (NNN 3자리 zero-pad)
- 같은 카테고리 안에 ID 중복 없음
- 헤더 `^## SP-...`만 정의로 보고, 본문 인용된 ID는 제외

### 4. values·tone placeholder 검사
초기 템플릿 텍스트(`<여기에 본문>`, `<자기 팀>` 등)가 남아있으면 경고.

## 출력

```
🩺 Spirit lint

 ✓ values.md (8 항목 — 사용자 정의됨)
 ✓ tone.md (~해요 체 + 5 안티패턴)
 ✓ docs/_templates/spirit/rule.md
 ✓ rules/security.md (3 룰)
 ✗ rules/testing.md → frontmatter category: 누락
 · rules/pr.md → ID SP-PR-002 중복

총 7개 / 1 fail / 1 warning

다음 단계:
 - rules/testing.md frontmatter 추가
 - rules/pr.md SP-PR-002 중복 해결 (002 → 003)
```

## 절대 금지
- 자동 수정하지 않아요. 사용자에게 위치만 알려주고 직접 수정 받아요.

## state.json 갱신

이 skill이 끝날 때 `.ax/state.json` 갱신 항목:
- cross_cut.spirit.values_filled, rules_count

갱신 방법: jq로 in-place. 실패해도 skill 본 작업은 영향 X (HUD는 부수효과).
```bash
jq '.last_skill = "spirit" | .skill_calls = ((.skill_calls // 0) + 1) | .updated_at = (now | todate)' \
 .ax/state.json > .ax/state.json.tmp && mv .ax/state.json.tmp .ax/state.json
```
