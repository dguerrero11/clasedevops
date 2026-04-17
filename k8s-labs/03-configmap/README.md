# Lab 03 - ConfigMap

## Concepto

Un **ConfigMap** almacena configuración no sensible (sin contraseñas).
Permite que la misma imagen Docker funcione en distintos entornos cambiando solo el ConfigMap.

## Formas de uso

```
ConfigMap → Pod
  ├── envFrom          → todas las claves como variables de entorno
  ├── env.valueFrom    → clave específica como variable de entorno
  └── volumeMount      → cada clave como un archivo en un directorio
```

## Comandos esenciales

```bash
# Crear desde YAML
kubectl apply -f 01-configmap-literal.yaml

# Crear imperativo (clave=valor)
kubectl create configmap mi-config \
  --from-literal=APP_ENV=dev \
  --from-literal=APP_PORT=3000

# Crear desde archivo
kubectl create configmap nginx-config --from-file=nginx.conf

# Ver el ConfigMap
kubectl get configmap app-config
kubectl describe configmap app-config
kubectl get configmap app-config -o yaml

# Editar en caliente (los Pods con volumen lo leen sin reiniciar)
kubectl edit configmap app-config
```

## Ejercicios

### Ejercicio 1 — Env vars desde ConfigMap
1. Aplica `01-configmap-literal.yaml`
2. Aplica `02-pod-con-configmap-envvar.yaml`
3. Lee los logs: `kubectl logs pod-config-env`
4. Verifica que las variables están seteadas: `kubectl exec pod-config-env -- env | grep APP`

### Ejercicio 2 — Archivos desde volumen
1. Aplica `03-pod-con-configmap-volumen.yaml`
2. Lee los logs: `kubectl logs pod-config-vol`
3. Entra al pod: `kubectl exec -it pod-config-vol -- sh`
4. Navega a `/etc/app-config/` y explora los archivos

### Ejercicio 3 — Actualización en caliente
1. Edita el ConfigMap: `kubectl edit configmap app-config`
2. Cambia el valor de `APP_LOG_LEVEL` a `debug`
3. Espera ~1 minuto
4. Entra al pod con volumen y verifica si el archivo cambió
5. ¿Cambió también la variable de entorno? ¿Por qué? (Respuesta: NO, las env vars requieren reinicio del Pod)

### Ejercicio 4 — Desafío
Crea un ConfigMap con una config de nginx personalizada y monta en un Pod nginx para que sirva una página custom.

## Limpieza

```bash
kubectl delete -f .
```
