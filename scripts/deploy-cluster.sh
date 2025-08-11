#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="ml-cluster"
NAMESPACE="model-registry"
MODELMESH_NAMESPACE="modelmesh-serving"

# Git repository settings
RESOURCE_MANAGER_REPO="git@github.com:shvyrev/resource-manager.git"
RESOURCE_MANAGER_BRANCH="dev"
RESOURCE_MANAGER_DIR="resource-manager"
RESOURCE_MANAGER_IMAGE="resource-manager:1.0.0"

MODEL_REGISTRY_REPO="git@github.com:shvyrev/ml-platform.git"
MODEL_REGISTRY_BRANCH="dev"
MODEL_REGISTRY_DIR="ml-platform"
MODEL_REGISTRY_IMAGE="model-registry:1.0.0"

# --- Functions ---

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

check_dependencies() {
    log "Проверка зависимостей..."
    for cmd in k3d kubectl docker git mvn; do
        if ! command -v "$cmd" &> /dev/null; then
            error "$cmd не найден. Установите его перед продолжением."
        fi
    done
    log "Все зависимости установлены"
}

cleanup() {
    log "Очистка предыдущих ресурсов..."
    if k3d cluster list | grep -q "$CLUSTER_NAME"; then
        warn "Удаление существующего кластера $CLUSTER_NAME"
        k3d cluster delete "$CLUSTER_NAME"
    fi
    if [ -d "$RESOURCE_MANAGER_DIR" ]; then
        warn "Удаление клонированного репозитория $RESOURCE_MANAGER_DIR"
        rm -rf "$RESOURCE_MANAGER_DIR"
    fi
    if [ -d "$MODEL_REGISTRY_DIR" ]; then
        warn "Удаление клонированного репозитория $MODEL_REGISTRY_DIR"
        rm -rf "$MODEL_REGISTRY_DIR"
    fi
}

create_cluster() {
    log "Создание кластера k3d..."
    k3d cluster create "$CLUSTER_NAME" \
        --servers 2 \
        --agents 2 \
        --port 80:80@loadbalancer \
        --wait
    log "Кластер $CLUSTER_NAME создан"
}

clone_and_build_resource_manager() {
    log "Клонирование репозитория $RESOURCE_MANAGER_REPO..."
    git clone --branch "$RESOURCE_MANAGER_BRANCH" "$RESOURCE_MANAGER_REPO"
    
    log "Переход в директорию $RESOURCE_MANAGER_DIR..."
    cd "$RESOURCE_MANAGER_DIR"
    
    log "Сборка Docker-образа resource-manager..."
    mvn clean package -DskipTests
    docker build -f src/main/docker/Dockerfile.jvm -t "$RESOURCE_MANAGER_IMAGE" .
    
    if [ $? -ne 0 ]; then
        error "Ошибка при сборке Docker-образа."
    fi
    
    log "Образ $RESOURCE_MANAGER_IMAGE успешно собран."
    
    log "Импорт образа в кластер k3d..."
    k3d image import "$RESOURCE_MANAGER_IMAGE" -c "$CLUSTER_NAME"
    
    log "Возврат в корневую директорию..."
    cd ..
}

clone_and_build_model_registry() {
    log "Клонирование репозитория $MODEL_REGISTRY_REPO..."
    git clone --branch "$MODEL_REGISTRY_BRANCH" "$MODEL_REGISTRY_REPO"
    
    log "Переход в директорию $MODEL_REGISTRY_DIR..."
    cd "$MODEL_REGISTRY_DIR"
    
    log "Сборка Docker-образа model-registry..."
    mvn clean package -DskipTests
    docker build -f src/main/docker/Dockerfile.jvm -t "$MODEL_REGISTRY_IMAGE" .
    
    if [ $? -ne 0 ]; then
        error "Ошибка при сборке Docker-образа."
    fi
    
    log "Образ $MODEL_REGISTRY_IMAGE успешно собран."
    
    log "Импорт образа в кластер k3d..."
    k3d image import "$MODEL_REGISTRY_IMAGE" -c "$CLUSTER_NAME"
    
    log "Возврат в корневую директорию..."
    cd ..
}

