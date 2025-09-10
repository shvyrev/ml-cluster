#!/bin/bash

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Конфигурация
CLUSTER_NAME="ml-cluster"
NAMESPACE="model-registry"
SERVICES_NAMESPACE="services"

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

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Создание namespace для сервисов
create_services_namespace() {
    log "Создание namespace для сервисов..."
    
    kubectl create namespace $SERVICES_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    log "Namespace $SERVICES_NAMESPACE создан"
}

# Создание ingress для Java микросервисов
create_microservices_ingress() {
    log "Создание ingress для Java микросервисов..."
    
    cat > k8s/07-microservices-ingress.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: microservices-ingress
  namespace: $SERVICES_NAMESPACE
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
    traefik.ingress.kubernetes.io/router.middlewares: default-cors@kubernetescrd
spec:
  rules:
    - http:
        paths:
          # Первый Java микросервис
          - path: /api/v1/service1
            pathType: Prefix
            backend:
              service:
                name: java-service-1
                port:
                  number: 8080
          
          # Второй Java микросервис
          - path: /api/v1/service2
            pathType: Prefix
            backend:
              service:
                name: java-service-2
                port:
                  number: 8080
          
          # Третий Java микросервис
          - path: /api/v1/service3
            pathType: Prefix
            backend:
              service:
                name: java-service-3
                port:
                  number: 8080
---
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: cors
  namespace: $SERVICES_NAMESPACE
spec:
  headers:
    accessControlAllowMethods:
      - GET
      - POST
      - PUT
      - DELETE
      - OPTIONS
    accessControlAllowOriginList:
      - "*"
    accessControlAllowHeaders:
      - "*"
    accessControlExposeHeaders:
      - "*"
    accessControlAllowCredentials: true
    accessControlMaxAge: 86400
EOF
    
    kubectl apply -f k8s/07-microservices-ingress.yaml
    log "Ingress для микросервисов создан"
}

# Создание шаблонов для Java микросервисов
create_service_templates() {
    log "Создание шаблонов для Java микросервисов..."
    
    for i in {1..3}; do
        cat > k8s/templates/java-service-${i}.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: java-service-${i}
  namespace: $SERVICES_NAMESPACE
  labels:
    app: java-service-${i}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: java-service-${i}
  template:
    metadata:
      labels:
        app: java-service-${i}
    spec:
      containers:
      - name: java-service-${i}
        image: localhost:5050/java-service-${i}:latest
        ports:
        - containerPort: 8080
        env:
        - name: SPRING_PROFILES_ACTIVE
          value: "kubernetes"
        - name: DB_HOST
          value: "postgres.${NAMESPACE}.svc.cluster.local"
        - name: DB_PORT
          value: "5432"
        - name: DB_NAME
          valueFrom:
            secretKeyRef:
              name: model-registry-secrets
              key: POSTGRES_DB
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: model-registry-secrets
              key: POSTGRES_USER
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: model-registry-secrets
              key: POSTGRES_PASSWORD
        - name: MINIO_ENDPOINT
          value: "minio.${NAMESPACE}.svc.cluster.local:9000"
        - name: MINIO_ACCESS_KEY
          valueFrom:
            secretKeyRef:
              name: model-registry-secrets
              key: MINIO_ACCESS_KEY
        - name: MINIO_SECRET_KEY
          valueFrom:
            secretKeyRef:
              name: model-registry-secrets
              key: MINIO_SECRET_KEY
        - name: KAFKA_BOOTSTRAP_SERVERS
          value: "redpanda.model-registry.svc.cluster.local:9092"
        - name: KAFKA_SCHEMA_REGISTRY_URL
          value: "http://redpanda.model-registry.svc.cluster.local:8081"
        livenessProbe:
          httpGet:
            path: /actuator/health
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /actuator/health/readiness
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: java-service-${i}
  namespace: $SERVICES_NAMESPACE
spec:
  selector:
    app: java-service-${i}
  ports:
  - port: 8080
    targetPort: 8080
    protocol: TCP
  type: ClusterIP
EOF
    done
    
    log "Шаблоны микросервисов созданы в k8s/templates/"
}

# Развертывание микросервисов
deploy_microservices() {
    log "Развертывание Java микросервисов..."
    
    create_services_namespace
    create_microservices_ingress
    
    # Применение шаблонов если они существуют
    if [ -d "k8s/templates" ]; then
        for template in k8s/templates/java-service-*.yaml; do
            if [ -f "$template" ]; then
                kubectl apply -f "$template"
                log "Применен шаблон: $template"
            fi
        done
    fi
    
    log "Микросервисы развернуты"
}

