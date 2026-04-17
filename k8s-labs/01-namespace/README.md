# Lab 01 - Namespace

## Concepto

Un **Namespace** divide un cluster de Kubernetes en entornos virtuales independientes.
Útil para multi-equipo o multi-entorno (dev / staging / prod).

## Comandos esenciales

```bash
# Ver todos los namespaces
kubectl get namespaces

# Crear desde YAML
kubectl apply -f namespace.yaml

# Crear imperativo
kubectl create namespace bootcamp

# Establecer namespace por defecto en el contexto actual
kubectl config set-context --current --namespace=bootcamp

# Ver en qué namespace estás trabajando
kubectl config view --minify | grep namespace

# Ver recursos en un namespace específico
kubectl get all -n bootcamp

# Ver recursos en TODOS los namespaces
kubectl get all -A
```

## Ejercicio

1. Crea un namespace llamado `dev` y otro llamado `prod`
2. Lista todos los namespaces y verifica que existen
3. Establece `dev` como namespace activo en tu contexto
4. Verifica que el cambio se aplicó

## Limpieza

```bash
kubectl delete namespace dev
kubectl delete namespace prod
# Volver al namespace bootcamp
kubectl config set-context --current --namespace=bootcamp
```
