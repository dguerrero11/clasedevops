# Guía del Instructor — Kubernetes Bootcamp Clase 2
## Almacenamiento Persistente: PV, PVC, StorageClass, NFS CSI, StatefulSet, DaemonSet

> **Prerequisitos de clase:**
> - Clase 1 completada (Namespace, Pod, ConfigMap, Secret, Deployment, Service)
> - Cluster funcionando: master01 + 3 workers
> - Servidor NFS: 192.168.109.210 con `/srv/nfs/k8s-storage` exportado
> - Acceso a internet para descargar el NFS CSI Driver

---

## Preparación antes de clase

```bash
# En master01
cd /root/kubernetes && git pull
kubectl create namespace bootcamp
kubectl config set-context --current --namespace=bootcamp

# Verificar conectividad con NFS
showmount -e 192.168.109.210
# Debe mostrar: /srv/nfs/k8s-storage 192.168.109.0/24

# Verificar que el directorio existe en el NFS
ssh root@192.168.109.210 "ls -la /srv/nfs/k8s-storage/"

# Instalar cliente NFS en todos los nodos (necesario para montar)
ansible all -i /root/kubernetes/ansible-k8s/inventory/hosts.ini \
  -m shell -a "dnf install -y nfs-utils" --become
```

---

## Introducción — El problema del almacenamiento (5 min)

> *"En la clase anterior vimos que los Pods son efímeros. Si borro un Pod
> y lo recreo, los archivos que estaban dentro desaparecen. ¿Qué pasa si
> tenemos una base de datos en un Pod?"*

**Demostración del problema:**
```bash
# Crear pod, escribir archivo, borrar pod → datos perdidos
kubectl run pod-efimero --image=busybox:1.36 \
  --command -- sh -c "echo 'dato importante' > /tmp/datos.txt && sleep 3600"

kubectl exec pod-efimero -- cat /tmp/datos.txt
kubectl delete pod pod-efimero
kubectl run pod-efimero --image=busybox:1.36 \
  --command -- sh -c "sleep 3600"
kubectl exec pod-efimero -- cat /tmp/datos.txt   # → No such file

kubectl delete pod pod-efimero
```

**Punto clave:** _"Para aplicaciones stateless (nginx, APIs REST) esto no importa.
Para bases de datos, caches, sistemas de archivos — necesitamos persistencia."_

---

## Lab 09 — Tipos de Volumen (emptyDir vs hostPath)

### ¿Qué explicar? (5 min)

> *"Antes de llegar a PV/PVC, veamos los volúmenes más simples.
> Son como los pasos previos en la evolución del almacenamiento en K8s."*

**emptyDir:**
- Vive mientras el Pod existe
- Si el Pod muere → se borra
- Si el Pod se reinicia → se conserva (solo muere con el Pod completo)
- Uso: compartir datos entre contenedores del mismo Pod (ya lo vimos con Sidecar)

**hostPath:**
- Monta un directorio del nodo físico
- Persiste incluso si el Pod muere
- Problema: el Pod queda "atado" al nodo → no se puede mover a otro worker
- Uso: logging, monitoring (DaemonSets)

### Demo en vivo

```bash
cd /root/kubernetes/k8s-labs

# emptyDir — compartir entre contenedores
kubectl apply -f 09-storage-intro/01-emptydir-demo.yaml
kubectl logs pod-emptydir -c reader -f   # ver datos en tiempo real
# Ctrl+C

# hostPath — leer logs del nodo
kubectl apply -f 09-storage-intro/02-hostpath-demo.yaml
kubectl exec pod-hostpath -- ls /host-logs/ | head -5
kubectl exec pod-hostpath -- cat /host-logs/k8s-test.log
```

**Preguntar:** _"¿En qué worker está corriendo el pod-hostpath?"_
```bash
kubectl get pod pod-hostpath -o wide
```
_"Si ese worker se cae y el pod pasa a otro worker, ¿los datos del log siguen ahí?"_
→ No, el log quedó en el primer worker.

