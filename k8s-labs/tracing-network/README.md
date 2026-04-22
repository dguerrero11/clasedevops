# Clase 5 - Distributed Tracing + NetworkPolicy

## Objetivo

Dos temas que completan el stack de observabilidad y seguridad del cluster:

1. **Distributed Tracing** — instrumentar una app con OpenTelemetry y visualizar el recorrido de cada request a través de los servicios usando Jaeger (y opcionalmente Tempo + Grafana).
2. **NetworkPolicy** — pasar de una red completamente plana (cualquier pod habla con cualquier pod) a un modelo zero-trust donde solo se permite el tráfico explícitamente declarado.

---

## Arquitectura — Tracing

```
  App (FastAPI/Express)          Namespace: monitoring
  Deployment "mi-tienda"
  ┌──────────────────────┐       ┌────────────────────┐
  │ OTEL SDK             │──────►│ Jaeger all-in-one  │
  │ BatchSpanProcessor   │ :4317 │ UI: NodePort :30686│
  │ OTLPSpanExporter     │ gRPC  │ OTLP gRPC: :4317   │
  └──────────────────────┘       └────────────────────┘
                                          │  (opcional)
                                 ┌────────▼───────────┐
                                 │ Tempo              │
                                 │ datasource Grafana │
                                 │ :3200              │
                                 └────────────────────┘
```

## Arquitectura — NetworkPolicy

```
ANTES (sin NetworkPolicy — red plana):
  frontend ──► backend ──► mysql    ← ok
  frontend ──────────────► mysql    ← PROBLEMA: frontend no debería hablar con mysql
  attacker ──► backend              ← PROBLEMA: cualquier pod llega a cualquier lado

DESPUÉS (con NetworkPolicy — zero-trust):
  frontend ──► backend ──► mysql    ← ok (reglas explícitas)
  frontend ──────────────► mysql    ← BLOQUEADO
  attacker ──► backend              ← BLOQUEADO (default-deny-all)
  prometheus ──► pods               ← ok (regla de scrape)
  cualquier pod ──► DNS :53         ← ok (regla DNS — crítica)
```

---

## Pre-requisitos

- Monitoring stack de Clase 3 corriendo (`kubectl get pods -n monitoring`)
- App del proyecto con al menos un endpoint HTTP
- Canal CNI instalado (para NetworkPolicy — ver Paso 4)

---

## PARTE 1 — Distributed Tracing

### Paso 1 — Instalar Jaeger

```bash
kubectl apply -f jaeger-deployment.yaml
kubectl apply -f jaeger-service.yaml

kubectl get pods -n monitoring -l app=jaeger
kubectl get svc -n monitoring jaeger
```

UI: `http://<IP-NODO>:30686` — estará vacía hasta que la app envíe trazas.

---

### Paso 2 — Instrumentar la app

**Python / FastAPI:**

```bash
pip install opentelemetry-api opentelemetry-sdk \
  opentelemetry-exporter-otlp-proto-grpc \
  opentelemetry-instrumentation-fastapi
```

Agregar al inicio de `main.py`:

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
import os

provider = TracerProvider()
exporter = OTLPSpanExporter(
    endpoint=os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://jaeger.monitoring.svc:4317"),
    insecure=True
)
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)

app = FastAPI()
FastAPIInstrumentor.instrument_app(app)
```

**Node.js / Express:**

```bash
npm install @opentelemetry/api @opentelemetry/sdk-node \
  @opentelemetry/exporter-trace-otlp-grpc \
  @opentelemetry/instrumentation-express \
  @opentelemetry/instrumentation-http
```

Crear `tracing.js` y cargarlo antes que todo:

```javascript
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
const { ExpressInstrumentation } = require('@opentelemetry/instrumentation-express');
const { HttpInstrumentation } = require('@opentelemetry/instrumentation-http');

const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter({
    url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://jaeger.monitoring.svc:4317',
  }),
  instrumentations: [new HttpInstrumentation(), new ExpressInstrumentation()],
  serviceName: process.env.OTEL_SERVICE_NAME || 'backend-api',
});
sdk.start();
```

---

### Paso 3 — Actualizar el Deployment con variables OTEL

Agregar en `spec.template.spec.containers[].env`:

```yaml
env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://jaeger.monitoring.svc:4317"
  - name: OTEL_SERVICE_NAME
    value: "mi-tienda-backend"
  - name: OTEL_TRACES_EXPORTER
    value: "otlp"
```

```bash
kubectl apply -f k8s/deployment.yaml
kubectl rollout status deployment/mi-tienda
```

---

### Paso 4 — Generar tráfico y ver trazas

```bash
for i in {1..10}; do
  curl -s http://<IP-NODO>:<NODEPORT>/api/productos > /dev/null
done
```

Abrir `http://<IP-NODO>:30686` → Service: `mi-tienda-backend` → Find Traces → clic en una traza para ver el flamegraph.

---

### (Opcional) Agregar Tempo para integración con Grafana

```bash
kubectl apply -f tempo-pvc.yaml
kubectl apply -f tempo-configmap.yaml
kubectl apply -f tempo-deployment.yaml
kubectl apply -f tempo-service.yaml
```

En Grafana: Configuration → Data Sources → Add → Tempo → URL: `http://tempo.monitoring.svc:3200` → Save & Test.

Explorar: Explore → datasource Tempo → TraceQL: `{.service.name="mi-tienda-backend"}` → Run query.

---

