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
ARTIFACT_STORE_NAMESPACE="artifact-store"
MODELMESH_NAMESPACE="modelmesh-serving"

# Git repository settings
RESOURCE_MANAGER_REPO="git@github.com:shvyrev/resource-manager.git"
RESOURCE_MANAGER_BRANCH="dev"
RESOURCE_MANAGER_DIR="resource-manager"
RESOURCE_MANAGER_IMAGE="resource-manager:1.0.0"

MODEL_REGISTRY_REPO="git@github.com:shvyrev/ml-platform.git"
MODEL_REGISTRY_BRANCH="AIPLT-49"
MODEL_REGISTRY_DIR="ml-platform"
MODEL_REGISTRY_IMAGE="model-registry:1.0.0"

ARTIFACT_STORE_REPO="git@github.com:shvyrev/artifact-store.git"
ARTIFACT_STORE_BRANCH="AIPLT-49"
ARTIFACT_STORE_DIR="artifact-store"
ARTIFACT_STORE_IMAGE="artifact-store:1.0.0"

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
    for cmd in k3d kubectl docker git mvn jq; do
        if ! command -v "$cmd" &> /dev/null; then
            error "$cmd не найден. Установите его перед продолжением."
        fi
    done
    log "Все зависимости установлены"
}

cleanup() {
    log "Очистка предыдущих ресурсов..."
    rm -rf resource-manager ml-platform artifact-store
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
    if [ -d "$ARTIFACT_STORE_DIR" ]; then
        warn "Удаление клонированного репозитория $ARTIFACT_STORE_DIR"
        rm -rf "$ARTIFACT_STORE_DIR"
    fi
}

