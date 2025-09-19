# Развертывание Keycloak в Kubernetes (k3d)

Это руководство описывает процесс развертывания Keycloak с PostgreSQL в локальном кластере Kubernetes с использованием k3d.

## Предварительные требования

- Установленный [k3d](https://k3d.io/v5.4.6/)
- Установленный [kubectl](https://kubernetes.io/docs/tasks/tools/)
- Установленный [Docker](https://docs.docker.com/get-docker/)

## Структура проекта

```
.
├── 01-namespace.yaml          # Namespace для Keycloak
├── 02-secrets.yaml           # Секреты для PostgreSQL и Keycloak
├── 03-postgresql.yaml        # Развертывание PostgreSQL
├── 04-keycloak.yaml          # Развертывание Keycloak
├── 05-ingress.yaml           # Ingress для доступа к Keycloak
├── create-cluster.sh         # Скрипт создания кластера k3d
├── deploy.sh                 # Основной скрипт развертывания
├── check-deployment.sh       # Скрипт проверки развертывания
└── README.md                 # Это руководство
```

## Быстрый старт

1. **Сделайте скрипты исполняемыми:**
   ```bash
   chmod +x *.sh
   ```

2. **Запустите полное развертывание:**
   ```bash
   ./deploy.sh
   ```

## Пошаговое руководство

### 1. Создание кластера k3d

```bash
./create-cluster.sh
```

Создает кластер `keycloak-cluster` с:
- 1 сервером
- 1 агентом  
- Пробросом порта 8089 на балансировщик нагрузки (внешний порт 8089 -> внутренний 80)

### 2. Применение манифестов

Манифесты применяются в правильном порядке:

```bash
# Создание namespace
kubectl apply -f 01-namespace.yaml

# Создание секретов
kubectl apply -f 02-secrets.yaml

# Развертывание PostgreSQL
kubectl apply -f 03-postgresql.yaml

# Развертывание Keycloak
kubectl apply -f 04-keycloak.yaml

# Настройка Ingress
kubectl apply -f 05-ingress.yaml
```

### 3. Проверка развертывания

```bash
./check-deployment.sh
```

## Доступ к Keycloak

### Через port-forward

```bash
kubectl port-forward -n keycloak-namespace svc/keycloak-service 8082:8080
```

Откройте в браузере:
- **Админка**: http://localhost:8082/admin
  - Логин: `admin`
  - Пароль: `admin`

- **Тестовый пользователь**: http://localhost:8082
  - Логин: `user`
  - Пароль: `password`

### Через Ingress

Добавьте в файл `/etc/hosts`:
```
127.0.0.1 keycloak.local
```

Откройте: http://keycloak.local:8089

## Конфигурация

### Секреты

В файле [`02-secrets.yaml`](02-secrets.yaml:1) содержатся:
- `POSTGRES_USER`: `admin`
- `POSTGRES_PASSWORD`: `pMAqXwWQpBcvU5kbwlOqHQ` (25 символов)
- `POSTGRES_DB`: `keycloak_db`
- `KEYCLOAK_CLIENT_SECRET`: `LZbXY16jR0BRFazUKO3qTAoqXL3Uoet7`

### База данных

PostgreSQL развернут с:
- Образ: `postgres:15`
- Персистентное хранилище: 1Gi
- Автоматическое создание БД `keycloak_db`

### Keycloak

Keycloak развернут с:
- Образ: `quay.io/keycloak/keycloak:26.3.1`
- Автоконфигурация realm `keycloak-realm`
- Готовый клиент `keycloak-app` и пользователь `user`
- Подключение к PostgreSQL
- Настройки proxy и hostname

## Управление кластером

### Остановка кластера

```bash
k3d cluster stop keycloak-cluster
```

### Запуск кластера

```bash
k3d cluster start keycloak-cluster
```

### Удаление кластера

```bash
k3d cluster delete keycloak-cluster
```

## Устранение неполадок

### Проверка логов

```bash
# Логи PostgreSQL
kubectl logs -n keycloak-namespace deployment/postgres-deployment

# Логи Keycloak  
kubectl logs -n keycloak-namespace deployment/keycloak-deployment
```

### Пересоздание развертывания

```bash
# Удаление развертывания
kubectl delete -f 04-keycloak.yaml
kubectl delete -f 03-postgresql.yaml

# Повторное создание
kubectl apply -f 03-postgresql.yaml
kubectl apply -f 04-keycloak.yaml
```

## Безопасность

- Все чувствительные данные хранятся в Kubernetes Secrets
- Пароли генерируются в base64 формате
- Доступ к админке защищен стандартными учетными данными Keycloak

## Примечания

- Кластер использует Traefik как Ingress Controller
- Для продакшн использования рекомендуется настроить TLS/SSL
- Персистентные тома сохраняют данные между перезапусками пода