# ADR 0002: `.claude/` vs `.ax/` 디렉토리 분리

## 상태
승인됨 (v0.5, 2026-05-01)
- v0.3에서 잘못된 통합 → v0.5에서 정정

## 컨텍스트
v0.3에서 모든 goax 자산을 `.ax/`로 통합했지만, Claude Code가 자동 로드하는 위치는 `.claude/skills/`, `.claude/agents/`. v0.3 구조는 슬래시 커맨드 자동 매칭이 동작하지 않았다.

## 검토된 대안

### A. `.ax/`에 다 두고 symlink로 `.claude/`에 노출
- Pros: goax 자산 한 곳에 모임
- Cons: Windows·일부 CI에서 symlink 이슈
- 결과: 기각

### B. `.claude/{skills,agents}` + `.ax/{spirit,mistakes,hooks,config}` (채택)
- Pros: Claude Code 표준 자동 로드 보장 + goax 자체 자산 격리
- Cons: 두 디렉토리 분리
- 결과: 채택

### C. 모두 `.claude/`로
- Pros: 표준 한 곳
- Cons: spirit/mistakes 같은 goax 자체 자산까지 .claude/에 두면 Claude Code가 의도하지 않은 동작 가능
- 결과: 기각

## 결정
- `.claude/` = Claude Code 표준 자산 (skills, agents, settings.json)
- `.ax/` = goax 자체 자산 (spirit, mistakes, hooks, config.yml, version)

## 결과
- v0.5: `.ax/{skills,agents}` → `.claude/{skills,agents}` mv
- hooks는 `.ax/hooks/`에 있되 `.claude/settings.json`이 호출 (이미 동작)
- mistakes 캡처: goax 자체 도구가 .claude/ 표준 위치를 검증하지 않은 점 → `audit` 카테고리 'tooling'에 누적
