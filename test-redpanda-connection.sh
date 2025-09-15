#!/bin/bash

set -e

echo "🔍 Тестирование подключения к Redpanda Kafka broker..."

# Проверка доступности порта
echo "Проверка доступности порта 9092..."
if nc -zv localhost 9092 2>/dev/null; then
    echo "✅ Порт 9092 доступен"
else
    echo "❌ Порт 9092 недоступен"
    exit 1
fi

# Проверка наличия kcat (kafkacat)
if command -v kcat &> /dev/null; then
    echo "✅ kcat (kafkacat) установлен"
    
    # Создание тестового топика
    echo "Создание тестового топика..."
    kubectl exec -n model-registry -it redpanda-0 -- \
        rpk topic create test-redpanda-connection --brokers localhost:9092
    
    # Отправка тестового сообщения
    echo "Отправка тестового сообщения..."
    echo "test_message_$(date +%s)" | kcat -P -b localhost:9092 -t test-redpanda-connection
    
    # Чтение тестового сообщения
    echo "Чтение тестового сообщения..."
    kcat -C -b localhost:9092 -t test-redpanda-connection -c 1 -o beginning
    
    echo "✅ Подключение к Redpanda успешно протестировано!"
else
    echo "⚠️  kcat (kafkacat) не установлен, проверка ограничена"
    echo "Порт 9092 доступен, но для полной проверки установите kcat:"
    echo "brew install kcat"
fi

echo ""
echo "🎉 Redpanda доступна по адресу: localhost:9092"
echo "Используйте следующие настройки в ваших приложениях:"
echo "bootstrap.servers=localhost:9092"