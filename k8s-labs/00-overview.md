# Kubernetes Bootcamp - Labs

## Clase 1 — Fundamentos

| Lab | Tema | Conceptos clave |
|-----|------|-----------------|
| 01 | Namespace | Aislamiento lógico |
| 02 | Pod | Unidad mínima de despliegue |
| 03 | ConfigMap | Configuración externalizada |
| 04 | Secret | Datos sensibles |
| 05 | ServiceAccount | Identidad de workloads |
| 06 | Deployment | Pods gestionados y rolling updates |
| 07 | Service | Exposición y descubrimiento de Pods |
| 08 | Ejercicio integrador | Todo junto |

## Clase 2 — Almacenamiento Persistente

| Lab | Tema | Conceptos clave | Namespace |
|-----|------|-----------------|-----------|
| 09 | Storage intro | emptyDir, hostPath | bootcamp |
| 10 | PV y PVC | Static provisioning, binding, reclaimPolicy | bootcamp |
| 11 | StorageClass y NFS CSI | Dynamic provisioning, CSI Driver | bootcamp |
| 12 | StatefulSet | Identidad estable, PVCs individuales, headless service | bootcamp |
| 13 | DaemonSet | Un pod por nodo, tolerations, cordon/drain | bootcamp |
| 14 | Ejercicio integrador | Stack completo con storage NFS dinámico | clase2 |

---

## Convenciones

- Cada lab tiene archivos YAML numerados + `README.md`
- Namespace de trabajo clase 1 y 2 (labs 09-13): `bootcamp`
- Lab 14 usa namespace propio: `clase2`
- Crear el namespace antes de empezar los labs 09-13:

```bash
kubectl create namespace bootcamp
kubectl config set-context --current --namespace=bootcamp
```

## Verificar cluster

```bash
kubectl cluster-info
kubectl get nodes
kubectl get namespaces
```

## Prerequisitos Clase 2

```bash
# Servidor NFS disponible en la red
showmount -e 192.168.109.210
# Debe mostrar: /srv/nfs/k8s-storage 192.168.109.0/24

# nfs-utils instalado en todos los nodos (necesario para montar NFS)
ansible all -i /root/kubernetes/ansible-k8s/inventory/hosts.ini \
  -m shell -a "dnf install -y nfs-utils" --become

# NFS CSI Driver instalado antes de los labs 11-14
kubectl get pods -n kube-system | grep nfs
kubectl get storageclass nfs-csi
```

---

## Lab 09 — Storage Intro

**Archivos:** `09-storage-intro/`

| Archivo | Descripción |
|---------|-------------|
| `01-emptydir-demo.yaml` | Pod con 2 contenedores (writer + reader) compartiendo emptyDir |
| `02-hostpath-demo.yaml` | Pod montando `/var/log` del nodo como `/host-logs` |

```bash
# emptyDir — datos compartidos entre contenedores del mismo pod
kubectl apply -f 09-storage-intro/01-emptydir-demo.yaml
kubectl logs pod-emptydir -c reader -f

# hostPath — datos del nodo
kubectl apply -f 09-storage-intro/02-hostpath-demo.yaml
kubectl get pod pod-hostpath -o wide          # ¿en qué nodo está?
kubectl exec pod-hostpath -- ls /host-logs/

# Limpieza
kubectl delete pod pod-emptydir pod-hostpath --ignore-not-found
```

**Punto clave:** emptyDir desaparece con el Pod. hostPath persiste pero ata el Pod al nodo.

---

## Lab 10 — PV y PVC (Static Provisioning)

**Archivos:** `10-pv-pvc/`

| Archivo | Descripción |
|---------|-------------|
| `01-pv-nfs.yaml` | PV `pv-nfs-clase2` — 2Gi, RWX, NFS 192.168.109.210, reclaimPolicy: Retain |
| `02-pvc.yaml` | PVC `pvc-bootcamp` — solicita 1Gi RWX, selector `clase: bootcamp` |
| `03-pod-con-pvc.yaml` | Pod que escribe timestamp en `/datos/historia.txt` |
| `04-dos-pods-mismo-pvc.yaml` | Pod escritor + pod lector en el mismo PVC (demuestra RWX) |