### Ejercicio — Los alumnos hacen (5 min)
```bash
# Ver cuánto espacio tiene el emptyDir
kubectl exec pod-emptydir -c writer -- df -h /data

# ¿Qué pasa si reinicias el contenedor (no el pod)?
kubectl exec pod-emptydir -c writer -- kill 1   # mata el proceso
kubectl get pod pod-emptydir --watch
# El contenedor se reinicia pero los datos en /data siguen
```

### Limpieza
```bash
kubectl delete pod pod-emptydir pod-hostpath
```

---

## Lab 10 — PV y PVC (Static Provisioning)

### ¿Qué explicar? (8 min)

> *"Para almacenamiento real necesitamos separar roles:
> El ADMIN sabe dónde están los discos físicos (NFS, SAN, cloud).
> El DEVELOPER solo quiere 'necesito 1GB' sin saber nada del hardware."*

Dibujar en pizarrón:
```
ADMIN                    KUBERNETES              DEVELOPER
  │                          │                      │
  ├── Crea PV ──────────────►│                      │
  │   (disco NFS real)       │                      │
  │                          │◄──── Crea PVC ───────┤
  │                          │      "necesito 1Gi"  │
  │                          │                      │
  │                     BINDING                     │
  │                    (busca PV compatible)         │
  │                          │                      │
  │                          │──── PVC Bound ───────►│
  │                          │                      │
  │                          │◄──── Pod usa PVC ────┤
```

**Política de reclamación (importante para la clase):**
- `Retain` → cuando el developer borra el PVC, el admin decide qué hacer con los datos
- `Delete` → cuando el developer borra el PVC, los datos se borran solos (dinámico)

### Demo en vivo

```bash
# Mostrar el servidor NFS primero
ssh root@192.168.109.210 "ls -la /srv/nfs/k8s-storage/"

# Crear el PV (rol de admin)
cat 10-pv-pvc/01-pv-nfs.yaml
kubectl apply -f 10-pv-pvc/01-pv-nfs.yaml
kubectl get pv
# Estado: Available — nadie lo está usando aún
```

**Señalar en el output:** `STORAGECLASS`, `CLAIM`, `RECLAIM POLICY`, `STATUS`

```bash
# Crear el PVC (rol de developer)
cat 10-pv-pvc/02-pvc.yaml
kubectl apply -f 10-pv-pvc/02-pvc.yaml
kubectl get pvc
# Estado: Bound → el binding ocurrió automáticamente
kubectl get pv
# Estado: Bound → el PV ahora tiene un CLAIM
```

**Preguntar:** _"¿El developer tuvo que saber la IP del servidor NFS? ¿El path?
¿La versión de NFS? — No. Solo pidió 1Gi con acceso RWX."_

```bash
# Pod usando el PVC
kubectl apply -f 10-pv-pvc/03-pod-con-pvc.yaml
kubectl logs pod-con-pvc

# Verificar los datos en el NFS
ssh root@192.168.109.210 "cat /srv/nfs/k8s-storage/historia.txt"
```

### Demo — Persistencia real

```bash
# Borrar el pod y recrearlo
kubectl delete pod pod-con-pvc
kubectl apply -f 10-pv-pvc/03-pod-con-pvc.yaml
kubectl logs pod-con-pvc
# El historial de arranques previos sigue ahí
```

**Momento WOW para la clase:** _"El Pod murió, el nodo pudo haber cambiado,
pero los datos siguen. ESTO es almacenamiento persistente."_

### Demo — Dos pods compartiendo mismo volumen (RWX)

```bash
kubectl apply -f 10-pv-pvc/04-dos-pods-mismo-pvc.yaml
kubectl get pods -o wide
# ¿Están en distintos nodos?

kubectl logs pod-lector -f   # ver datos en tiempo real
```

