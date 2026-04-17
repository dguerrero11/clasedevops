# Guía de Laboratorios de IA en Kubernetes

Cómo funciona cada ejercicio, qué recursos crea y por qué.

---

## Arquitectura general del bootcamp

```
┌─────────────────────────────────────────────────────────────┐
│  Windows Host (RTX 4070, CUDA 12.9) — 192.168.109.1        │
│  Docker Desktop → Ollama :11434                             │
│    ├── llama3.2:3b  (2 GB)   → rápido, demos               │
│    ├── mistral      (4.4 GB) → equilibrado                  │
│    └── llama3.1:8b  (4.9 GB) → razonamiento complejo       │
└──────────────────────┬──────────────────────────────────────┘
                       │ HTTP REST
         ┌─────────────┴────────────────────────────┐
         │  Kubernetes Cluster — namespace: bootcamp  │
         │                                            │
         │  :30095  Lab 15 — Chat API (Flask)         │
         │  :30096  Lab 16 — Open WebUI               │
         │  :30097  Lab 17 — RAG API + ChromaDB       │
         │  Jobs    Lab 18 — Batch / Parallel / Cron  │
         │  :30090  Lab 19 — Prometheus               │
         │  :30300  Lab 19 — Grafana                  │
         └────────────────────────────────────────────┘
```

Ollama corre en la máquina Windows con acceso directo a la GPU. Los Pods de Kubernetes lo contactan a través de la red del host (`192.168.109.1:11434`). La URL se almacena en un **ConfigMap** para no hardcodearla en el código.

---

## Lab 15 — Tu primera app de IA en Kubernetes

### ¿Qué se despliega?

| Recurso | Nombre | Para qué sirve |
|---------|--------|----------------|
| ConfigMap | `ollama-config` | URL de Ollama + nombre del modelo por defecto |
| Pod | `ollama-test` | Verifica que el cluster puede hablar con Ollama |
| Deployment | `chat-api` | API Flask con 2 réplicas que recibe preguntas |
| Service | NodePort :30095 | Expone la API al exterior |

### Cómo funciona internamente

**1. El ConfigMap guarda la configuración:**
```yaml
OLLAMA_BASE_URL: "http://192.168.109.1:11434"
MODEL_NAME: "llama3.2:3b"
```
Los Pods leen estas variables de entorno en lugar de tener la IP hardcodeada. Si Ollama se mueve a otra máquina, solo se actualiza el ConfigMap.

**2. El Pod de prueba verifica conectividad:**
Hace un `curl` a `/api/tags` de Ollama y muestra los modelos disponibles en los logs. Si falla aquí, el problema es de red (firewall, IP incorrecta).

**3. El Deployment Chat API:**
- Corre `python:3.11-slim`, instala Flask y requests al arrancar
- Expone 3 endpoints: `/health`, `/models`, `/chat`
- El endpoint `/chat` toma un `{"prompt": "..."}` y lo reenvía a Ollama
- Con 2 réplicas, Kubernetes distribuye el tráfico entre los 2 Pods

**4. Demo de Prompt Engineering con init containers:**
Un Pod multi-contenedor con 3 init containers que se ejecutan en secuencia:
- `zero-shot`: pregunta directa sin contexto adicional
- `few-shot`: incluye ejemplos antes de la pregunta
- `chain-of-thought`: pide razonamiento paso a paso ("piensa antes de responder")

Cada técnica produce respuestas de diferente calidad con el mismo modelo.

### Comandos del lab

```bash
kubectl apply -f 01-configmap-ollama.yaml
kubectl apply -f 02-pod-test-ollama.yaml
kubectl logs ollama-test -n bootcamp

kubectl apply -f 03-deployment-chat-api.yaml
kubectl get pods -n bootcamp -w

# Probar la API
curl http://192.168.109.143:30095/chat \
  -H "Content-Type: application/json" \
  -d '{"prompt": "Que es un Pod en Kubernetes?"}'

# Ver las 3 técnicas de prompt
kubectl apply -f 04-ejercicio-prompt-engineering.yaml
kubectl logs prompt-engineering-demo -n bootcamp -c zero-shot
kubectl logs prompt-engineering-demo -n bootcamp -c few-shot
kubectl logs prompt-engineering-demo -n bootcamp -c chain-of-thought
```

