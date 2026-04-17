# Lab 08 - Ejercicio Integrador

## Objetivo

Desplegar una aplicación web completa usando **todos los recursos** aprendidos:

```
Namespace
  └── ServiceAccount
  └── ConfigMap
  └── Secret
  └── Deployment (usa SA + ConfigMap + Secret)
        └── Pod x3 (con volumeMount del ConfigMap)
  └── Service NodePort
```

## Despliegue

```bash
# Desplegar todo con un solo comando
kubectl apply -f todo-en-uno.yaml

# Verificar que todo esté corriendo
kubectl get all -n mi-app

# Ver los pods con más detalle
kubectl get pods -n mi-app -o wide

# Esperar a que todos los pods estén Ready
kubectl rollout status deployment/mi-app-deployment -n mi-app
```

## Acceder a la app

```bash
# Obtener IP del nodo
kubectl get nodes -o wide

# Acceder via NodePort
curl http://<NODE_IP>:30090

# O con port-forward
kubectl port-forward service/mi-app-service 8080:80 -n mi-app
# → http://localhost:8080
```

## Desafíos del ejercicio integrador

### Nivel 1 — Exploración
Responde estas preguntas usando solo `kubectl`:
1. ¿Cuántos pods están corriendo? ¿En qué nodos?
2. ¿Cuál es la IP del Service? ¿Y los endpoints?
3. ¿Cuál es el valor del API_KEY en los pods (decodificado)?
4. ¿Qué archivo está montado en `/usr/share/nginx/html`?

```bash
# Pistas:
kubectl get pods -n mi-app -o wide
kubectl get endpoints mi-app-service -n mi-app
kubectl exec -n mi-app <pod> -- env | grep API_KEY
kubectl exec -n mi-app <pod> -- ls /usr/share/nginx/html
```

### Nivel 2 — Modificar la app en caliente
1. Edita el ConfigMap para cambiar el contenido de `index.html`:
   ```bash
   kubectl edit configmap mi-app-config -n mi-app
   ```
2. Espera ~1 minuto y recarga la página
3. ¿Actualizó sin reiniciar los pods?

### Nivel 3 — Escalar y actualizar
1. Escala el deployment a 5 réplicas
2. Actualiza la imagen a `nginx:1.26` con rolling update
3. Monitorea el rollout con `--watch`
4. Haz rollback al finalizar

### Nivel 4 — Provocar y recuperar fallos
1. Borra un pod manualmente: `kubectl delete pod <nombre> -n mi-app`
2. ¿Qué pasa? ¿Cuántos pods hay después?
3. Escala a 0 réplicas: `kubectl scale deployment mi-app-deployment --replicas=0 -n mi-app`
4. ¿Qué pasa al acceder al servicio?
5. Vuelve a 3 réplicas

### Nivel 5 — Desafío final
Sin borrar el namespace, modifica la aplicación para:
- Agregar un sidecar container que imprima la fecha cada 10 segundos
- Agregar una variable de entorno `BOOTCAMP_ALUMNO` con tu nombre (desde un nuevo ConfigMap)
- Cambiar el Service a tipo `ClusterIP` y verifica que solo es accesible dentro del cluster

## Limpieza

```bash
# Borrar todo el namespace (elimina todos los recursos dentro)
kubectl delete namespace mi-app

# Verificar que se borró
kubectl get all -n mi-app
```

> **Pro tip:** Borrar el namespace es la forma más rápida de limpiar todos los recursos de una app.
