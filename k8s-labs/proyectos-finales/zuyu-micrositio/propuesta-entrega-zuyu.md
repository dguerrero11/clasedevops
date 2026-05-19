# Propuesta de Entrega — Proyecto Final
## Micrositio de Pedidos y Delivery para Negocios ZUYU

| Campo | Detalle |
|-------|---------|
| **Alumno** | _(nombre del alumno)_ |
| **Proyecto** | Micrositio de Pedidos y Delivery — ZUYU |
| **Fecha de aceptación** | Abril 2026 |
| **Fecha de entrega** | _(definir con instructor)_ |
| **Instructor** | Daniel Guerrero |

---

## ✅ Propuesta Aceptada

La propuesta fue revisada y **aprobada en su totalidad**. El proyecto demuestra una
comprensión sólida de los requisitos de infraestructura de producción y justifica cada
componente con consecuencias de negocio concretas. El alcance es ambicioso y adecuado
para un proyecto final de bootcamp.

---

## Alcance Aceptado

### Aplicación
| Componente | Tecnología | Estado |
|------------|------------|--------|
| Servidor web + API | Node.js + Express 5.x | ✅ Aceptado |
| Vistas | EJS + Alpine.js | ✅ Aceptado |
| Base de datos | MongoDB 7.0 (Replica Set 3 nodos) | ✅ Aceptado |
| Cola de mensajes | Redis 7.2 + BullMQ | ✅ Aceptado |
| Worker asíncrono | Node.js + BullMQ | ✅ Aceptado |
| Notificaciones | Resend (email) / Twilio Sandbox (WhatsApp) | ✅ Aceptado |
| Delivery API | Uber Direct / Lalamove / iVoy (abstracción multi-carrier) | ✅ Aceptado |

### Infraestructura Kubernetes
| Componente | Implementación | Estado |
|------------|----------------|--------|
| Cluster | 1 master + 2 workers, Rocky Linux 9, kubeadm + Calico | ✅ Aceptado |
| Storage | NFS CSI StorageClass, ReadWriteOnce | ✅ Aceptado |
| StatefulSet MongoDB | 3 nodos, headless service, Replica Set | ✅ Aceptado |
| Ingress + TLS | nginx-ingress + cert-manager (ClusterIssuer self-signed) | ✅ Aceptado |
| NetworkPolicy | Default deny-all + reglas explícitas | ✅ Aceptado |
| Observabilidad logs | Loki + Grafana Alloy + Grafana | ✅ Aceptado |
| Observabilidad métricas | Prometheus + Grafana (kube-prometheus-stack) | ✅ Aceptado |
| CI/CD | Tekton Pipelines + ArgoCD | ✅ Aceptado |
| Despliegue gradual | Argo Rollouts (Canary 10%→50%→100%) | ✅ Aceptado |
| Escalado automático | KEDA + HPA (métrica: longitud de cola Redis) | ✅ Aceptado |
| Gobernanza | ResourceQuota por namespace | ✅ Aceptado |

---

## Entregables Requeridos

### 1. Repositorio GitHub (público)

Estructura mínima requerida:

```
micrositio-pedidos/
├── app/
│   ├── views/          ← plantillas EJS del micrositio y panel del negocio
│   ├── routes/         ← catálogo, pedidos, autenticación, webhooks
│   ├── models/         ← Mongoose schemas (Pedido, Producto, Negocio)
│   └── public/         ← CSS y Alpine.js
├── worker/             ← BullMQ consumer (notificaciones + delivery updates)
├── k8s/
│   ├── namespace.yaml
│   ├── mongodb/        ← StatefulSet, headless service, PVC
│   ├── redis/          ← Deployment, service
│   ├── api/            ← Deployment, service, ingress
│   ├── worker/         ← Deployment, KEDA ScaledObject
│   ├── networkpolicy/  ← deny-all + reglas por servicio
│   ├── resourcequota/  ← cuotas por namespace
│   └── rollouts/       ← Argo Rollouts canary config
├── tekton/
│   ├── task-git-clone.yaml
│   ├── task-build-push.yaml
│   ├── pipeline.yaml
│   └── pipelinerun.yaml
├── argocd/
│   └── application.yaml
├── monitoring/
│   ├── prometheus-values.yaml   ← helm values kube-prometheus-stack
│   └── loki-values.yaml         ← helm values loki stack
├── docker-compose.yml           ← para desarrollo local
└── README.md                    ← guía de despliegue completa
```

---

### 2. Manifiestos Kubernetes (obligatorios)

Cada archivo debe estar en el repositorio y funcionar con `kubectl apply`:

#### MongoDB Replica Set
- [ ] `StatefulSet` con 3 réplicas
- [ ] `headless Service` (`clusterIP: None`)
- [ ] `PersistentVolumeClaim` con StorageClass `nfs-csi`
- [ ] Script de inicialización del Replica Set (`rs.initiate()`)
- [ ] Prueba de transacciones atómicas (crear pedido + descontar stock en una transacción)

