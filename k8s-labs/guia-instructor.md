# Guía del Instructor — Kubernetes Bootcamp Clase 1

> **Para el instructor:** Este documento es tu guía de clase. Cada sección tiene el contexto
> teórico que debes explicar, los comandos a ejecutar en vivo y los puntos de discusión
> con los alumnos. Los ejercicios están diseñados para ser progresivos: primero el instructor
> demuestra, luego los alumnos replican.

---

## Preparación antes de clase

```bash
# En master01 — verificar que el cluster está listo
kubectl get nodes
kubectl get pods -A | grep -v Running   # no debe haber pods en error

# Crear namespace de trabajo
kubectl create namespace bootcamp
kubectl config set-context --current --namespace=bootcamp

# Bajar últimos cambios del repo
cd /root/kubernetes && git pull
cd k8s-labs
```

---

## Lab 01 — Namespace

### ¿Qué explicar? (5 min)

> *"Imaginen que un cluster de Kubernetes es un edificio de oficinas. Los Namespaces
> son los pisos o departamentos. Cada equipo trabaja en su propio espacio, con sus
> propios recursos, sin interferir con los demás."*

- Un cluster puede tener decenas de equipos corriendo al mismo tiempo
- Los namespaces permiten separar: `dev`, `staging`, `prod`, o por equipo
- Los recursos dentro de un namespace tienen nombres únicos **entre sí**, pero pueden
  repetirse en distintos namespaces (puedes tener `backend` en `dev` y en `prod`)
- Kubernetes ya viene con namespaces del sistema: `kube-system`, `kube-flannel`

### Demo en vivo (instructor)

```bash
# Mostrar los namespaces que ya existen en el cluster
kubectl get namespaces

# Crear desde YAML — mostrar el archivo primero
cat 01-namespace/namespace.yaml
kubectl apply -f 01-namespace/namespace.yaml

# Observar los labels que pusimos
kubectl describe namespace bootcamp

# Establecer como namespace activo
kubectl config set-context --current --namespace=bootcamp
kubectl config view --minify | grep namespace
```

**Punto de discusión:** _"¿Ven la diferencia entre `kubectl create` (imperativo) y
`kubectl apply -f` (declarativo)? En producción siempre usamos YAML para tener
control de versiones de nuestra infraestructura."_

### Ejercicio — Los alumnos hacen (5 min)

```bash
# Crear namespaces para distintos entornos
kubectl create namespace dev
kubectl create namespace prod

# Verificar
kubectl get namespaces

# Pregunta: ¿Qué pasa si intentas crear el mismo namespace dos veces?
kubectl create namespace dev   # → Error: already exists

# ¿Y con apply?
kubectl apply -f 01-namespace/namespace.yaml  # → configured (idempotente)
```

**Pregunta para los alumnos:** _"¿Cuál es la diferencia en el comportamiento?
¿Por qué `apply` es mejor para automatización?"_

### Limpieza

```bash
kubectl delete namespace dev
kubectl delete namespace prod
```

---

## Lab 02 — Pod

### ¿Qué explicar? (7 min)

> *"Si los Namespaces son los pisos del edificio, los Pods son las habitaciones.
> Y dentro de cada habitación viven los contenedores — los procesos reales que
> hacen el trabajo."*

Dibujar en pizarrón o mostrar diagrama:
```
Pod
├── Contenedor 1 (app)    ← comparten
├── Contenedor 2 (sidecar)   la misma IP
└── Volumen compartido       y red (localhost)
```

- Un Pod es la unidad mínima — no se despliegan contenedores solos
- Tienen su propia IP dentro de la red de Flannel (`10.244.x.x`)
- Son **efímeros**: si el Pod muere, no regresa solo (para eso existe Deployment)
- En producción casi nunca se crean Pods directamente

### Demo en vivo — Pod básico (instructor)

```bash
# Mostrar el YAML antes de aplicarlo
cat 02-pod/01-pod-basico.yaml
```

