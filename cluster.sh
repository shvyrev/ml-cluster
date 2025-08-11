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
    echo "  shell                         - Открыть shell в контейнере"
    echo "  help                          - Показать эту справку"
    echo ""
    echo "Примеры:"
    echo "  $0 deploy                     # Развернуть полный кластер"
    echo "  $0 services init              # Инициализировать сервисы"
    echo "  $0 services build java-service-1  # Собрать и загрузить образ"
    echo "  $0 port-forward postgres      # Прокинуть порт PostgreSQL"
    echo "  $0 port-forward keycloak      # Прокинуть порт Keycloak"
    echo "  $0 status                     # Показать статус кластера"
}

# Port forwarding
port_forward() {
    local service="$1"
    
    case "$service" in
        "postgres")
            log "Проброс порта PostgreSQL на localhost:5432"
            kubectl port-forward -n model-registry svc/postgres 5432:5432
            ;;
        "minio")
            log "Проброс порта MinIO UI на localhost:9001"
            kubectl port-forward -n model-registry svc/minio 9001:9001
            kubectl port-forward -n model-registry svc/minio 9000:9000
            ;;
        "keycloak")
            log "Проброс порта Keycloak на localhost:8082"
            kubectl port-forward -n model-registry svc/keycloak 8082:8080
            ;;
        *)
            error "Неизвестный сервис: $service"
            echo "Доступные сервисы: postgres, minio, keycloak"
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