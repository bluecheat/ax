# Changelog

릴리스 기록이에요. 사용자는 굳이 볼 필요 없어요. goax는 plugin이라 항상 최신을 쓰면 돼요.

## 버전

- [0.5.4](0.5.4.md) — hook 도달 범위: SubagentStart 포인터 · Stop 게이트 · 주입 중복 제거(실측 1,200회) · 인계 노트 기한 추적
- [0.5.3](0.5.3.md) — 산문이던 진단을 스크립트로(rules·spirit 폐기, doctor-scan 도달 지도) + 세션 간 인계 노트 STATUS.md
- [0.5.2](0.5.2.md) — 계획 시점의 합의 리뷰(architect → evaluator, Size 축) + 하네스 위치만 보여주는 HUD
- [0.5.1](0.5.1.md) — 문서가 앞서 있던 엣지 셋을 코드로: 레인 원장 · 레인 모드 · evaluator 게이트
- [0.5.0](0.5.0.md) — 0에서 1로 가는 길과, 가를 수 있는지부터 묻는 병렬
- [0.4.2](0.4.2.md) — 검색이 슬러그를 넘어서고, 설치가 파일이 됐어요
- [0.4.1](0.4.1.md) — 하네스 테제의 빈 절반 채우기 + 실사용에서 드러난 결함 정리
- [0.4.0](0.4.0.md) — 공개 준비: 훅 우회 차단 + 집행 강도의 정직한 문서화
- [0.3.1](0.3.1.md) — 집행 실체 검증 (I6·sensor liveness) + git hook 전 환경 기본
- [0.3.0](0.3.0.md) — 재베이스라인: 행동 스캐폴딩 lean 전환 + model_tier 분기
- [0.2.5](0.2.5.md) — 플러그인 전면 정비: SSOT 버그·유령 참조 제거 + smoke 재작성
- [0.2.4](0.2.4.md) — triage 4단계 역면접(Reverse Interview) + intent_notes 스키마 실체화
- [0.2.3](0.2.3.md) — MEMORY.md 회상 인덱스 품질·토큰 개선
- [0.2.2](0.2.2.md) — triage-search 공백 키워드 크래시 수정
- [0.2.1](0.2.1.md) — triage 검색 연관성·토큰 효율 개선 + MEMORY.md·BM25 인덱스
- [0.2.0](0.2.0.md) — OpenCode Hybrid 호환 + AGENTS.md Constitution SSOT
- [0.1.20](0.1.20.md) — 보안 경화 + CLI-agnostic fallback + L3 일반화 + slash wrapper 폐기
- [0.1.19](0.1.19.md) — audit §4.2 압축·탈맥락 원칙 박스
- [0.1.18](0.1.18.md) — brownfield 보호 + spec-validate visibility + friction anti-pattern + install→up rename
- [0.1.17](0.1.17.md) — doctor 시각화 개편 (emoji 매핑 + Plugin update 단일 y/n + changelog 발췌)
- [0.1.16](0.1.16.md) — SDD 슬림화 (plan.md 폐기 + tier 2 단계 + spec-validate 강화)
- [0.1.15](0.1.15.md) — spec/README 출고 제거 (Layer 3 책임 분리)
- [0.1.14](0.1.14.md) — Confirmation Friction Policy
- [0.1.13](0.1.13.md) — MANIFEST install 검증 + rules-tokens 재작성
- [0.1.12](0.1.12.md) — ops.md opt-in 강등
- [0.1.11](0.1.11.md) — audit 3단계 강제 + mistake archive
- [0.1.10](0.1.10.md) — mistake skill 본문 작성 강제 + template 청소
- [0.1.9](0.1.9.md) — rule-enforcement 스키마 + mistake/audit 분리 + CLAUDE.md no-append
- [0.1.8](0.1.8.md) — capture 안전성 + install upgrade-safe (mistake loop 기반 다지기)
- [0.1.7](0.1.7.md) — hook bootstrap guard + CONVENTION 카운트 정확화 + onboarding Sub-Q5 codify
- [0.1.6](0.1.6.md) — skill 명명 일관화 + null-guard + doctor disclosure + plugin perspective cleanup
- [0.1.5](0.1.5.md) — hook `set -e` 일관 제거 + 신규 hook 가드 #5 #6
- [0.1.4](0.1.4.md) — awk count 패턴 수정 + 신규 project hook 4가지 가드 + CONVENTION 형식 통일
- [0.1.3](0.1.3.md) — state.json 버전 stamp + hook chain safety + xargs 보안 hardening
- [0.1.2](0.1.2.md) — 템플릿 이주 (`_TEMPLATE` 인스턴스 디렉토리에서 `_templates/`로 통합, 우회 필터 5군데 제거)
- [0.1.1](0.1.1.md) — mistakes 자기충돌 차단 + SSOT 안내 정정 + @import 클레임 정합화 + hook modernization
- [0.1.0](0.1.0.md) — Initial release

## 업데이트

```
/plugin marketplace update goax
/plugin install goax
```

이게 끝이에요.