**Señalar en el YAML:**
- `resources.requests` vs `resources.limits` — el Pod pide 100m CPU pero no puede usar más de 200m
- `containerPort: 80` — es solo informativo, no abre nada por sí solo
- `labels` — clave para que los Services encuentren los Pods más adelante

```bash
kubectl apply -f 02-pod/01-pod-basico.yaml
kubectl get pods --watch   # mostrar cómo pasa por los estados

# Cuando está Running:
kubectl get pod pod-nginx -o wide    # ← ¿en qué nodo quedó?
```

**Pregunta:** _"¿Quién decidió en qué worker correr el pod? — El Scheduler del
Control Plane. Nosotros no elegimos, él balancea."_

```bash
kubectl describe pod pod-nginx       # mostrar Events al final — es el historial
kubectl logs pod-nginx               # logs de nginx arrancando

# Entrar al contenedor
kubectl exec -it pod-nginx -- bash
  nginx -v
  cat /etc/nginx/nginx.conf
  exit

# Port-forward — acceder desde el master
kubectl port-forward pod/pod-nginx 8080:80 &
curl http://localhost:8080
kill %1
```

### Demo en vivo — Patrón Sidecar

> *"A veces necesitamos un 'asistente' corriendo junto a nuestra app.
> Por ejemplo: un proceso que lea los logs y los envíe a un sistema centralizado.
> A esto se le llama patrón Sidecar."*

```bash
cat 02-pod/02-pod-multiples-contenedores.yaml
kubectl apply -f 02-pod/02-pod-multiples-contenedores.yaml
kubectl get pods   # notar READY 2/2

# Ver los logs del sidecar en tiempo real
kubectl logs pod-sidecar -c sidecar-log-reader -f
# Ctrl+C

# ¿Por qué el contenedor "app" no tiene logs en stdout?
kubectl logs pod-sidecar -c app   # → vacío, escribe al archivo
```

**Punto clave:** _"READY 2/2 significa que los 2 contenedores están corriendo.
Comparten exactamente la misma red y el mismo volumen `emptyDir`."_

### Demo en vivo — Init Container

> *"¿Qué pasa si nuestra app necesita que la base de datos esté lista antes de
> arrancar? Con un Init Container podemos hacer que espere."*

```bash
kubectl apply -f 02-pod/03-pod-init-container.yaml
kubectl get pods --watch  # ← mostrar Init:0/1 → PodInitializing → Running

kubectl logs pod-init -c init-esperar-servicio
kubectl describe pod pod-init | grep -A15 "Init Containers:"
# State: Terminated — terminó exitosamente
```

### Ejercicio — Los alumnos hacen (10 min)

**Ejercicio 1:** Investigar el Pod
```bash
# 1. ¿En qué worker está pod-nginx?
kubectl get pod pod-nginx -o wide

# 2. ¿Cuál es su IP?
kubectl get pod pod-nginx -o jsonpath='{.status.podIP}'

# 3. ¿Cuánto CPU y memoria tiene asignado?
kubectl describe pod pod-nginx | grep -A6 "Limits:"

# 4. Entra al pod y crea un archivo en /tmp
kubectl exec -it pod-nginx -- bash
  echo "Hola K8s" > /tmp/prueba.txt
  cat /tmp/prueba.txt
  exit
```

**Ejercicio 2 — Desafío:** _"Borra el pod y vuélvelo a crear. ¿Qué pasó con el archivo
que creaste en /tmp?"_ → El archivo desapareció. Los Pods son efímeros.

```bash
kubectl delete pod pod-nginx
kubectl apply -f 02-pod/01-pod-basico.yaml
kubectl exec pod-nginx -- cat /tmp/prueba.txt   # → No such file or directory
```

**Conclusión del Lab:** _"Por eso en producción no guardamos estado en Pods.
Para eso existen los Persistent Volumes (tema de la próxima clase)."_

### Limpieza

```bash
kubectl delete -f 02-pod/
```

---

## Lab 03 — ConfigMap

### ¿Qué explicar? (5 min)

