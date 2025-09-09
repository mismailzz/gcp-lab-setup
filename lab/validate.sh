#!/bin/bash
set -euo pipefail

PROJECT_ID="${1:?project id required}"

CLUSTER_NAME="my-gke-cluster"
ZONE="us-central1-c"
DEPLOYMENT_NAME="nginx-filestore"
NAMESPACE="default"
EXPECTED_REPLICAS=2
PERSISTENT_VOLUME_NAME="filestore-pv"
PERSISTENT_VOLUME_CLAIM_NAME="filestore-pvc"

DEADLINE=$((SECONDS + 10800))   # 3 hours timeout
SLEEP=10                        # seconds between retries

run_checks() {
  local ok=true

  # [1/6] Checking PV driver
  if ! kubectl get pv "$PERSISTENT_VOLUME_NAME" -o jsonpath='{.spec.csi.driver}' 2>/dev/null | grep -q "filestore.csi.storage.gke.io"; then
    echo "[validate] Check failed: PV CSI driver"
    ok=false
  fi

  # [2/6] PVC bound
  if ! kubectl get pvc "$PERSISTENT_VOLUME_CLAIM_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Bound"; then
    echo "[validate] Check failed: PVC not Bound"
    ok=false
  fi

  # [3/6] Deployment exists
  if ! kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "[validate] Check failed: Deployment missing"
    ok=false
  fi

  # [4/6] Expected replicas
  READY_REPLICAS=$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  if [[ "$READY_REPLICAS" != "$EXPECTED_REPLICAS" ]]; then
    echo "[validate] Check failed: Replica count ($READY_REPLICAS/$EXPECTED_REPLICAS)"
    ok=false
  fi

  # [5/6] Image and port
  if ! kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o json 2>/dev/null | grep -q '"image": "nginx"'; then
    echo "[validate] Check failed: Wrong image"
    ok=false
  fi
  if ! kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o json 2>/dev/null | grep -q '"containerPort": 80'; then
    echo "[validate] Check failed: Wrong port"
    ok=false
  fi

  # [6/6] File contents
  POD_NAME=$(kubectl get pods -l app="$DEPLOYMENT_NAME" -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [[ -n "$POD_NAME" ]]; then
    if ! kubectl exec -n "$NAMESPACE" "$POD_NAME" -- cat /usr/share/nginx/html/index.html 2>/dev/null | grep -iq "Filestore"; then
      echo "[validate] Check failed: Missing 'Filestore' in index.html"
      ok=false
    fi
  else
    echo "[validate] Check failed: No pod found"
    ok=false
  fi

  if [ "$ok" = true ]; then
    echo "[validate] All checks passed âœ…"
    echo "[validate] LAB COMPLETED SUCCESSFULLY ðŸŽ‰"
    return 0
  else
    return 1
  fi
}

echo "[validate] Waiting for resources to become ready in project $PROJECT_ID (timeout 3 hours)â€¦"
gcloud container clusters get-credentials "$CLUSTER_NAME" --zone "$ZONE" --project "$PROJECT_ID" >/dev/null 2>&1

while (( SECONDS < DEADLINE )); do
  if run_checks; then
    echo "True"
    exit 0
  fi
  echo "[validate] Not ready yet, retrying in ${SLEEP}sâ€¦"
  sleep "$SLEEP"
done

echo "[validate] Timed out after 3 hours âŒ"
echo "[validate] LAB TIMED OUT, PROCEEDING TO DESTROY"
echo "False"
exit 1
