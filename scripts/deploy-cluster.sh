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
REGISTRY_PORT="5050"
NAMESPACE="model-registry"
MODELMESH_NAMESPACE="modelmesh-serving"

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

# Функция проверки готовности подов
wait_for_pods() {
    local namespace=$1
    local timeout=${2:-300}
    
    log "Ожидание готовности подов в namespace: $namespace"
    
    if ! kubectl wait --for=condition=ready pod --all -n $namespace --timeout=${timeout}s; then
        error "Тайм-аут ожидания готовности подов в namespace: $namespace"
        return 1
    fi
    
    log "Все поды в namespace $namespace готовы"
}

# Функция генерации случайных паролей
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Функция кодирования в base64
encode_base64() {
    echo -n "$1" | base64 | tr -d '\n'
}

# Создание secrets
create_secrets() {
    log "Создание secrets..."
    
    # Генерация паролей
    POSTGRES_PASSWORD=$(generate_password)
    MINIO_ACCESS_KEY="admin"
    MINIO_SECRET_KEY=$(generate_password)
    KEYCLOAK_CLIENT_SECRET=$(generate_password)
    
    # Создание секретов
    kubectl create secret generic model-registry-secrets \
        --namespace=$NAMESPACE \
        --from-literal=POSTGRES_USER=admin \
        --from-literal=POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
        --from-literal=POSTGRES_DB=model_registry_db \
        --from-literal=MINIO_ACCESS_KEY=$MINIO_ACCESS_KEY \
        --from-literal=MINIO_SECRET_KEY=$MINIO_SECRET_KEY \
        --from-literal=KEYCLOAK_CLIENT_SECRET=$KEYCLOAK_CLIENT_SECRET \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Сохранение паролей в файл для справки
    cat > .env <<EOF
# Сгенерированные пароли для кластера $CLUSTER_NAME
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
MINIO_ACCESS_KEY=$MINIO_ACCESS_KEY
MINIO_SECRET_KEY=$MINIO_SECRET_KEY
KEYCLOAK_CLIENT_SECRET=$KEYCLOAK_CLIENT_SECRET

# Команды для port-forward:
# kubectl port-forward -n $NAMESPACE svc/postgres 5432:5432
# kubectl port-forward -n $NAMESPACE svc/minio 9001:9001
EOF
    
    log "Пароли сохранены в файл .env"
}

# Проверка зависимостей
check_dependencies() {
    log "Проверка зависимостей..."
    
    for cmd in k3d kubectl docker; do
        if ! command -v $cmd &> /dev/null; then
            error "$cmd не найден. Установите его перед продолжением."
            exit 1
        fi
    done
    
    log "Все зависимости установлены"
}

# Очистка предыдущих ресурсов
cleanup() {
    log "Очистка предыдущих ресурсов..."
    
    # Удаление кластера если существует
    if k3d cluster list | grep -q $CLUSTER_NAME; then
        warn "Удаление существующего кластера $CLUSTER_NAME"
        k3d cluster delete $CLUSTER_NAME
    fi
    
    # Удаление registry если существует
    if k3d registry list | grep -q $REGISTRY_NAME; then
        warn "Удаление существующего registry $REGISTRY_NAME"
        k3d registry delete $REGISTRY_NAME
    fi
}

# Создание registry
create_registry() {
    log "Создание registry..."
    k3d registry create $REGISTRY_NAME --port $REGISTRY_PORT
    log "Registry создан: k3d-$REGISTRY_NAME:$REGISTRY_PORT"
}

# Создание кластера
create_cluster() {
    log "Создание кластера k3d..."
    
    k3d cluster create $CLUSTER_NAME \
        --servers 2 \
        --agents 2 \
        --port 4200:80@loadbalancer \
        --registry-use k3d-$REGISTRY_NAME:$REGISTRY_PORT \
        --registry-config registries.yaml \
        --wait
    
    log "Кластер $CLUSTER_NAME создан"
}

# Развертывание базовых манифестов
deploy_manifests() {
    log "Развертывание манифестов из k8s/..."
    
    # Применение манифестов в правильном порядке
    kubectl apply -f k8s/00-namespace.yaml
    
    # Создание secrets
    create_secrets
    
    # Остальные манифесты
    kubectl apply -f k8s/02-postgres.yaml
    kubectl apply -f k8s/03-minio.yaml
    kubectl apply -f k8s/04-keycloak.yaml
    kubectl apply -f ingress.yaml
    
    log "Базовые манифесты применены"
}

# Установка ModelMesh Serving
install_modelmesh() {
    log "Установка ModelMesh Serving..."
    
    # Применение CRD и основных компонентов
    # kubectl apply -f modelmesh-serving/config/crd/
    # kubectl apply -f modelmesh-serving/config/default/
    
    log "Создание namespace для ModelMesh если не существует"
    kubectl create namespace $MODELMESH_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

    cd modelmesh-serving
    ./scripts/install.sh --namespace modelmesh-serving --quickstart --enable-self-signed-ca
    cd ..
    
    log "ModelMesh Serving установлен"
}

# Проверка готовности сервисов
check_services() {
    log "Проверка готовности сервисов..."
    
    # Ожидание готовности основных сервисов
    wait_for_pods $NAMESPACE 300
    
    # Проверка доступности сервисов
    log "Проверка доступности PostgreSQL..."
    kubectl exec -n $NAMESPACE deployment/postgres -- pg_isready -U admin
    
    log "Проверка доступности MinIO..."
    kubectl exec -n $NAMESPACE deployment/minio -- mc --version > /dev/null
    
    log "Проверка готовности Keycloak..."
    if ! kubectl wait --for=condition=ready pod -n $NAMESPACE -l app=keycloak --timeout=300s; then
        warn "Keycloak не готов после 300 секунд ожидания, но развертывание продолжается"
    else
        log "Keycloak готов к работе"
    fi
    
    log "Все сервисы готовы к работе"
}

# Вывод информации о кластере
show_cluster_info() {
    log "Информация о кластере:"
    echo ""
    echo "Кластер: $CLUSTER_NAME"
    echo "Registry: k3d-$REGISTRY_NAME:$REGISTRY_PORT"
    echo "Loadbalancer: http://localhost:4200"
    echo ""
    echo "Доступные сервисы:"
    echo "- PostgreSQL: kubectl port-forward -n $NAMESPACE svc/postgres 5432:5432"
    echo "- MinIO UI: kubectl port-forward -n $NAMESPACE svc/minio 9001:9001"
    echo "- Keycloak: kubectl port-forward -n $NAMESPACE svc/keycloak 8082:8080"
    echo "  * Админка: http://localhost:8082/admin (admin/admin)"
    echo "  * Realm: model-registry-realm"
    echo "  * Пользователь: alice/alice"
    echo ""
    echo "Для просмотра подов: kubectl get pods -n $NAMESPACE"
    echo "Для просмотра сервисов: kubectl get svc -n $NAMESPACE"
    echo ""
    echo "Пароли сохранены в файле .env"
}

# Основная функция
main() {
    log "Начало развертывания кластера $CLUSTER_NAME"
    
    check_dependencies
    cleanup
    create_registry
    create_cluster
    deploy_manifests
    install_modelmesh
    check_services
    show_cluster_info
    
    log "Развертывание завершено успешно!"
}

# Запуск
main "$@" 