deploy_core_manifests() {
    log "Развертывание основных манифестов..."
    kubectl apply -f k8s/00-namespace.yaml
    kubectl apply -f k8s/02-postgres.yaml
    kubectl apply -f k8s/03-minio.yaml
    kubectl apply -f k8s/04-keycloak.yaml
    kubectl apply -f ingress.yaml
    log "Основные манифесты применены."
}

deploy_resource_manager() {
    log "Развертывание манифестов resource-manager..."
    kubectl apply -f "$RESOURCE_MANAGER_DIR/k3s/"
    log "Манифесты resource-manager применены."
}

deploy_model_registry() {
    log "Развертывание манифестов model-registry..."
    kubectl apply -f "$MODEL_REGISTRY_DIR/k3s/"
    log "Манифесты model-registry применены."
}

create_secrets() {
    log "Создание secrets..."
    POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    MINIO_ACCESS_KEY="admin"
    MINIO_SECRET_KEY=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    KEYCLOAK_CLIENT_SECRET=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    kubectl create secret generic model-registry-secrets \
        --namespace="$NAMESPACE" \
        --from-literal=POSTGRES_USER=admin \
        --from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
        --from-literal=POSTGRES_DB=model_registry_db \
        --from-literal=MINIO_ACCESS_KEY="$MINIO_ACCESS_KEY" \
        --from-literal=MINIO_SECRET_KEY="$MINIO_SECRET_KEY" \
        --from-literal=KEYCLOAK_CLIENT_SECRET="$KEYCLOAK_CLIENT_SECRET" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    cat > .env <<EOF
# Сгенерированные пароли для кластера $CLUSTER_NAME
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
MINIO_ACCESS_KEY=$MINIO_ACCESS_KEY
MINIO_SECRET_KEY=$MINIO_SECRET_KEY
KEYCLOAK_CLIENT_SECRET=$KEYCLOAK_CLIENT_SECRET
EOF
    log "Пароли сохранены в файл .env"
}

wait_for_pods() {
    local namespace=$1
    local timeout=${2:-300}
    
    log "Ожидание готовности подов в namespace: $namespace"
    
    if ! kubectl wait --for=condition=ready pod --all -n "$namespace" --timeout=${timeout}s; then
        error "Тайм-аут ожидания готовности подов в namespace: $namespace"
        return 1
    fi
    
    log "Все поды в namespace $namespace готовы"
}

install_modelmesh() {
    log "Установка ModelMesh Serving..."
    log "Создание namespace для ModelMesh если не существует"
    kubectl create namespace "$MODELMESH_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    cd modelmesh-serving
    ./scripts/install.sh --namespace "$MODELMESH_NAMESPACE" --quickstart --enable-self-signed-ca
    cd ..
    log "ModelMesh Serving установлен"
}

check_services() {
    log "Проверка готовности сервисов..."
    wait_for_pods "$NAMESPACE" 300
    
    log "Проверка доступности PostgreSQL..."
    kubectl exec -n "$NAMESPACE" deployment/postgres -- pg_isready -U admin
    
    log "Проверка доступности MinIO..."
    kubectl exec -n "$NAMESPACE" deployment/minio -- mc --version > /dev/null
    
    log "Проверка готовности Keycloak..."
    if ! kubectl wait --for=condition=ready pod -n "$NAMESPACE" -l app=keycloak --timeout=300s; then
        warn "Keycloak не готов после 300 секунд ожидания, но развертывание продолжается"
    else
        log "Keycloak готов к работе"
    fi
    
    log "Все сервисы готовы к работе"
}

show_cluster_info() {
    log "Информация о кластере:"
    echo ""
    echo "Кластер: $CLUSTER_NAME"
    echo "Loadbalancer: http://localhost:80"
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

# --- Main function ---

main() {
    log "Начало развертывания кластера $CLUSTER_NAME"
    
    check_dependencies
    cleanup
    create_cluster
    
    clone_and_build_resource_manager
    clone_and_build_model_registry
    
    deploy_core_manifests
    create_secrets
    deploy_resource_manager
    deploy_model_registry
    
    install_modelmesh
    check_services
    show_cluster_info
    
    log "Развертывание завершено успешно!"
}

# Run
main "$@"