> *"¿Han visto aplicaciones que tienen el entorno hardcodeado en el código?
> `if env == 'production'`... ConfigMap resuelve esto: la configuración
> va separada de la imagen Docker."*

Principio **12-factor app**: la configuración debe venir del entorno, no del código.

Dos formas de usar un ConfigMap:
1. **Variables de entorno** — se cargan al arrancar el Pod
2. **Archivos montados** — cada clave se convierte en un archivo, soporta hot reload

### Demo en vivo (instructor)

```bash
cat 03-configmap/01-configmap-literal.yaml
kubectl apply -f 03-configmap/01-configmap-literal.yaml

# Notar: puede guardar tanto variables como archivos completos
kubectl describe configmap app-config

# Forma 1: env vars
kubectl apply -f 03-configmap/02-pod-con-configmap-envvar.yaml
kubectl logs pod-config-env
kubectl exec pod-config-env -- env | grep APP
```

**Preguntar:** _"¿Cómo cambiaríamos el entorno de producción a desarrollo?
Solo cambiamos el ConfigMap. La imagen Docker no se toca."_

```bash
# Forma 2: volumen
kubectl apply -f 03-configmap/03-pod-con-configmap-volumen.yaml
kubectl logs pod-config-vol

# Notar los symlinks
kubectl exec -it pod-config-vol -- sh
  ls -la /etc/app-config/   # symlinks → ..data/
  cat /etc/app-config/app.properties
  exit
```

**Explicar los symlinks:** _"Kubernetes usa symlinks para el hot reload. Cuando
actualizamos el ConfigMap, cambia el directorio `..data` que apuntan los symlinks,
sin que el Pod tenga que reiniciarse."_

### Demo — Hot reload en vivo

```bash
# Terminal 1: observar el archivo
kubectl exec -it pod-config-vol -- sh -c "watch -n2 cat /etc/app-config/APP_LOG_LEVEL"

# Terminal 2: editar el ConfigMap
kubectl edit configmap app-config
# Cambiar: APP_LOG_LEVEL: info → APP_LOG_LEVEL: debug
# Guardar: ESC :wq

# Esperar ~60 segundos y observar Terminal 1
```

**Preguntar:** _"¿Las variables de entorno cambiaron también?"_
```bash
kubectl exec pod-config-env -- env | grep APP_LOG_LEVEL  # → sigue en "info"
```

**Conclusión:** _"Variables de entorno = reinicio del Pod. Volumen = hot reload.
Elijan según si su app puede/no puede reiniciarse."_

### Ejercicio — Los alumnos hacen (8 min)

```bash
# 1. Crear un ConfigMap con sus propios datos
kubectl create configmap mi-config \
  --from-literal=MI_NOMBRE="TuNombre" \
  --from-literal=MI_EQUIPO="DevOps"

# 2. Verificar
kubectl get configmap mi-config -o yaml

# 3. Crear un pod que use ese ConfigMap como env var
# (modificar 02-pod-con-configmap-envvar.yaml cambiando el nombre del CM)

# 4. Verificar que la variable está disponible
kubectl exec <pod> -- env | grep MI_
```

### Limpieza

```bash
kubectl delete -f 03-configmap/
kubectl delete configmap mi-config 2>/dev/null; true
```

---

## Lab 04 — Secret

### ¿Qué explicar? (5 min)

> *"ConfigMap es para configuración general. Secret es para lo que NO quieres
> que aparezca en los logs: contraseñas, tokens de API, certificados TLS."*

**Punto crítico para la clase:**
- Los valores en Secret están en **Base64** — eso NO es cifrado
- Cualquiera con acceso al cluster puede decodificarlo con `base64 -d`
- En producción, Secret se combina con: **Vault**, **Sealed Secrets**, o
  **External Secrets Operator** para cifrado real

### Demo en vivo (instructor)