#### NetworkPolicy
- [ ] `default-deny-all.yaml` — bloquea todo tráfico por defecto
- [ ] `allow-api-to-mongo.yaml` — solo el API puede conectarse a MongoDB
- [ ] `allow-api-to-redis.yaml` — solo el API puede escribir en Redis
- [ ] `allow-worker-to-redis.yaml` — solo el worker puede leer de Redis
- [ ] `allow-ingress-to-api.yaml` — solo el ingress puede hablar con el API
- [ ] Demostración en vivo: pod sin autorización recibe `Connection refused` al intentar conectarse a MongoDB

#### Ingress + TLS
- [ ] `Ingress` con host `zuyu.local` (o similar)
- [ ] `Certificate` de cert-manager (ClusterIssuer self-signed)
- [ ] App accesible por HTTPS sin advertencias de certificado expirado

#### KEDA + HPA
- [ ] `ScaledObject` apuntando a la cola Redis del worker
- [ ] `minReplicaCount: 1`, `maxReplicaCount: 5`
- [ ] Demostración: insertar mensajes en la cola → pods del worker escalan → cola vacía → pods bajan

#### Argo Rollouts (Canary)
- [ ] `Rollout` del API con estrategia canary (10% → 50% → 100%)
- [ ] `AnalysisTemplate` (puede ser básico: verificar que los pods estén Running)
- [ ] Demostración: `kubectl argo rollouts promote` para avanzar el canary

#### ResourceQuota
- [ ] `ResourceQuota` en el namespace del proyecto
- [ ] Límites de CPU y memoria definidos
- [ ] Demostración: intentar crear un pod que exceda la cuota → debe ser rechazado

#### CI/CD (Tekton + ArgoCD)
- [ ] Pipeline completo: git clone → build → push a Docker Hub
- [ ] `ArgoCD Application` apuntando al repo, `selfHeal: true`, `prune: true`
- [ ] Demostración del ciclo: `git push` → Tekton construye → ArgoCD despliega

#### Observabilidad
- [ ] Prometheus scrapeando métricas del API y del worker
- [ ] Dashboard Grafana con al menos: latencia del API, longitud de cola Redis, error rate
- [ ] Loki recibiendo logs del API y del worker
- [ ] Búsqueda de un pedido por `pedidoId` en Grafana Explore

---

### 3. README.md

El README debe incluir:
- [ ] Diagrama de arquitectura (texto ASCII o imagen)
- [ ] Pre-requisitos del cluster
- [ ] Pasos de instalación ordenados y reproducibles
- [ ] Comandos de verificación para cada componente
- [ ] Sección de troubleshooting con errores conocidos

---

### 4. Demo en vivo (presentación)

La presentación tiene una duración máxima de **20 minutos** y debe demostrar:

| # | Demo | Tiempo estimado |
|---|------|----------------|
| 1 | Flujo completo de un pedido: cliente pide → repartidor asignado → entrega | 4 min |
| 2 | MongoDB Replica Set: matar un nodo y mostrar que el sistema sigue funcionando | 2 min |
| 3 | NetworkPolicy: pod no autorizado intenta conectarse a MongoDB → bloqueado | 2 min |
| 4 | KEDA: insertar mensajes en la cola → worker escala → cola vacía → worker baja | 3 min |
| 5 | CI/CD: `git push` → Tekton build → ArgoCD deploy | 3 min |
| 6 | Canary: despliegue gradual del API (10% → promover → 100%) | 2 min |
| 7 | Observabilidad: buscar un pedido por ID en los logs de Loki | 2 min |
| 8 | Preguntas | 2 min |

---

## Rúbrica de Evaluación

### Distribución de puntos (100 pts)

| Categoría | Puntos | Criterio |
|-----------|--------|---------|
| **MongoDB Replica Set** | 15 pts | StatefulSet correcto + transacción atómica demostrada + tolerancia a fallo de 1 nodo |
| **NetworkPolicy** | 15 pts | Default deny-all + reglas explícitas + demostración de bloqueo en vivo |
| **KEDA + Escalado** | 15 pts | ScaledObject configurado + demostración de scale-up y scale-down |
| **CI/CD (Tekton + ArgoCD)** | 15 pts | Pipeline completo + ciclo git push → deploy demostrado |
| **Canary Release** | 10 pts | Rollout configurado + promoción en vivo |
| **Observabilidad** | 10 pts | Prometheus + Loki funcionando + búsqueda de pedido por ID en Grafana |
| **Ingress + TLS** | 5 pts | HTTPS funcionando con cert-manager |
| **ResourceQuota** | 5 pts | Cuotas definidas + demostración de rechazo por exceso |
| **Repositorio y README** | 5 pts | Estructura correcta + guía reproducible |
| **Aplicación funcional** | 5 pts | Flujo de pedido completo funciona end-to-end |

### Criterios de calificación por categoría

