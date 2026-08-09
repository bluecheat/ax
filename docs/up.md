# goax 도입 — Brownfield (이미 운영 중인 프로젝트)

> 모든 도입은 Claude Code 안에서 자연어 또는 slash command로 진행해요.
> bash CLI(`goax up` 같은) 시절은 끝났어요. 지금은 plugin이에요.

## 한 줄 요약

```
/plugin marketplace add https://github.com/bluecheat/ax
/plugin install goax
```

설치 후, Claude Code에서 한 줄:

```
"goax up"   # 또는 /up — "goax 도입해줘" / "goax 설치" / "goax 셋업" 도 같은 skill 발동
```

→ `up` skill이 발동해서 프로젝트를 분석하고 사용자 동의 후 `.ax/`를 깔아요.
첫 호출 = install, 두 번째부터 = idempotent update (plugin 갱신 후 재호출 — 사용자 customize 자산은 `.suggested` 패턴으로 보존).
기존 자산(CLAUDE.md, hooks, 모듈, 외부 spec 중 하나라도)이 있으면 `.ax/.onboarding-pending` 마커를 남기고 `onboarding` skill로 이어가요.

## 흐름 (실제로 일어나는 일)

```
1. /up 또는 "goax up" / "goax 도입해줘"
  └─ up skill
   ├─ 1. 프로젝트 분석 (Claude가 코드를 직접 읽음)
   │  ├─ 모노레포/싱글
   │  ├─ 모듈 목록
   │  ├─ CLAUDE.md, hooks, 외부 spec, AI 리뷰 도구
   │  └─ Stack, 도메인 후보 (의미 있는 것만)
   ├─ 2. Plan 출력 (4계층 + Cross-cut으로 깔릴 자산 표)
   ├─ 3. 단일 동의 프롬프트 (Y/n)
   ├─ 4. 설치 — plugin templates → 사용자 프로젝트로 cp
   │  ├─ .ax/spirit/{values,tone,rules}/
   │  ├─ .ax/hooks/*.sh
   │  ├─ .ax/config.yml
   │  ├─ .ax/mistakes/
   │  ├─ .ax/docs/{adr, _templates/spec}/
   │  ├─ CLAUDE.md (기존 있으면 .ax/CLAUDE.md.suggested)
   │  └─ .claude/settings.json (기존 있으면 .ax/settings.json.suggested)
   └─ 5. brownfield → onboarding 위임 / greenfield → 안내만

2. (brownfield 한정) "goax 도입 마무리해줘" 또는 /onboarding
  └─ onboarding skill — Q1~Q5
   ├─ Q1 도메인 매핑 (모듈명·패키지에서 도메인 추출, 사용자 검수)
   ├─ Q2 위험도 (L0~L3 매트릭스를 사용자와 함께 결정)
   ├─ Q3 CLAUDE.md 룰 분류 (CRITICAL / MANDATORY / CONVENTION)
   ├─ Q4 외부 spec 처리 (링크만 / SDD 포맷 변환 흡수)
   ├─ Q5 4계층 활성화 (Layer 1 시그널화 + Layer 2 placeholder + 첫 ADR)
   └─ 마무리 — .ax/.onboarding-pending 마커 삭제
```

## 결정 항목 (onboarding이 묻는 것)

| Q | 항목 | 권장 옵션 |
|---|---|---|
| Q1 | 도메인 매핑 | 자동 추출 결과를 사용자와 함께 검수 |
| Q2 | 위험도 매트릭스 | L0~L3로 도메인별 분류, 보수적으로 시작 |
| Q3 | CLAUDE.md 룰 처리 | 시그널 라벨 + 카테고리별 spirit/rules 분리 |
| Q4 | 외부 spec | [a] 링크만 / [b] SDD 포맷 변환 흡수 |
| Q5 | 4계층 활성화 | 즉시 활성 (CLAUDE.md prepend + Layer 2 placeholder + 첫 ADR) |

## 안전 장치

- 모든 변경은 사용자 *동의 후*에만 적용. 동의 전엔 파일 변경 0.
- 기존 `CLAUDE.md`·`.claude/settings.json`이 있으면 `.ax/*.suggested`로 떨어트리고 사용자가 머지.
- Sensors(`.ax/hooks/`)는 default `mode: warning`. 첫날부터 fail로 PR 막지 않아요.
- `doctor`로 결손·drift 진단. 강제 변경은 없음.

## 진단·운영

```
/doctor     # 4계층 결손 + _templates drift 진단
/rules      # 통합 룰 인덱스 (Constitution + Spirit + Module)
/audit      # mistakes 회고 + 룰 승격 후보
/spec <slug> # 새 SDD spec
/spec-validate   # NEEDS CLARIFICATION 게이팅
```

## 안티 패턴

- 첫날 fail 모드로 모든 PR 차단 → 팀 반발 → 도입 자체 실패
- 도메인 위험도를 사용자 동의 없이 박기 → onboarding 무력화
- 외부 spec을 무리하게 흡수 → 다른 팀 워크플로우 깨짐

## 관련 문서

- [`README.md`](../README.md) — 설치·명령 매핑
- [`CONCEPTS.md`](../CONCEPTS.md) — 설계 사상
- [`docs/sdd.md`](sdd.md) — Spec-Driven Development
- [`docs/spirit.md`](spirit.md) — Spirit 작성·적용
- [`changelog/0.1.0.md`](../changelog/0.1.0.md) "Design decisions" 섹션 — 결정 근거 (거부된 대안 포함)
