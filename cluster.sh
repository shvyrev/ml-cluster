#!/bin/bash

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция для вывода сообщений
log() {
    echo -e "${GREEN}[CLUSTER]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[CLUSTER]${NC} $1"
}

error() {
    echo -e "${RED}[CLUSTER]${NC} $1"
}

info() {
    echo -e "${BLUE}[CLUSTER]${NC} $1"
}

# Проверка существования скриптов
check_scripts() {
    local scripts=("scripts/deploy-cluster.sh" "scripts/destroy-cluster.sh" "scripts/manage-services.sh")
    
    for script in "${scripts[@]}"; do
        if [ ! -f "$script" ]; then
            error "Скрипт $script не найден"
            return 1
        fi
        
        if [ ! -x "$script" ]; then
            chmod +x "$script"
            log "Добавлены права на выполнение для $script"
        fi
    done
}

# Показать помощь
show_help() {
    echo "ML Platform Cluster Management"
    echo "============================="
    echo ""
    echo "Использование: $0 [КОМАНДА] [АРГУМЕНТЫ]"
    echo ""
    echo "Команды управления кластером:"
    echo "  deploy                        - Развернуть полный кластер"
    echo "  start                         - Запустить кластер"
    echo "  stop                          - Остановить кластер"
    echo "  destroy                       - Удалить кластер"
    echo "  status                        - Показать статус кластера"
    echo ""
    echo "Команды управления сервисами:"
    echo "  services init                 - Инициализировать namespace для сервисов"
    echo "  services templates            - Создать шаблоны для Java сервисов"
    echo "  services deploy               - Развернуть микросервисы"
    echo "  services build NAME [DOCKERFILE] - Собрать и загрузить образ"
    echo "  services restart NAME         - Перезапустить сервис"
    echo "  services logs NAME [follow]   - Показать логи сервиса"
    echo "  services status               - Показать статус сервисов"
    echo ""
    echo "Утилиты:"
    echo "  port-forward postgres         - Прокинуть порт PostgreSQL (5432)"
    echo "  port-forward minio            - Прокинуть порт MinIO UI (9001)"
    echo "  port-forward keycloak         - Прокинуть порт Keycloak (8082)"
    echo "  port-forward artifact-store   - Прокинуть порты всех сервисов artifact-store"
    echo "  port-forward redpanda         - Прокинуть порт Redpanda/Kafka (9092)"
    echo "  shell                         - Открыть shell в контейнере"
    echo "  help                          - Показать эту справку"
    echo ""
    echo "Примеры:"
    echo "  $0 deploy                     # Развернуть полный кластер"
    echo "  $0 services init              # Инициализировать сервисы"
    echo "  $0 services build java-service-1  # Собрать и загрузить образ"
    echo "  $0 port-forward postgres      # Прокинуть порт PostgreSQL"
    echo "  $0 port-forward keycloak      # Прокинуть порт Keycloak"
    echo "  $0 port-forward artifact-store # Прокинуть порты всех сервисов artifact-store"
    echo "  $0 port-forward redpanda      # Прокинуть порт Redpanda/Kafka"
    echo "  $0 status                     # Показать статус кластера"
}