**Señalar:** _"El pod-escritor está en worker01 y el pod-lector en worker02,
pero ambos ven el mismo archivo. Esto es NFS: Red File System — sistema
de archivos compartido en red."_

### Ejercicio — Los alumnos hacen (8 min)

```bash
# 1. ¿Cuál es la capacidad total del PV vs lo que pidió el PVC?
kubectl get pv pv-nfs-clase2
kubectl get pvc pvc-bootcamp
# PV tiene 2Gi, PVC pidió 1Gi → el PV tiene espacio libre pero está 100% reservado

# 2. ¿Qué pasa si intentas crear otro PVC que apunte al mismo PV?
kubectl create -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-segundo
  namespace: bootcamp
spec:
  accessModes: [ReadWriteMany]
  resources:
    requests:
      storage: 500Mi
  storageClassName: ""
EOF
kubectl get pvc pvc-segundo
# → Pending. El PV ya está Bound a otro PVC. 1 PV = 1 PVC (en static provisioning)
kubectl delete pvc pvc-segundo

# 3. Demostrar reclaimPolicy Retain
kubectl delete pvc pvc-bootcamp
kubectl get pv pv-nfs-clase2
# Estado: Released (no Available) — el admin debe limpiarlo manualmente
```

**Punto de discusión:** _"¿Por qué es importante Retain en producción?
Si alguien borra un PVC por error, los datos de la BD siguen ahí.
El admin puede recuperarlos."_

### Limpieza

```bash
kubectl delete pod pod-con-pvc pod-escritor pod-lector --ignore-not-found
kubectl delete pvc pvc-bootcamp --ignore-not-found
kubectl delete pv pv-nfs-clase2 --ignore-not-found
```

---

## Lab 11 — StorageClass y NFS CSI Driver (Dynamic Provisioning)

### ¿Qué explicar? (7 min)

> *"El problema con static provisioning: el admin tiene que crear un PV
> para cada PVC manualmente. En un cluster con cientos de aplicaciones,
> eso no escala. Dynamic Provisioning automatiza todo esto."*

```
Static:     Admin crea PV → Developer crea PVC → Binding
Dynamic:    Developer crea PVC → StorageClass → CSI Driver crea PV automático
```

**CSI = Container Storage Interface:**
- Estándar para que los proveedores de storage (NFS, AWS EBS, Ceph, etc.)
  se integren con Kubernetes sin modificar el core
- El NFS CSI Driver es el plugin que habla con nuestro servidor NFS

### Demo en vivo — Instalación del Driver

```bash
bash 11-storageclass-nfs-csi/00-instalar-nfs-csi.sh

# Verificar pods del driver (uno por nodo = DaemonSet interno!)
kubectl get pods -n kube-system | grep nfs
# csi-nfs-controller   3/3   Running  ← el cerebro
# csi-nfs-node-xxxx    3/3   Running  ← en cada nodo

# El driver se registra como CSI
kubectl get csidrivers
# nfs.csi.k8s.io
```

**Señalar:** _"¿Ven que hay un pod por nodo para el csi-nfs-node?
¡Eso es un DaemonSet! Lo vamos a ver en detalle en el Lab 13."_

```bash
# Crear la StorageClass
cat 11-storageclass-nfs-csi/01-storageclass-nfs.yaml
kubectl apply -f 11-storageclass-nfs-csi/01-storageclass-nfs.yaml
kubectl get storageclass
# nfs-csi (default)
```

**Señalar `(default)`:** _"Al ser la StorageClass por defecto, cualquier PVC
que no especifique `storageClassName` usará esta automáticamente."_

### Demo — Magia del aprovisionamiento dinámico

