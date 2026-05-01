# AX Preset — 당근 AX팀 권장 룰

`ax-first init --preset ax`로 활성화되는 프리셋.

## 무엇이 추가되는가

1. **CLAUDE.md.overlay** — 9 CRITICAL + 3 MANDATORY + 3 CONVENTION이 기존 CLAUDE.md 끝에 append.
2. *(향후 v0.2)* hooks 강도가 `warning` → 일부 `fail` 로 자동 설정.
3. *(향후 v0.2)* `.coderabbit.yaml` 한국어 템플릿.
4. *(향후 v0.3)* 당근 도메인 위험도 기본값(payment=L3, order=L2 등) `config.yml`에 자동 반영.

## 적용 후 첫 작업

- `CLAUDE.md`에 추가된 9 CRITICAL이 우리 팀에 맞지 않으면 `--force`로 재init 또는 직접 편집.
- `.ax-first/config.yml` 의 `domain_risk` 매트릭스를 자기 프로젝트 도메인으로 갱신.
- `ax-first doctor`로 결손 검사.

## 출처

본 프리셋의 CRITICAL 9개는 `crou-mono`와 `commerce-monorepo/projects/commerce` 두 레퍼런스 프로젝트에서 추출되었어.
- `crou-mono`: NestJS/Next.js/RN/Go 폴리글랏 — 룰은 SSR Hydration, React 버전 격리, 콘텐츠 소프트 딜리트, NestJS DI 등.
- `commerce`: Kotlin/Spring Boot 모노 — 룰은 모듈 의존 방향, Clean Arch, integration tag, val-only 등.

본 프리셋은 둘에서 **공통적으로 적용 가능한 9개**만 추렸어. 스택 특수 룰은 자기 모듈 CLAUDE.md에 추가하길.
