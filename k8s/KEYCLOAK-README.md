# Keycloak для Model Registry

Этот документ описывает установку и настройку Keycloak для аутентификации и авторизации в Model Registry.

## Обзор

Keycloak настроен с:
- **Realm**: `model-registry-realm`
- **Client**: `model-registry-app`
- **Пользователь**: `alice` (пароль: `alice`)
- **Роль**: `admin` в клиенте `model-registry-app`

## Установка

### 1. Развертывание в Kubernetes

```bash
# Применить все конфигурации
kubectl apply -f k8s/

# Или по отдельности
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/01-secrets.yaml
kubectl apply -f k8s/02-postgres.yaml
kubectl apply -f k8s/04-keycloak.yaml
```

### 2. Проверка статуса

```bash
# Проверить статус подов
kubectl get pods -n model-registry

# Проверить логи Keycloak
kubectl logs -n model-registry deployment/keycloak -f

# Проверить сервисы
kubectl get svc -n model-registry
```

## Доступ к Keycloak

### Локальный доступ

```bash
# Проброс портов для доступа к Keycloak
kubectl port-forward -n model-registry svc/keycloak 8082:8080
```

Затем откройте в браузере: http://localhost:8082

### Доступ через Ingress

Если у вас настроен Ingress контроллер (например, Traefik):
- URL: http://keycloak.local
- Добавьте в `/etc/hosts`: `127.0.0.1 keycloak.local`

## Учетные данные

### Администратор Keycloak
- **Пользователь**: `admin`
- **Пароль**: `admin`
- **URL**: http://localhost:8082/admin

### Пользователь приложения
- **Пользователь**: `alice`
- **Пароль**: `alice`
- **Realm**: `model-registry-realm`

## Конфигурация Client

### Основные настройки клиента
- **Client ID**: `model-registry-app`
- **Client Secret**: `LZbXY16jR0BRFazUKO3qTAoqXL3Uoet7`
- **Protocol**: `openid-connect`
- **Access Type**: `confidential`

### Endpoint'ы

```
# Базовый URL
BASE_URL=http://localhost:8082

# Основные endpoints
Authorization Endpoint: ${BASE_URL}/realms/model-registry-realm/protocol/openid-connect/auth
Token Endpoint: ${BASE_URL}/realms/model-registry-realm/protocol/openid-connect/token
Userinfo Endpoint: ${BASE_URL}/realms/model-registry-realm/protocol/openid-connect/userinfo
Logout Endpoint: ${BASE_URL}/realms/model-registry-realm/protocol/openid-connect/logout
```

## Тестирование аутентификации

### Получение токена

```bash
# Получить токен для пользователя alice
curl -X POST \
  http://localhost:8082/realms/model-registry-realm/protocol/openid-connect/token \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'grant_type=password&client_id=model-registry-app&client_secret=LZbXY16jR0BRFazUKO3qTAoqXL3Uoet7&username=alice&password=alice'
```

### Проверка токена

```bash
# Получить информацию о пользователе
curl -X GET \
  http://localhost:8082/realms/model-registry-realm/protocol/openid-connect/userinfo \
  -H 'Authorization: Bearer YOUR_ACCESS_TOKEN'
```

## Интеграция с приложением

### Переменные окружения

```bash
# Для интеграции с вашим приложением
export KEYCLOAK_URL=http://keycloak:8080
export KEYCLOAK_REALM=model-registry-realm
export KEYCLOAK_CLIENT_ID=model-registry-app
export KEYCLOAK_CLIENT_SECRET=LZbXY16jR0BRFazUKO3qTAoqXL3Uoet7
```

### Пример конфигурации для приложения

```yaml
keycloak:
  auth-server-url: http://keycloak:8080
  realm: model-registry-realm
  resource: model-registry-app
  credentials:
    secret: LZbXY16jR0BRFazUKO3qTAoqXL3Uoet7
  ssl-required: external
  public-client: false
  confidential-port: 0
```

## Роли и права доступа

### Роли клиента
- **admin**: Полный доступ к Model Registry
- **user**: Ограниченный доступ только для чтения

### Пользователи
- **alice**: Пользователь с ролью `admin`

## Настройка дополнительных пользователей

1. Зайдите в админку Keycloak: http://localhost:8082/admin
2. Выберите realm `model-registry-realm`
3. Перейдите в раздел "Users"
4. Нажмите "Add user"
5. Заполните данные пользователя
6. Во вкладке "Credentials" установите пароль
7. Во вкладке "Role Mapping" назначьте роли

## Troubleshooting

### Проблемы с подключением к базе данных
```bash
# Проверить доступность PostgreSQL
kubectl exec -it -n model-registry deployment/postgres -- psql -U admin -d keycloak_db -c "\l"
```

### Проблемы с импортом realm
```bash
# Проверить ConfigMap с конфигурацией realm
kubectl get configmap -n model-registry keycloak-realm-config -o yaml
```

### Логи Keycloak
```bash
# Подробные логи
kubectl logs -n model-registry deployment/keycloak --tail=100
```

## Персистентность данных

- Данные Keycloak сохраняются в PostgreSQL
- Конфигурация импортируется при каждом запуске
- Изменения через админку сохраняются в базе данных

## Безопасность

⚠️ **Важно**: В продакшене обязательно измените:
- Пароли администратора
- Client secret
- Настройки SSL/TLS
- Настройки CORS и redirect URIs 