```bash
# Mostrar cómo se crea con base64
echo -n "mi-password" | base64    # → bWktcGFzc3dvcmQ=
echo -n "admin" | base64          # → YWRtaW4=

cat 04-secret/01-secret.yaml
kubectl apply -f 04-secret/01-secret.yaml

# Describe no muestra los valores — solo el tamaño
kubectl describe secret db-credentials

# Pero -o yaml sí los muestra (en base64)
kubectl get secret db-credentials -o yaml
```

**Demostrar que se puede decodificar:**
```bash
kubectl get secret db-credentials \
  -o jsonpath='{.data.DB_PASSWORD}' | base64 -d
# → mi-password
```

**Preguntar a los alumnos:** _"Si se puede decodificar tan fácilmente,
¿por qué usamos Secret en vez de ConfigMap?"_

Respuesta: separación de responsabilidades + RBAC (puedes dar acceso a ConfigMaps
sin dar acceso a Secrets) + es la base para integrar con sistemas de cifrado real.

```bash
kubectl apply -f 04-secret/02-pod-con-secret.yaml
kubectl logs pod-con-secret

# Kubernetes decodifica automáticamente al inyectar
kubectl exec pod-con-secret -- env | grep DB
```

### Ejercicio — Los alumnos hacen (5 min)

```bash
# 1. Crear un Secret con sus propias credenciales
kubectl create secret generic mis-credenciales \
  --from-literal=USUARIO=alumno \
  --from-literal=PASSWORD=bootcamp123

# 2. Decodificar el PASSWORD manualmente
kubectl get secret mis-credenciales \
  -o jsonpath='{.data.PASSWORD}' | base64 -d

# 3. Pregunta: ¿Qué pasa si haces kubectl describe secret?
# ¿Puedes ver el valor del PASSWORD?
kubectl describe secret mis-credenciales
```

**Discusión final:** _"En proyectos reales, los Secrets nunca deben estar
commiteados en Git en texto plano ni en base64. ¿Han visto filtraciones de
credenciales en repositorios públicos?"_

### Limpieza

```bash
kubectl delete -f 04-secret/
kubectl delete secret mis-credenciales 2>/dev/null; true
```

---

## Lab 05 — ServiceAccount + RBAC

### ¿Qué explicar? (7 min)

> *"Hasta ahora hablamos de cómo las personas se autentican en Kubernetes
> (kubectl con kubeconfig). Pero ¿qué pasa cuando una APP necesita hablar
> con la API de Kubernetes? Por ejemplo: un operador que escala pods,
> un pipeline de CI/CD que despliega, un dashboard que lista recursos."*

Dibujar en pizarrón:
```
¿Quién puede hacer qué?

PERSONAS    → kubeconfig + certificados
APLICACIONES → ServiceAccount + Token JWT

ServiceAccount → RoleBinding → Role → Permisos sobre recursos
```

**Conceptos RBAC:**
- `Role` — permisos dentro de un namespace (get, list, create, delete)
- `ClusterRole` — permisos en todo el cluster
- `RoleBinding` — conecta un Role con un Subject (user, group, serviceaccount)

### Demo en vivo (instructor)

```bash
cat 05-serviceaccount/01-serviceaccount.yaml
cat 05-serviceaccount/02-role-rolebinding.yaml

# Señalar: resources, verbs — el principio de mínimo privilegio
# Solo puede hacer GET/LIST/WATCH en pods y configmaps
# NO puede borrar, NO puede crear, NO puede tocar secrets

kubectl apply -f 05-serviceaccount/01-serviceaccount.yaml
kubectl apply -f 05-serviceaccount/02-role-rolebinding.yaml

kubectl get serviceaccounts
kubectl describe rolebinding pod-reader-binding
```

**Verificar permisos con `can-i` — muy útil para troubleshooting:**
```bash
kubectl auth can-i list pods \
  --as=system:serviceaccount:bootcamp:app-serviceaccount -n bootcamp
# → yes

kubectl auth can-i delete pods \
  --as=system:serviceaccount:bootcamp:app-serviceaccount -n bootcamp
# → no

kubectl auth can-i create deployments \
  --as=system:serviceaccount:bootcamp:app-serviceaccount -n bootcamp
# → no
```

