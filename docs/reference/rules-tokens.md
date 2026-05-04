# Rules Tokens — 룰 식별·검색 컨벤션

> 모든 룰에 표준 토큰을 박아 두면 사람도 grep도 1초 안에 찾는다.

## 토큰 형식

```
<scope>:<LEVEL>:<id>
```

| 부분 | 의미 | 예 |
|---|---|---|
| `scope` | 적용 범위 | `AX` (전역), `api`, `web`, `payment`, `<module>`, `*` |
| `LEVEL` | 등급 (대문자) | `CRITICAL`, `MANDATORY`, `CONVENTION` |
| `id` | 3자리 0-padded 순차 | `001`, `042`, `127` |

### 예시

| 토큰 | 해석 |
|---|---|
| `AX:CRITICAL:001` | 전역 비협상 룰 #1 |
| `api:CRITICAL:003` | api 모듈 비협상 룰 #3 |
| `payment:MANDATORY:002` | payment 도메인 사람 게이트 룰 #2 |
| `*:CONVENTION:015` | 모든 모듈 공통 컨벤션 #15 |

## 룰 본문 작성

```markdown
🔴 **`AX:CRITICAL:001`** 파괴적 명령 자동 차단

위반 시 hook이 명령을 멈춘다. `rm -rf /`, `git push --force` 등.

<!-- adr: docs/adr/0003-destructive-cmd-blocklist.md -->
```

권장 요소:
- 등급 이모지 (`🔴 🟡 🔵`) + 토큰 (백틱 안)
- 한 줄 요약 후 빈 줄 + 본문
- 결정 근거 ADR이 있으면 `<!-- adr: ... -->` 코멘트

## grep 패턴 모음

```bash
grep -rn 'CRITICAL'              --include='CLAUDE.md' .   # 전체 CRITICAL
grep -rn 'AX:'                   --include='CLAUDE.md' .   # 전역만
grep -rn 'api:CRITICAL'          --include='CLAUDE.md' .   # api 모듈 CRITICAL
grep -rn 'payment:'              --include='CLAUDE.md' .   # payment 도메인 전체
grep -rn 'CRITICAL:00[1-9]'      --include='CLAUDE.md' .   # 1~9번 CRITICAL
grep -rn '`[a-z*]\+:MANDATORY'   --include='CLAUDE.md' .   # 모든 MANDATORY (정규식)
```

## CLI

`goax rules`가 위 grep을 wrap. 직접 grep 안 쳐도 됨:

```bash
goax rules                          # 모든 룰 트리
goax rules --level critical
goax rules --scope payment
goax rules --module apps/api
goax find AX:CRITICAL:001           # ID로 1개 + 관련 ADR 같이
goax rules --json                   # 다른 도구 연동
```

## ID 발급 규칙

| 상황 | 처리 |
|---|---|
| 신규 룰 추가 | scope 안에서 마지막 ID + 1 |
| 룰 폐기 | ID는 재사용 안 함 — frontmatter에 `status: deprecated` 추가 |
| 룰 재배치 (scope 변경) | 새 scope의 다음 ID 발급, 본문에 `replaces: api:CRITICAL:003` 명시 |
| 룰 분할 | 옛 ID `replaces`로 표시, 새 ID 둘 발급 |

## 안티 패턴

- 토큰 없는 룰 → CLI/grep에서 못 찾음 → goax doctor가 경고
- ID 충돌 (같은 scope·level·id) → goax rules가 fail
- LEVEL 소문자 (`critical`) → 대문자 통일 (`CRITICAL`)
- ADR 링크 없는 CRITICAL → context drift 위험 (강제 아님, 권장)

## 마이그레이션 (기존 룰에 토큰 부여)

```bash
goax rules --untokenized      # 토큰 없는 룰 목록
goax rules --renumber <scope> # scope 안 ID 재정렬 (충돌 해결)
```
