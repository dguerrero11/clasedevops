# Lab 06 - Deployment

## Concepto

Un **Deployment** es el recurso principal para desplegar aplicaciones stateless.
Gestiona automáticamente un **ReplicaSet**, que a su vez gestiona los **Pods**.

```
Deployment
  └── ReplicaSet (v1)
        ├── Pod-1
        ├── Pod-2
        └── Pod-3
```

**Características clave:**
- Mantiene N réplicas siempre activas (self-healing)
- Rolling updates: actualiza pods de a uno sin downtime
- Rollback: vuelta atrás en un comando

## Comandos esenciales

```bash
# Crear deployment
kubectl apply -f 01-deployment.yaml

# Ver deployments
kubectl get deployments
kubectl get deploy                          # abreviación

# Ver el estado del rollout
kubectl rollout status deployment/nginx-deployment

# Ver historial de versiones
kubectl rollout history deployment/nginx-deployment

# Ver ReplicaSets (el Deployment gestiona éstos)
kubectl get replicasets
kubectl get rs

# Ver pods del deployment
kubectl get pods -l app=nginx

# Escalar (imperativo)
kubectl scale deployment nginx-deployment --replicas=5

# --- ROLLING UPDATE ---

# Actualizar imagen (genera una nueva versión)
kubectl set image deployment/nginx-deployment nginx=nginx:1.26

# Monitorear el rollout
kubectl rollout status deployment/nginx-deployment --timeout=60s

# --- ROLLBACK ---

# Volver a la versión anterior
kubectl rollout undo deployment/nginx-deployment

# Volver a una versión específica
kubectl rollout undo deployment/nginx-deployment --to-revision=1

# Ver detalles de una revisión
kubectl rollout history deployment/nginx-deployment --revision=2

# --- PAUSA / RESUME (para aplicar múltiples cambios) ---
kubectl rollout pause deployment/nginx-deployment
kubectl set image deployment/nginx-deployment nginx=nginx:1.27
kubectl set resources deployment nginx-deployment -c nginx --limits=cpu=300m
kubectl rollout resume deployment/nginx-deployment
```

## Health Checks (Probes)

| Probe | ¿Cuándo falla? | Consecuencia |
|-------|----------------|--------------|
| `livenessProbe` | App está muerta/colgada | Kubernetes reinicia el contenedor |
| `readinessProbe` | App no está lista para tráfico | Kubernetes la saca del Service |
| `startupProbe` | App tarda mucho en arrancar | Evita que las otras probes maten el pod antes de arrancar |

## Ejercicios

### Ejercicio 1 — Crear y escalar
1. Aplica `01-deployment.yaml`
2. Verifica que los 3 pods estén `Running`
3. Escala a 5 réplicas: `kubectl scale deployment nginx-deployment --replicas=5`
4. Reduce a 1 réplica
5. ¿Qué pasa si escalas a 0?

### Ejercicio 2 — Rolling Update
1. Observa en una terminal: `kubectl get pods -w`
2. En otra terminal, actualiza la imagen: `kubectl set image deployment/nginx-deployment nginx=nginx:1.26`
3. Observa cómo los pods se reemplazan uno a uno
4. Verifica: `kubectl rollout status deployment/nginx-deployment`

### Ejercicio 3 — Rollback
1. Aplica una imagen que no existe (provocar fallo):
   ```bash
   kubectl set image deployment/nginx-deployment nginx=nginx:no-existe
   ```
2. Observa: `kubectl rollout status deployment/nginx-deployment`
3. ¿Qué pasa con los pods? ¿El servicio sigue funcionando?
4. Haz rollback: `kubectl rollout undo deployment/nginx-deployment`

### Ejercicio 4 — Liveness Probe falló
1. Modifica el deployment para que el livenessProbe apunte a `/health` (ruta que no existe)
2. Aplica el cambio
3. Observa con `kubectl describe pod <nombre>` el estado de las probes
4. ¿Cuántas veces reinicia el contenedor antes de `CrashLoopBackOff`?

### Ejercicio 5 — Desafío
Despliega `02-deployment-con-config.yaml` (requiere tener el SA del lab 05).
Luego verifica que las variables de entorno están disponibles en los pods.

## Limpieza

```bash
kubectl delete -f .
```
