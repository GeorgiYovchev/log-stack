# Log Processing Pipeline Documentation (Loki + Kafka + Fluent Bit)

## 1. Overview

This document describes how to deploy a full log processing pipeline using:

- **Kafka** – message broker used as the ingestion buffer  
- **Fluent Bit** – consumer of Kafka messages and forwarder to Loki  
- **Loki** – log storage backend  
- **Grafana** – visualization UI  

Promtail is **not used** in this setup. Instead, **Fluent Bit consumes directly from Kafka** and pushes logs to Loki.

---

## 2. Architecture
```
Kubernetes → Fluent Bit → Kafka (buffer 3 days) → Fluent Bit → Loki (storage 7 days) → Grafana
```

**Storage Efficiency**: ~12:1 compression ratio (Kafka 1.6GB → Loki 210MB)

---

## 3. Initial Deployment

### Directory Structure
```bash
mkdir -p /opt/log-stack/data/{kafka,loki,grafana}
cd /opt/log-stack

# Set proper permissions
sudo chown -R 1001:1001 /opt/log-stack/data/kafka
sudo chmod -R 777 /opt/log-stack/data/loki
sudo chown -R 472:472 /opt/log-stack/data/grafana
```

### Configuration Files

All configuration files are in this repository:

- [`docker-compose.yml`](./docker-compose.yml) - Main stack definition with Kafka, Loki, Grafana, Fluent Bit
- [`fluent-bit.conf`](./fluent-bit.conf) - Fluent Bit configuration (Kafka input → Loki output)
- [`loki-config.yml`](./loki-config.yml) - Loki storage and retention settings

**Important**: Edit `docker-compose.yml` and replace `YOUR_PUBLIC_IP` with your actual server IP.

### Deploy
```bash
cd /opt/log-stack
docker compose up -d
docker compose ps
```

---

## 4. Verification
```bash
# Check services
docker compose ps

# Check Kafka topics
docker exec kafka kafka-topics.sh --list --bootstrap-server localhost:9092

# Test produce/consume
echo '{"message": "test", "level": "info"}' | \
docker exec -i kafka kafka-console-producer.sh \
  --bootstrap-server localhost:9092 \
  --topic logs

# Verify logs in Grafana: http://YOUR_IP:3000
# Login: admin/admin
# Query: {job="kafka_consumer"}
```

---

## 5. Kubernetes Integration

Add Kafka output to your Kubernetes Fluent Bit (ArgoCD/Helm values):
```yaml
[OUTPUT]
    Name        kafka
    Match       kube.*
    Brokers     YOUR_PUBLIC_IP:19092
    Topics      logs
```

---

## 6. CI/CD and Configuration Management

### Why CI/CD?

- ✅ **Zero Data Loss**: Only changed services restart
- ✅ **Validation**: Configs tested before deployment
- ✅ **Auditability**: All changes tracked in Git
- ✅ **Rollback**: Easy revert if needed

### Repository Structure
```
log-stack/
├── docker-compose.yml
├── fluent-bit.conf
├── loki-config.yml
├── ansible/
│   ├── playbook.yml          # Smart restart logic
│   └── inventory.yml         # Server details
└── .gitlab-ci.yml           # Pipeline definition
```

### Setup

1. **Add SSH key to GitLab**:
   - Settings → CI/CD → Variables
   - Key: `SSH_PRIVATE_KEY`
   - Value: Your SSH private key
   - Flags: ✅ Protect variable

2. **Edit `ansible/inventory.yml`**:
```yaml
   all:
     children:
       log_stack:
         hosts:
           log-server:
             ansible_host: YOUR_IP
             ansible_user: root
```

### Workflow
```bash
# 1. Create feature branch
git checkout -b feature/increase-kafka-retention

# 2. Edit config (e.g., docker-compose.yml)
# Change: KAFKA_CFG_LOG_RETENTION_HOURS=72
# To:     KAFKA_CFG_LOG_RETENTION_HOURS=96

# 3. Push and create MR
git add docker-compose.yml
git commit -m "Increase Kafka retention to 4 days"
git push origin feature/increase-kafka-retention

# 4. Create MR → Pipeline validates configs
# 5. Merge to main → Ansible deploys → Only Kafka restarts
```

### Smart Restart Matrix

| Change | Services Restarted | Data Loss |
|--------|-------------------|-----------|
| Kafka config in docker-compose.yml | ✅ Kafka only | ❌ No |
| Loki config in loki-config.yml | ✅ Loki only | ❌ No |
| Fluent Bit config in fluent-bit.conf | ✅ Fluent Bit only | ❌ No |
| Grafana config in docker-compose.yml | ✅ Grafana only | ❌ No |

**Why No Data Loss?** Volumes persist in `/opt/log-stack/data/` - only containers restart.

---

## 7. Monitoring
```bash
# Data sizes
du -sh /opt/log-stack/data/{kafka,loki,grafana}

# Metrics
curl http://localhost:3100/metrics | grep loki_distributor_lines_received_total

# Consumer lag
docker exec kafka kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe --group fluentbit-consumer
```

---

## 8. Troubleshooting

### Kafka
```bash
docker logs kafka --tail=50
docker exec kafka kafka-topics.sh --list --bootstrap-server localhost:9092
```

### Fluent Bit
```bash
docker logs fluent-bit --tail=50
```

### Loki
```bash
curl http://localhost:3100/ready
docker logs loki --tail=50
```

### Network
```bash
# Test external Kafka connectivity
telnet YOUR_PUBLIC_IP 19092
```

---

## 9. Summary

**Pipeline**: Kubernetes → Kafka → Fluent Bit → Loki → Grafana

**Key Features**:
- Kafka: 3 days retention, port 19092
- Loki: 7 days retention, 12x compression
- Persistent storage in `/opt/log-stack/data/`
- CI/CD with GitLab + Ansible
- Smart restarts (only changed services)