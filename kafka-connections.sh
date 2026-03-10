#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Порты Kafka брокеров для проверки
PORTS=(9092 9093 9094)

# IP адреса Kafka брокеров (можно задать через переменную KAFKA_BROKERS_IPS или параметр --brokers)
KAFKA_BROKERS_IPS=${KAFKA_BROKERS_IPS:-""}

# Функция для парсинга аргументов командной строки
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --brokers)
                shift
                KAFKA_BROKERS_IPS="$1"
                shift
                ;;
            -h|--help)
                echo "Использование:"
                echo "  $0 [--brokers \"ip1,ip2,ip3\"]"
                echo "  KAFKA_BROKERS_IPS=\"10.0.0.1,10.0.0.2,10.0.0.3\" $0"
                echo ""
                echo "Примеры:"
                echo "  $0 --brokers \"10.0.0.1,10.0.0.2,10.0.0.3\""
                echo '  KAFKA_BROKERS_IPS="10.0.0.1,10.0.0.2,10.0.0.3" ./kafka_connections.sh'
                exit 0
                ;;
            *)
                echo "Неизвестный параметр: $1"
                echo "Используйте --help для справки"
                exit 1
                ;;
        esac
    done
}

# Парсим аргументы
parse_args "$@"

echo -e "${GREEN}=== Проверка активных подключений на порты Kafka ===${NC}"

# Функция для получения имени хоста по IP (с таймаутом)
get_hostname() {
    local ip=$1
    local hostname=$(timeout 2 host "$ip" 2>/dev/null | awk '/domain name pointer/ {print $5}' | sed 's/\.$//')
    if [[ -z "$hostname" ]]; then
        echo "$ip"
    else
        echo "$hostname ($ip)"
    fi
}

# Парсим список брокеров из строки (через запятую)
if [[ -n "$KAFKA_BROKERS_IPS" ]]; then
    IFS=',' read -ra KAFKA_BROKERS <<< "$KAFKA_BROKERS_IPS"
else
    KAFKA_BROKERS=()
fi

# Добавляем автоопределение брокеров если список пустой
if [[ ${#KAFKA_BROKERS[@]} -eq 0 ]]; then
    echo -e "${YELLOW}Автоопределение Kafka брокеров...${NC}"
    for port in "${PORTS[@]}"; do
        broker_pid=$(ss -tlnp | grep ":$port " | awk '{print $7}' | sed 's/.*users:\((\([0-9]*\),.*\))/\2/')
        if [[ -n "$broker_pid" ]]; then
            broker_cmd=$(ps -p "$broker_pid" -o cmd --no-headers 2>/dev/null)
            if echo "$broker_cmd" | grep -q -E "(kafka|Kafka|KAFKA)"; then
                broker_ip=$(ss -tlnp | grep ":$port " | awk '{print $5}' | cut -d: -f1 | head -1)
                if [[ -n "$broker_ip" && "$broker_ip" != "0.0.0.0" && "$broker_ip" != "127.0.0.1" && "$broker_ip" != "::" ]]; then
                    KAFKA_BROKERS+=("$broker_ip")
                fi
            fi
        fi
    done
    # Удаляем дубликаты
    mapfile -t KAFKA_BROKERS < <(printf '%s\n' "${KAFKA_BROKERS[@]}" | sort -u)
fi

echo -e "\n${YELLOW}Kafka брокеры для исключения:${NC}"
if [[ ${#KAFKA_BROKERS[@]} -eq 0 ]]; then
    echo "  Брокеры не заданы"
else
    printf '  %s\n' "${KAFKA_BROKERS[@]}"
fi

echo -e "\n${GREEN}=== Активные клиентские подключения ===${NC}"

# Проверяем активные подключения на каждый порт
found_connections=false
for port in "${PORTS[@]}"; do
    echo -e "\n--- Порт $port ---"

    connections=$(ss -tn '( dport = :'"$port"' or sport = :'"$port"' )' | grep ESTAB)

    if [[ -z "$connections" ]]; then
        echo "  Нет активных подключений"
        continue
    fi

    found_connections=true

    while IFS= read -r line; do
        local_addr=$(echo "$line" | awk '{print $4}')
        remote_addr=$(echo "$line" | awk '{print $5}')
        remote_ip=$(echo "$remote_addr" | cut -d: -f1)

        # Пропускаем localhost
        if [[ "$remote_ip" == "127.0.0.1" || "$remote_ip" == "::1" ]]; then
            continue
        fi

        # Проверяем, является ли remote_ip одним из брокеров
        skip=false
        for broker in "${KAFKA_BROKERS[@]}"; do
            if [[ "$remote_ip" == "$broker" ]]; then
                skip=true
                break
            fi
        done

        if [[ "$skip" == false ]]; then
            hostname_info=$(get_hostname "$remote_ip")
            direction=$( [[ "$local_addr" =~ :$port: ]] && echo "-> исходящее" || echo "<- входящее" )
            echo -e "  ${YELLOW}$hostname_info${NC} $direction"
        fi
    done <<< "$connections"
done

if [[ "$found_connections" == false ]]; then
    echo -e "\n${RED}Активных клиентских подключений не найдено${NC}"
fi
