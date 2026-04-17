# Kubernetes Cheatsheet — Bootcamp

## Setup inicial

```bash
kubectl create namespace bootcamp
kubectl config set-context --current --namespace=bootcamp
```

## Comandos más usados

### Ver recursos
```bash
kubectl get pods                         # pods del namespace activo
kubectl get pods -A                      # pods de todos los namespaces
kubectl get pods -o wide                 # + IP y nodo
kubectl get pods --watch                 # en tiempo real
kubectl get all                          # todos los recursos
kubectl get all -n bootcamp              # en namespace específico
```

### Inspeccionar
```bash
kubectl describe pod <nombre>            # eventos, estado, probes
kubectl describe deployment <nombre>
kubectl logs <pod>                       # logs del pod
kubectl logs <pod> -c <contenedor>       # contenedor específico
kubectl logs <pod> -f                    # seguimiento en tiempo real
kubectl logs <pod> --previous            # logs del contenedor anterior
```

### Ejecutar
```bash
kubectl exec -it <pod> -- bash           # terminal interactiva
kubectl exec -it <pod> -- sh             # si no tiene bash
kubectl exec <pod> -- <comando>          # ejecutar un comando
```

### Port-forward
```bash
kubectl port-forward pod/<nombre> 8080:80
kubectl port-forward service/<nombre> 8080:80
kubectl port-forward deployment/<nombre> 8080:80
```

### Crear / Actualizar / Borrar
```bash
kubectl apply -f archivo.yaml            # crear o actualizar
kubectl apply -f directorio/             # todos los YAML del directorio
kubectl delete -f archivo.yaml           # borrar lo que define el archivo
kubectl delete pod <nombre>              # borrar pod específico
kubectl delete namespace <nombre>        # borra el namespace y TODO lo que contiene
```

### Deployment
```bash
kubectl scale deployment <nombre> --replicas=5
kubectl set image deployment/<nombre> <container>=<imagen>:<tag>
kubectl rollout status deployment/<nombre>
kubectl rollout history deployment/<nombre>
kubectl rollout undo deployment/<nombre>
kubectl rollout undo deployment/<nombre> --to-revision=2
```

### Labels y filtros
```bash
kubectl get pods -l app=nginx            # filtrar por label
kubectl get pods -l app=nginx,env=prod   # múltiples labels
kubectl label pod <nombre> env=test      # agregar label
kubectl label pod <nombre> env=prod --overwrite  # modificar label
```

### ConfigMap y Secret
```bash
kubectl create configmap <nombre> --from-literal=KEY=VALUE
kubectl create secret generic <nombre> --from-literal=KEY=VALUE
kubectl get configmap <nombre> -o yaml
kubectl get secret <nombre> -o yaml
kubectl edit configmap <nombre>          # editar en caliente
```

### RBAC
```bash
kubectl auth can-i <verbo> <recurso>
kubectl auth can-i list pods --as=system:serviceaccount:<ns>:<sa>
kubectl get roles -n <namespace>
kubectl get rolebindings -n <namespace>
```

### Nodos
```bash
kubectl get nodes
kubectl get nodes -o wide                # con IPs
kubectl describe node <nombre>
kubectl cordon <nodo>                    # no schedular más pods
kubectl uncordon <nodo>                  # volver a schedular
kubectl drain <nodo>                     # vaciar el nodo (mantenimiento)
```

### Contextos
```bash
kubectl config get-contexts              # ver todos los contextos
kubectl config use-context <nombre>      # cambiar contexto
kubectl config set-context --current --namespace=<ns>  # cambiar namespace
kubectl config view --minify             # ver contexto actual
```

## Recursos y sus abreviaciones

| Recurso | Abreviación |
|---------|-------------|
| pods | po |
| services | svc |
| deployments | deploy |
| replicasets | rs |
| namespaces | ns |
| configmaps | cm |
| serviceaccounts | sa |
| persistentvolumes | pv |
| persistentvolumeclaims | pvc |
| nodes | no |

## Verbos RBAC

`get` `list` `watch` `create` `update` `patch` `delete` `deletecollection`

## Estados de un Pod

| Estado | Significado |
|--------|-------------|
| `Pending` | Esperando ser asignado a un nodo |
| `Init:0/1` | Init containers corriendo |
| `Running` | Al menos un contenedor corriendo |
| `Completed` | Todos los contenedores terminaron OK |
| `Error` | Al menos un contenedor terminó con error |
| `CrashLoopBackOff` | El contenedor falla repetidamente, K8s espera para reintentar |
| `ImagePullBackOff` | No puede descargar la imagen |
| `Terminating` | El pod está siendo eliminado |
