# Быстрый старт ML Platform

## 🚀 Развертывание за 5 минут

### 1. Развернуть кластер
```bash
./cluster.sh deploy
```

### 2. Настроить микросервисы
```bash
./cluster.sh services init
./cluster.sh services templates
```

### 3. Проверить статус
```bash
./cluster.sh status
```

## 📊 Проверка работы

### Доступ к сервисам
```bash
# Проверка loadbalancer
curl http://localhost:4200

# Проверка ingress для микросервисов
curl http://localhost:4200/api/v1/service1/health
curl http://localhost:4200/api/v1/service2/health
curl http://localhost:4200/api/v1/service3/health
```

### Доступ к базе данных
```bash
# В отдельном терминале
./cluster.sh port-forward postgres

# В другом терминале
psql -h localhost -U admin -d model_registry_db
```

### Доступ к MinIO
```bash
# В отдельном терминале
./cluster.sh port-forward minio

# Открыть в браузере: http://localhost:9001
# Логин: admin, пароль: смотрите в .env
```

### Доступ к Keycloak
```bash
# В отдельном терминале
./cluster.sh port-forward keycloak

# Открыть в браузере: http://localhost:8082
# Админка: http://localhost:8082/admin (admin/admin)
# Realm: model-registry-realm
# Пользователь: alice/alice
```

## 🔧 Развертывание Java сервиса

### 1. Создать Dockerfile
```dockerfile
FROM openjdk:17-jre-slim
WORKDIR /app
COPY target/service.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

### 2. Собрать и развернуть
```bash
# Сборка образа
./cluster.sh services build java-service-1

# Развертывание
kubectl apply -f k8s/templates/java-service-1.yaml

# Проверка
./cluster.sh services status
```

### 3. Настройка hosts
```properties
...

127.0.0.1 keycloak.local
127.0.0.1 registry.local
127.0.0.1 minio.local
127.0.0.1 predict.local
127.0.0.1 example.com
127.0.0.1 nginx.local
127.0.0.1 resource-manager.local
127.0.0.1 model-registry.local
127.0.0.1 artifact-store.local
127.0.0.1 keycloak

...
```
### 4. Настройка Keycloak
1. Keycloak Dashboard - http://keycloak.local
2. Manage Realms - [v] model-registry-realm
3. Realm Settings -> General -> Frontend URL -> http://keycloak:8080/ -> [Save]

## 🛑 Остановка и очистка

```bash
# Остановить кластер
./cluster.sh stop

# Удалить полностью
./cluster.sh destroy
```

## 📋 Полезные команды

```bash
# Логи сервиса
./cluster.sh services logs java-service-1 follow

# Перезапуск сервиса
./cluster.sh services restart java-service-1

# Shell доступ
./cluster.sh shell

# Статус всех компонентов
kubectl get all -A
```

---

**Все готово! 🎉**

Подробная документация: [CLUSTER-README.md](CLUSTER-README.md) 