# Port forwarding
port_forward() {
    local service="$1"
    
    case "$service" in
        "postgres")
            # Проверяем доступность кластера
            if ! kubectl cluster-info &> /dev/null; then
                error "Kubernetes кластер недоступен. Убедитесь, что кластер запущен:"
                echo "  $0 start    # Запустить кластер"
                echo "  $0 status   # Показать статус кластера"
                exit 1
            fi
            
            # Проверяем существование namespace
            if ! kubectl get namespace model-registry &> /dev/null; then
                error "Namespace 'model-registry' не найден. Возможно, сервисы не развернуты."
                echo "  $0 services deploy   # Развернуть сервисы"
                exit 1
            fi
            
            # Проверяем существование сервиса postgres
            if ! kubectl get svc postgres -n model-registry &> /dev/null; then
                error "Сервис 'postgres' не найден в namespace 'model-registry'"
                echo "  kubectl get svc -n model-registry   # Показать доступные сервисы"
                exit 1
            fi
            
            log "Проброс порта PostgreSQL на localhost:5432"
            
            # Запускаем порт-форвардинг
            kubectl port-forward -n model-registry svc/postgres 5432:5432 &
            POSTGRES_PID=$!
            
            # Проверяем, что процесс запустился успешно
            if ! kill -0 $POSTGRES_PID 2>/dev/null; then
                error "Не удалось запустить порт-форвардинг для PostgreSQL"
                exit 1
            fi
            
            # Выводим информацию о подключении
            echo ""
            echo "🔗 Подключение к PostgreSQL:"
            echo "PostgreSQL:        localhost:5432"
            echo ""
            echo "📋 Учетные данные (по умолчанию):"
            echo "Username:          admin"
            echo "Password:          password"
            echo "Database:          model_registry_db"
            echo ""
            echo "🛑 Чтобы остановить проброс портов — нажмите Ctrl+C"
            
            # Обработка прерывания для корректного завершения процесса
            trap 'kill $POSTGRES_PID; exit' INT
            wait
            ;;
        "minio")
            # Проверяем доступность кластера
            if ! kubectl cluster-info &> /dev/null; then
                error "Kubernetes кластер недоступен. Убедитесь, что кластер запущен:"
                echo "  $0 start    # Запустить кластер"
                echo "  $0 status   # Показать статус кластера"
                exit 1
            fi
            
            # Проверяем существование namespace
            if ! kubectl get namespace model-registry &> /dev/null; then
                error "Namespace 'model-registry' не найден. Возможно, сервисы не развернуты."
                echo "  $0 services deploy   # Развернуть сервисы"
                exit 1
            fi
            
            # Проверяем существование сервиса minio
            if ! kubectl get svc minio -n model-registry &> /dev/null; then
                error "Сервис 'minio' не найден в namespace 'model-registry'"
                echo "  kubectl get svc -n model-registry   # Показать доступные сервисы"
                exit 1
            fi
            
            log "Проброс портов MinIO UI на localhost:9001 и MinIO API на localhost:9000"
            
            # Запускаем порт-форвардинг
            kubectl port-forward -n model-registry svc/minio 9001:9001 &
            MINIO_CONSOLE_PID=$!
            
            kubectl port-forward -n model-registry svc/minio 9000:9000 &
            MINIO_API_PID=$!
            
            # Проверяем, что процессы запустились успешно
            if ! kill -0 $MINIO_CONSOLE_PID 2>/dev/null || ! kill -0 $MINIO_API_PID 2>/dev/null; then
                error "Не удалось запустить порт-форвардинг для MinIO"
                kill $MINIO_CONSOLE_PID $MINIO_API_PID 2>/dev/null || true
                exit 1
            fi
            
            # Выводим информацию о подключении
            echo ""
            echo "🔗 Подключение к MinIO:"
            echo "MinIO Console:     http://localhost:9001"
            echo "MinIO API:         http://localhost:9000"
            echo ""
            echo "📋 Учетные данные (по умолчанию):"
            echo "Access Key:        AKIAIOSFODNN7EXAMPLE"
            echo "Secret Key:        wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
            echo ""
            echo "🛑 Чтобы остановить проброс портов — нажмите Ctrl+C"
            
            # Обработка прерывания для корректного завершения процесса
            trap 'kill $MINIO_CONSOLE_PID $MINIO_API_PID; exit' INT
            wait
            ;;
        "keycloak")
            # Проверяем доступность кластера
            if ! kubectl cluster-info &> /dev/null; then
                error "Kubernetes кластер недоступен. Убедитесь, что кластер запущен:"
                echo "  $0 start    # Запустить кластер"
                echo "  $0 status   # Показать статус кластера"
                exit 1
            fi
            
            # Проверяем существование namespace
            if ! kubectl get namespace model-registry &> /dev/null; then
                error "Namespace 'model-registry' не найден. Возможно, сервисы не развернуты."
                echo "  $0 services deploy   # Развернуть сервисы"
                exit 1
            fi
            
            # Проверяем существование сервиса keycloak
            if ! kubectl get svc keycloak -n model-registry &> /dev/null; then
                error "Сервис 'keycloak' не найден в namespace 'model-registry'"
                echo "  kubectl get svc -n model-registry   # Показать доступные сервисы"
                exit 1
            fi
            
            log "Проброс порта Keycloak на localhost:8082"
            
            # Запускаем порт-форвардинг
            kubectl port-forward -n model-registry svc/keycloak 8082:8080 &
            KEYCLOAK_PID=$!
            
            # Проверяем, что процесс запустился успешно
            if ! kill -0 $KEYCLOAK_PID 2>/dev/null; then
                error "Не удалось запустить порт-форвардинг для Keycloak"
                exit 1
            fi
            
            # Выводим информацию о подключении
            echo ""
            echo "🔗 Подключение к Keycloak:"
            echo "Keycloak UI:       http://localhost:8082"
            echo ""
            echo "📋 Учетные данные (по умолчанию):"
            echo "Username:          admin"
            echo "Password:          admin"
            echo ""
            echo "🛑 Чтобы остановить проброс портов — нажмите Ctrl+C"
            
            # Обработка прерывания для корректного завершения процесса
            trap 'kill $KEYCLOAK_PID; exit' INT
            wait
            ;;
        "artifact-store")
            # Проверяем доступность кластера
            if ! kubectl cluster-info &> /dev/null; then
                error "Kubernetes кластер недоступен. Убедитесь, что кластер запущен:"
                echo "  $0 start    # Запустить кластер"
                echo "  $0 status   # Показать статус кластera"
                exit 1
            fi
            
            # Проверяем существование namespace
            if ! kubectl get namespace artifact-store &> /dev/null; then
                error "Namespace 'artifact-store' не найден. Возможно, сервисы не развернуты."
                echo "  $0 services deploy   # Развернуть сервисы"
                exit 1
            fi
            
            log "Проброс портов всех сервисов artifact-store namespace"
            log "PostgreSQL: localhost:5432, MinIO Console: localhost:9001, MinIO API: localhost:9000, Artifact Store: localhost:8080"
            
            # Запускаем порт-форвардинг всех сервисов в фоне
            kubectl port-forward -n artifact-store svc/postgres 5432:5432 &
            POSTGRES_PID=$!
            
            kubectl port-forward -n artifact-store svc/minio 9001:9001 &
            MINIO_CONSOLE_PID=$!
            
            kubectl port-forward -n artifact-store svc/minio 9000:9000 &
            MINIO_API_PID=$!
            
            kubectl port-forward -n artifact-store svc/artifact-store 8099:8080 &
            ARTIFACT_STORE_PID=$!
            
            # Извлекаем credentials MinIO из secret
            MINIO_ACCESS_KEY=""
            MINIO_SECRET_KEY=""
            
            # Пытаемся получить credentials из secret
            if kubectl get secret -n artifact-store artifact-store-secrets &> /dev/null; then
                MINIO_ACCESS_KEY=$(kubectl get secret -n artifact-store artifact-store-secrets -o jsonpath='{.data.MINIO_ACCESS_KEY}' | base64 -d 2>/dev/null || echo "")
                MINIO_SECRET_KEY=$(kubectl get secret -n artifact-store artifact-store-secrets -o jsonpath='{.data.MINIO_SECRET_KEY}' | base64 -d 2>/dev/null || echo "")
            fi
            
            # Если не удалось получить credentials, используем значения по умолчанию
            if [ -z "$MINIO_ACCESS_KEY" ]; then
                MINIO_ACCESS_KEY="AKIAIOSFODNN7EXAMPLE"
            fi
            if [ -z "$MINIO_SECRET_KEY" ]; then
                MINIO_SECRET_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
            fi
            
            # Выводим информацию о подключениях
            echo ""
            echo "🔗 Подключения к сервисам artifact-store:"
            echo "PostgreSQL:        localhost:5432"
            echo "MinIO Console:     http://localhost:9001"
            echo "MinIO API:         http://localhost:9000"
            echo "Artifact Store:    http://localhost:8080"
            echo ""
            echo "📋 Учетные данные:"
            echo "PostgreSQL: пользователь=admin, пароль=password, база=artifact_store_db"
            echo "MinIO Endpoint:    http://localhost:9000"
            echo "MinIO Access Key:  $MINIO_ACCESS_KEY"
            echo "MinIO Secret Key:  $MINIO_SECRET_KEY"
            echo ""
            echo "🛑 Чтобы остановить проброс портов — нажмите Ctrl+C"
            
            # Обработка прерывания для корректного завершения всех процессов
            trap 'kill $POSTGRES_PID $MINIO_CONSOLE_PID $MINIO_API_PID $ARTIFACT_STORE_PID; exit' INT
            wait
            ;;
        "redpanda")
            # Проверяем доступность кластера
            if ! kubectl cluster-info &> /dev/null; then
                error "Kubernetes кластер недоступен. Убедитесь, что кластер запущен:"
                echo "  $0 start    # Запустить кластер"
                echo "  $0 status   # Показать статус кластера"
                exit 1
            fi
            
            # Проверяем существование namespace
            if ! kubectl get namespace model-registry &> /dev/null; then
                error "Namespace 'model-registry' не найден. Возможно, сервисы не развернуты."
                echo "  $0 services deploy   # Развернуть сервисы"
                exit 1
            fi
            
            # Проверяем существование сервиса redpanda-external
            if ! kubectl get svc redpanda-external -n model-registry &> /dev/null; then
                error "Сервис 'redpanda-external' не найден в namespace 'model-registry'"
                echo "  kubectl get svc -n model-registry   # Показать доступные сервисы"
                exit 1
            fi
            
            log "Проброс порта Redpanda/Kafka на localhost:9092"
            
            # Запускаем порт-форвардинг
            kubectl port-forward -n model-registry svc/redpanda-external 9092:9092 &
            REDPANDA_PID=$!
            
            # Проверяем, что процесс запустился успешно
            if ! kill -0 $REDPANDA_PID 2>/dev/null; then
                error "Не удалось запустить порт-форвардинг для Redpanda"
                exit 1
            fi
            
            # Выводим информацию о подключении
            echo ""
            echo "🔗 Подключение к Redpanda/Kafka:"
            echo "Kafka Bootstrap:   localhost:9092"
            echo ""
            echo "📋 Использование в Java-приложении:"
            echo "bootstrap.servers=localhost:9092"
            echo ""
            echo "🛑 Чтобы остановить проброс портов — нажмите Ctrl+C"
            
            # Обработка прерывания для корректного завершения процесса
            trap 'kill $REDPANDA_PID; exit' INT
            wait
            ;;
        *)
            error "Неизвестный сервис: $service"
            echo "Доступные сервисы: postgres, minio, keycloak, artifact-store, redpanda"
            exit 1
            ;;
    esac
}