```bash
# Crear PV (rol admin) — estado: Available
kubectl apply -f 10-pv-pvc/01-pv-nfs.yaml
kubectl get pv

# Crear PVC (rol developer) — estado: Bound tras el binding
kubectl apply -f 10-pv-pvc/02-pvc.yaml
kubectl get pvc
kubectl get pv   # ahora aparece CLAIM

# Probar persistencia: borrar pod y recrear — los datos sobreviven
kubectl apply -f 10-pv-pvc/03-pod-con-pvc.yaml
kubectl logs pod-con-pvc
kubectl delete pod pod-con-pvc
kubectl apply -f 10-pv-pvc/03-pod-con-pvc.yaml
kubectl logs pod-con-pvc   # historial de arranques anteriores visible

# RWX: dos pods en distintos nodos comparten el mismo volumen
kubectl apply -f 10-pv-pvc/04-dos-pods-mismo-pvc.yaml
kubectl get pods -o wide
kubectl logs pod-lector -f

# Ver datos directamente en el NFS
ssh root@192.168.109.210 "cat /srv/nfs/k8s-storage/historia.txt"

# reclaimPolicy Retain — al borrar el PVC el PV queda Released, no Available
kubectl delete pvc pvc-bootcamp
kubectl get pv pv-nfs-clase2   # Released

# Limpieza
kubectl delete pod pod-con-pvc pod-escritor pod-lector --ignore-not-found
kubectl delete pvc pvc-bootcamp --ignore-not-found
kubectl delete pv pv-nfs-clase2 --ignore-not-found
```

---

## Lab 11 — StorageClass y NFS CSI Driver (Dynamic Provisioning)

**Archivos:** `11-storageclass-nfs-csi/`

| Archivo | Descripción |
|---------|-------------|
| `00-instalar-nfs-csi.sh` | Instala el NFS CSI Driver v4.9.0 vía Helm |
| `01-storageclass-nfs.yaml` | StorageClass `nfs-csi` (default), provisioner: nfs.csi.k8s.io |
| `02-pvc-dinamico.yaml` | PVC `pvc-dinamico` — 500Mi, storageClassName: nfs-csi |
| `03-pod-pvc-dinamico.yaml` | Pod que usa el PVC dinámico |

```bash
# Instalar el driver (requiere Helm)
bash 11-storageclass-nfs-csi/00-instalar-nfs-csi.sh

# Verificar: controller (1) + node por nodo (DaemonSet interno)
kubectl get pods -n kube-system | grep nfs
kubectl get csidrivers   # nfs.csi.k8s.io

# Crear la StorageClass como default
kubectl apply -f 11-storageclass-nfs-csi/01-storageclass-nfs.yaml
kubectl get storageclass   # nfs-csi (default)

# PVC → PV automático → subdirectorio en NFS
kubectl apply -f 11-storageclass-nfs-csi/02-pvc-dinamico.yaml
kubectl get pvc pvc-dinamico --watch       # Pending → Bound
kubectl get pv                              # PV creado automáticamente

# El CSI Driver crea: /srv/nfs/k8s-storage/bootcamp/pvc-dinamico/
ssh root@192.168.109.210 "find /srv/nfs/k8s-storage -type d"

# Al borrar el PVC, el PV y el directorio NFS se borran (reclaimPolicy: Delete)
kubectl delete pvc pvc-dinamico
kubectl get pv   # desapareció

# Limpieza
kubectl delete pod pod-pvc-dinamico --ignore-not-found
kubectl delete pvc pvc-dinamico --ignore-not-found
```

---

## Lab 12 — StatefulSet

**Archivos:** `12-statefulset/`

| Archivo | Descripción |
|---------|-------------|
| `01-statefulset-postgres.yaml` | Headless Service + StatefulSet postgres (namespace: bootcamp) |

**Recursos creados por el YAML:**
- `Service/postgres-headless` — clusterIP: None, namespace: bootcamp
- `StatefulSet/postgres` — 1 réplica, image: postgres:15-alpine, namespace: bootcamp
- `PVC/postgres-data-postgres-0` — 1Gi RWO, StorageClass: nfs-csi (creado automáticamente)

