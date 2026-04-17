# Lab 12 - StatefulSet

## Concepto

StatefulSet = Deployment + identidad estable + storage individual por pod.

```
StatefulSet: postgres
  ├── postgres-0  → PVC: postgres-data-postgres-0  → NFS: /bootcamp/postgres-data-postgres-0/
  ├── postgres-1  → PVC: postgres-data-postgres-1  → NFS: /bootcamp/postgres-data-postgres-1/
  └── postgres-2  → PVC: postgres-data-postgres-2  → NFS: /bootcamp/postgres-data-postgres-2/
```

## Deployment vs StatefulSet

| | Deployment | StatefulSet |
|---|---|---|
| Nombres de pod | Aleatorios `nginx-abc123` | Ordenados `postgres-0`, `postgres-1` |
| Orden arranque | Paralelo | Secuencial: 0 → 1 → 2 |
| Orden parada | Paralelo | Inverso: 2 → 1 → 0 |
| Storage | Compartido o sin estado | PVC **individual** por pod |
| DNS | IP aleatoria | DNS estable por pod |
| Si borro postgres-0 | Recrea con nuevo nombre | Recrea exactamente como `postgres-0` |
| Uso | APIs, nginx, apps stateless | DBs, Kafka, Zookeeper, ElasticSearch |

## DNS de StatefulSet (Headless Service)

```bash
# Pod individual accesible por nombre DNS:
postgres-0.postgres-headless.bootcamp.svc.cluster.local
postgres-1.postgres-headless.bootcamp.svc.cluster.local

# El Headless Service (clusterIP: None) NO tiene IP virtual
# El DNS resuelve directamente a la IP del pod
# Esto permite que pods se conecten a instancias específicas
```

## Comandos

```bash
# Aplicar
kubectl apply -f 01-statefulset-postgres.yaml

# Ver StatefulSet y pods (notar nombres ordenados)
kubectl get statefulset
kubectl get pods -l app=postgres

# Ver PVCs creados automáticamente
kubectl get pvc -n bootcamp

# Conectar a PostgreSQL
kubectl exec -it postgres-0 -- psql -U admin -d bootcamp

# Comandos SQL útiles:
# CREATE TABLE alumnos (id SERIAL, nombre VARCHAR(50));
# INSERT INTO alumnos (nombre) VALUES ('Ana'), ('Luis');
# SELECT * FROM alumnos;
# \q

# Probar DNS del headless service
kubectl run dns-test --image=busybox:1.36 --restart=Never \
  --command -- nslookup postgres-0.postgres-headless.bootcamp.svc.cluster.local
kubectl logs dns-test
kubectl delete pod dns-test
```

## Ejercicios

### Ejercicio 1 — Crear datos y probar persistencia
```bash
# 1. Crear tabla e insertar datos
kubectl exec -it postgres-0 -- psql -U admin -d bootcamp

# 2. Borrar el pod (no el StatefulSet)
kubectl delete pod postgres-0

# 3. Observar que se recrea con el MISMO nombre
kubectl get pods --watch

# 4. Verificar que los datos persisten
kubectl exec -it postgres-0 -- psql -U admin -d bootcamp -c "SELECT * FROM alumnos;"
```

### Ejercicio 2 — Escalar y observar PVCs
```bash
kubectl scale statefulset postgres --replicas=2

# ¿Cuántos PVCs hay ahora?
kubectl get pvc

# ¿postgres-1 tiene los mismos datos que postgres-0?
kubectl exec postgres-1 -- psql -U admin -d bootcamp -c "\dt"
```

### Ejercicio 3 — DNS directo a pod
```bash
kubectl run curl-test --image=curlimages/curl:8.5.0 --restart=Never \
  --command -- sleep 3600

# Conectar directamente a postgres-0 por nombre
kubectl exec curl-test -- \
  nc -zv postgres-0.postgres-headless.bootcamp.svc.cluster.local 5432

kubectl delete pod curl-test
```

## Limpieza

```bash
kubectl delete -f 01-statefulset-postgres.yaml
# Los PVCs NO se borran con el StatefulSet (protección de datos intencional)
kubectl delete pvc -l app=postgres -n bootcamp
kubectl get pv   # verificar que los PVs se borraron (reclaimPolicy: Delete)
```
