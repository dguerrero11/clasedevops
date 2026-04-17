# Lab 04 - Secret

## Concepto

Un **Secret** almacena datos sensibles: contraseñas, tokens, claves TLS.
- Los valores se almacenan en **base64** (¡no es cifrado!)
- En producción se complementan con: Sealed Secrets, Vault, External Secrets Operator
- Kubernetes puede restringir quién puede leer Secrets con RBAC

## Tipos de Secret

| Tipo | Uso |
|------|-----|
| `Opaque` | Genérico (default) |
| `kubernetes.io/tls` | Certificados TLS |
| `kubernetes.io/dockerconfigjson` | Credenciales de registry privado |
| `kubernetes.io/service-account-token` | Token de ServiceAccount |

## Comandos esenciales

```bash
# Crear desde YAML
kubectl apply -f 01-secret.yaml

# Crear imperativo (los valores se encodean automáticamente)
kubectl create secret generic db-credentials \
  --from-literal=DB_USER=admin \
  --from-literal=DB_PASSWORD=mi-password

# Ver secrets (los valores aparecen ofuscados)
kubectl get secrets
kubectl describe secret db-credentials

# Ver el valor decodificado (¡cuidado en producción!)
kubectl get secret db-credentials -o jsonpath='{.data.DB_PASSWORD}' | base64 -d

# Codificar/decodificar manualmente
echo -n "mi-valor" | base64
echo "bWktdmFsb3I=" | base64 -d
```

## Ejercicios

### Ejercicio 1 — Crear y leer un Secret
1. Aplica `01-secret.yaml`
2. Lista los secrets: `kubectl get secrets`
3. Intenta ver el password: `kubectl get secret db-credentials -o yaml`
4. ¿Los valores están en texto plano? ¿Son seguros?
5. Decodifica el password manualmente con `base64 -d`

### Ejercicio 2 — Pod con Secret
1. Aplica `02-pod-con-secret.yaml`
2. Verifica los logs: `kubectl logs pod-con-secret`
3. Entra al pod y ejecuta: `echo $DB_PASSWORD` — ¿puedes ver el valor?

### Ejercicio 3 — Secret TLS
Crea un Secret de tipo TLS con un certificado autofirmado:
```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt \
  -subj "/CN=mi-app.local"

kubectl create secret tls mi-tls-secret \
  --cert=tls.crt --key=tls.key -n bootcamp
```

### Ejercicio 4 — Desafío
Crea un Secret con credenciales de imagePullSecret para un registry privado.
Pista: `kubectl create secret docker-registry`

## Limpieza

```bash
kubectl delete -f .
kubectl delete secret mi-tls-secret
```
