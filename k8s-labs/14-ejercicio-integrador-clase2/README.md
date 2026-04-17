# Lab 14 - Ejercicio Integrador Clase 2

## Stack completo

```
[Namespace: clase2]
  │
  ├── ConfigMap: app-config
  │     DB_HOST, DB_PORT, DB_NAME, APP_ENV
  │
  ├── Secret: db-secret
  │     DB_USER (admin) | DB_PASSWORD (bootcamp123)
  │
  ├── StatefulSet: postgres (1 réplica)
  │   └── Init: postgres-0
  │       PVC: pgdata-postgres-0 (1Gi)
  │         └── StorageClass: nfs-csi
  │             └── NFS: 192.168.109.210:/srv/nfs/k8s-storage/clase2/pgdata-postgres-0/
  │
  ├── Service: postgres-headless (ClusterIP: None)
  ├── Service: postgres-service (ClusterIP)
  │
  ├── Deployment: frontend (2 réplicas)
  │   └── Init Container: wait-for-postgres
  │   └── Container: nginx:1.25
  │
  └── Service: frontend-service (NodePort: 30091)
```

## Prerequisito

El NFS CSI Driver debe estar instalado (Lab 11):
```bash
kubectl get pods -n kube-system | grep nfs   # debe estar Running
kubectl get storageclass nfs-csi             # debe existir
```

## Despliegue

```bash
# Desplegar todo el stack
kubectl apply -f app-con-storage.yaml

# Monitorear el arranque
kubectl get pods -n clase2 --watch

# Orden esperado:
# 1. postgres-0 → Init containers → Running
# 2. frontend-xxx → Init: 0/1 (esperando postgres) → Running

# Verificar todos los recursos
kubectl get all -n clase2
kubectl get pvc -n clase2
kubectl get pv | grep clase2

# Acceder al frontend
curl http://192.168.109.143:30091
curl http://192.168.109.144:30091
curl http://192.168.109.145:30091
```

## Ejercicios por nivel

### Nivel 1 — Exploración
```bash
# ¿En qué nodo está postgres-0?
kubectl get pods -n clase2 -o wide

# ¿Cuántos PVCs se crearon? ¿Y PVs?
kubectl get pvc -n clase2
kubectl get pv

# ¿Qué subdirectorio creó el CSI Driver en el NFS?
ssh root@192.168.109.210 "find /srv/nfs/k8s-storage/clase2 -type d"

# ¿Qué hace el Init Container del frontend?
kubectl describe pod -n clase2 -l app=frontend | grep -A10 "Init Containers"

# ¿Qué variables de entorno tiene el frontend?
kubectl exec -n clase2 \
  $(kubectl get pods -n clase2 -l app=frontend -o jsonpath='{.items[0].metadata.name}') \
  -- env | grep -E "DB_|APP_"
```

### Nivel 2 — Probar persistencia de PostgreSQL
```bash
# 1. Crear tabla e insertar datos
kubectl exec -it postgres-0 -n clase2 -- psql -U admin -d bootcamp

# En psql:
CREATE TABLE registros (
  id SERIAL PRIMARY KEY,
  mensaje TEXT,
  fecha TIMESTAMP DEFAULT NOW()
);
INSERT INTO registros (mensaje) VALUES
  ('Dato persistente 1'),
  ('Dato persistente 2'),
  ('Clase 2 - Storage!');
SELECT * FROM registros;
\q

# 2. Borrar el pod de postgres (NO el StatefulSet)
kubectl delete pod postgres-0 -n clase2

# 3. Observar que se recrea con el mismo nombre
kubectl get pods -n clase2 --watch

# 4. Verificar que los datos sobrevivieron
kubectl exec -it postgres-0 -n clase2 -- \
  psql -U admin -d bootcamp -c "SELECT * FROM registros;"
```

### Nivel 3 — Escalar el StatefulSet
```bash
# Escalar a 2 réplicas de postgres
kubectl scale statefulset postgres --replicas=2 -n clase2
kubectl get pods -n clase2 --watch

# ¿Cuántos PVCs se crearon ahora?
kubectl get pvc -n clase2

# ¿postgres-1 tiene los mismos datos que postgres-0?
kubectl exec postgres-1 -n clase2 -- \
  psql -U admin -d bootcamp -c "SELECT * FROM registros;"
# No — cada pod tiene su propio storage independiente
```

### Nivel 4 — Desafío: Init Container en acción
```bash
# Escalar postgres a 0 (simular DB caída)
kubectl scale statefulset postgres --replicas=0 -n clase2

# Forzar restart del frontend
kubectl rollout restart deployment frontend -n clase2

# Observar que el frontend se queda en Init
kubectl get pods -n clase2 --watch
# frontend-xxx   0/1   Init:0/1   <- esperando postgres

# Volver a levantar postgres
kubectl scale statefulset postgres --replicas=1 -n clase2

# Ahora el frontend avanza
kubectl get pods -n clase2 --watch
```

## Limpieza

```bash
# Borrar el namespace borra TODOS los recursos dentro (excepto PVs)
kubectl delete namespace clase2

# Verificar que los PVs también se borraron (reclaimPolicy: Delete)
kubectl get pv | grep clase2   # no debe mostrar nada
```