```bash
kubectl apply -f 12-statefulset/01-statefulset-postgres.yaml

# Nombres de pod ordenados (no hashes)
kubectl get pods -l app=postgres
kubectl get pvc    # postgres-data-postgres-0

# DNS estable hacia pods individuales
kubectl run dns-test --image=busybox:1.36 --restart=Never \
  --command -- sleep 3600
kubectl exec dns-test -- nslookup postgres-0.postgres-headless.bootcamp.svc.cluster.local
kubectl delete pod dns-test

# Probar persistencia: crear tabla → borrar pod → datos sobreviven
kubectl exec -it postgres-0 -- psql -U admin -d bootcamp
# > CREATE TABLE alumnos (id SERIAL PRIMARY KEY, nombre VARCHAR(50));
# > INSERT INTO alumnos (nombre) VALUES ('Ana García'), ('Luis Martínez');
# > SELECT * FROM alumnos;
# > \q

kubectl delete pod postgres-0
kubectl get pods --watch         # se recrea con el mismo nombre: postgres-0
kubectl exec -it postgres-0 -- psql -U admin -d bootcamp -c "SELECT * FROM alumnos;"

# Escalar — cada réplica obtiene su propio PVC independiente
kubectl scale statefulset postgres --replicas=2
kubectl get pvc   # postgres-data-postgres-0 y postgres-data-postgres-1
# postgres-1 tiene storage vacío (no replica datos de postgres-0)

kubectl scale statefulset postgres --replicas=1
kubectl delete pvc postgres-data-postgres-1   # los PVCs NO se borran automáticamente

# Limpieza
kubectl delete -f 12-statefulset/01-statefulset-postgres.yaml
kubectl delete pvc -l app=postgres -n bootcamp
```

---

## Lab 13 — DaemonSet

**Archivos:** `13-daemonset/`

| Archivo | Descripción |
|---------|-------------|
| `01-daemonset-log-agent.yaml` | DaemonSet `log-agent` con toleration para control-plane |

**Recursos creados:**
- `DaemonSet/log-agent` — image: busybox:1.36, monta `/var/log` del nodo, namespace: bootcamp
- Toleration: `node-role.kubernetes.io/control-plane:NoSchedule` → corre también en master01

```bash
kubectl apply -f 13-daemonset/01-daemonset-log-agent.yaml

# 1 pod por nodo — debe coincidir con kubectl get nodes
kubectl get pods -l app=log-agent -o wide
kubectl get nodes --no-headers | wc -l
kubectl get pods -l app=log-agent --no-headers | wc -l   # mismo número

# DaemonSets ya presentes en el cluster
kubectl get daemonset -n kube-system    # kube-proxy
kubectl get daemonset -n kube-flannel   # kube-flannel-ds

# Cordon/Drain — el pod del DaemonSet NO se mueve con el drain
kubectl cordon k8s-worker03
kubectl get nodes   # k8s-worker03: SchedulingDisabled
kubectl get pods -l app=log-agent -o wide   # sigue corriendo en worker03

kubectl drain k8s-worker03 --ignore-daemonsets --delete-emptydir-data
kubectl uncordon k8s-worker03

# Limpieza
kubectl delete -f 13-daemonset/01-daemonset-log-agent.yaml
```

---

## Lab 14 — Ejercicio Integrador Clase 2

**Archivos:** `14-ejercicio-integrador-clase2/`

| Archivo | Descripción |
|---------|-------------|
| `app-con-storage.yaml` | Stack completo en namespace `clase2` (7 recursos) |

**Recursos del stack:**

| Recurso | Nombre | Detalle |
|---------|--------|---------|
| Namespace | `clase2` | Namespace dedicado |
| ConfigMap | `app-config` | DB_HOST, DB_PORT, DB_NAME, APP_ENV |
| Secret | `db-secret` | DB_USER=admin, DB_PASSWORD=bootcamp123 |
| Service | `postgres-headless` | clusterIP: None — DNS directo a pods |
| Service | `postgres-service` | ClusterIP — para conexión de la app |
| StatefulSet | `postgres` | 1 réplica, postgres:15-alpine |
| PVC (auto) | `pgdata-postgres-0` | 1Gi RWO, StorageClass: nfs-csi |
| Deployment | `frontend` | 2 réplicas, nginx:1.25 + init container |
| Service | `frontend-service` | NodePort :30091 |

