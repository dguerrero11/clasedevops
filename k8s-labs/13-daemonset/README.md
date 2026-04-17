# Lab 13 - DaemonSet

## Concepto

DaemonSet garantiza **exactamente 1 Pod por nodo**.

```
Cluster (4 nodos):
  master01     → [log-agent-xxxx]
  k8s-worker01 → [log-agent-yyyy]
  k8s-worker02 → [log-agent-zzzz]
  k8s-worker03 → [log-agent-wwww]

  Agregar nodo → pod creado automáticamente
  Eliminar nodo → pod destruido automáticamente
```

## Ya tienes DaemonSets en tu cluster

```bash
kubectl get daemonset -n kube-system
# kube-proxy: 4 desired, 4 ready

kubectl get daemonset -n kube-flannel
# kube-flannel-ds: 4 desired, 4 ready
```

## Tolerations — correr en el nodo master

El nodo `control-plane` tiene un **taint** que impide que pods normales corran ahí:
```
node-role.kubernetes.io/control-plane:NoSchedule
```

Para que el DaemonSet también corra en el master, se necesita una **toleration**:
```yaml
tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
```

Sin esto, el DaemonSet solo correría en los 3 workers.

## Comandos

```bash
# Aplicar
kubectl apply -f 01-daemonset-log-agent.yaml

# Ver 1 pod por nodo
kubectl get pods -l app=log-agent -o wide

# Contar: debe ser igual al número de nodos
kubectl get nodes --no-headers | wc -l
kubectl get pods -l app=log-agent --no-headers | wc -l

# Ver logs del agente en un nodo específico
kubectl logs -l app=log-agent \
  --field-selector spec.nodeName=k8s-worker01

# Mantenimiento de nodo
kubectl cordon k8s-worker03       # no acepta nuevos pods
kubectl drain k8s-worker03 \
  --ignore-daemonsets \           # DaemonSets se ignoran en drain
  --delete-emptydir-data

# Volver a servicio
kubectl uncordon k8s-worker03
```

## Ejercicios

### Ejercicio 1 — Verificar cobertura total
```bash
kubectl apply -f 01-daemonset-log-agent.yaml
kubectl get pods -l app=log-agent -o wide

# ¿Está en el master también?
kubectl get pods -l app=log-agent -o wide | grep master
```

### Ejercicio 2 — Quitar toleration y ver qué pasa
```bash
kubectl edit daemonset log-agent
# Borrar la sección de tolerations y guardar

# ¿El pod del master se elimina?
kubectl get pods -l app=log-agent -o wide --watch
```

### Ejercicio 3 — Cordon y drain
```bash
kubectl cordon k8s-worker03
kubectl get nodes   # STATUS: SchedulingDisabled

# ¿El pod del DaemonSet en worker03 sigue corriendo?
kubectl get pods -l app=log-agent -o wide
# Sí — DaemonSet ignora el cordon

kubectl uncordon k8s-worker03
```

## Comparar con kube-proxy (DaemonSet real)

```bash
kubectl describe daemonset kube-proxy -n kube-system | head -20
# Fijarse en: Node-Selector, Tolerations, Update Strategy
```

## Limpieza

```bash
kubectl delete -f 01-daemonset-log-agent.yaml
```