**Explicar `--as`:** _"Puedes simular ser cualquier ServiceAccount para verificar
sus permisos. Muy útil cuando una app dice 'forbidden' y no sabes por qué."_

```bash
# Pod que llama a la API con su token
kubectl apply -f 05-serviceaccount/03-pod-con-serviceaccount.yaml
kubectl logs pod-api-caller
# Ver el token JWT montado automáticamente
```

**Mostrar dónde está el token dentro del pod:**
```bash
kubectl exec pod-api-caller -- ls /var/run/secrets/kubernetes.io/serviceaccount/
# token  ca.crt  namespace
```

### Ejercicio — Los alumnos hacen (8 min)

```bash
# 1. Verificar qué puede hacer el SA default
kubectl auth can-i list pods \
  --as=system:serviceaccount:bootcamp:default -n bootcamp

# 2. Crear un SA que SOLO pueda ver ConfigMaps
cat << 'EOF' | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: config-reader
  namespace: bootcamp
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: configmap-reader
  namespace: bootcamp
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: config-reader-binding
  namespace: bootcamp
subjects:
- kind: ServiceAccount
  name: config-reader
  namespace: bootcamp
roleRef:
  kind: Role
  name: configmap-reader
  apiGroup: rbac.authorization.k8s.io
EOF

# 3. Verificar permisos
kubectl auth can-i list configmaps \
  --as=system:serviceaccount:bootcamp:config-reader -n bootcamp
# → yes

kubectl auth can-i list pods \
  --as=system:serviceaccount:bootcamp:config-reader -n bootcamp
# → no
```

**Discusión:** _"¿Por qué el principio de mínimo privilegio es importante?
Si comprometen un pod, ¿qué puede hacer el atacante con ese ServiceAccount?"_

### Limpieza

```bash
kubectl delete -f 05-serviceaccount/
kubectl delete sa config-reader 2>/dev/null; true
kubectl delete role configmap-reader 2>/dev/null; true
kubectl delete rolebinding config-reader-binding 2>/dev/null; true
```

---

## Lab 06 — Deployment

### ¿Qué explicar? (8 min)

> *"Hasta ahora creamos Pods directamente. Pero si el Pod muere, no regresa.
> Un Deployment es un 'supervisor' que garantiza que SIEMPRE haya N réplicas
> corriendo. Si un Pod muere, lo recrea. Si actualizas la imagen, lo hace
> sin downtime."*

Jerarquía (dibujar):
```
Deployment
  └── ReplicaSet  ← maneja el número de réplicas
        ├── Pod-1
        ├── Pod-2
        └── Pod-3
```

Al hacer un update, el Deployment crea un **nuevo ReplicaSet** y va
subiendo los nuevos pods mientras baja los viejos.

### Demo en vivo — Deployment básico (instructor)

```bash
cat 06-deployment/01-deployment.yaml
# Señalar: replicas, selector, strategy, livenessProbe, readinessProbe

kubectl apply -f 06-deployment/01-deployment.yaml
kubectl get pods --watch   # ver los 3 pods crearse

kubectl get deployment
kubectl get replicaset
kubectl get pods -o wide   # ← distribuidos en los 3 workers!
```

**Señalar:** _"El scheduler distribuyó los pods en workers distintos automáticamente.
Alta disponibilidad sin configuración extra."_

```bash
kubectl describe deployment nginx-deployment
# Señalar: RollingUpdate, liveness/readiness probes
```

**Explicar las Probes:**
- `livenessProbe`: si falla → Kubernetes reinicia el contenedor
- `readinessProbe`: si falla → Kubernetes saca el pod del Service (no le manda tráfico)

### Demo — Scaling

```bash
# Escalar a 5 réplicas
kubectl scale deployment nginx-deployment --replicas=5
kubectl get pods --watch

# ¿En qué workers están?
kubectl get pods -o wide
```