## PARTE 2 — NetworkPolicy

> **Requisito:** Canal CNI (Flannel NO enforcea NetworkPolicy).

### Paso 1 — Instalar Canal CNI

```bash
# Verificar CNI actual
kubectl get pods -n kube-system | grep flannel

# Instalar Canal (Flannel overlay + Calico NetworkPolicy)
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/canal.yaml

# Esperar a que los pods de Canal estén Running
kubectl get pods -n kube-system --watch | grep canal
```

---

### Paso 2 — Demo del problema (antes de aplicar policies)

```bash
kubectl run attacker --image=busybox --rm -it -- sh
# Desde dentro:
nc -zv mysql 3306        # → FUNCIONA (problema)
nc -zv backend-svc 8080  # → FUNCIONA (problema)
exit
```

---

### Paso 3 — Aplicar policies en el orden correcto

```bash
# PRIMERO las reglas de allow (para no dejar la app caída)
kubectl apply -f networkpolicy-allow-dns.yaml                    # CRÍTICO
kubectl apply -f networkpolicy-allow-frontend-to-backend.yaml
kubectl apply -f networkpolicy-allow-backend-to-db.yaml
kubectl apply -f networkpolicy-allow-prometheus.yaml

# LUEGO el deny
kubectl apply -f networkpolicy-default-deny.yaml
```

---

### Paso 4 — Verificar

```bash
# La app sigue funcionando
curl http://<IP-NODO>:<NODEPORT>/api/productos

# Frontend NO puede llegar a la DB
kubectl exec deploy/frontend -- nc -zv mysql 3306 -w 3
# → Connection timed out (BLOQUEADO)

# Backend SÍ puede llegar a la DB
kubectl exec deploy/backend -- nc -zv mysql 3306 -w 3
# → open (PERMITIDO)

# Ver todas las policies activas
kubectl get networkpolicy -n default
```

---

## Troubleshooting

### No aparecen trazas en Jaeger

```bash
# Verificar variables de entorno en el pod
kubectl exec deploy/mi-tienda -- env | grep OTEL

# Verificar conectividad al puerto OTLP
kubectl exec deploy/mi-tienda -- \
  wget -qO- http://jaeger.monitoring.svc:4317 2>&1

# Ver logs de la app buscando errores OTLP
kubectl logs deploy/mi-tienda | grep -i "otlp\|trace\|span"

# Verificar que Jaeger está corriendo
kubectl get pods -n monitoring -l app=jaeger
kubectl logs -n monitoring deployment/jaeger --tail=20
```

### NetworkPolicy no bloquea el tráfico

```bash
# Verificar que Canal está activo
kubectl get pods -n kube-system | grep canal

# Los labels del pod deben coincidir con el podSelector de la policy
kubectl get pods --show-labels
kubectl describe networkpolicy default-deny-all -n default
```

### App se cae después de aplicar default-deny

La causa más común es que falta la regla de DNS. Los pods no pueden resolver nombres de servicio.

```bash
# Solución inmediata
kubectl apply -f networkpolicy-allow-dns.yaml
```

### Canal no termina de instalar

```bash
kubectl describe pod -n kube-system -l k8s-app=canal | grep -A 10 Events
curl -I https://docker.io   # verificar conectividad a internet
```

---

## Limpieza

```bash
# Tracing
kubectl delete -f jaeger-deployment.yaml
kubectl delete -f jaeger-service.yaml
kubectl delete -f tempo-pvc.yaml
kubectl delete -f tempo-configmap.yaml
kubectl delete -f tempo-deployment.yaml
kubectl delete -f tempo-service.yaml

# NetworkPolicy (orden inverso: primero quitar el deny)
kubectl delete -f networkpolicy-default-deny.yaml
kubectl delete -f networkpolicy-allow-frontend-to-backend.yaml
kubectl delete -f networkpolicy-allow-backend-to-db.yaml
kubectl delete -f networkpolicy-allow-dns.yaml
kubectl delete -f networkpolicy-allow-prometheus.yaml
```

---

## Archivos

| Archivo | Recurso | Descripción |
|---------|---------|-------------|
| `jaeger-deployment.yaml` | Deployment | Jaeger all-in-one con OTLP gRPC/HTTP habilitado |
| `jaeger-service.yaml` | Service NodePort | UI en :30686, OTLP gRPC en :4317, HTTP en :4318 |
| `tempo-pvc.yaml` | PVC 2Gi (opcional) | Almacenamiento persistente para Tempo |
| `tempo-configmap.yaml` | ConfigMap (opcional) | Configuración de Tempo con backends OTLP y Jaeger |
| `tempo-deployment.yaml` | Deployment (opcional) | Tempo para integración con Grafana |
| `tempo-service.yaml` | Service (opcional) | Expone Tempo en :3200 internamente |
| `networkpolicy-default-deny.yaml` | NetworkPolicy | Bloquea todo el tráfico por defecto — aplicar al final |
| `networkpolicy-allow-frontend-to-backend.yaml` | NetworkPolicy | Ingress al backend solo desde frontend :8080 |
| `networkpolicy-allow-backend-to-db.yaml` | NetworkPolicy | Ingress a MySQL solo desde backend :3306 |
| `networkpolicy-allow-dns.yaml` | NetworkPolicy | Egress UDP/TCP :53 para todos los pods — CRITICO |
| `networkpolicy-allow-prometheus.yaml` | NetworkPolicy | Ingress desde namespace monitoring para scrape |
