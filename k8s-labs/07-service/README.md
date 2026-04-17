# Lab 07 - Service

## Concepto

Un **Service** es una abstracción estable que expone un conjunto de Pods.
Los Pods tienen IPs efímeras — el Service provee:
- **IP virtual estable** (ClusterIP)
- **Nombre DNS** resolvible desde cualquier Pod del cluster
- **Load balancing** entre todas las réplicas

## Tipos de Service

```
ClusterIP (default)
  → IP interna del cluster, solo accesible dentro del cluster
  → DNS: <service>.<namespace>.svc.cluster.local

NodePort
  → Expone un puerto en cada nodo del cluster
  → Acceso: http://<IP-nodo>:<nodePort>

LoadBalancer
  → Solicita IP externa al proveedor cloud (AWS/GCP/Azure)
  → En bare-metal necesita MetalLB

ExternalName
  → Alias DNS a un servicio externo (ej: mi-db → rds.aws.com)
```

## Cómo funciona el selector

```yaml
# El Service tiene:
selector:
  app: backend

# El Pod tiene en sus labels:
labels:
  app: backend     ← El Service lo selecciona
```

Si el Pod no tiene el label → el Service **no** lo incluye.

## DNS interno de Kubernetes

Desde cualquier Pod:
```bash
# Mismo namespace
curl http://backend-service/

# Otro namespace
curl http://backend-service.bootcamp.svc.cluster.local/

# Ver todos los DNS
cat /etc/resolv.conf
```

## Comandos esenciales

```bash
# Aplicar servicios
kubectl apply -f 01-service-clusterip.yaml

# Ver servicios
kubectl get services
kubectl get svc

# Ver detalles (incluyendo Endpoints = IPs de los Pods)
kubectl describe service backend-service

# Ver endpoints (IPs reales de los Pods que reciben tráfico)
kubectl get endpoints backend-service

# Port-forward a un servicio (para pruebas locales)
kubectl port-forward service/backend-service 8080:80

# Acceso a NodePort (reemplaza con IP de tu nodo)
kubectl get nodes -o wide    # ver IPs de los nodos
curl http://<NODE_IP>:30080

# Crear service imperativo
kubectl expose deployment nginx-deployment --port=80 --type=NodePort
```

## Ejercicios

### Ejercicio 1 — ClusterIP básico
1. Aplica `01-service-clusterip.yaml` (crea Deployment + Service)
2. Verifica el servicio: `kubectl get svc backend-service`
3. ¿Tiene IP asignada? ¿Cuál es?
4. Verifica los endpoints: `kubectl get endpoints backend-service`
5. Haz port-forward y accede desde tu navegador

### Ejercicio 2 — DNS interno
1. Asegúrate de que el backend-service esté corriendo
2. Aplica `04-comunicacion-entre-servicios.yaml`
3. Lee los logs: `kubectl logs pod-test-dns`
4. ¿Pudo resolver el nombre? ¿Pudo hacer curl?

### Ejercicio 3 — NodePort
1. Aplica el deployment del lab 06 si no lo tienes
2. Aplica `02-service-nodeport.yaml`
3. Obtén la IP del nodo: `kubectl get nodes -o wide`
4. Accede desde tu navegador: `http://<NODE_IP>:30080`

### Ejercicio 4 — Labels y selectors
1. Modifica el label de un pod del backend: `kubectl label pod <nombre> app=otro-label --overwrite`
2. ¿Cambia el número de endpoints del service? `kubectl get endpoints backend-service`
3. ¿Qué conclusión sacas sobre cómo funciona el selector?

### Ejercicio 5 — Desafío
Despliega dos versiones de una app (v1 y v2) con distintos labels.
Crea un Service que apunte a v1 y luego cambia el selector para apuntar a v2.
Esto simula un **blue-green deployment**.

## Limpieza

```bash
kubectl delete -f .
```
