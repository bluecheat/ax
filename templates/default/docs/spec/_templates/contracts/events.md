# Events — <피처 이름>

> 발행/구독하는 이벤트 스키마.

---

## <Event Name>

| 항목 | 값 |
|---|---|
| Topic | `<topic-name>` |
| Schema | JSON / Avro / Protobuf |
| 멱등성 키 | `<field>` |

```json
{
  "id": "uuid",
  "type": "<event.type>",
  "occurredAt": "ISO-8601",
  "payload": {
    "<field>": "<value>"
  }
}
```

### 발행 트리거
<언제·어디서>

### 구독자
- <서비스 A> — <어떻게 처리>
- <서비스 B> — ...

### 멱등성 / 재시도
<중복 처리 전략>