**Preguntar:** _"¿Qué pasa si escalamos a 0?"_
```bash
kubectl scale deployment nginx-deployment --replicas=0
kubectl get pods   # → No resources found
kubectl scale deployment nginx-deployment --replicas=3
```

### Demo — Rolling Update (momento más importante del lab)

```bash
# Terminal 1: observar en tiempo real
kubectl get pods --watch &

# Actualizar imagen
kubectl set image deployment/nginx-deployment nginx=nginx:1.26
kubectl rollout status deployment/nginx-deployment
```

**Señalar mientras sucede:**
- _"¿Ven que nunca se caen todos los pods al mismo tiempo?"_
- _"maxUnavailable:1 y maxSurge:1 garantizan que siempre hay al menos 2/3 pods activos"_

```bash
# Ver el historial
kubectl rollout history deployment/nginx-deployment
kubectl rollout history deployment/nginx-deployment --revision=1
kubectl rollout history deployment/nginx-deployment --revision=2
```

### Demo — Rollback

```bash
# Simular un error: imagen que no existe
kubectl set image deployment/nginx-deployment nginx=nginx:version-no-existe
kubectl get pods --watch
```

**Señalar:** _"Los pods viejos siguen corriendo. El servicio NO se cae.
Kubernetes no baja lo viejo hasta que lo nuevo esté listo."_

```bash
kubectl describe pod $(kubectl get pods | grep -v Running | grep nginx | awk 'NR==1{print $1}') | tail -8
# → ErrImagePull / ImagePullBackOff

# Recuperar con rollback
kubectl rollout undo deployment/nginx-deployment
kubectl rollout status deployment/nginx-deployment
kubectl describe deployment nginx-deployment | grep Image
```

### Ejercicio — Los alumnos hacen (10 min)

**Ejercicio guiado:**
```bash
# 1. Desplegar el deployment completo con ConfigMap y Secret
kubectl apply -f 06-deployment/02-deployment-con-config.yaml

# 2. Verificar que los pods tienen las variables
kubectl get pods -l app=webapp
kubectl exec $(kubectl get pods -l app=webapp -o jsonpath='{.items[0].metadata.name}') \
  -- env | grep APP_ENV

# 3. Escalar a 4 réplicas
kubectl scale deployment webapp-deployment --replicas=4

# 4. Simular un fallo de liveness probe:
# Entrar a un pod y matar el proceso nginx
kubectl exec -it $(kubectl get pods -l app=webapp -o jsonpath='{.items[0].metadata.name}') \
  -- nginx -s stop
# ¿Qué pasa? Observar con kubectl get pods --watch
```

**Punto de discusión:** _"La livenessProbe detectó que nginx murió y reinició
el contenedor automáticamente. Ese es el self-healing de Kubernetes."_

### Limpieza

```bash
kubectl delete -f 06-deployment/
```

---

## Lab 07 — Service

### ¿Qué explicar? (7 min)

> *"Los pods tienen IPs efímeras — cambian cada vez que se recrean.
> Si el frontend tiene hardcodeada la IP del backend, se rompe cada vez
> que el backend escala o se reinicia. El Service resuelve esto:
> es una IP virtual estable + nombre DNS + balanceo de carga."*

```
Sin Service:                    Con Service:
Frontend → 10.244.1.5 ✗        Frontend → backend-service ✓
           10.244.2.3 ✗                    ↓ (siempre disponible)
           (cambian siempre)     [Pod-1] [Pod-2] [Pod-3]
```

**Tipos de Service:**
- `ClusterIP` — solo dentro del cluster (default)
- `NodePort` — expone en un puerto del nodo (30000-32767)
- `LoadBalancer` — IP externa vía proveedor cloud

### Demo en vivo (instructor)

```bash
kubectl apply -f 07-service/01-service-clusterip.yaml
kubectl get service
kubectl get endpoints backend-service
```

**Señalar:** _"Los endpoints son las IPs reales de los Pods que están detrás
del Service. Cuando el pod muere y se recrea con nueva IP, los endpoints
se actualizan automáticamente."_