# Сборка и загрузка образов в registry
build_and_push_images() {
    local service_name="$1"
    local dockerfile_path="$2"
    
    if [ -z "$service_name" ]; then
        error "Не указано имя сервиса"
        return 1
    fi
    
    if [ -z "$dockerfile_path" ]; then
        dockerfile_path="./Dockerfile"
    fi
    
    log "Сборка образа для $service_name..."
    
    # Сборка образа
    docker build -t localhost:5050/${service_name}:latest -f "$dockerfile_path" .
    
    # Загрузка в registry
    docker push localhost:5050/${service_name}:latest
    
    log "Образ $service_name загружен в registry"
}

# Перезапуск сервиса
restart_service() {
    local service_name="$1"
    
    if [ -z "$service_name" ]; then
        error "Не указано имя сервиса"
        return 1
    fi
    
    log "Перезапуск сервиса $service_name..."
    
    kubectl rollout restart deployment/$service_name -n $SERVICES_NAMESPACE
    kubectl rollout status deployment/$service_name -n $SERVICES_NAMESPACE
    
    log "Сервис $service_name перезапущен"
}

# Показать логи сервиса
show_logs() {
    local service_name="$1"
    local follow="${2:-false}"
    
    if [ -z "$service_name" ]; then
        error "Не указано имя сервиса"
        return 1
    fi
    
    if [ "$follow" = "true" ]; then
        kubectl logs -n $SERVICES_NAMESPACE -l app=$service_name -f
    else
        kubectl logs -n $SERVICES_NAMESPACE -l app=$service_name --tail=100
    fi
}

# Показать статус сервисов
show_services_status() {
    log "Статус микросервисов:"
    
    echo ""
    echo "Поды в namespace $SERVICES_NAMESPACE:"
    kubectl get pods -n $SERVICES_NAMESPACE -o wide
    
    echo ""
    echo "Сервисы в namespace $SERVICES_NAMESPACE:"
    kubectl get svc -n $SERVICES_NAMESPACE
    
    echo ""
    echo "Ingress в namespace $SERVICES_NAMESPACE:"
    kubectl get ingress -n $SERVICES_NAMESPACE
    
    echo ""
    echo "Доступные эндпоинты:"
    echo "- Service 1: http://localhost/api/v1/service1"
    echo "- Service 2: http://localhost/api/v1/service2"
    echo "- Service 3: http://localhost/api/v1/service3"
    echo ""
    echo "RedPanda Kafka:"
    echo "- Bootstrap Servers: redpanda.model-registry.svc.cluster.local:9092"
    echo "- Console UI: http://kafka.local"
    echo "- Schema Registry: http://redpanda.model-registry.svc.cluster.local:8081"
}

# Показать помощь
show_help() {
    echo "Использование: $0 [КОМАНДА] [АРГУМЕНТЫ]"
    echo ""
    echo "Команды:"
    echo "  init                          - Создать namespace и ingress для микросервисов"
    echo "  templates                     - Создать шаблоны для Java микросервисов"
    echo "  deploy                        - Развернуть все микросервисы"
    echo "  build SERVICE_NAME [DOCKERFILE] - Собрать и загрузить образ в registry"
    echo "  restart SERVICE_NAME          - Перезапустить сервис"
    echo "  logs SERVICE_NAME [follow]    - Показать логи сервиса"
    echo "  status                        - Показать статус всех сервисов"
    echo "  help                          - Показать эту справку"
    echo ""
    echo "Примеры:"
    echo "  $0 init                       # Создать namespace и ingress"
    echo "  $0 templates                  # Создать шаблоны"
    echo "  $0 build java-service-1       # Собрать образ java-service-1"
    echo "  $0 restart java-service-1     # Перезапустить сервис"
    echo "  $0 logs java-service-1 follow # Показать логи с подпиской"
    echo "  $0 status                     # Показать статус всех сервисов"
}

# Основная функция
main() {
    local command="${1:-help}"
    
    case "$command" in
        "init")
            create_services_namespace
            create_microservices_ingress
            ;;
        "templates")
            mkdir -p k8s/templates
            create_service_templates
            ;;
        "deploy")
            deploy_microservices
            ;;
        "build")
            build_and_push_images "$2" "$3"
            ;;
        "restart")
            restart_service "$2"
            ;;
        "logs")
            show_logs "$2" "$3"
            ;;
        "status")
            show_services_status
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