```bash
# En el NFS, antes:
ssh root@192.168.109.210 "ls /srv/nfs/k8s-storage/"

# Crear el PVC
kubectl apply -f 11-storageclass-nfs-csi/02-pvc-dinamico.yaml

# Ver cómo se crea el PV automáticamente
kubectl get pvc pvc-dinamico --watch
# Pending → Bound (en segundos)
kubectl get pv
# Aparece un PV con nombre automático

# En el NFS, después:
ssh root@192.168.109.210 "ls /srv/nfs/k8s-storage/"
# Apareció el subdirectorio bootcamp/pvc-dinamico/
```

**Momento WOW:** _"Nadie tuvo que crear el PV. El CSI Driver habló con el
servidor NFS y creó el directorio automáticamente. El developer solo necesita
saber el nombre de la StorageClass."_

```bash
kubectl apply -f 11-storageclass-nfs-csi/03-pod-pvc-dinamico.yaml
kubectl logs pod-pvc-dinamico
# Ver el df -h del punto de montaje
```

### Ejercicio — Los alumnos hacen (8 min)

```bash
# 1. Crear su propio PVC dinámico
kubectl create -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mi-pvc
  namespace: bootcamp
spec:
  accessModes: [ReadWriteMany]
  resources:
    requests:
      storage: 200Mi
  storageClassName: nfs-csi
EOF

# 2. Verificar que se creó el PV automático
kubectl get pvc mi-pvc
kubectl get pv | grep mi-pvc

# 3. Ver el subdirectorio en NFS
ssh root@192.168.109.210 "ls -la /srv/nfs/k8s-storage/"

# 4. Borrar el PVC y ver que el PV también se borra (reclaimPolicy: Delete)
kubectl delete pvc mi-pvc
kubectl get pv   # el PV desapareció
ssh root@192.168.109.210 "ls /srv/nfs/k8s-storage/"  # el directorio se borró
```

**Pregunta:** _"¿Cuándo usarían Retain vs Delete?"_
- `Delete` → ambientes de desarrollo, datos temporales
- `Retain` → producción, bases de datos, datos críticos

### Limpieza

```bash
kubectl delete -f 11-storageclass-nfs-csi/03-pod-pvc-dinamico.yaml
kubectl delete -f 11-storageclass-nfs-csi/02-pvc-dinamico.yaml
```

---

## Lab 12 — StatefulSet

### ¿Qué explicar? (8 min)

> *"Ahora que tenemos storage persistente, podemos hablar de StatefulSet.
> Imaginen que tienen una base de datos con 3 réplicas: primaria y 2 réplicas.
> ¿Pueden ser intercambiables? No — la primaria tiene un rol específico,
> las réplicas necesitan conectarse siempre a la misma primaria."*

**Diferencia clave Deployment vs StatefulSet:**

| | Deployment | StatefulSet |
|---|---|---|
| Pods | nginx-abc123 (random) | postgres-0, postgres-1 |
| Arranque | Paralelo | Secuencial: 0 → 1 → 2 |
| Storage | Compartido o sin estado | PVC individual por pod |
| DNS | IP aleatoria | postgres-0.postgres-headless... |
| Si borro postgres-0 | Recrea con nuevo nombre | Recrea exactamente como postgres-0 |

**Headless Service:**
- `clusterIP: None` → no hay IP virtual
- El DNS resuelve directamente a la IP del pod
- Permite direccionar pods individuales por nombre

### Demo en vivo

```bash
cat 12-statefulset/01-statefulset-postgres.yaml
kubectl apply -f 12-statefulset/01-statefulset-postgres.yaml

# Observar el orden de creación
kubectl get pods --watch
# postgres-0 → Running
# (si hubiera réplicas: postgres-1 espera a que postgres-0 esté Ready)

kubectl get statefulset
kubectl get pvc   # un PVC por pod: postgres-data-postgres-0
kubectl get pv    # PV creado automáticamente por NFS CSI
```

**Señalar nombres:** _"El PVC se llama `postgres-data-postgres-0`.
Es el template del StatefulSet más el nombre del pod.
Si agrego postgres-1, se crearía `postgres-data-postgres-1` automáticamente."_