# Открыть shell в контейнере
open_shell() {
    local pod_name="$1"
    local namespace="${2:-model-registry}"
    
    if [ -z "$pod_name" ]; then
        echo "Доступные поды:"
        kubectl get pods -A
        read -p "Введите имя пода: " pod_name
        read -p "Введите namespace [model-registry]: " namespace
        namespace=${namespace:-model-registry}
    fi
    
    log "Подключение к поду $pod_name в namespace $namespace"
    kubectl exec -it -n "$namespace" "$pod_name" -- /bin/bash
}

# Основная функция
main() {
    local command="${1:-help}"
    
    # Проверка скриптов
    check_scripts
    
    case "$command" in
        "deploy")
            log "Развертывание полного кластера..."
            ./scripts/deploy-cluster.sh
            ;;
        "start")
            ./scripts/destroy-cluster.sh start
            ;;
        "stop")
            ./scripts/destroy-cluster.sh stop
            ;;
        "destroy")
            ./scripts/destroy-cluster.sh destroy
            ;;
        "status")
            ./scripts/destroy-cluster.sh status
            ;;
        "services")
            shift
            ./scripts/manage-services.sh "$@"
            ;;
        "port-forward")
            port_forward "$2"
            ;;
        "shell")
            open_shell "$2" "$3"
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        *)
            error "Неизвестная команда: $command"
            show_help
            exit 1
            ;;
    esac
}

# Запуск
main "$@" 