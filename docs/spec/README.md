# Spec — 도메인 정의

> goax 자체의 도메인 정의·인터페이스·계약을 기록하는 공간.
> 사용자 프로젝트는 자기 도메인 spec을 여기에 채워요.

## 무엇이 들어가는가

- **도메인 정의** — 핵심 개념, 용어, 경계
- **인터페이스 / 계약** — CLI 명령 input/output 스펙
- **데이터 모델** — config.yml schema, mistakes 파일 schema 등
- **불변량 (Invariants)** — 어떤 상황에서도 깨지지 않아야 할 것

## ADR과의 차이

| | docs/adr/ | docs/spec/ |
|---|---|---|
| 다루는 것 | 결정의 *근거* (왜) | 도메인의 *정의* (무엇) |
| 시제 | 과거형 ("우리는 X를 채택했다") | 현재형 ("X는 Y이다") |
| 변경 빈도 | 낮음 (결정은 이력) | 중간 (도메인 진화에 따라) |

## 파일 명명

- `docs/spec/<domain>.md` — 도메인 단위
- `docs/spec/glossary.md` — 용어 사전
- `docs/spec/<area>/<sub-spec>.md` — 디렉토리 분할 가능

## 사용자 프로젝트에서

`goax init`이 깐 `docs/{adr,spec}/`에 자기 도메인 spec을 추가하면 돼요.
- 채팅 도메인이면 `docs/spec/chat.md`
- 결제 도메인이면 `docs/spec/payment.md`
- 용어가 많으면 `docs/spec/glossary.md`