### Demo — Persistencia real de base de datos

```bash
# Conectar a PostgreSQL
kubectl exec -it postgres-0 -- psql -U admin -d bootcamp

# Dentro de psql:
CREATE TABLE alumnos (
  id SERIAL PRIMARY KEY,
  nombre VARCHAR(50),
  fecha TIMESTAMP DEFAULT NOW()
);

INSERT INTO alumnos (nombre) VALUES
  ('Ana García'), ('Luis Martínez'), ('María López');

SELECT * FROM alumnos;
\q
```

```bash
# MATAR el pod — la pregunta del millón: ¿se pierden los datos?
kubectl delete pod postgres-0
kubectl get pods --watch
# postgres-0 se recrea con el MISMO nombre

# Verificar datos
kubectl exec -it postgres-0 -- psql -U admin -d bootcamp -c "SELECT * FROM alumnos;"
# Los datos siguen ahí
```

**Momento de impacto:** _"Borramos el pod, se recreó, se volvió a montar
el mismo PVC (mismo directorio NFS), y los datos están intactos.
ESO es un StatefulSet con almacenamiento persistente."_

### Demo — DNS estable

```bash
# Lanzar pod temporal para probar DNS
kubectl run dns-test --image=busybox:1.36 --restart=Never \
  --command -- sleep 3600

kubectl exec dns-test -- nslookup postgres-headless
# Devuelve la IP directa del pod (no una IP virtual)

kubectl exec dns-test -- nslookup postgres-0.postgres-headless.bootcamp.svc.cluster.local
# Resuelve exactamente postgres-0

kubectl delete pod dns-test
```

### Ejercicio — Los alumnos hacen (10 min)

```bash
# 1. Escalar el StatefulSet a 2 réplicas y observar el orden
kubectl scale statefulset postgres --replicas=2
kubectl get pods --watch
# postgres-1 espera a que postgres-0 esté Ready

# 2. ¿Cuántos PVCs hay ahora?
kubectl get pvc
# postgres-data-postgres-0  y  postgres-data-postgres-1

# 3. ¿Los dos pods comparten los datos?
kubectl exec postgres-0 -- psql -U admin -d bootcamp -c "SELECT * FROM alumnos;"
kubectl exec postgres-1 -- psql -U admin -d bootcamp -c "SELECT * FROM alumnos;"
# postgres-1 tiene su propio PVC vacío — cada instancia tiene storage separado

# 4. Volver a 1 réplica (el orden importa: elimina postgres-1 primero)
kubectl scale statefulset postgres --replicas=1
kubectl get pods --watch
# postgres-1 se elimina, postgres-0 sigue

# 5. ¿El PVC de postgres-1 se borró?
kubectl get pvc
# No se borra automáticamente — intencional, para proteger datos
kubectl delete pvc postgres-data-postgres-1
```

**Discusión:** _"¿Por qué el PVC no se borra automáticamente al escalar hacia abajo?
Es una protección: en producción una base de datos puede tener datos críticos.
Kubernetes no los borra sin confirmación explícita."_

### Limpieza

```bash
kubectl delete -f 12-statefulset/01-statefulset-postgres.yaml
kubectl delete pvc -l app=postgres -n bootcamp
```

---

## Lab 13 — DaemonSet

### ¿Qué explicar? (5 min)

> *"¿Qué pasa si necesitan un agente de monitoreo en TODOS los nodos?
> ¿O un recolector de logs? No quieren crear un Deployment y contar
> cuántos nodos tienen. Un DaemonSet lo hace automáticamente."*

**Regla del DaemonSet:**
- 1 pod por nodo, siempre
- Al agregar nodo → pod creado automáticamente
- Al eliminar nodo → pod destruido automáticamente