```bash
kubectl describe service backend-service
# Selector: app=backend — así encuentra los pods
```

**Demostrar cómo los labels conectan Service con Pods:**
```bash
kubectl get pods -l app=backend
# Mismo resultado que los endpoints
```

### Demo — DNS interno

```bash
kubectl apply -f 07-service/04-comunicacion-entre-servicios.yaml
kubectl logs pod-test-dns
```

**Señalar en los logs:**
```
# Nombre corto — funciona en el mismo namespace
backend-service → 10.99.x.x ✓

# FQDN — funciona desde cualquier namespace
backend-service.bootcamp.svc.cluster.local → 10.99.x.x ✓
```

**Preguntar:** _"Si tengo un pod en el namespace `prod` y quiero llamar
a un servicio en `dev`, ¿qué nombre uso?"_
→ `nombre-servicio.dev.svc.cluster.local`

### Demo — NodePort

```bash
kubectl apply -f 07-service/02-service-nodeport.yaml
kubectl get service

# Probar desde master (después del fix de firewall)
curl http://192.168.109.143:30080
curl http://192.168.109.144:30080
curl http://192.168.109.145:30080
```

**Señalar:** _"El request puede llegar a cualquier worker y Kubernetes
lo redirige al pod correcto, independientemente de en qué worker esté."_

### Ejercicio — Los alumnos hacen (8 min)

```bash
# 1. Ver cuántos endpoints tiene el service
kubectl get endpoints backend-service

# 2. Escalar el deployment y observar cómo cambian los endpoints
kubectl scale deployment backend-deployment --replicas=5
kubectl get endpoints backend-service
# ¿Cuántos endpoints hay ahora?

# 3. Desafío: cambiar el label de un pod y ver qué pasa
POD=$(kubectl get pods -l app=backend -o jsonpath='{.items[0].metadata.name}')
kubectl label pod $POD app=otro-label --overwrite
kubectl get endpoints backend-service
# ¿Cuántos endpoints quedan?

# Restaurar
kubectl label pod $POD app=backend --overwrite
```

**Conclusión:** _"El Service no conoce los pods por nombre — los encuentra
por labels. Si un pod no tiene el label correcto, no recibe tráfico."_

### Limpieza

```bash
kubectl delete -f 07-service/
```

---

## Lab 08 — Ejercicio Integrador

### ¿Qué explicar? (3 min)

> *"Ahora van a desplegar todo lo que aprendieron hoy en un solo comando.
> Una aplicación real con: namespace propio, identidad, configuración,
> secretos, réplicas y exposición al exterior."*

### Demo — Despliegue completo

```bash
cat 08-ejercicio-integrador/todo-en-uno.yaml
# Recorrer el archivo señalando cada recurso

kubectl apply -f 08-ejercicio-integrador/todo-en-uno.yaml
kubectl get all -n mi-app
```

```bash
# Acceder a la app
curl http://192.168.109.144:30090
```

**Señalar en el HTML:** _"Esta página viene directamente del ConfigMap,
montado como volumen en el pod nginx. No está en la imagen Docker."_

### Ejercicio final — Los alumnos resuelven solos (15 min)

**Instrucciones para los alumnos:**

```bash
# NIVEL 1: Exploración (todos)
# Respondan estas preguntas usando solo kubectl:

# 1. ¿En qué nodos están corriendo los 3 pods?
kubectl get pods -n mi-app -o wide

# 2. ¿Cuál es la IP del Service?
kubectl get service -n mi-app

# 3. ¿Cuántos endpoints tiene el service?
kubectl get endpoints mi-app-service -n mi-app

# 4. ¿Qué archivos hay montados en /usr/share/nginx/html?
kubectl exec -n mi-app \
  $(kubectl get pods -n mi-app -o jsonpath='{.items[0].metadata.name}') \
  -- ls /usr/share/nginx/html

# 5. ¿Cuál es el valor del API_KEY (decodificado)?
kubectl get secret mi-app-secret -n mi-app \
  -o jsonpath='{.data.API_KEY}' | base64 -d
```

