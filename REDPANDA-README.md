# RedPanda Event Streaming Platform

Интеграция RedPanda в ML-платформу для Event Sourcing и потоковой обработки данных.

## 🚀 Быстрый старт

### Доступ к RedPanda

**Внутренний доступ (для микросервисов):**
```bash
KAFKA_BOOTSTRAP_SERVERS=redpanda.model-registry.svc.cluster.local:9092
KAFKA_SCHEMA_REGISTRY_URL=http://redpanda.model-registry.svc.cluster.local:8081
```

**Внешний доступ (для администрирования):**
- RedPanda Console: http://kafka.local
- Kafka Broker: redpanda.model-registry.svc.cluster.local:9092
- Admin API: порт 9644

### Проверка работы RedPanda

```bash
# Проверить статус подов RedPanda
kubectl get pods -n model-registry -l app=redpanda

# Просмотреть логи RedPanda
kubectl logs -n model-registry -l app=redpanda --tail=50

# Проверить доступность Kafka
kubectl exec -n model-registry -it deployment/redpanda-0 -- \
  rpk cluster info --brokers redpanda:9092
```

## 📋 Конфигурация

### Переменные окружения для микросервисов

Добавьте в ваши Java микросервисы:

```properties
# Kafka Configuration
KAFKA_BOOTSTRAP_SERVERS=redpanda.model-registry.svc.cluster.local:9092
KAFKA_SCHEMA_REGISTRY_URL=http://redpanda.model-registry.svc.cluster.local:8081

# Spring Kafka (пример)
spring.kafka.bootstrap-servers=redpanda.model-registry.svc.cluster.local:9092
spring.kafka.properties.schema.registry.url=http://redpanda.model-registry.svc.cluster.local:8081
```

### Spring Boot конфигурация

```java
@Configuration
public class KafkaConfig {

    @Value("${KAFKA_BOOTSTRAP_SERVERS}")
    private String bootstrapServers;

    @Bean
    public Map<String, Object> producerConfigs() {
        Map<String, Object> props = new HashMap<>();
        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class);
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class);
        return props;
    }

    @Bean
    public ProducerFactory<String, String> producerFactory() {
        return new DefaultKafkaProducerFactory<>(producerConfigs());
    }

    @Bean
    public KafkaTemplate<String, String> kafkaTemplate() {
        return new KafkaTemplate<>(producerFactory());
    }
}
```

## 🎯 Использование для Event Sourcing

### Пример событий для ML-платформы

```java
// Событие тренировки модели
public class ModelTrainingEvent {
    private String modelId;
    private String datasetVersion;
    private String algorithm;
    private LocalDateTime startTime;
    private Map<String, Object> hyperparameters;
}

// Событие деплоя модели
public class ModelDeploymentEvent {
    private String modelId;
    private String version;
    private String environment;
    private LocalDateTime deploymentTime;
}

// Событие предсказания
public class PredictionEvent {
    private String modelId;
    private String requestId;
    private LocalDateTime timestamp;
    private Double prediction;
    private Map<String, Object> features;
}
```

### Топики для Event Sourcing

```bash
# Создание топиков для ML событий
kubectl exec -n model-registry -it deployment/redpanda-0 -- \
  rpk topic create \
  model-training-events \
  model-deployment-events \
  prediction-events \
  model-evaluation-events \
  --brokers redpanda:9092

# Просмотр топиков
kubectl exec -n model-registry -it deployment/redpanda-0 -- \
  rpk topic list --brokers redpanda:9092
```

## 🔧 Утилиты и команды

### Port Forwarding

```bash
# Для доступа к RedPanda Console локально
./cluster.sh port-forward redpanda-console

# Для доступа к Kafka broker локально
kubectl port-forward -n model-registry svc/redpanda-external 9092:9092
```

### Мониторинг и диагностика

```bash
# Проверить здоровье кластера
kubectl exec -n model-registry -it deployment/redpanda-0 -- \
  rpk cluster health --brokers redpanda:9092

# Просмотр метрик
kubectl exec -n model-registry -it deployment/redpanda-0 -- \
  rpk cluster metrics --brokers redpanda:9092

# Описание топика
kubectl exec -n model-registry -it deployment/redpanda-0 -- \
  rpk topic describe model-training-events --brokers redpanda:9092
```

