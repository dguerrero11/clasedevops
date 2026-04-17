#!/bin/bash
# ============================================================
# LIMPIEZA TOTAL — Kubernetes Bootcamp Clase 2
# ============================================================

echo "=== Limpieza Clase 2 ==="

echo "--- Borrando namespace clase2 ---"
kubectl delete namespace clase2 --ignore-not-found

echo "--- Borrando recursos en namespace bootcamp ---"
kubectl delete daemonset log-agent -n bootcamp --ignore-not-found
kubectl delete statefulset postgres -n bootcamp --ignore-not-found
kubectl delete service postgres-headless -n bootcamp --ignore-not-found
kubectl delete pod pod-emptydir pod-hostpath pod-con-pvc \
  pod-escritor pod-lector pod-pvc-dinamico --ignore-not-found -n bootcamp
kubectl delete pvc --all -n bootcamp --ignore-not-found

echo "--- Limpiando PVs en estado Released ---"
kubectl get pv --no-headers | grep -E "Released|Available" | \
  awk '{print $1}' | xargs kubectl delete pv 2>/dev/null || true

echo "--- Borrando namespace bootcamp ---"
kubectl delete namespace bootcamp --ignore-not-found

echo ""
echo "=== Estado final ==="
kubectl get namespaces
echo ""
kubectl get pv 2>/dev/null || echo "No hay PVs"
echo ""
echo "=== Limpieza completada ==="
