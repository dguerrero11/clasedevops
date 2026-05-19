# Loki + Promtail + Tempo — Observabilidad Completa

Complemento a la Clase 3. Agrega **logs** (Loki + Promtail) y **trazas distribuidas** (Tempo)
al stack de métricas ya existente (Prometheus + Grafana).

---

## Stack completo al terminar

```
Todos los pods del cluster
  │ logs (stdout/stderr)
  ▼
Promtail (DaemonSet 1 pod/nodo)
  │ push
  ▼
Loki :3100 ──────────────────────────────────┐
                                              │
Node Exporter + kube-state-metrics           │  Grafana :30300
  │ scrape cada 15s                          ├─ Prometheus datasource
  ▼                                           ├─ Loki datasource
Prometheus :30090 ─────────────────────────  ├─ Tempo datasource
                                              │    (correlaciones entre las 3)
App instrumentada con OTLP/Jaeger            │
  │ push traces                              │
  ▼                                           │
Tempo :3200 ─────────────────────────────────┘
```

---

## Prerequisito — etiquetar el namespace

Promtail accede a archivos del host (`/var/log`). Kubernetes 1.25+ bloquea
esto sin el label de PodSecurity:

```bash
kubectl label namespace monitoring \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/warn=privileged \
  pod-security.kubernetes.io/audit=privileged \
  --overwrite

# Verificar
kubectl get namespace monitoring --show-labels | grep pod-security
```

---

## Paso 1 — Desplegar Loki

```bash
cd k8s-labs/monitoring

kubectl apply -f loki/loki-configmap.yaml
kubectl apply -f loki/loki-pvc.yaml
kubectl apply -f loki/loki-deployment.yaml
kubectl apply -f loki/loki-service.yaml

# Esperar ~30s
kubectl get pods -n monitoring -l app=loki
# NAME            READY   STATUS    RESTARTS   AGE
# loki-xxxxxx     1/1     Running   0          1m

# Verificar que está listo
kubectl logs -n monitoring deployment/loki --tail=5
```

### ❌ Si hay error de permisos NFS

```bash
# En el servidor NFS
ssh root@192.168.109.210 "chown -R 10001:10001 /srv/nfs/k8s"

# O descomentar el initContainer en loki-deployment.yaml y re-aplicar
kubectl rollout restart deployment/loki -n monitoring
```

---

## Paso 2 — Desplegar Promtail

```bash
kubectl apply -f promtail/promtail-rbac.yaml
kubectl apply -f promtail/promtail-configmap.yaml
kubectl apply -f promtail/promtail-daemonset.yaml

# 1 pod por nodo (4 pods en este cluster)
kubectl get pods -n monitoring -l app=promtail -o wide
# NAME              READY   STATUS    NODE
# promtail-xxxxx    1/1     Running   master01
# promtail-xxxxx    1/1     Running   worker01
# promtail-xxxxx    1/1     Running   worker02
# promtail-xxxxx    1/1     Running   worker03
```

### Verificar que Promtail llega a Loki

```bash
# Ver targets que Promtail está recolectando
kubectl port-forward -n monitoring daemonset/promtail 9080:9080 &
curl -s http://localhost:9080/targets | python3 -m json.tool | head -40
kill %1
```

---

## Paso 3 — Desplegar Tempo

```bash
kubectl apply -f tempo/tempo-configmap.yaml
kubectl apply -f tempo/tempo-pvc.yaml
kubectl apply -f tempo/tempo-deployment.yaml
kubectl apply -f tempo/tempo-service.yaml

# Esperar ~30s
kubectl get pods -n monitoring -l app=tempo

# Verificar ready
kubectl logs -n monitoring deployment/tempo --tail=5
```

---

## Paso 4 — Actualizar Grafana (datasources automáticos)

```bash
# 1. Aplicar el ConfigMap de datasources
kubectl apply -f grafana-datasources-provisioning.yaml

# 2. Agregar el volumen y el volumeMount al Deployment de Grafana
kubectl patch deployment grafana -n monitoring --type=json -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/volumes/-",
    "value": {
      "name": "datasources",
      "configMap": {"name": "grafana-datasources"}
    }
  },
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/volumeMounts/-",
    "value": {
      "name": "datasources",
      "mountPath": "/etc/grafana/provisioning/datasources"
    }
  }
]'

# 3. Reiniciar Grafana
kubectl rollout restart deployment/grafana -n monitoring
kubectl rollout status deployment/grafana -n monitoring

# 4. Verificar
echo "Abrir: http://192.168.109.142:30300 → Connections → Data sources"
echo "Deben aparecer: Prometheus, Loki, Tempo"
```

---

## Paso 5 — Habilitar trazas en Tekton Pipelines

Tekton tiene soporte nativo de OpenTelemetry. Un solo comando lo activa:

```bash
kubectl patch configmap config-tracing -n tekton-pipelines \
  --type merge \
  -p '{
    "data": {
      "backend": "otlp",
      "endpoint": "tempo.monitoring.svc:4317",
      "stackdriver-project-id": ""
    }
  }'

# Reiniciar el controller para que tome la config
kubectl rollout restart deployment/tekton-pipelines-controller -n tekton-pipelines

# Verificar: la próxima vez que corras un PipelineRun, aparecerá en Tempo
```

---

## Verificar stack completo