```bash
# NIVEL 2: Modificar en caliente (intermedios)
# Cambiar el contenido de la página web sin reiniciar los pods

kubectl edit configmap mi-app-config -n mi-app
# Editar la sección index.html → agregar tu nombre
# Guardar y esperar ~60 segundos
curl http://192.168.109.144:30090
# ¿Cambió la página?
```

```bash
# NIVEL 3: Escalar y actualizar (avanzados)
kubectl scale deployment mi-app-deployment --replicas=5 -n mi-app
kubectl set image deployment/mi-app-deployment app=nginx:1.26 -n mi-app
kubectl rollout status deployment/mi-app-deployment -n mi-app
kubectl rollout undo deployment/mi-app-deployment -n mi-app
```

```bash
# NIVEL 4: Self-healing (todos)
# Borrar un pod y observar que se recrea solo
kubectl delete pod \
  $(kubectl get pods -n mi-app -o jsonpath='{.items[0].metadata.name}') \
  -n mi-app
kubectl get pods -n mi-app --watch
# ¿Cuántos pods hay? ¿Kubernetes recreó el que borraste?
```

---

## Cierre de Clase (5 min)

### Resumen de lo aprendido

| Recurso | Para qué sirve | Ejemplo del día |
|---------|---------------|-----------------|
| Namespace | Aislar entornos | `bootcamp`, `mi-app` |
| Pod | Ejecutar contenedores | `pod-nginx`, `pod-sidecar` |
| ConfigMap | Configuración no sensible | `app-config`, página HTML |
| Secret | Contraseñas y tokens | `db-credentials`, `API_KEY` |
| ServiceAccount | Identidad de apps | `app-serviceaccount` |
| Deployment | Gestionar réplicas | `nginx-deployment` rolling update |
| Service | Exponer y descubrir | `backend-service`, NodePort |

### Preguntas frecuentes

**¿Por qué no usar Pods directamente en producción?**
Porque no tienen auto-restart. Un Deployment sí.

**¿Cuándo usar ConfigMap vs Secret?**
Contraseñas → Secret. Todo lo demás → ConfigMap.

**¿Qué pasa si borro un namespace?**
Se borran TODOS los recursos dentro. Es la forma más rápida de limpiar.

### Limpieza final

```bash
kubectl delete namespace mi-app
kubectl delete namespace bootcamp
kubectl get namespaces   # verificar que quedó limpio
```

### Tarea para la próxima clase

_"Antes de la próxima clase, intenten responder:_
1. _¿Qué pasa cuando una app necesita guardar datos que sobrevivan al reinicio del Pod?_
2. _¿Cómo expondrías múltiples servicios en el puerto 80 con diferentes rutas?_

_Esas preguntas las respondemos con **PersistentVolumes** e **Ingress**."_

---

## Troubleshooting frecuente en clase

| Síntoma | Causa probable | Solución |
|---------|---------------|----------|
| Pod en `ImagePullBackOff` | Imagen no existe o registry privado | Verificar nombre de imagen |
| Pod en `CrashLoopBackOff` | App falla al arrancar | `kubectl logs <pod> --previous` |
| Service sin endpoints | Labels no coinciden | Verificar `selector` vs `labels` del pod |
| `kubectl get all --watch` falla | Bug kubectl 1.28 con `all` | Usar `kubectl get pods --watch` |
| NodePort "No route to host" | firewalld nftables vs kube-proxy iptables | `FirewallBackend=iptables` en workers |
| DNS interno falla desde pods | flannel.1/cni0 sin zona en firewalld | Agregar a zona trusted en master |
| Secret no decodifica bien | Espacios o newline en base64 | Usar `echo -n` (sin newline) |

---

*Repo del curso: github.com/dguerrero11/bootcampkubernetes*
*En el cluster: `cd /root/kubernetes && git pull`*
