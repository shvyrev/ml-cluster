# ML Platform Cluster Management

Автоматизированная система развертывания и управления кластером k3d для ML-платформы с поддержкой Java микросервисов.

## 🚀 Быстрый старт

### 1. Развернуть полный кластер
```bash
./cluster.sh deploy
```

### 2. Инициализировать микросервисы
```bash
./cluster.sh services init
./cluster.sh services templates
```

### 3. Проверить статус
```bash
./cluster.sh status
```

## 📋 Предварительные требования

- **k3d** v5.0+
- **kubectl** 
- **docker**
- **openssl** (для генерации паролей)

### Проверка зависимостей
```bash
k3d version
kubectl version --client
docker version
```

## 🏗️ Архитектура кластера

### Компоненты
- **k3d кластер**: `ml-cluster` (2 сервера, 2 агента)
- **Registry**: `k3d-ml-registry:5050`
- **Namespace**: `model-registry` (основные сервисы)
- **Namespace**: `services` (Java микросервисы)

### Сервисы
- **PostgreSQL**: База данных
- **MinIO**: S3-совместимое хранилище
- **Keycloak**: Аутентификация и авторизация
- **ModelMesh Serving**: ML модели
- **3 Java микросервиса**: Через ingress

### Порты
- **4200**: HTTP LoadBalancer (Traefik)
- **5050**: Docker Registry
- **5432**: PostgreSQL (port-forward)
- **8082**: Keycloak (port-forward)
- **9001**: MinIO UI (port-forward)

## 📚 Команды управления

### Основные команды

#### Развертывание кластера
```bash
# Полное развертывание
./cluster.sh deploy

# Запуск остановленного кластера
./cluster.sh start

# Остановка кластера
./cluster.sh stop

# Удаление кластера
./cluster.sh destroy

# Статус кластера
./cluster.sh status
```

#### Управление микросервисами
```bash
# Инициализация namespace и ingress
./cluster.sh services init

# Создание шаблонов
./cluster.sh services templates

# Развертывание всех сервисов
./cluster.sh services deploy

# Сборка и загрузка образа
./cluster.sh services build java-service-1

# Перезапуск сервиса
./cluster.sh services restart java-service-1

# Просмотр логов
./cluster.sh services logs java-service-1
./cluster.sh services logs java-service-1 follow

# Статус сервисов
./cluster.sh services status
```

#### Утилиты
```bash
# Port forwarding
./cluster.sh port-forward postgres  # localhost:5432
./cluster.sh port-forward minio     # localhost:9001
./cluster.sh port-forward keycloak  # localhost:8082

# Shell доступ
./cluster.sh shell                  # Интерактивный выбор пода
./cluster.sh shell postgres-xyz     # Прямое подключение
```

## 🔧 Конфигурация

### Переменные окружения
После развертывания создается файл `.env` с паролями:
```bash
# Автоматически сгенерированные пароли
POSTGRES_PASSWORD=...
MINIO_ACCESS_KEY=admin
MINIO_SECRET_KEY=...
KEYCLOAK_CLIENT_SECRET=...

# Keycloak настройки
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=admin
KEYCLOAK_REALM=model-registry-realm
KEYCLOAK_CLIENT_ID=model-registry-app
```

### Структура файлов
```
.
├── cluster.sh                     # Главный скрипт
├── scripts/
│   ├── deploy-cluster.sh         # Развертывание
│   ├── destroy-cluster.sh        # Управление жизненным циклом
│   └── manage-services.sh        # Управление сервисами
├── k8s/
│   ├── 00-namespace.yaml         # Namespace
│   ├── 01-secrets.yaml           # Секреты (заменяется)
│   ├── 02-postgres.yaml          # PostgreSQL
│   ├── 03-minio.yaml             # MinIO
│   ├── 04-keycloak.yaml          # Keycloak
│   ├── 07-microservices-ingress.yaml  # Ingress для микросервисов
│   └── templates/                # Шаблоны для Java сервисов
├── registries.yaml               # Конфигурация registry
├── ingress.yaml                  # Ingress для ModelMesh
└── .env                          # Переменные окружения
```

## 🚢 Развертывание Java микросервисов

### 1. Создание Dockerfile
```dockerfile
FROM openjdk:17-jre-slim

WORKDIR /app
COPY target/service.jar app.jar

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "app.jar"]
```

