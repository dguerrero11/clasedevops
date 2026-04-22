# Clase 4 - Tekton + ArgoCD: GitOps CI/CD

## Objetivo

Implementar un pipeline GitOps completo: Tekton construye y publica la imagen de contenedor, ArgoCD detecta los cambios en Git y despliega automáticamente. Al terminar, un `git push` es el único comando necesario para llevar código a producción.

---

## Arquitectura

```
  Developer
     │
     │  git push
     ▼
  GitHub Repo
  ├── app/
  │   ├── index.html
  │   └── Dockerfile
  └── k8s/
      ├── deployment.yaml   ← ArgoCD lee esto
      └── service.yaml
     │
     │  PipelineRun (manual o webhook)
     ▼
  ┌──────────────────────────────────────────────────────┐
  │              Namespace: tekton-pipelines              │
  │                                                        │
  │  Task: git-clone          Task: build-push            │
  │  ┌──────────────┐         ┌──────────────────┐        │
  │  │ alpine/git   │────────►│ gcr.io/kaniko    │        │
  │  │ clona repo   │workspace│ build + push     │        │
  │  │ → /workspace │  NFS    │ → Docker Hub     │        │
  │  └──────────────┘  PVC    └──────────────────┘        │
  └──────────────────────────────────────────────────────┘
                                        │
                                        │ imagen:v2 pusheada
                                        ▼
  ┌──────────────────────────────────────────────────────┐
  │               Namespace: argocd                       │
  │                                                        │
  │  ArgoCD Application "mi-tienda"                       │
  │  ┌──────────────────────────────────────────────┐     │
  │  │ repoURL: github.com/usuario/k8s-gitops-demo  │     │
  │  │ path: k8s/                                   │     │
  │  │ syncPolicy: automated + selfHeal + prune     │     │
  │  └──────────────────────────────────────────────┘     │
  │              │ sync automático cada ~3 min             │
  └──────────────┼───────────────────────────────────────┘
                 │ kubectl apply
                 ▼
          Namespace: default
          Deployment "mi-tienda"
```

---

## Pre-requisitos

### Cluster
- Tekton Pipelines instalado
- StorageClass `nfs-csi` disponible (workspace del Pipeline)
- ArgoCD instalado en namespace `argocd`

### Alumno
- Cuenta en GitHub con repo `k8s-gitops-demo` (público)
- Cuenta en Docker Hub con token de acceso

---

## Paso 1 — Instalar Tekton

```bash
kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml

# Esperar a que todos los pods estén Running (~2 min)
kubectl get pods -n tekton-pipelines --watch
```

Instalar CLI:
```bash
curl -LO https://github.com/tektoncd/cli/releases/download/v0.35.0/tkn_0.35.0_Linux_x86_64.tar.gz
tar xzf tkn_0.35.0_Linux_x86_64.tar.gz -C /usr/local/bin tkn
tkn version
```

---

## Paso 2 — Crear Secret de Docker Hub

```bash
kubectl create secret docker-registry docker-credentials \
  --docker-server=docker.io \
  --docker-username=<TU_USUARIO> \
  --docker-password=<TU_TOKEN> \
  -n tekton-pipelines
```

---

## Paso 3 — Aplicar Tasks y Pipeline

```bash
kubectl apply -f task-git-clone.yaml
kubectl apply -f task-build-push.yaml
kubectl apply -f pipeline-build-deploy.yaml

# Verificar
kubectl get tasks -n tekton-pipelines
kubectl get pipelines -n tekton-pipelines
```

---

## Paso 4 — Lanzar el primer PipelineRun

Editar [`pipelinerun-demo.yaml`](pipelinerun-demo.yaml) y reemplazar `USUARIO` con tu usuario de GitHub y Docker Hub:

```yaml
params:
  - name: repo-url
    value: "https://github.com/TU_USUARIO/k8s-gitops-demo"
  - name: image
    value: "TU_USUARIO/mi-tienda:v1"
```

```bash
kubectl apply -f pipelinerun-demo.yaml

# Ver logs en tiempo real
tkn pipelinerun logs --last -f -n tekton-pipelines
```