---

## Lab 16 — Open WebUI: tu propio ChatGPT

### ¿Qué se despliega?

| Recurso | Nombre | Para qué sirve |
|---------|--------|----------------|
| Deployment | `open-webui` | Interfaz web visual para chatear con los modelos |
| Service | NodePort :30096 | Acceso desde el browser |

### Cómo funciona internamente

Open WebUI es una aplicación React + Python (`ghcr.io/open-webui/open-webui`) que se conecta directamente a Ollama a través de la variable de entorno `OLLAMA_BASE_URL`. No necesita intermediarios: el browser habla con Open WebUI, que habla con Ollama.

```
Browser → Open WebUI (Pod K8s :30096) → Ollama (Windows :11434)
```

**Variables de entorno clave:**
- `OLLAMA_BASE_URL`: dónde está Ollama
- `DEFAULT_MODELS`: modelo que carga por defecto al abrir el chat
- `WEBUI_SECRET_KEY`: clave para firmar las sesiones de usuario

**Health checks:**
El Deployment tiene `livenessProbe` y `readinessProbe` apuntando a `/health`. Kubernetes espera 60 segundos antes de empezar a verificar (la app tarda en arrancar) y reinicia el Pod si falla 5 veces seguidas.

**Almacenamiento:**
Usa `emptyDir` para `/app/backend/data`. Esto significa que las conversaciones y configuraciones se pierden cuando el Pod se reinicia. Para persistir datos habría que usar un PVC (ejercicio de extensión).

### Acceso y modelos disponibles

```
http://192.168.109.143:30096
```

| Modelo | Tamaño | Velocidad | Uso recomendado |
|--------|--------|-----------|-----------------|
| llama3.2:3b | 2 GB | Rápido | Demos, preguntas simples |
| mistral | 4.4 GB | Medio | Resúmenes, redacción |
| llama3.1:8b | 4.9 GB | Lento | Razonamiento complejo |

```bash
kubectl apply -f deployment.yaml
kubectl get pods -n bootcamp -l app=open-webui -w
# Esperar ~2 minutos hasta que el probe pase a Ready
```

---

## Lab 17 — RAG: el LLM que sabe de tus documentos

### ¿Qué es RAG?

**RAG** (Retrieval-Augmented Generation) es una técnica que resuelve un problema fundamental de los LLMs: no saben nada de tus datos privados o recientes.

En lugar de reentrenar el modelo (costoso), RAG:
1. Indexa tus documentos como vectores matemáticos (embeddings)
2. Ante cada pregunta, busca los fragmentos más relevantes
3. Los incluye en el prompt como contexto
4. El LLM responde basándose en ese contexto

### ¿Qué se despliega?

| Recurso | Nombre | Para qué sirve |
|---------|--------|----------------|
| StatefulSet | `chromadb` | Base de datos vectorial que guarda los embeddings |
| PVC (NFS) | `chromadb-pvc` | Persistencia de los embeddings entre reinicios |
| ConfigMap | `bootcamp-docs` | Los 13 documentos de Kubernetes a indexar |
| Job | `indexer` | Convierte los documentos a embeddings y los guarda en ChromaDB |
| Deployment | `rag-api` | API Flask que recibe preguntas y ejecuta el flujo RAG |
| Service | NodePort :30097 | Expone la RAG API al exterior |

### Cómo funciona el flujo completo

```
Pregunta del usuario
      ↓
RAG API: convertir la pregunta a embedding (via Ollama /api/embeddings)
      ↓
RAG API: buscar los 3 documentos más similares en ChromaDB (búsqueda coseno)
      ↓
RAG API: construir prompt = contexto de documentos + pregunta original
      ↓
RAG API: enviar prompt a Ollama /api/generate
      ↓
Respuesta basada SOLO en los documentos indexados
```

