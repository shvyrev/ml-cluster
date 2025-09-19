#!/bin/bash

# Основной скрипт развертывания Keycloak в k3d
set -e

echo "=== РАЗВЕРТЫВАНИЕ KEYCLOAK В K3D ==="

# Создаем кластер (если нужно)
echo "1. Создание кластера k3d..."
if [ ! -f "create-cluster.sh" ]; then
    echo "Ошибка: файл create-cluster.sh не найден"
    exit 1
fi
./create-cluster.sh

# Применяем манифесты
echo -e "\n2. Применение манифестов Kubernetes..."

echo "Создание namespace..."
kubectl apply -f 01-namespace.yaml

echo "Создание secrets..."
kubectl apply -f 02-secrets.yaml

echo "Развертывание PostgreSQL..."
kubectl apply -f 03-postgresql.yaml

echo "Ожидание запуска PostgreSQL (30 секунд)..."
sleep 30

echo "Развертывание Keycloak..."
kubectl apply -f 04-keycloak.yaml

echo "Настройка Ingress..."
kubectl apply -f 05-ingress.yaml

echo -e "\n3. Ожидание запуска сервисов (60 секунд)..."
sleep 60

# Проверяем развертывание
echo -e "\n4. Проверка развертывания..."
./check-deployment.sh

echo -e "\n=== РАЗВЕРТЫВАНИЕ ЗАВЕРШЕНО ==="
echo ""
echo "ДЛЯ ДОСТУПА К KEYCLOAK:"
echo "1. Пробросьте порт: kubectl port-forward -n keycloak-namespace svc/keycloak-service 8082:8080"
echo "2. Откройте в браузере:"
echo "   - Админка: http://localhost:8082/admin (логин: admin, пароль: admin)"
echo "   - Тестовый пользователь: http://localhost:8082 (логин: user, пароль: password)"
echo ""
echo "ДЛЯ ДОСТУПА ЧЕРЕЗ INGRESS:"
echo "Добавьте в /etc/hosts: 127.0.0.1 keycloak.local"
echo "Откройте: http://keycloak.local:8089"