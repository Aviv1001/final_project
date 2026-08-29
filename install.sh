#!/bin/sh
##############
# Version 0.0.1
# written by Aviv
# date 29\08\2026
##############
set -eu

cd "$(dirname "$0")"

echo "installing into this cluster:"
kubectl config current-context

# The state file holds the worker's secret key, so keep it private.
umask 077
terraform -chdir=terraform init
terraform -chdir=terraform apply

# The namespace is in this file, so it goes first.
kubectl apply -f k8s/app.yaml

kubectl -n lectures create configmap lecture-config \
  --from-literal=BUCKET="$(terraform -chdir=terraform output -raw bucket)" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n lectures create secret generic aws-key \
  --from-literal=AWS_ACCESS_KEY_ID="$(terraform -chdir=terraform output -raw access_key_id)" \
  --from-literal=AWS_SECRET_ACCESS_KEY="$(terraform -chdir=terraform output -raw secret_access_key)" \
  --dry-run=client -o yaml | kubectl apply -f -

# A pod reads its environment once, when it starts.
kubectl -n lectures rollout restart deployment

kubectl -n lectures rollout status --timeout=3m deployment/worker
kubectl -n lectures rollout status --timeout=3m deployment/web

echo "done. open http://localhost:30080/"