> **Nota:** El volumeClaimTemplate del StatefulSet en este lab se llama `pgdata`
> (distinto al Lab 12 donde se llama `postgres-data`).
> PVC resultante: `pgdata-postgres-0`.

```bash
# Prerequisito: NFS CSI Driver y StorageClass instalados (Lab 11)
kubectl get storageclass nfs-csi

# Desplegar
kubectl apply -f 14-ejercicio-integrador-clase2/app-con-storage.yaml
kubectl get pods -n clase2 --watch
# Orden: postgres-0 Running → frontend init container pasa → frontend Running

kubectl get all -n clase2
kubectl get pvc -n clase2    # pgdata-postgres-0
kubectl get pv | grep clase2

# Frontend accesible desde cualquier worker
curl http://192.168.109.143:30091
curl http://192.168.109.144:30091
curl http://192.168.109.145:30091
```

**Ejercicios:**

```bash
# Nivel 1 — Exploración
kubectl get pods -n clase2 -o wide
kubectl describe pod -n clase2 -l app=frontend | grep -A10 "Init Containers"
ssh root@192.168.109.210 "find /srv/nfs/k8s-storage/clase2 -type d"
# Subdirectorio creado: /srv/nfs/k8s-storage/clase2/pgdata-postgres-0/

# Nivel 2 — Persistencia de PostgreSQL
kubectl exec -it postgres-0 -n clase2 -- psql -U admin -d bootcamp
# > CREATE TABLE registros (id SERIAL PRIMARY KEY, mensaje TEXT, fecha TIMESTAMP DEFAULT NOW());
# > INSERT INTO registros (mensaje) VALUES ('Dato persistente 1'), ('Clase 2 - Storage!');
# > SELECT * FROM registros;
# > \q

kubectl delete pod postgres-0 -n clase2
kubectl get pods -n clase2 --watch   # se recrea con el mismo nombre

kubectl exec -it postgres-0 -n clase2 -- \
  psql -U admin -d bootcamp -c "SELECT * FROM registros;"
# Los datos sobrevivieron

# Nivel 3 — Escalar StatefulSet
kubectl scale statefulset postgres --replicas=2 -n clase2
kubectl get pvc -n clase2   # pgdata-postgres-0 y pgdata-postgres-1
# postgres-1 tiene su propio storage vacío (no comparte datos con postgres-0)

kubectl scale statefulset postgres --replicas=1 -n clase2

# Nivel 4 — Init Container en acción
kubectl scale statefulset postgres --replicas=0 -n clase2
kubectl rollout restart deployment frontend -n clase2
kubectl get pods -n clase2 --watch   # frontend queda en Init:0/1

kubectl scale statefulset postgres --replicas=1 -n clase2
kubectl get pods -n clase2 --watch   # ahora el frontend avanza a Running

# Limpieza
kubectl delete namespace clase2
kubectl get pv | grep clase2   # debe estar vacío (reclaimPolicy: Delete)
```

---

## Tabla de decisión — Storage

```
¿Los datos deben sobrevivir al Pod?
    NO → emptyDir (o sin volumen)
    SÍ → PVC con StorageClass

¿Múltiples pods en distintos nodos necesitan los mismos datos?
    NO → ReadWriteOnce (RWO)
    SÍ → ReadWriteMany (RWX) — NFS

¿La app necesita identidad estable (base de datos)?
    SÍ → StatefulSet
    NO → Deployment

¿Necesitas un agente en todos los nodos?
    SÍ → DaemonSet
```

| Recurso | Para qué | Cuándo |
|---------|----------|--------|
| emptyDir | Datos temporales entre containers del mismo Pod | Sidecar, caché efímero |
| hostPath | Acceso al filesystem del nodo | Solo en DaemonSets |
| PV + PVC | Storage persistente, admin lo provisiona | Control total del storage |
| StorageClass | PVs automáticos bajo demanda | Aprovisionamiento dinámico |
| StatefulSet | Apps con identidad y storage individual | PostgreSQL, Kafka, Zookeeper |
| DaemonSet | Exactamente 1 pod por nodo | Logging, monitoring, networking |