### 2. Сборка и развертывание
```bash
# Сборка образа
./cluster.sh services build java-service-1 ./Dockerfile

# Развертывание
kubectl apply -f k8s/templates/java-service-1.yaml
```

### 3. Доступ к сервисам
```bash
# Через ingress
curl http://localhost:4200/api/v1/service1/health
curl http://localhost:4200/api/v1/service2/health
curl http://localhost:4200/api/v1/service3/health
```

## 🔍 Мониторинг и отладка

### Просмотр ресурсов
```bash
# Поды
kubectl get pods -A

# Сервисы
kubectl get svc -A

# Ingress
kubectl get ingress -A

# События
kubectl get events --sort-by='.firstTimestamp'
```

### Логи
```bash
# Все поды в namespace
kubectl logs -n model-registry --all-containers=true

# Конкретный сервис
./cluster.sh services logs java-service-1 follow

# Traefik (LoadBalancer)
kubectl logs -n kube-system -l app.kubernetes.io/name=traefik
```

### Отладка сети
```bash
# Проверка DNS
kubectl exec -it deployment/postgres -n model-registry -- nslookup minio.model-registry.svc.cluster.local

# Проверка подключения
kubectl exec -it deployment/postgres -n model-registry -- nc -zv minio.model-registry.svc.cluster.local 9000
```

## 🛠️ Устранение неполадок

### Проблема: Поды не запускаются
```bash
# Проверка описания пода
kubectl describe pod <pod-name> -n <namespace>

# Проверка образов
kubectl get pods -o jsonpath='{.items[*].spec.containers[*].image}'

# Проверка registry
docker images | grep localhost:5050
```

### Проблема: Сервисы недоступны
```bash
# Проверка ingress
kubectl get ingress -A

# Проверка endpoints
kubectl get endpoints -A

# Проверка сервисов
kubectl get svc -A
```

### Проблема: Ошибки базы данных
```bash
# Подключение к PostgreSQL
./cluster.sh port-forward postgres
psql -h localhost -U admin -d model_registry_db

# Проверка статуса
kubectl exec -n model-registry deployment/postgres -- pg_isready -U admin
```

## 🔄 Обновления

### Обновление конфигурации
```bash
# Применение изменений
kubectl apply -f k8s/

# Перезапуск deployment
kubectl rollout restart deployment/postgres -n model-registry
```

### Обновление образов
```bash
# Сборка нового образа
./cluster.sh services build java-service-1

# Перезапуск сервиса
./cluster.sh services restart java-service-1
```

## 📞 Полезные команды

### Быстрый доступ к базе данных
```bash
# Port forward
./cluster.sh port-forward postgres &

# Подключение
psql -h localhost -U admin -d model_registry_db

# Или через kubectl
kubectl exec -it -n model-registry deployment/postgres -- psql -U admin -d model_registry_db
```

### Быстрый доступ к MinIO
```bash
# Port forward
./cluster.sh port-forward minio &

# Открыть в браузере
open http://localhost:9001
```

### Быстрый доступ к Keycloak
```bash
# Port forward
./cluster.sh port-forward keycloak &

# Открыть в браузере
open http://localhost:8082

# Админка Keycloak
open http://localhost:8082/admin  # admin/admin

# Данные для входа:
# Realm: model-registry-realm
# Client: model-registry-app
# Пользователь: alice/alice
```

### Экспорт/импорт данных
```bash
# Экспорт БД
kubectl exec -n model-registry deployment/postgres -- pg_dump -U admin model_registry_db > backup.sql

# Импорт БД
kubectl exec -i -n model-registry deployment/postgres -- psql -U admin -d model_registry_db < backup.sql
```

## 🆘 Поддержка

В случае проблем:
1. Проверьте статус кластера: `./cluster.sh status`
2. Проверьте логи: `./cluster.sh services logs <service-name>`
3. Проверьте ресурсы: `kubectl get all -A`
4. Перезапустите проблемный сервис: `./cluster.sh services restart <service-name>`

## 📝 Примечания

- Все пароли генерируются автоматически и сохраняются в `.env`
- Registry работает на localhost:5050
- Ingress настроен для работы с Traefik
- Поддерживается hot-reload для Java сервисов
- Все данные сохраняются в PVC кластера 