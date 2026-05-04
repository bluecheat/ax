# Reference — Critical Rules 매트릭스

goax가 지원하는 룰 카테고리와 자동 검증 가능 여부.

| 카테고리 | 예시 | Sensor 자동화 | 비고 |
|---|---|---|---|
| **모듈 의존 방향** | `core → rest` 위반 차단 | ✅ Structural (`circular_analysis.py`) | 가성비 최고 |
| **Clean Arch 패키지** | Repository는 application/port/out/ | ✅ Structural | grep 또는 정적 분석 |
| **인터페이스 강제** | UseCase는 class 아님 | ✅ Structural | grep |
| **DI 검증** | `@UseGuards`+`forwardRef(AuthModule)` | △ 부분 | tsc 통과 + 기동 테스트 필요 |
| **SSR Hydration** | `typeof window` 분기 금지 | ✅ grep |  |
| **DDL 동반** | Entity 변경 시 SQL 파일 함께 | ✅ pre-commit | git diff 분석 |
| **Test 태그** | `@SpringBootTest`+`@Tags("Integration")` | ✅ grep | regex |
| **Domain val-only** | val + Rich Domain | ✅ grep | regex |
| **Secrets 검출** | password/api_key 평문 | ✅ pre-commit | regex (false positive 가능) |
| **파괴적 명령** | `rm -rf /`, `git push --force` | ✅ pre-bash | 패턴 화이트리스트 |
| **Traffic estimation** | risk≥L2 PR에 estimation 첨부 | △ 사람 게이트 | PR description 검사 |
| **Bug fix 가드 테스트** | bug fix PR에 reproduction test | △ 사람 게이트 | 테스트 파일 존재 검사 가능 |
| **사용자 데이터 보호** | 콘텐츠 하드 DELETE 금지 | ✅ grep | DELETE FROM 패턴 |

## 자동화 우선순위

1. **High ROI / Low effort**: SSR Hydration, val-only, Secrets, 파괴적 명령 → 정규식 한 줄
2. **High ROI / Medium effort**: 모듈 의존 방향, Clean Arch 패키지 → 자기 프로젝트 분석 스크립트 + CI 연결
3. **Medium ROI / High effort**: DI 검증, DDL 동반 → CI에서 부분 자동화
4. **Low automation / High discipline**: Traffic estimation, 가드 테스트 → 사람 게이트 + PR template
