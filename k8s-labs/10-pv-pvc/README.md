# Lab 10 - PersistentVolume y PersistentVolumeClaim

## Concepto

**PV** = el disco físico (lo gestiona el admin)
**PVC** = la solicitud del desarrollador (no sabe dónde está el disco)

```
ADMIN                     KUBERNETES               DEVELOPER
  │                           │                       │
  ├── Crea PV ───────────────►│                       │
  │   (disco NFS real)        │                       │
  │                           │◄──── Crea PVC ────────┤
  │                           │      "necesito 1Gi"   │
  │                           │                       │
  │                      BINDING                      │
  │              (busca PV compatible)                │
  │                           │                       │
  │                           │──── PVC Bound ───────►│
  │                           │                       │
  │                           │◄──── Pod usa PVC ─────┤
```

## Estados de un PVC

| Estado | Significado |
|--------|-------------|
| `Pending` | Buscando un PV compatible |
| `Bound` | Vinculado a un PV — listo para usar |
| `Lost` | El PV desapareció (problema grave) |

## Estados de un PV

| Estado | Significado |
|--------|-------------|
| `Available` | Libre, esperando ser reclamado |
| `Bound` | Vinculado a un PVC |
| `Released` | El PVC fue borrado, datos conservados (Retain) |
| `Failed` | Error en el aprovisionamiento |

## Modos de acceso y NFS

| Modo | Abrev | Descripción |
|------|-------|-------------|
| `ReadWriteOnce` | RWO | Solo 1 nodo monta en R/W |
| `ReadOnlyMany` | ROX | Múltiples nodos montan en R |
| `ReadWriteMany` | RWX | Múltiples nodos montan en R/W ← **NFS** |

## Comandos

```bash
# Ver PVs del cluster (sin namespace)
kubectl get pv
kubectl describe pv pv-nfs-clase2

# Ver PVCs del namespace
kubectl get pvc -n bootcamp
kubectl describe pvc pvc-bootcamp

# Ver qué PV está usando un PVC
kubectl get pvc pvc-bootcamp -o jsonpath='{.spec.volumeName}'

# Ver archivos en el servidor NFS
ssh root@192.168.109.210 "ls -la /srv/nfs/k8s-storage/"
```

## Ejercicios

### Ejercicio 1 — Crear PV y PVC manualmente
```bash
kubectl apply -f 01-pv-nfs.yaml
kubectl get pv                        # Estado: Available

kubectl apply -f 02-pvc.yaml
kubectl get pvc                        # Estado: Bound
kubectl get pv                         # Estado: Bound (tiene CLAIM)
```

### Ejercicio 2 — Probar persistencia
```bash
kubectl apply -f 03-pod-con-pvc.yaml
kubectl logs pod-con-pvc               # ver historial de arranques

kubectl delete pod pod-con-pvc
kubectl apply -f 03-pod-con-pvc.yaml
kubectl logs pod-con-pvc               # ¿aparece el arranque anterior?
```

### Ejercicio 3 — Dos pods, mismo volumen
```bash
kubectl apply -f 04-dos-pods-mismo-pvc.yaml
kubectl get pods -o wide               # ¿están en distintos nodos?
kubectl logs pod-lector -f             # ver datos del escritor en tiempo real
```

### Ejercicio 4 — reclaimPolicy Retain
```bash
kubectl delete pvc pvc-bootcamp
kubectl get pv pv-nfs-clase2           # Estado: Released (no Available!)
# Los datos siguen en el NFS
ssh root@192.168.109.210 "cat /srv/nfs/k8s-storage/historia.txt"
```

## Limpieza

```bash
kubectl delete pod pod-con-pvc pod-escritor pod-lector --ignore-not-found
kubectl delete pvc pvc-bootcamp --ignore-not-found
kubectl delete pv pv-nfs-clase2 --ignore-not-found
```