---

## Paso 5 — Instalar ArgoCD

```bash
kubectl create namespace argocd

kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Esperar ~3 min
kubectl get pods -n argocd --watch
```

Exponer con NodePort:
```bash
kubectl patch svc argocd-server -n argocd \
  -p '{"spec":{"type":"NodePort","ports":[{"port":443,"nodePort":30443,"targetPort":8080,"protocol":"TCP"}]}}'
```

Obtener contraseña inicial:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

UI: `https://<IP-NODO>:30443` | User: `admin`

---

## Paso 6 — Crear la Application

Editar [`argocd-application.yaml`](argocd-application.yaml) con la URL de tu repo y aplicar:

```bash
kubectl apply -f argocd-application.yaml

# Verificar sincronización
kubectl get application -n argocd
# SYNC STATUS: Synced  |  HEALTH STATUS: Healthy
```

---

## Demo: commit → deploy automático

```bash
# 1. Modificar el código
vim app/index.html   # cambiar algo visible

# 2. Actualizar el tag de imagen en el manifiesto
vim k8s/deployment.yaml  # image: usuario/mi-tienda:v2

# 3. Push
git add . && git commit -m "feat: update to v2" && git push

# 4. Lanzar Pipeline para construir v2
# (editar pipelinerun-demo.yaml con tag v2 y aplicar de nuevo)
kubectl apply -f pipelinerun-demo.yaml
tkn pipelinerun logs --last -f -n tekton-pipelines

# 5. ArgoCD detecta el cambio y sincroniza automáticamente (~3 min)
# O forzar sync inmediato:
argocd app sync mi-tienda

# 6. Verificar rollout
kubectl rollout status deployment/mi-tienda
```

**Rollback desde ArgoCD UI:**
```
ArgoCD → mi-tienda → History and Rollback → seleccionar revisión anterior → Rollback
```

---

## Troubleshooting

### PipelineRun falla en el paso clone

```bash
tkn taskrun list -n tekton-pipelines
tkn taskrun logs <nombre-del-taskrun> -n tekton-pipelines

# Verificar que el PVC del workspace se creó
kubectl get pvc -n tekton-pipelines
```

Causas comunes: URL de repo mal escrita, repo privado sin credenciales, `nfs-csi` no disponible.

### Kaniko no puede hacer push

```bash
# Verificar que el Secret existe
kubectl get secret docker-credentials -n tekton-pipelines

# Verificar que el Secret tiene el formato correcto
kubectl get secret docker-credentials -n tekton-pipelines \
  -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d
```

### ArgoCD muestra OutOfSync pero no sincroniza

```bash
argocd app get mi-tienda | grep "Sync Policy"
argocd app get --refresh mi-tienda
argocd app diff mi-tienda
```

### ArgoCD no puede acceder al repo de GitHub

```bash
argocd repo list

# Agregar repo manualmente (si es privado)
argocd repo add https://github.com/usuario/k8s-gitops-demo \
  --username <user> --password <token>
```

---

## Limpieza

```bash
kubectl delete -f argocd-application.yaml
kubectl delete -f pipeline-build-deploy.yaml
kubectl delete -f task-git-clone.yaml
kubectl delete -f task-build-push.yaml

# Eliminar ArgoCD completo
kubectl delete namespace argocd

# Eliminar Tekton completo
kubectl delete -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
```

---

## Archivos

| Archivo | Recurso | Descripción |
|---------|---------|-------------|
| `task-git-clone.yaml` | Task | Clona un repo Git en el workspace compartido |
| `task-build-push.yaml` | Task | Usa Kaniko para build + push de la imagen |
| `pipeline-build-deploy.yaml` | Pipeline | Encadena clone → build con workspace NFS |
| `pipelinerun-demo.yaml` | PipelineRun | Lanza el pipeline — editar USUARIO antes de usar |
| `argocd-application.yaml` | Application | Declara la app en ArgoCD — editar USUARIO antes de usar |

> `secret-docker-credentials.yaml` no está en el repo (contiene credenciales). Crear con `kubectl create secret docker-registry`.
