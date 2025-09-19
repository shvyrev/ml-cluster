#!/bin/bash

# Скрипт создания кластера k3d для Keycloak
set -e

echo "Создание кластера k3d: keycloak-cluster..."

# Создаем кластер k3d с одним сервером и одним агентом
k3d cluster create keycloak-cluster \
  --servers 1 \
  --agents 1 \
  --port "8089:80@loadbalancer" \
  --wait

echo "Кластер успешно создан!"

# Проверяем статус кластера
echo "Проверка статуса кластера..."
kubectl cluster-info
kubectl get nodes

echo "Готово! Кластер k3d 'keycloak-cluster' создан и настроен."