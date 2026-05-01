# Spec — 도메인 정의

> 이 디렉토리는 우리 프로젝트의 도메인 정의·인터페이스·계약을 기록하는 공간이에요.
> ADR은 *결정의 근거*(왜)를, Spec은 *도메인의 정의*(무엇)를 다뤄요.

## 무엇을 적나

- 도메인 핵심 개념·용어·경계
- 인터페이스 / 계약 (API spec, 이벤트 스키마 등)
- 데이터 모델 + 불변량
- 비즈니스 룰 (코드와 분리해서 사람도 읽도록)

## 파일 명명

- `<domain>.md` — 도메인 단위 (예: `payment.md`, `order.md`)
- `glossary.md` — 용어 사전
- `<area>/<sub>.md` — 디렉토리 분할

## 빈 상태

지금은 비어있어요. 도메인 spec을 추가하세요:

```bash
# 예: 결제 도메인 spec 추가
touch docs/spec/payment.md

# 예: 용어 사전
touch docs/spec/glossary.md
```

## 연관

- ADR (결정): [`docs/adr/`](../adr/)
- Constitution (룰): [`../../CLAUDE.md`](../../CLAUDE.md)
- Spirit (태도): [`../../.ax/spirit/`](../../.ax/spirit/)