**Ya tienen DaemonSets corriendo:**
```bash
kubectl get daemonset -n kube-system    # kube-proxy
kubectl get daemonset -n kube-flannel   # kube-flannel-ds
```

### Demo en vivo

```bash
cat 13-daemonset/01-daemonset-log-agent.yaml
# Señalar: tolerations → permite correr en el master (control-plane)

kubectl apply -f 13-daemonset/01-daemonset-log-agent.yaml
kubectl get pods -l app=log-agent -o wide

# Contar: debe haber tantos pods como nodos
kubectl get nodes --no-headers | wc -l
kubectl get pods -l app=log-agent --no-headers | wc -l
# Mismo número

# Ver logs de un pod específico por nodo
kubectl logs -l app=log-agent --field-selector spec.nodeName=k8s-worker01
```

**Preguntar:** _"¿Cuántos pods del kube-proxy hay? ¿Y cuántos nodos?
¿Coincide? — Exactamente. kube-proxy es un DaemonSet."_

### Demo — Cordon y Drain

```bash
# Marcar un nodo como no schedulable
kubectl cordon k8s-worker03
kubectl get nodes   # worker03 aparece como SchedulingDisabled

# El pod del DaemonSet SIGUE corriendo (DaemonSet ignora cordon)
kubectl get pods -l app=log-agent -o wide

# Drain: vaciar un nodo (para mantenimiento)
kubectl drain k8s-worker03 --ignore-daemonsets --delete-emptydir-data
kubectl get pods -o wide   # los pods migraron

# Volver a schedulable
kubectl uncordon k8s-worker03
```

**Explicar:** _"En producción, cuando van a hacer mantenimiento en un servidor,
primero hacen `cordon` (no acepta nuevos pods) luego `drain` (mueve los que tiene)
y finalmente hacen el mantenimiento. Al terminar, `uncordon`."_

### Ejercicio — Los alumnos hacen (5 min)

```bash
# 1. ¿En cuántos nodos está el log-agent?
kubectl get pods -l app=log-agent -o wide

# 2. Comparar con kube-proxy:
kubectl get pods -n kube-system -l k8s-app=kube-proxy -o wide

# 3. ¿Qué pasaría si quitamos la toleration del DaemonSet?
# Editarlo:
kubectl edit daemonset log-agent
# Borrar las líneas de tolerations
# ¿El pod del master se borra?
```

### Limpieza

```bash
kubectl delete -f 13-daemonset/01-daemonset-log-agent.yaml
```

---

## Lab 14 — Ejercicio Integrador Clase 2

### ¿Qué explicar? (3 min)

> *"Ahora juntan todo lo de hoy con lo de la clase anterior:
> una app con base de datos real, almacenamiento NFS dinámico,
> StatefulSet para la DB y Deployment para el frontend."_

```bash
# Desplegar el stack completo
kubectl apply -f 14-ejercicio-integrador-clase2/app-con-storage.yaml
kubectl get pods -n clase2 --watch
```

```bash
# Cuando todo esté Running
kubectl get pvc -n clase2
kubectl get pv
ssh root@192.168.109.210 "find /srv/nfs/k8s-storage/clase2 -type d"
```

### Ejercicios por nivel

**Nivel 1 — Exploración (todos):**
```bash
# ¿Qué recursos se crearon?
kubectl get all -n clase2
kubectl get pvc -n clase2
kubectl get pv | grep clase2

# ¿El frontend tiene Init Container? ¿Para qué sirve?
kubectl describe pod -n clase2 -l app=frontend | grep -A10 "Init Containers"

# Acceder al frontend
curl http://192.168.109.144:30091
```

**Nivel 2 — Probar persistencia (intermedios):**
```bash
# Crear datos en la DB
kubectl exec -it postgres-0 -n clase2 -- \
  psql -U admin -d bootcamp -c \
  "CREATE TABLE test (msg TEXT); INSERT INTO test VALUES ('persistente!');"

# Borrar el pod de postgres
kubectl delete pod postgres-0 -n clase2
kubectl get pods -n clase2 --watch

# Verificar datos
kubectl exec -it postgres-0 -n clase2 -- \
  psql -U admin -d bootcamp -c "SELECT * FROM test;"
```

