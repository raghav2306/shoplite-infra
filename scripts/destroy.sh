#!/usr/bin/env bash
# Tears down everything `terraform apply` created, in an order that works with
# Argo CD running:
#
#   1. delete the Argo CD Applications. Their finalizer makes Argo CD delete what
#      it deployed, including the Ingress, so the LB controller removes the ALB.
#      (Deleting the Ingress with kubectl doesn't work: self-heal recreates it.)
#   2. delete the ecommerce namespace: the StatefulSets' PVCs aren't owned by
#      Argo CD, and the EBS CSI driver must still be running to delete their volumes.
#   3. wait until no ALB is left for this cluster. A leftover ALB or its security
#      groups keep Terraform from deleting the VPC.
#   4. terraform destroy
#
# Usage: scripts/destroy.sh [extra terraform destroy args, e.g. -auto-approve]
set -euo pipefail
cd "$(dirname "$0")/.."

CLUSTER="$(terraform output -raw cluster_name)"
REGION="$(terraform output -raw region)"

if aws eks describe-cluster --name "$CLUSTER" --region "$REGION" >/dev/null 2>&1; then
  aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" >/dev/null

  echo "==> 1/4 Deleting Argo CD Applications (Argo CD removes their resources)"
  if kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
    kubectl -n argocd delete applications --all --wait --timeout=10m
  fi

  echo "==> 2/4 Deleting namespace ecommerce (PVCs -> EBS volumes)"
  kubectl delete namespace ecommerce --ignore-not-found --wait --timeout=10m
else
  echo "==> Cluster $CLUSTER not found; skipping the Kubernetes cleanup"
fi

echo "==> 3/4 Waiting for this cluster's load balancers to be deleted"
for _ in $(seq 1 30); do
  LBS="$(aws resourcegroupstaggingapi get-resources --region "$REGION" \
    --resource-type-filters elasticloadbalancing:loadbalancer \
    --tag-filters "Key=elbv2.k8s.aws/cluster,Values=$CLUSTER" \
    --query 'ResourceTagMappingList[].ResourceARN' --output text)"
  [ -z "$LBS" ] && break
  echo "    still there: $LBS"
  sleep 10
done
if [ -n "$LBS" ]; then
  echo "Load balancers still exist after 5 minutes. Delete them in the EC2 console, then re-run." >&2
  exit 1
fi

echo "==> 4/4 terraform destroy"
terraform destroy "$@"
