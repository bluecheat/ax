# ADR 0003: Spirit을 Cross-cutting Layer로 도입

## 상태
승인됨 (v0.3, 2026-05-01)

## 컨텍스트
Persona가 늘어날수록 톤·휴리스틱·의사결정이 분기되는 *consistency drift* 문제 관찰.
선행 사례:

## 검토된 대안

### A. SOUL.md / BRAIN.md / SPIRIT.md 3 파일 그대로
- Pros: 표준 패턴
- Cons: SOUL ≈ CLAUDE.md, BRAIN ≈ persona — 이미 있는 자산과 중복
- 결과: 기각

### B. SPIRIT만 신규, SOUL/BRAIN은 기존 자산 매핑 (채택)
- SOUL ≈ CLAUDE.md (Layer 1 Constitution)
- BRAIN ≈ `.claude/skills/personas/<role>/SKILL.md`
- SPIRIT = 신규 = `.ax/spirit/{values, tone, rules}`
- Pros: 기존 자산 재활용, 단일 신규 디렉토리
- Cons: 매핑 학습 필요 (CONCEPTS.md §2.9에 명시)
- 결과: 채택

### C. 수학적 드리프트 감지(코사인 유사도+EMA) 즉시 도입
- Pros: 정량 측정
- Cons: NumPy 의존성, 비용·복잡도 ↑, 검증 시간 부족
- 결과: v0.6+ 미루기. 지금은 mistakes 카테고리 누적량으로 정성 측정

## 결정
- `.ax/spirit/` 디렉토리 신설
- `values.md`, `tone.md`는 spirit/ 직속 — values·tone은 룰이 아니라 메타
- `rules/<카테고리>.md`는 1 파일 = 1 카테고리 (security, naming, pr, testing, ...)
- Triage가 spirit_context로 자동 주입
- spirit 누락 시 fail로 차단

## 결과
- v0.3 본 구현: spirit 디렉토리 + CLI (`goax spirit add/lint/status`) + Triage 자동 주입 + rules CLI 통합
- 향후 버전: drift 정량 측정은 보류