**¿Por qué ChromaDB?**
ChromaDB almacena documentos como vectores numéricos de alta dimensión (embeddings). Cuando llega una pregunta, también se convierte a vector y se calcula la distancia coseno con todos los documentos. Los más cercanos son los más relevantes semánticamente.

**El Job indexer:**
Se ejecuta una sola vez. Lee los 13 documentos del ConfigMap, llama a `POST /api/embeddings` de Ollama para convertir cada uno a vector, y los guarda en ChromaDB via REST API.

**La RAG API (Flask):**
```python
# Pseudocódigo del endpoint /query
embedding = ollama.embeddings(question)           # vectorizar la pregunta
chunks = chromadb.query(embedding, n_results=3)   # buscar los 3 más relevantes
prompt = f"Contexto:\n{chunks}\n\nPregunta: {question}"
response = ollama.generate(model, prompt)          # responder con contexto
```

### PVC con NFS (conexión con labs de storage)

ChromaDB usa un PVC aprovisionado con `nfs-csi`. Los embeddings persisten en el servidor NFS. Si el Pod de ChromaDB se reinicia, los datos no se pierden. Esto conecta los conceptos de Lab 10/11 (PV, PVC, StorageClass) con un caso de uso real de IA.

### Comandos del lab

```bash
kubectl apply -f 01-chromadb.yaml
kubectl apply -f 02-documentos-configmap.yaml
kubectl apply -f 03-indexer-job.yaml
kubectl logs -n bootcamp -l job-name=indexer -f   # ver indexación

kubectl apply -f 04-rag-api.yaml
kubectl get pods -n bootcamp -w

# Consultar el RAG
curl http://192.168.109.143:30097/health
curl http://192.168.109.143:30097/query \
  -H "Content-Type: application/json" \
  -d '{"question": "Cuando usar StatefulSet en lugar de Deployment?"}'

# Ver cuántos documentos hay indexados
curl http://192.168.109.143:30097/stats
```

---

## Lab 18 — Jobs de IA: procesamiento en lote

### Jobs vs Deployments

| Característica | Deployment | Job |
|---------------|-----------|-----|
| Duración | Continuo | Finito (corre y termina) |
| Reinicio | Siempre | Solo en fallo |
| Caso de uso IA | API de inferencia | Procesar datasets, reportes |
| Coste | Siempre activo | Solo cuando corre |

---

### Lab 18.1 — Batch Summarizer

**¿Qué hace?**
Un Job que procesa 8 errores reales de Kubernetes, le pide al LLM que clasifique cada uno y proponga una solución, y guarda el informe en el NFS.

**¿Cómo funciona?**

```
ConfigMap: lista de 8 errores JSON
      ↓
Job (1 Pod): lee la lista, itera sobre cada error
      ↓
Para cada error: POST /api/generate → "clasifica este error y propone solución"
      ↓
Guarda resultado en /results/report.txt (PVC NFS)
      ↓
Job termina con status: Completed
```

El script Python itera secuencialmente. El Pod termina cuando acaba con el último error. Kubernetes marca el Job como `Complete`.

```bash
kubectl apply -f 01-batch-summarizer.yaml
kubectl logs -n bootcamp -l job-name=batch-summarizer -f
kubectl get jobs -n bootcamp

# Ver resultados en NFS
kubectl run reader --rm -it --image=busybox -n bootcamp --restart=Never \
  --overrides='{"spec":{"volumes":[{"name":"r","persistentVolumeClaim":{"claimName":"batch-results-pvc"}}],"containers":[{"name":"reader","image":"busybox","command":["cat"],"args":["/results/report.txt"],"volumeMounts":[{"name":"r","mountPath":"/results"}]}]}}' \
  -- cat /results/report.txt
```

**Resultado esperado:**
```
[1/8] CATEGORIA: Pod    | SOLUCION: Verificar que la imagen existe en el registry
[2/8] CATEGORIA: Node   | SOLUCION: Revisar estado del kubelet en el nodo
...
[8/8] CATEGORIA: Auth   | SOLUCION: kubectl create secret ...
```

