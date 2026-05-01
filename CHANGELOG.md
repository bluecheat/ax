# Changelog

## v0.1.0 (2026-05-01) — initial

### Added
- CLI: `init` / `triage` / `audit` / `doctor` / `update`
- `install.sh` standalone + submodule 모드
- `templates/default/` — 4계층 골격 (Constitution / Triage / Mistake Loop / Hooks)
- `templates/presets/ax/` — 당근 AX팀 9 CRITICAL overlay
- 4개 hooks (block-destructive / check-protected-paths / lint-changed / critical-rule-grep)
- 4개 skills (triage / critical-rules / steering-loop / adr-write / skill-audit)
- 2개 agents (architect / evaluator)
- 자체 문서: concepts / customization / examples (crou-mono, commerce) / reference

### Known Limitations
- `ax-first audit` 카테고리 추출이 단순 grep — 향후 frontmatter 파서로 강화 예정
- preset이 `ax` 한 종류 — `oss` 등 추가 예정
- 모든 hooks는 `warning-only` 모드 시작 — `fail` 모드 자동 전환 로직 부재

### Roadmap
- v0.2 — `/steering-audit`이 룰 승격 PR 자동 작성
- v0.3 — `evaluator` agent의 별도 Claude 세션 호출 자동화
- v0.4 — sensors 통계 대시보드, fail 모드 자동 전환
