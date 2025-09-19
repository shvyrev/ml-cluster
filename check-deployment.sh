#!/bin/bash

# Скрипт проверки развертывания Keycloak
set -e

echo "=== ПРОВЕРКА РАЗВЕРТЫВАНИЯ KEYCLOAK ==="

# Проверяем namespace
echo "1. Проверка namespace..."
kubectl get namespace keycloak-namespace

# Проверяем pods
echo -e "\n2. Проверка pods..."
kubectl get pods -n keycloak-namespace

# Проверяем services
echo -e "\n3. Проверка services..."
kubectl get services -n keycloak-namespace

# Проверяем ingress
echo -e "\n4. Проверка ingress..."
kubectl get ingress -n keycloak-namespace

# Проверяем PVC
echo -e "\n5. Проверка PersistentVolumeClaims..."
kubectl get pvc -n keycloak-namespace

# Проверяем logs PostgreSQL
echo -e "\n6. Логи PostgreSQL..."
POSTGRES_POD=$(kubectl get pods -n keycloak-namespace -l app=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$POSTGRES_POD" ]; then
    kubectl logs $POSTGRES_POD -n keycloak-namespace --tail=10
else
    echo "PostgreSQL pod не найден"
fi

# Проверяем logs Keycloak
echo -e "\n7. Логи Keycloak..."
KEYCLOAK_POD=$(kubectl get pods -n keycloak-namespace -l app=keycloak -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$KEYCLOAK_POD" ]; then
    kubectl logs $KEYCLOAK_POD -n keycloak-namespace --tail=10
else
    echo "Keycloak pod не найден"
fi

# Пробрасываем порт Keycloak
echo -e "\n8. Проброс порта Keycloak на localhost:8082..."
echo "Запустите в отдельном терминале:"
echo "kubectl port-forward -n keycloak-namespace svc/keycloak-service 8082:8080"
echo ""
echo "После проброса порта откройте в браузере:"
echo "Админка: http://localhost:8082/admin (admin/admin)"
echo "Тестовый пользователь: http://localhost:8082 (user/password)"

# Проверяем readiness probes
echo -e "\n9. Проверка readiness probes..."
kubectl describe pods -n keycloak-namespace | grep -A5 -B5 "Readiness"

echo -e "\n=== ПРОВЕРКА ЗАВЕРШЕНА ==="