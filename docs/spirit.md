# Spirit

Spirit은 모든 sub-agent가 공유하는 *태도·문화·일하는 방식*이에요. 4계층 하네스의 Cross-cut.

## 위치

`.ax/spirit/` (사용자 프로젝트에 깔리는 자산):

- `values.md` — 핵심 가치 (긍정 편향 금지·비판적 사고·결과→근거→다음 액션·추측 대신 질문·작은 단위·자가 점검·안전 우선)
- `tone.md` — 어체·말씨 (`~해요 체` 강제 + 안티패턴)
- `rules/<카테고리>.md` — 카테고리별 룰 (security, naming, pr, testing, error-handling, concurrency, observability, architecture, data)

## 자동 주입 흐름

1. 사용자 메시지 → `triage` 발동
2. Triage가 size×risk 분류 + 매칭된 `spirit_context` 결정
3. 후속 skill 호출 시 spirit 파일들이 컨텍스트로 함께 로드됨
4. 모든 plugin skill은 시작 전 `values.md` + `tone.md` 명시 로드 (SKILL.md 상단 "시작 전 필수" 블록)

## 운영 명령

```
/spirit     # spirit 무결성 점검
/rules            # spirit + Constitution + Module 통합 인덱스
/audit            # mistakes → spirit/rules 승격
```

## 자기 프로젝트 맞춤화

`.ax/spirit/rules/<카테고리>.md`에 새 카테고리 파일을 추가하면 자동 주입 대상에 포함돼요. 룰 토큰 컨벤션:

- Spirit: `SP-<CAT>-NNN` (예: `SP-SEC-001`)
- Constitution(CLAUDE.md): `<scope>:<LEVEL>:<id>` (예: `AX:CRITICAL:001`)

## 더 보기

- 4계층 안 Spirit 위치: [`CONCEPTS.md`](../CONCEPTS.md) 2.9
- Skill 주입 흐름: [`docs/skill-routing.md`](skill-routing.md)
- 작성 가이드: `templates/default/.ax/spirit/README.md`
- 무결성 점검: `/spirit`
- 결정 기록: [`changelog/0.1.0.md`](../changelog/0.1.0.md) "설계 결정 — Spirit Cross-cutting (v0.3)"