create_cluster() {
    log "Создание кластера k3d..."
    k3d cluster create "$CLUSTER_NAME" \
        --servers 2 \
        --agents 2 \
        --port 80:80@loadbalancer \
        --port 9093:9093@loadbalancer \
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

clone_and_build_artifact_store() {
    log "Клонирование репозитория $ARTIFACT_STORE_REPO..."
    git clone --branch "$ARTIFACT_STORE_BRANCH" "$ARTIFACT_STORE_REPO"
    
    log "Переход в директорию $ARTIFACT_STORE_DIR..."
    cd "$ARTIFACT_STORE_DIR"
    
    log "Сборка Docker-образа artifact-store..."
    mvn clean package -DskipTests
    docker build -f src/main/docker/Dockerfile.jvm -t "$ARTIFACT_STORE_IMAGE" .
    
    if [ $? -ne 0 ]; then
        error "Ошибка при сборке Docker-образа."
    fi
    
    log "Образ $ARTIFACT_STORE_IMAGE успешно собран."
    
    log "Импорт образа в кластер k3d..."
    k3d image import "$ARTIFACT_STORE_IMAGE" -c "$CLUSTER_NAME"
    
    log "Возврат в корневую директорию..."
    cd ..
}

deploy_core_manifests() {
    log "Развертывание основных манифестов..."
    kubectl apply -f k8s/00-namespace.yaml
    kubectl apply -f k8s/02-postgres.yaml
    kubectl apply -f k8s/03-minio.yaml
    kubectl apply -f k8s/04-keycloak.yaml
    kubectl apply -f k8s/05-redpanda.yaml
    kubectl apply -f k8s/06-redpanda-console.yaml
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

deploy_artifact_store() {
    log "Развертывание манифестов artifact-store..."
    kubectl apply -f "$ARTIFACT_STORE_DIR/k3s/"
    log "Манифесты artifact-store применены."
}

create_resource_manager_secrets() {
    log "Создание секретов для resource-manager..."

    # Проверяем, существует ли namespace 'resource-manager', и если нет, создаем его
    if ! kubectl get namespace resource-manager &> /dev/null; then
        log "Создание namespace 'resource-manager'..."
        kubectl create namespace resource-manager
    fi

    # Получаем секреты MinIO из model-registry
    log "Получение секретов MinIO из namespace 'model-registry'..."
    # Исправлено: используем правильные имена ключей (MINIO_ACCESS_KEY)
    MODEL_REGISTRY_MINIO_ACCESS_KEY=$(kubectl get secret model-registry-secrets -n "$NAMESPACE" -o jsonpath='{.data.MINIO_ACCESS_KEY}' | base64 --decode)
    MODEL_REGISTRY_MINIO_SECRET_KEY=$(kubectl get secret model-registry-secrets -n "$NAMESPACE" -o jsonpath='{.data.MINIO_SECRET_KEY}' | base64 --decode)

    # Получаем секреты MinIO из artifact-store
    log "Получение секретов MinIO из namespace 'artifact-store'..."
    ARTIFACT_STORE_MINIO_ACCESS_KEY=$(kubectl get secret artifact-store-secrets -n "artifact-store" -o jsonpath='{.data.MINIO_ACCESS_KEY}' | base64 --decode)
    ARTIFACT_STORE_MINIO_SECRET_KEY=$(kubectl get secret artifact-store-secrets -n "artifact-store" -o jsonpath='{.data.MINIO_SECRET_KEY}' | base64 --decode)

    # Создаем новый секрет для resource-manager
    log "Создание секрета 'resource-manager-secrets' в namespace 'resource-manager'..."
    kubectl create secret generic resource-manager-secrets \
        --namespace=resource-manager \
        --from-literal=MODEL_REGISTRY_MINIO_ACCESS_KEY="$MODEL_REGISTRY_MINIO_ACCESS_KEY" \
        --from-literal=MODEL_REGISTRY_MINIO_SECRET_KEY="$MODEL_REGISTRY_MINIO_SECRET_KEY" \
        --from-literal=ARTIFACT_STORE_MINIO_ACCESS_KEY="$ARTIFACT_STORE_MINIO_ACCESS_KEY" \
        --from-literal=ARTIFACT_STORE_MINIO_SECRET_KEY="$ARTIFACT_STORE_MINIO_SECRET_KEY" \
        --dry-run=client -o yaml | kubectl apply -f -
        
    log "Секреты для resource-manager успешно созданы."
}

create_artifact_store_secrets() {
    log "Создание секретов для artifact-store..."

    # Проверяем, существует ли namespace 'artifact-store', и если нет, создаем его
    if ! kubectl get namespace artifact-store &> /dev/null; then
        log "Создание namespace 'artifact-store'..."
        kubectl create namespace artifact-store
    fi

    # Получаем секреты MinIO и Keycloak из model-registry
    log "Получение секретов MinIO и Keycloak из namespace 'model-registry'..."
    MODEL_REGISTRY_MINIO_ACCESS_KEY=$(kubectl get secret model-registry-secrets -n "$NAMESPACE" -o jsonpath='{.data.MINIO_ACCESS_KEY}' | base64 --decode)
    MODEL_REGISTRY_MINIO_SECRET_KEY=$(kubectl get secret model-registry-secrets -n "$NAMESPACE" -o jsonpath='{.data.MINIO_SECRET_KEY}' | base64 --decode)
    KEYCLOAK_CLIENT_SECRET=$(kubectl get secret model-registry-secrets -n "$NAMESPACE" -o jsonpath='{.data.KEYCLOAK_CLIENT_SECRET}' | base64 --decode)

    
    # Генерируем новые пароли для PostgreSQL
    log "Генерация новых секретов для PostgreSQL..."
    POSTGRES_USER="admin"
    POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    POSTGRES_DB="artifact_store_db"

    # Создаем новый секрет для artifact-store
    log "Создание секрета 'artifact-store-secrets' в namespace '$ARTIFACT_STORE_NAMESPACE'..."
    kubectl create secret generic artifact-store-secrets \
        --namespace="$ARTIFACT_STORE_NAMESPACE" \
        --from-literal=POSTGRES_USER="$POSTGRES_USER" \
        --from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
        --from-literal=POSTGRES_DB="$POSTGRES_DB" \
        --from-literal=MINIO_ACCESS_KEY="$MODEL_REGISTRY_MINIO_ACCESS_KEY" \
        --from-literal=MINIO_SECRET_KEY="$MODEL_REGISTRY_MINIO_SECRET_KEY" \
        --from-literal=KEYCLOAK_CLIENT_SECRET="$KEYCLOAK_CLIENT_SECRET" \
        --dry-run=client -o yaml | kubectl apply -f -
        
    log "Секреты для artifact-store успешно созданы."
}

create_secrets() {
    log "Создание secrets..."

    POSTGRES_USER="admin"
    POSTGRES_DB="model_registry_db"
    POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

    MODEL_REGISTRY_MINIO_ACCESS_KEY="admin"
    MODEL_REGISTRY_MINIO_SECRET_KEY=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

    KEYCLOAK_CLIENT_SECRET="LZbXY16jR0BRFazUKO3qTAoqXL3Uoet7"
    kubectl create secret generic model-registry-secrets \
        --namespace="$NAMESPACE" \
        --from-literal=POSTGRES_USER="$POSTGRES_USER" \
        --from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
        --from-literal=POSTGRES_DB="$POSTGRES_DB" \
        --from-literal=MINIO_ACCESS_KEY="$MODEL_REGISTRY_MINIO_ACCESS_KEY" \
        --from-literal=MINIO_SECRET_KEY="$MODEL_REGISTRY_MINIO_SECRET_KEY" \
        --from-literal=KEYCLOAK_CLIENT_SECRET="$KEYCLOAK_CLIENT_SECRET" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    cat > .env <<EOF
# Сгенерированные пароли для кластера $CLUSTER_NAME
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
MODEL_REGISTRY_MINIO_ACCESS_KEY=$MODEL_REGISTRY_MINIO_ACCESS_KEY
MODEL_REGISTRY_MINIO_SECRET_KEY=$MODEL_REGISTRY_MINIO_SECRET_KEY
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
    
    # Проверяем существование директории modelmesh-serving
    if [ -d "modelmesh-serving" ]; then
        cd modelmesh-serving
        if [ -f "./scripts/install.sh" ]; then
            ./scripts/install.sh --namespace "$MODELMESH_NAMESPACE" --quickstart --enable-self-signed-ca
        else
            warn "Скрипт install.sh не найден в modelmesh-serving/scripts/, пропускаем установку ModelMesh"
        fi
        cd ..
    else
        warn "Директория modelmesh-serving не найдена, пропускаем установку ModelMesh"
    fi
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
    
    log "Проверка готовности RedPanda..."
    if ! kubectl wait --for=condition=ready pod -n "$NAMESPACE" -l app=redpanda --timeout=300s; then
        warn "RedPanda не готов после 300 секунд ожидания, но развертывание продолжается"
    else
        log "RedPanda готов к работе"
    fi
    
    # Дополнительная проверка готовности сервисов artifact-store
    log "Проверка готовности artifact-store..."
    wait_for_pods "artifact-store" 300
    log "Все сервисы готовы к работе"
}

# Функция для создания топиков RedPanda
create_redpanda_topics() {
    log "Создание топиков RedPanda..."
    
    # Список топиков для создания
    local topics=(
        "endpoint.events"
        "endpoint.events.cmd"
        "endpoint.events.dlq"
        "file.events"
        "file.events.cmd"
        "file.events.dlq"
        "model.events"
        "model.events.cmd"
        "model.events.dlq"
        "resource.events"
        "resource.events.cmd"
        "resource.events.dlq"
    )
    
    # Ожидаем готовности RedPanda
    log "Ожидание готовности RedPanda для создания топиков..."
    if ! kubectl wait --for=condition=ready pod -n "$NAMESPACE" -l app=redpanda --timeout=120s; then
        warn "RedPanda не готов после 120 секунд ожидания, пропускаем создание топиков"
        return 1
    fi
    
    # Создаем каждый топик
    for topic in "${topics[@]}"; do
        log "Проверка топика: $topic"
        # Проверяем, существует ли топик
        if kubectl exec -n "$NAMESPACE" redpanda-0 -- rpk topic list | grep -q "^$topic$"; then
            log "Топик $topic уже существует, пропускаем создание"
        else
            log "Создание топика: $topic"
            if kubectl exec -n "$NAMESPACE" redpanda-0 -- rpk topic create "$topic"; then
                log "Топик $topic успешно создан"
            else
                warn "Не удалось создать топик $topic"
            fi
        fi
    done
    
    log "Все топики RedPanda созданы"
}

# Функция для пропатчивания Secret'а
patch_modelmesh_serving() {
    log "Начинаем патчить Secret 'storage-config' для modelmesh-serving..."

    # 1. Получаем учетные данные MinIO из Secret'а
    local access_key=$(kubectl get secret model-registry-secrets -n "$NAMESPACE" -o jsonpath="{.data.MINIO_ACCESS_KEY}" | base64 --decode)
    local secret_key=$(kubectl get secret model-registry-secrets -n "$NAMESPACE" -o jsonpath="{.data.MINIO_SECRET_KEY}" | base64 --decode)

    if [ -z "$access_key" ] || [ -z "$secret_key" ]; then
        error "Не удалось получить учетные данные MinIO. Проверьте Secret 'model-registry-secrets'."
        exit 1
    fi

    # 2. Создаем JSON-конфигурацию для ModelMesh
    local minio_config_json=$(jq -n \
        --arg access_key "$access_key" \
        --arg secret_key "$secret_key" \
        '{
            "type": "s3",
            "access_key_id": $access_key,
            "secret_access_key": $secret_key,
            "endpoint_url": "http://minio.model-registry.svc.cluster.local:9000",
            "insecure": "true",
            "region": "us-south",
            "bucket": "model-registry-bucket"
        }')

    # 3. Кодируем JSON в base64
    local new_minio_config=$(echo -n "$minio_config_json" | base64 -w 0)

    # 4. Патчим Secret
    kubectl patch secret storage-config -n modelmesh-serving --type=json -p='[{"op": "replace", "path": "/data/localMinIO", "value":"'"$new_minio_config"'"}]'
    log "Secret 'storage-config' успешно пропатчен."
}

show_cluster_info() {
    log "Информация о кластере:"
    echo ""
    echo "Кластер: $CLUSTER_NAME"
    echo "Loadbalancer: http://localhost:80"
    echo "Kafka Broker (внешний доступ): localhost:9093"
    echo ""
    echo "Доступные сервисы:"
    echo "- PostgreSQL: kubectl port-forward -n $NAMESPACE svc/postgres 5432:5432"
    echo "- MinIO UI: kubectl port-forward -n $NAMESPACE svc/minio 9001:9001"
    echo "- Keycloak: kubectl port-forward -n $NAMESPACE svc/keycloak 8082:8080"
    echo "- RedPanda Console: http://kafka.local"
    echo "  * Kafka Broker (внешний доступ): localhost:9093"
    echo "  * Kafka Broker (внутри кластера): redpanda.model-registry.svc.cluster.local:9092"
    echo "  * Admin API: порт 9644"
    echo "  * Админка Keycloak: http://localhost:8082/admin (admin/admin)"
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
    clone_and_build_artifact_store
    
    deploy_core_manifests
    create_secrets # Создание секрета для model-registry
    create_artifact_store_secrets
    create_resource_manager_secrets # Создание секрета для resource-manager
    
    deploy_resource_manager
    deploy_model_registry
    deploy_artifact_store
    
    install_modelmesh
    patch_modelmesh_serving

    check_services
    create_redpanda_topics
    show_cluster_info
    
    log "Развертывание завершено успешно!"
}

# Run
main "$@"