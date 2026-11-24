# scripts

Wrappers around Terraform for steps that need kubectl or AWS calls in a set
order. Terraform can't do these on its own. Run them from anywhere: each one
changes into the repo root first.

| Script | Needed? | What it does |
|---|---|---|
| `apply.sh` | Optional, for convenience | `terraform init` + `apply`, then kubeconfig, the app's Secrets, the Argo CD status and the CI values |
| `destroy.sh` | **Required** for teardown | Removes what Argo CD and the LB controller created, then `terraform destroy` |

## apply.sh

```bash
scripts/apply.sh                 # shows the plan and asks before changing anything
scripts/apply.sh -auto-approve   # no prompt
GITOPS_DIR=~/code/shoplite-gitops scripts/apply.sh
```

1. Checks that `terraform`, `aws` and `kubectl` are installed, and prints the AWS account it will use
2. `terraform init` + `terraform apply` (extra arguments are passed to `apply`)
3. `aws eks update-kubeconfig` for the new cluster
4. Creates the `ecommerce` namespace and applies the 5 required Secrets from
   `$GITOPS_DIR/base/<name>/secret.yaml` (default `GITOPS_DIR=../shoplite-gitops`).
   Missing files are listed, not treated as errors
5. Prints the Argo CD Application's sync and health status, how to open the UI,
   and `github_ci_role_arn` / `ecr_registry` for the CI workflow

Every step is idempotent, so it's safe to re-run after changing a `.tf` file or a
Secret.

**Without it:** run the commands under "The same steps by hand" in the
[main README](../README.md#create-everything).

## destroy.sh

```bash
scripts/destroy.sh
scripts/destroy.sh -auto-approve
```

**Why a plain `terraform destroy` isn't enough:** the app's ALB and EBS volumes
are created inside the cluster (by the LB controller and the EBS CSI driver),
not by Terraform, so Terraform doesn't know about them. If they still exist,
deleting the VPC hangs on the ALB's network interfaces and security groups,
and the volumes keep costing money. You can't just `kubectl delete` the
Ingress first either: Argo CD's self-heal recreates it within seconds.

The script removes things in an order that works:

1. `kubectl -n argocd delete applications --all`: the Application's finalizer
   makes Argo CD delete everything it deployed, including the Ingress, so the
   LB controller deletes the ALB
2. `kubectl delete namespace ecommerce`: removes the StatefulSets' PVCs, which
   Argo CD doesn't own, while the EBS CSI driver is still running to delete their volumes
3. Polls AWS for up to 5 minutes until no load balancer tagged with this
   cluster is left. If one remains, it stops and asks you to delete it in the
   EC2 console
4. `terraform destroy` (extra arguments are passed through)

If the cluster is already gone, steps 1–2 are skipped.

Needs the Terraform state, since it reads `cluster_name` and `region` from
`terraform output`.
