# Lab 05 - ServiceAccount

## Concepto

Un **ServiceAccount** es la identidad de un Pod en el cluster.
Permite que aplicaciones llamen a la API de Kubernetes con permisos controlados.

```
Pod → ServiceAccount → RoleBinding → Role → Permisos sobre recursos
```

- Cada Pod usa el SA `default` si no se especifica otro
- El token JWT del SA se monta automáticamente en el Pod
- Los permisos se definen con **RBAC** (Role-Based Access Control)

## RBAC: Componentes

| Recurso | Scope | Descripción |
|---------|-------|-------------|
| `Role` | Namespace | Permisos dentro de un namespace |
| `ClusterRole` | Cluster | Permisos en todo el cluster |
| `RoleBinding` | Namespace | Asocia Role a un Subject |
| `ClusterRoleBinding` | Cluster | Asocia ClusterRole a un Subject |

## Comandos esenciales

```bash
# Crear ServiceAccount
kubectl apply -f 01-serviceaccount.yaml

# Aplicar RBAC
kubectl apply -f 02-role-rolebinding.yaml

# Ver ServiceAccounts
kubectl get serviceaccounts
kubectl describe serviceaccount app-serviceaccount

# Verificar permisos (can-i)
kubectl auth can-i list pods \
  --as=system:serviceaccount:bootcamp:app-serviceaccount \
  -n bootcamp

kubectl auth can-i delete deployments \
  --as=system:serviceaccount:bootcamp:app-serviceaccount \
  -n bootcamp

# Ver Roles y Bindings
kubectl get roles -n bootcamp
kubectl get rolebindings -n bootcamp
kubectl describe rolebinding pod-reader-binding
```

## Ejercicios

### Ejercicio 1 — Crear SA y verificar permisos
1. Aplica los 3 archivos en orden
2. Verifica qué puede hacer el SA:
   ```bash
   kubectl auth can-i list pods --as=system:serviceaccount:bootcamp:app-serviceaccount -n bootcamp
   kubectl auth can-i create pods --as=system:serviceaccount:bootcamp:app-serviceaccount -n bootcamp
   kubectl auth can-i delete secrets --as=system:serviceaccount:bootcamp:app-serviceaccount -n bootcamp
   ```

### Ejercicio 2 — Pod llama a la API
1. Aplica `03-pod-con-serviceaccount.yaml`
2. Lee los logs: `kubectl logs pod-api-caller`
3. ¿Qué pods puede ver? ¿Por qué solo ve los de ese namespace?

### Ejercicio 3 — SA sin permisos
1. Crea un pod igual pero con `serviceAccountName: default`
2. Intenta hacer el mismo curl a la API
3. ¿Qué error obtienes? ¿Por qué?

### Ejercicio 4 — Desafío RBAC
Crea un Role que permita:
- Listar y ver Deployments
- Leer ConfigMaps
- Crear y borrar Pods

Luego verifica con `kubectl auth can-i`

## Limpieza

```bash
kubectl delete -f .
```