### Producing/Consuming сообщений

```bash
# Producing сообщений
kubectl exec -n model-registry -it deployment/redpanda-0 -- \
  rpk topic produce model-training-events --brokers redpanda:9092

# Consuming сообщений
kubectl exec -n model-registry -it deployment/redpanda-0 -- \
  rpk topic consume model-training-events --brokers redpanda:9092
```

## 🛠️ Интеграция с микросервисами

### Обновление шаблонов микросервисов

Шаблоны автоматически включают переменные окружения для RedPanda:

```yaml
env:
- name: KAFKA_BOOTSTRAP_SERVERS
  value: "redpanda.model-registry.svc.cluster.local:9092"
- name: KAFKA_SCHEMA_REGISTRY_URL
  value: "http://redpanda.model-registry.svc.cluster.local:8081"
```

### Пример Spring Boot application.properties

```properties
# Kafka
spring.kafka.bootstrap-servers=${KAFKA_BOOTSTRAP_SERVERS}
spring.kafka.consumer.group-id=ml-platform-group
spring.kafka.consumer.auto-offset-reset=earliest
spring.kafka.properties.schema.registry.url=${KAFKA_SCHEMA_REGISTRY_URL}

# Producer settings
spring.kafka.producer.acks=all
spring.kafka.producer.retries=3
spring.kafka.producer.batch-size=16384
spring.kafka.producer.buffer-memory=33554432
```

## 🔒 Безопасность

### Network Policies (если используются)

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: redpanda-allow-services
  namespace: model-registry
spec:
  podSelector:
    matchLabels:
      app: redpanda
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: services
    ports:
    - protocol: TCP
      port: 9092
    - protocol: TCP
      port: 8081
```

## 📊 Мониторинг

### Prometheus метрики

RedPanda автоматически экспортирует метрики в формате Prometheus:

```yaml
# Пример конфигурации Prometheus
scrape_configs:
  - job_name: 'redpanda'
    static_configs:
      - targets: ['redpanda.model-registry.svc.cluster.local:9644']
```

### Key метрики для мониторинга

- `redpanda_kafka_request_latency_seconds`
- `redpanda_kafka_request_rates`
- `redpanda_storage_log_size_bytes`
- `redpanda_raft_leader_changes`

## 🚀 Production рекомендации

### Ресурсы

```yaml
resources:
  requests:
    memory: "2Gi"
    cpu: "1000m"
  limits:
    memory: "4Gi" 
    cpu: "2000m"
```

### Persistence

```yaml
volumeClaimTemplates:
- metadata:
    name: redpanda-data
  spec:
    accessModes:
    - ReadWriteOnce
    resources:
      requests:
        storage: 10Gi
    storageClassName: local-path
```

### Репликация

Кластер настроен на 3 реплики для отказоустойчивости. Рекомендуется:

- Минимум 3 брокера для production
- replication factor 3 для важных топиков
- Регулярные бэкапы данных

## 🆘 Troubleshooting

### Common issues

**Поды не запускаются:**
```bash
kubectl describe pod -n model-registry -l app=redpanda
kubectl logs -n model-registry -l app=redpanda
```

**Нет доступа к Kafka:**
```bash
# Проверить DNS разрешение
kubectl exec -n services -it deployment/java-service-1 -- \
  nslookup redpanda.model-registry.svc.cluster.local

# Проверить подключение
kubectl exec -n services -it deployment/java-service-1 -- \
  nc -zv redpanda.model-registry.svc.cluster.local 9092
```

**RedPanda Console недоступна:**
```bash
# Проверить ingress
kubectl get ingress -n model-registry

# Проверить сервис
kubectl get svc -n model-registry redpanda-external
```

## 📞 Поддержка

В случае проблем:

1. Проверить логи: `kubectl logs -n model-registry -l app=redpanda`
2. Проверить статус подов: `kubectl get pods -n model-registry -l app=redpanda`
3. Проверить подключение: `nc -zv redpanda.model-registry.svc.cluster.local 9092`
4. Проверить топики: `rpk topic list --brokers redpanda:9092`

Подробная документация: [RedPanda Documentation](https://docs.redpanda.com)