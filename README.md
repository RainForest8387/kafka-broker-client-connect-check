# kafka-broker-client-connect-check

Варианты использования:
1. Через переменную окружения (рекомендуется):
```bash
KAFKA_BROKERS_IPS="10.0.1.10,10.0.1.11,10.0.1.12" ./kafka_connections.sh
```

2. Через параметр командной строки:
```bash
./kafka_connections.sh --brokers "10.0.1.10,10.0.1.11,10.0.1.12"
```

3. Без параметров (автоопределение):
```bash
./kafka_connections.sh
```