```bash
kubectl get pods -n monitoring

# Debe mostrar:
# grafana       1/1 Running
# loki          1/1 Running
# node-exporter ×4 Running
# prometheus    1/1 Running
# promtail      ×4 Running   (DaemonSet)
# tempo         1/1 Running
# kube-state-metrics  1/1 Running
```

---

## Explorar logs en Grafana (Loki)

1. Grafana → **Explore** → Datasource: **Loki**
2. Query builder → Label filters:
   - `namespace = demo` → ver logs de la app
   - `namespace = tekton-pipelines` → ver logs de los tasks de CI/CD
   - `namespace = argocd` → ver sync events de ArgoCD
3. Cambiar a modo **Code** y usar LogQL:

```logql
# Logs de error de la app
{namespace="demo"} |= "error"

# Todos los logs de ArgoCD
{namespace="argocd"}

# Logs de un pod específico
{pod="page-demo-f74bc7f8d-m9b7q"}

# Buscar texto en cualquier namespace
{namespace=~"demo|argocd|tekton-pipelines"} |= "error"
```

---

## Explorar trazas en Grafana (Tempo)

1. Grafana → **Explore** → Datasource: **Tempo**
2. Query type: **Search** → buscar por servicio o trace ID
3. Si Tekton está configurado: correr un PipelineRun y luego buscar
   por `Service: tekton-pipelines-controller`

### Enviar una traza de prueba manualmente

```bash
# Probar que Tempo recibe trazas via Zipkin (formato simple)
TEMPO_IP=$(kubectl get svc tempo -n monitoring -o jsonpath='{.spec.clusterIP}')

kubectl run test-trace --rm -it --restart=Never \
  --image=curlimages/curl:latest \
  --namespace=monitoring -- \
  curl -X POST "http://$TEMPO_IP:9411/api/v2/spans" \
  -H "Content-Type: application/json" \
  -d '[{
    "traceId":"aabbccddeeff0011",
    "id":"aabbccddeeff0011",
    "name":"test-bootcamp",
    "timestamp":'"$(date +%s%6N)"',
    "duration":1500000,
    "localEndpoint":{"serviceName":"demo-app"},
    "tags":{"namespace":"demo","pod":"page-demo-test"}
  }]'

# Verificar en Grafana → Explore → Tempo → Search
# Debe aparecer una traza "test-bootcamp"
```

---

## Correlación entre las 3 señales (el poder real)

```
Prometheus detecta: error_rate de demo sube al 5%
        ↓
Grafana: haz clic en el punto del error en la gráfica
        ↓
Loki: ves los logs en ese momento exacto
        ↓
Tempo: haz clic en el traceID del log
        ↓
Traza completa: ves exactamente qué llamada falló y por qué
```

Esto es **observabilidad completa**: métricas → logs → trazas enlazados.

---

## Troubleshooting

### ❌ Loki crashea en arranque

```bash
kubectl logs -n monitoring deployment/loki
# Si ves: "permission denied" → problema de NFS
ssh root@192.168.109.210 "chown -R 10001:10001 /srv/nfs/k8s"
kubectl rollout restart deployment/loki -n monitoring
```

### ❌ Promtail en Pending — PodSecurity

```bash
# Síntoma: 
# pods in Pending: violates PodSecurity "restricted:latest"
kubectl label namespace monitoring \
  pod-security.kubernetes.io/enforce=privileged --overwrite
```

### ❌ Grafana no muestra Loki/Tempo en Data sources

```bash
# Verificar que el ConfigMap está montado
kubectl describe deployment grafana -n monitoring | grep -A5 "Mounts:"
# Debe aparecer datasources → /etc/grafana/provisioning/datasources

# Si no aparece, re-aplicar el patch
kubectl rollout restart deployment/grafana -n monitoring
```

### ❌ No aparecen logs en Loki

```bash
# Verificar que Promtail llega a Loki
kubectl logs -n monitoring daemonset/promtail --tail=20
# Buscar: "Successfully sent batch" → OK
# Si ves "connection refused" → Loki no está listo aún
```

### ❌ Tempo: error de permisos en WAL

```bash
ssh root@192.168.109.210 "chown -R 10001:10001 /srv/nfs/k8s"
kubectl rollout restart deployment/tempo -n monitoring
```

---

## Archivos

| Archivo | Descripción |
|---------|-------------|
| `loki/loki-configmap.yaml` | Config de Loki: filesystem storage, schema v13 |
| `loki/loki-pvc.yaml` | PVC 5Gi en nfs-csi |
| `loki/loki-deployment.yaml` | Loki en modo single-binary |
| `loki/loki-service.yaml` | ClusterIP :3100 |
| `promtail/promtail-rbac.yaml` | SA + ClusterRole para leer pods |
| `promtail/promtail-configmap.yaml` | Config de scraping: todos los namespaces |
| `promtail/promtail-daemonset.yaml` | 1 pod por nodo, monta /var/log |
| `tempo/tempo-configmap.yaml` | Config de Tempo: OTLP, Jaeger, Zipkin |
| `tempo/tempo-pvc.yaml` | PVC 5Gi en nfs-csi |
| `tempo/tempo-deployment.yaml` | Tempo en modo single-binary |
| `tempo/tempo-service.yaml` | ClusterIP con puertos: 3200, 4317, 4318, 14268, 9411 |
| `grafana-datasources-provisioning.yaml` | Datasources automáticos + correlaciones |
