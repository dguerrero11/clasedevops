# Lab 02 - Pod

## Concepto

El **Pod** es la unidad mínima de despliegue en Kubernetes.
- Contiene uno o más contenedores Docker
- Comparten red (localhost), IPC y volúmenes
- Tienen una IP propia dentro del cluster
- Son **efímeros** — si mueren, no se recrean solos (para eso existe Deployment)

## Ciclo de vida de un Pod

```
Pending → Running → Succeeded / Failed / Unknown
```

## Comandos esenciales

```bash
# Crear un Pod
kubectl apply -f 01-pod-basico.yaml

# Ver pods en el namespace activo
kubectl get pods
kubectl get pods -o wide          # ver IP y nodo
kubectl get pods --watch          # modo watch en tiempo real

# Inspeccionar un Pod
kubectl describe pod pod-nginx

# Ver logs
kubectl logs pod-nginx
kubectl logs pod-sidecar -c sidecar-log-reader  # logs de contenedor específico
kubectl logs pod-nginx -f                        # seguimiento en tiempo real

# Ejecutar comandos dentro del pod
kubectl exec -it pod-nginx -- bash
kubectl exec pod-nginx -- nginx -v

# Port-forward: acceder al pod desde tu máquina local
kubectl port-forward pod/pod-nginx 8080:80
# Luego visita: http://localhost:8080

# Ver eventos del pod
kubectl get events --field-selector involvedObject.name=pod-nginx
```

## Ejemplos incluidos

| Archivo | Patrón |
|---------|--------|
| `01-pod-basico.yaml` | Pod simple con nginx |
| `02-pod-multiples-contenedores.yaml` | Patrón Sidecar |
| `03-pod-init-container.yaml` | Init Container |

## Ejercicios

### Ejercicio 1 — Pod básico
1. Aplica `01-pod-basico.yaml`
2. Espera a que pase a `Running`: `kubectl get pods --watch`
3. Haz port-forward y visita `http://localhost:8080`
4. Entra al contenedor y modifica `/usr/share/nginx/html/index.html`
5. Recarga la página — ¿qué ves?

### Ejercicio 2 — Sidecar
1. Aplica `02-pod-multiples-contenedores.yaml`
2. Observa los logs del sidecar: `kubectl logs pod-sidecar -c sidecar-log-reader -f`
3. ¿Cuántos contenedores tiene el pod? Usa `kubectl describe`

### Ejercicio 3 — Init Container
1. Aplica `03-pod-init-container.yaml`
2. Observa con `kubectl get pods --watch` cómo pasa por el estado `Init:0/1`
3. Lee los logs del init container: `kubectl logs pod-init -c init-esperar-servicio`

### Ejercicio 4 — Desafío
Crea un Pod con imagen `curlimages/curl` que haga `curl http://pod-nginx` (requiere saber la IP).
Pista: `kubectl get pod pod-nginx -o jsonpath='{.status.podIP}'`

## Limpieza

```bash
kubectl delete pod pod-nginx
kubectl delete pod pod-sidecar
kubectl delete pod pod-init

# O borrar todos los archivos del lab de una vez
kubectl delete -f .
```
