#!/bin/bash
# ============================================================
# LIMPIEZA TOTAL DEL BOOTCAMP
# Elimina todos los recursos creados durante los labs
# ============================================================

echo "=== Limpieza de Kubernetes Bootcamp ==="
echo ""

echo "--- Borrando namespace 'mi-app' (lab 08) ---"
kubectl delete namespace mi-app --ignore-not-found

echo ""
echo "--- Borrando recursos del namespace 'bootcamp' ---"

# Lab 07 - Services
kubectl delete -f k8s-labs/07-service/ -n bootcamp --ignore-not-found 2>/dev/null || true

# Lab 06 - Deployment
kubectl delete -f k8s-labs/06-deployment/ -n bootcamp --ignore-not-found 2>/dev/null || true

# Lab 05 - ServiceAccount
kubectl delete -f k8s-labs/05-serviceaccount/ -n bootcamp --ignore-not-found 2>/dev/null || true

# Lab 04 - Secret
kubectl delete -f k8s-labs/04-secret/ -n bootcamp --ignore-not-found 2>/dev/null || true

# Lab 03 - ConfigMap
kubectl delete -f k8s-labs/03-configmap/ -n bootcamp --ignore-not-found 2>/dev/null || true

# Lab 02 - Pods
kubectl delete -f k8s-labs/02-pod/ -n bootcamp --ignore-not-found 2>/dev/null || true

echo ""
echo "--- Borrando namespace 'bootcamp' ---"
kubectl delete namespace bootcamp --ignore-not-found

echo ""
echo "--- Estado final del cluster ---"
kubectl get namespaces
kubectl get all -A | grep -v "kube-system\|kube-public\|kube-node-lease"

echo ""
echo "=== Limpieza completada ==="