---

### Lab 18.2 — Parallel Classifier

**¿Qué hace?**
Un Job con `parallelism=3` que lanza 3 Pods **simultáneamente**. Cada Pod procesa una categoría distinta (infra, network, storage) usando su índice único.

**¿Cómo funciona el Job Indexado?**

```yaml
spec:
  completions: 3
  parallelism: 3
  completionMode: Indexed   # cada Pod recibe JOB_COMPLETION_INDEX = 0, 1 o 2
```

```python
# En el script Python de cada Pod:
index = int(os.environ.get("JOB_COMPLETION_INDEX", "0"))
categorias = ["infra", "network", "storage"]
mi_categoria = categorias[index]   # Pod 0 → infra, Pod 1 → network, Pod 2 → storage
```

Los 3 Pods trabajan al mismo tiempo. El tiempo total es el del Pod más lento (no la suma de los tres). Cada uno escribe en `/results/categoria-{index}.txt`.

**Comparación:**
| Sin paralelismo | Con parallelism=3 |
|-----------------|-------------------|
| 1 Pod, 9 textos en secuencia | 3 Pods, 3 textos cada uno |
| Tiempo: T×3 | Tiempo: T×1 |

```bash
kubectl apply -f 02-parallel-classifier.yaml
kubectl logs -n bootcamp -l job-name=parallel-classifier --prefix=true
kubectl get pods -n bootcamp -l job-name=parallel-classifier
```

---

### Lab 18.3 — CronJob Nocturno

**¿Qué hace?**
Un CronJob programado a las 2:00 AM que lee logs simulados del cluster, los analiza con `llama3.1:8b` y genera un informe de incidentes con severidad y recomendaciones.

**¿Cómo funciona?**

```yaml
spec:
  schedule: "0 2 * * *"            # cada día a las 2:00 AM
  concurrencyPolicy: Forbid         # no lanzar nuevo job si el anterior sigue corriendo
  successfulJobsHistoryLimit: 7     # conservar historial de 7 días
  failedJobsHistoryLimit: 3         # conservar últimos 3 fallos
```

Kubernetes no ejecuta el CronJob directamente: crea un **Job** en el momento programado, que a su vez crea un **Pod**. Se puede inspeccionar con `kubectl get jobs`.

**Trigger manual para la demo (sin esperar las 2 AM):**
```bash
kubectl apply -f 03-cronjob-log-analyzer.yaml
kubectl get cronjobs -n bootcamp

# Lanzar inmediatamente
kubectl create job --from=cronjob/log-analyzer log-analyzer-manual -n bootcamp
kubectl logs -n bootcamp -l job-name=log-analyzer-manual -f
```

**Resultado esperado:**
```
PROBLEMA 1: Evicción de pods por presión de almacenamiento
  SEVERIDAD: ADVERTENCIA
  ACCION: Ampliar disco o reducir uso de storage ephemeral

PROBLEMA 2: OOMKilled en contenedor ml-trainer
  SEVERIDAD: CRITICO
  ACCION: Aumentar memory limit o optimizar el modelo
```

---

## Lab 19 — Observabilidad: Prometheus + Grafana para IA

### ¿Qué se despliega?

| Recurso | Nombre | Puerto | Para qué sirve |
|---------|--------|--------|----------------|
| Deployment | `ollama-exporter` | ClusterIP :8000 | Traduce la API de Ollama a métricas Prometheus |
| Deployment | `prometheus` | NodePort :30090 | Recolecta y almacena métricas (series de tiempo) |
| Deployment | `grafana` | NodePort :30300 | Visualiza métricas con dashboards |
| PVC (NFS) | `prometheus-pvc` | — | Persistencia de las métricas de Prometheus |

### ¿Por qué un exporter?

Prometheus usa el modelo **pull**: él va a buscar las métricas a los targets, no al revés. Los targets deben exponer un endpoint `/metrics` en formato texto (`# HELP`, `# TYPE`, `metrica valor`).

Ollama no tiene endpoint `/metrics` nativo. El **ollama-exporter** resuelve esto:

```
Prometheus (cada 15s)
    → GET ollama-exporter:8000/metrics
        → ollama-exporter llama a Ollama cada 30s:
            GET 192.168.109.1:11434/api/tags  (modelos disponibles)
            GET 192.168.109.1:11434/api/ps    (modelos en GPU)
        → convierte JSON a formato Prometheus
    ← devuelve métricas en texto plano
```

### Flujo de datos completo

```
Ollama (Windows)
    ↑ consulta REST cada 30s
ollama-exporter (Pod K8s :8000)
    ↑ scrape /metrics cada 15s
Prometheus (Pod K8s :9090)
    ↑ query PromQL
Grafana (Pod K8s :3000)
    ↑ abre el browser
Instructor / Alumno
```

### Métricas disponibles

| Métrica | Tipo | Descripción |
|---------|------|-------------|
| `ollama_models_available` | Gauge | Modelos descargados en disco |
| `ollama_models_loaded` | Gauge | Modelos actualmente en VRAM |
| `ollama_model_size_bytes{model="..."}` | Gauge | Tamaño de cada modelo en bytes |
| `ollama_gpu_memory_used_mb` | Gauge | VRAM estimada en uso |
| `ollama_scrape_errors_total` | Counter | Errores al contactar Ollama |
| `up{job="..."}` | Gauge | 1 si el target está accesible, 0 si no |

### Queries PromQL para la demo

```promql
# Modelos disponibles
ollama_models_available

# Tamaño en GB por modelo
ollama_model_size_bytes / 1024 / 1024 / 1024

# Modelos cargados en GPU ahora mismo
ollama_models_loaded

# Estado de todos los targets
up

# VRAM estimada en uso (MB)
ollama_gpu_memory_used_mb
```

### Accesos

```
Prometheus: http://192.168.109.143:30090
Grafana:    http://192.168.109.143:30300  (admin / bootcamp2026)
```

### Comandos del lab

```bash
kubectl apply -f 03-ollama-exporter.yaml
kubectl get pod -n bootcamp -l app=ollama-exporter -w

kubectl apply -f 01-prometheus.yaml
kubectl get pvc prometheus-pvc -n bootcamp

kubectl apply -f 02-grafana.yaml
kubectl get all -n bootcamp -l module=19-observabilidad

# Verificar métricas del exporter directamente
kubectl port-forward -n bootcamp svc/ollama-exporter 8000:8000
curl http://localhost:8000/metrics | grep ollama_
```

---

## Resumen: qué concepto K8s demuestra cada lab

| Lab | Recurso K8s nuevo | Concepto de IA |
|-----|-------------------|----------------|
| 15 | ConfigMap, Deployment, NodePort | LLM, Prompt Engineering (zero-shot, few-shot, CoT) |
| 16 | Deployment + emptyDir | Interfaz de chat, múltiples modelos |
| 17 | Job, PVC NFS, StatefulSet | RAG, embeddings, búsqueda vectorial |
| 18.1 | Job (serial) | Batch inference, análisis de errores |
| 18.2 | Job Indexado (parallelism=3) | Workers de IA en paralelo |
| 18.3 | CronJob | Automatización nocturna con LLM |
| 19 | Exporter pattern, PVC Prometheus | Observabilidad de workloads de IA |

---

## Nota sobre producción

Lo que construimos en estos labs es didáctico. En entornos reales:

- **Modelos**: se sirven con frameworks como vLLM, TGI o Triton (no Ollama)
- **Observabilidad**: `kube-prometheus-stack` (Helm) instala Prometheus + Grafana + Alertmanager + node-exporter en un comando
- **RAG**: se usan bases de datos vectoriales gestionadas (Pinecone, Weaviate Cloud) o PostgreSQL con pgvector
- **Batch**: se usan frameworks como Ray, Spark o Argo Workflows para datasets de millones de registros
- **Seguridad**: los modelos no son accesibles directamente, hay un API gateway con autenticación

La arquitectura del bootcamp expone las mismas piezas pero simplificadas, para que se entienda qué hace cada componente por separado.