**Nivel 3 — Desafío (avanzados):**
```bash
# Escalar el frontend a 3 réplicas
kubectl scale deployment frontend --replicas=3 -n clase2

# ¿Todos los pods del frontend usan el mismo Init Container?
kubectl get pods -n clase2 -l app=frontend
kubectl describe pod <pod-frontend> -n clase2 | grep -A5 "Init Containers"

# Escalar postgres a 2 réplicas y observar
kubectl scale statefulset postgres --replicas=2 -n clase2
kubectl get pvc -n clase2   # ¿cuántos PVCs ahora?
kubectl get pv              # ¿cuántos PVs?
```

---

## Cierre de Clase 2 (5 min)

### Resumen de lo aprendido

| Recurso | Para qué sirve | Cuándo usarlo |
|---------|---------------|---------------|
| emptyDir | Compartir datos entre contenedores del mismo Pod | Sidecar, cache temporal |
| hostPath | Acceder a archivos del nodo | DaemonSets (logging, monitoring) |
| PV | Disco real en el cluster | Storage permanente (admin lo crea) |
| PVC | Solicitud de storage | El developer pide lo que necesita |
| StorageClass | Automatizar creación de PVs | Aprovisionamiento dinámico |
| NFS CSI Driver | Aprovisionar en NFS | Storage compartido RWX |
| StatefulSet | Apps con estado e identidad estable | DBs, Kafka, Zookeeper |
| DaemonSet | Un pod por nodo | Logging, monitoring, networking |

### La decisión clave en storage

```
¿Los datos deben sobrevivir al Pod?
    NO → emptyDir (o sin volumen)
    SÍ → PVC con StorageClass

¿Múltiples pods en distintos nodos necesitan los mismos datos?
    NO → ReadWriteOnce (RWO) — más rápido, block storage
    SÍ → ReadWriteMany (RWX) — NFS, Ceph, etc.

¿Es una base de datos o app con identidad?
    SÍ → StatefulSet
    NO → Deployment
```

### Tarea para próxima clase

_"Investiguen:_
1. _¿Cómo expondrían la app al exterior con SSL/TLS?_
   → **Ingress Controller**
2. _¿Cómo se escala automáticamente según la carga?_
   → **HPA (Horizontal Pod Autoscaler)**"_

---

## Troubleshooting de storage

| Síntoma | Causa | Solución |
|---------|-------|----------|
| PVC en `Pending` | No hay PV compatible | Verificar storageClass, accessMode y capacidad |
| PVC en `Pending` con CSI | Driver no instalado o NFS inaccesible | `kubectl get pods -n kube-system \| grep nfs` |
| Pod en `ContainerCreating` con PVC | NFS no montable desde el nodo | Verificar `nfs-utils` instalado y conectividad |
| `Permission denied` en el volumen | `no_root_squash` no configurado en NFS | Verificar `/etc/exports` en servidor NFS |
| StatefulSet pods no arrancan | PVC no se pudo crear | Verificar StorageClass y logs del CSI driver |
| PV en `Released` tras borrar PVC | `reclaimPolicy: Retain` | Borrar manualmente: `kubectl delete pv <nombre>` |

```bash
# Comandos de diagnóstico
kubectl describe pvc <nombre>          # ver eventos de binding
kubectl describe pv <nombre>           # ver detalles del volumen
kubectl logs -n kube-system -l app=csi-nfs-controller  # logs del CSI driver
showmount -e 192.168.109.210           # ver exports del NFS desde master
```

---

*Repo del curso: github.com/dguerrero11/bootcampkubernetes*
*En el cluster: `cd /root/kubernetes && git pull`*