**MongoDB Replica Set (15 pts)**
- 15 pts: 3 nodos Running + transacción atómica funciona + se mata 1 nodo y el sistema sigue operando
- 10 pts: 3 nodos Running + transacción funciona, sin demo de tolerancia a fallo
- 5 pts: MongoDB corre pero no es Replica Set (instancia sola)
- 0 pts: MongoDB no funciona

**NetworkPolicy (15 pts)**
- 15 pts: Default deny-all activo + reglas correctas + pod no autorizado bloqueado en vivo
- 10 pts: Reglas creadas y pods se comunican correctamente, sin demo de bloqueo
- 5 pts: NetworkPolicy creado pero no bloquea correctamente
- 0 pts: Sin NetworkPolicy

**KEDA + Escalado (15 pts)**
- 15 pts: Scale-up al insertar mensajes + scale-down al vaciar cola + tiempo de respuesta razonable
- 10 pts: Scale-up funciona, scale-down no demostrado
- 5 pts: ScaledObject creado pero sin demo de escalado real
- 0 pts: Sin KEDA

**CI/CD — Tekton + ArgoCD (15 pts)**
- 15 pts: `git push` → Tekton build exitoso → ArgoCD despliega automáticamente
- 10 pts: Tekton funciona + ArgoCD funciona, sync manual
- 5 pts: Solo uno de los dos funciona
- 0 pts: Sin CI/CD

**Canary Release (10 pts)**
- 10 pts: Rollout con estrategia canary + demostración de 10% → 50% → 100%
- 5 pts: Rollout configurado pero no demostrado en vivo
- 0 pts: Sin Argo Rollouts

**Observabilidad (10 pts)**
- 10 pts: Dashboard Grafana + Prometheus scrapeando API/worker + búsqueda de pedido en Loki
- 7 pts: Prometheus + Grafana funcionan, Loki no
- 4 pts: Solo Prometheus, sin Grafana ni Loki
- 0 pts: Sin observabilidad

---

## Puntos Extra (hasta +10 pts)

| Extra | Puntos | Descripción |
|-------|--------|-------------|
| Multi-carrier real | +5 pts | Demostrar conmutación entre Uber Direct y Lalamove según ciudad del negocio |
| AnalysisTemplate en Rollout | +3 pts | Canary con análisis automático (rollback si error rate > umbral) |
| Alertas en Grafana | +2 pts | Alerta disparada cuando la cola del worker supera un umbral |

---

## Condiciones de Entrega

### Obligatorias para aprobar
- [ ] El repositorio debe ser público en GitHub antes de la fecha de entrega
- [ ] Todos los manifiestos en `k8s/` deben funcionar con `kubectl apply -f`
- [ ] La aplicación debe recibir al menos un pedido completo durante la demo
- [ ] Los 7 demos de la presentación deben ejecutarse en el cluster real (no capturas de pantalla)

### No se acepta
- ❌ Manifiestos que no funcionan (`kubectl apply` da error)
- ❌ Componentes simulados o con capturas de pantalla en lugar de demo en vivo
- ❌ MongoDB sin Replica Set (instancia sola no cumple el requisito de transacciones)
- ❌ NetworkPolicy sin demostración de bloqueo
- ❌ README sin instrucciones de instalación reproducibles

---

## Recursos de Referencia del Bootcamp

| Tema | Clase | Archivos |
|------|-------|---------|
| Storage, PVC, StatefulSet | Clase 2 | `k8s-labs/12-statefulset/` |
| Prometheus + Grafana | Clase 3 | `k8s-labs/monitoring/` |
| Tekton + ArgoCD | Clase 4 | `k8s-labs/tekton-argocd/` |
| NetworkPolicy | Clase 5 | `k8s-labs/tracing-network/` |

---

## Preguntas Frecuentes

**¿Puedo usar Helm para instalar MongoDB?**
Sí, siempre que el Helm chart configure un Replica Set de 3 nodos y el StatefulSet quede
en el repositorio (como `values.yaml`).

**¿El Uber Direct necesita ser una integración real?**
Para la demo puede usarse el sandbox de Uber Direct o una respuesta simulada con el mismo
contrato de la API. Lo que se evalúa es la arquitectura (worker + cola + webhook), no la
integración con el carrier real.

**¿Los logs de Loki deben estar en español?**
No, lo importante es que incluyan el `pedidoId` como campo estructurado para que la
búsqueda funcione.

**¿Puedo usar `docker-compose` para la demo local?**
El `docker-compose.yml` es para desarrollo. La demo de evaluación debe ejecutarse
**en el cluster Kubernetes**, no en Docker Compose.

---

## Firma de Aceptación

> Al entregar el proyecto, el alumno confirma que:
> - El código y los manifiestos son de su autoría
> - El sistema fue desplegado y probado en un cluster Kubernetes real
> - El README es suficiente para que otra persona reproduzca el despliegue

---

*Documento generado por el instructor — Bootcamp Kubernetes DevOps 2026*
