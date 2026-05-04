---
name: rules
description: "프로젝트의 모든 룰을 한눈에 — 'goax rules', 'rules 보여줘', '룰 인덱스', 'CRITICAL 룰', 'critical', 'mandatory'. CLAUDE.md(Constitution) + .ax/spirit/rules/(Spirit) + module CLAUDE.md(Layer 2) 통합 인덱스. 작업 시작·PR 직전 위반 검출 흐름 포함."
---

# goax rules — 룰 통합 인덱스 + 위반 검출

## 발동 트리거
- "goax rules", "rules 보여줘", "룰 인덱스"
- "CRITICAL 룰만", "MANDATORY 룰", "보안 룰"
- "find AX:CRITICAL:001" 같은 토큰 검색
- 코드 작성/수정 직전, PR 작성 직전 — 적용 가능한 CRITICAL 검사

## 시작 전 필수
`.ax/spirit/values.md`, `tone.md` 따라요.

## 시그널 포맷

```
🔴 CRITICAL 자동 차단 (Sensors가 막음, 우회 불가)
🟡 MANDATORY 사람 승인 필요 (명시적 게이트)
🔵 CONVENTION 일반 가이드 (권장, 차단 X)
```

## 1. 룰 소스 3 곳

| Source | 위치 | 토큰 형식 |
|---|---|---|
| Constitution | `CLAUDE.md` (root) | `<scope>:CRITICAL:NNN` 등 |
| Spirit | `.ax/spirit/rules/<category>.md` | `SP-<CAT>-NNN` |
| Module | `<module>/CLAUDE.md` | scope에 모듈 prefix |

## 2. 출력 (인덱스 모드)

```
🔴 CRITICAL (자동 차단)
 - AX:CRITICAL:001 — 결제 API는 멱등성 키 필수 [Constitution]
  📍 CLAUDE.md:14
 - AX:CRITICAL:002 — DB 마이그레이션 PR은 ADR 필수 [Constitution]
  📍 CLAUDE.md:18

🟡 MANDATORY (사람 게이트)
 - AX:MANDATORY:001 — ... [Constitution]

🔵 CONVENTION (가이드)
 - SP-NAMING-001 — 파일명 kebab-case [Spirit/naming]
  📍 .ax/spirit/rules/naming.md:7
 - SP-PR-002 — 커밋 메시지 한국어 [Spirit/pr]
 ...

총 N개 룰 (CRITICAL: a / MANDATORY: b / CONVENTION: c)
```

## 3. 필터

- `--level critical` / `--level mandatory` / `--level convention`
- `--source constitution` / `--source spirit` / `--source module`
- `--category security` 등 Spirit 카테고리
- `find <token>` — 정확 매칭 (예: `find AX:CRITICAL:001`)

자연어 매핑:
- "CRITICAL 룰만" → `--level critical`
- "spirit 룰" → `--source spirit`
- "보안 룰" → `--category security`

## 4. 위반 검출 흐름 (이전 critical-rules skill 통합)

작업 *직전* 또는 PR *직전* 다음을 따라요:

1. **CLAUDE.md의 `## CRITICAL` 섹션 우선 로드** — 매번 다시 읽어요. 외워서 적용 X (사용자가 갱신해도 반영 안 됨).
2. **변경 파일이 어떤 모듈인지 파악** → 해당 모듈의 `<module>/CLAUDE.md`도 함께 로드
3. **위반 가능성 평가**:
 - 🔴 CRITICAL → 작업 중단, 사용자 보고 + 우회 거부
 - 🟡 MANDATORY → 사용자 승인 요청
 - 🔵 CONVENTION → 진행하면서 코멘트로 안내
4. **자동 검출 파트너**: `.ax/hooks/pre-commit/critical-rule-grep.sh` (deterministic). 사용자가 grep 패턴을 추가하려면 그 파일 수정.

## 안티 패턴

- 룰을 외워서 적용 → 사용자가 갱신해도 반영 안 됨. CLAUDE.md를 SSOT로
- 모든 룰을 동등 가중치 → CRITICAL 우선
- 룰 본문을 임의로 요약 → 사용자에게 보여줄 땐 원문 그대로

## state.json 갱신

이 skill이 끝날 때 `.ax/state.json` 갱신 항목:
- last_skill, skill_calls만 갱신 (룰 본문 변경 없음 — read-only)

갱신 방법: jq로 in-place. 실패해도 skill 본 작업은 영향 X (HUD는 부수효과).
```bash
# 메타데이터만 — read-only skill이라 derived value 변경 없음
jq '.last_skill = "rules" | .skill_calls = ((.skill_calls // 0) + 1) | .updated_at = (now | todate)' \
 .ax/state.json > .ax/state.json.tmp && mv .ax/state.json.tmp .ax/state.json
```
