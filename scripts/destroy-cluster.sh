#!/bin/bash

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Конфигурация
CLUSTER_NAME="ml-cluster"
REGISTRY_NAME="image-registry"

# Функция для вывода сообщений
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Функция подтверждения
confirm() {
    local message="$1"
    local default="${2:-n}"
    
    if [[ "$default" == "y" ]]; then
        local prompt="$message [Y/n]: "
    else
        local prompt="$message [y/N]: "
    fi
    
    read -p "$prompt" response
    
    if [[ -z "$response" ]]; then
        response="$default"
    fi
    
    case "$response" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Остановка кластера
stop_cluster() {
    log "Остановка кластера $CLUSTER_NAME..."
    
    if k3d cluster list | grep -q $CLUSTER_NAME; then
        k3d cluster stop $CLUSTER_NAME
        log "Кластер $CLUSTER_NAME остановлен"
    else
        warn "Кластер $CLUSTER_NAME не найден"
    fi
}

# Запуск кластера
start_cluster() {
    log "Запуск кластера $CLUSTER_NAME..."
    
    if k3d cluster list | grep -q $CLUSTER_NAME; then
        k3d cluster start $CLUSTER_NAME
        log "Кластер $CLUSTER_NAME запущен"
        
        # Ожидание готовности кластера
        sleep 10
        kubectl cluster-info
    else
        error "Кластер $CLUSTER_NAME не найден"
        exit 1
    fi
}

# Удаление кластера
destroy_cluster() {
    log "Удаление кластера $CLUSTER_NAME..."
    
    if k3d cluster list | grep -q $CLUSTER_NAME; then
        k3d cluster delete $CLUSTER_NAME
        log "Кластер $CLUSTER_NAME удален"
    else
        warn "Кластер $CLUSTER_NAME не найден"
    fi
}

# Удаление registry
destroy_registry() {
    log "Удаление registry $REGISTRY_NAME..."
    
    if k3d registry list | grep -q $REGISTRY_NAME; then
        k3d registry delete $REGISTRY_NAME
        log "Registry $REGISTRY_NAME удален"
    else
        warn "Registry $REGISTRY_NAME не найден"
    fi
}

# Очистка файлов
cleanup_files() {
    log "Очистка файлов..."
    
    if [[ -f ".env" ]]; then
        rm .env
        log "Файл .env удален"
    fi
    
    # Очистка kubeconfig если нужно
    if confirm "Очистить kubeconfig от записей кластера?"; then
        kubectl config delete-context k3d-$CLUSTER_NAME 2>/dev/null || true
        kubectl config delete-cluster k3d-$CLUSTER_NAME 2>/dev/null || true
        kubectl config delete-user admin@k3d-$CLUSTER_NAME 2>/dev/null || true
        log "Kubeconfig очищен"
    fi
}

# Показать статус кластера
show_status() {
    log "Статус кластера:"
    
    echo ""
    echo "Кластеры k3d:"
    k3d cluster list
    
    echo ""
    echo "Registry k3d:"
    k3d registry list
    
    echo ""
    if k3d cluster list | grep -q $CLUSTER_NAME; then
        echo "Кластер $CLUSTER_NAME: существует"
        
        # Проверка запущен ли кластер через kubectl
        if kubectl get nodes --request-timeout=5s &>/dev/null; then
            echo "Статус: запущен"
            echo ""
            echo "Поды:"
            kubectl get pods --all-namespaces || true
        else
            echo "Статус: остановлен"
        fi
    else
        echo "Кластер $CLUSTER_NAME: не найден"
    fi
}

# Показать помощь
show_help() {
    echo "Использование: $0 [КОМАНДА]"
    echo ""
    echo "Команды:"
    echo "  stop      - Остановить кластер"
    echo "  start     - Запустить кластер"
    echo "  destroy   - Удалить кластер и registry"
    echo "  status    - Показать статус кластера"
    echo "  help      - Показать эту справку"
    echo ""
    echo "Примеры:"
    echo "  $0 stop      # Остановить кластер"
    echo "  $0 start     # Запустить кластер"
    echo "  $0 destroy   # Удалить все (с подтверждением)"
    echo "  $0 status    # Показать статус"
}

# Основная функция
main() {
    local command="${1:-help}"
    
    case "$command" in
        "stop")
            stop_cluster
            ;;
        "start")
            start_cluster
            ;;
        "destroy")
            if confirm "Вы уверены, что хотите удалить кластер $CLUSTER_NAME и все связанные ресурсы?"; then
                destroy_cluster
                destroy_registry
                cleanup_files
                log "Все ресурсы удалены"
            else
                log "Операция отменена"
            fi
            ;;
        "status")
            show_status
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