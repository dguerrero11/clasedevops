# Lab 09 - Almacenamiento en Kubernetes

## Concepto

Por defecto el almacenamiento de un Pod es **efímero** — si el Pod muere, los datos desaparecen.
Kubernetes ofrece distintos tipos de volúmenes según la necesidad:

| Tipo | Persistencia | Uso |
|------|-------------|-----|
| `emptyDir` | Dura lo que el Pod | Compartir datos entre contenedores del mismo Pod |
| `hostPath` | Dura lo que el Nodo | Acceso a archivos del nodo (logs, docker socket) |
| `nfs` | Permanente | Compartir datos entre Pods en distintos nodos |
| `PersistentVolume` | Permanente | Almacenamiento gestionado por el cluster |

## Jerarquía de Storage en Kubernetes

```
StorageClass  (define CÓMO aprovisionar)
     ↓
PersistentVolume - PV  (el disco real)
     ↓
PersistentVolumeClaim - PVC  (la solicitud del desarrollador)
     ↓
Pod  (monta el PVC como volumen)
```

## Problema del almacenamiento efímero

```bash
# Demostrar que los datos no persisten
kubectl run pod-efimero --image=busybox:1.36 \
  --command -- sh -c "echo 'dato importante' > /tmp/datos.txt && sleep 3600"

kubectl exec pod-efimero -- cat /tmp/datos.txt   # existe

kubectl delete pod pod-efimero
kubectl run pod-efimero --image=busybox:1.36 \
  --command -- sh -c "sleep 3600"

kubectl exec pod-efimero -- cat /tmp/datos.txt   # No such file!
kubectl delete pod pod-efimero
```

## Comandos esenciales

```bash
kubectl get pv                     # PersistentVolumes (cluster-wide)
kubectl get pvc                    # PersistentVolumeClaims (namespace)
kubectl get storageclass           # StorageClasses disponibles
kubectl describe pvc <nombre>      # ver estado del binding y eventos
kubectl get pv -o wide             # ver política de reclamación
```

## Ejercicios

### Ejercicio 1 — emptyDir
1. Aplica `01-emptydir-demo.yaml`
2. Observa los logs del reader: `kubectl logs pod-emptydir -c reader -f`
3. ¿Qué pasa si el contenedor `writer` se reinicia? ¿Los datos persisten?
4. ¿Qué pasa si borras el Pod completo?

### Ejercicio 2 — hostPath
1. Aplica `02-hostpath-demo.yaml`
2. ¿En qué nodo está el pod? `kubectl get pod pod-hostpath -o wide`
3. Conecta al nodo via SSH y verifica el archivo:
   `ssh root@<IP-nodo> "cat /var/log/k8s-test.log"`
4. Borra el pod, recréalo en el mismo nodo. ¿Persiste el archivo?

## Limpieza

```bash
kubectl delete pod pod-emptydir pod-hostpath --ignore-not-found
```
