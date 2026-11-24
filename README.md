# shoplite-infra

Terraform for the ShopLite platform on AWS: one `apply` creates the network,
the EKS cluster and its add-ons, the image registry, a role for CI, and
Argo CD. From then on, Argo CD deploys the app from Git.

## Where this fits

ShopLite is split into three repos, each with one job:

| Repo | Job | Run by |
|---|---|---|
| **shoplite-infra** (this one) | AWS resources and cluster add-ons, including Argo CD | You, with Terraform |
| [shoplite-microservices](https://github.com/raghav2306/shoplite-microservices) | App code. **CI:** test, build and push images, then bump the tag in gitops | GitHub Actions |
| [shoplite-gitops](https://github.com/raghav2306/shoplite-gitops) | **CD:** the Kubernetes manifests, the desired state of the cluster | Argo CD |

```
push code ──► GitHub Actions ──► ECR (image :<sha>)
                    │
                    └──► commit newTag: <sha> to shoplite-gitops
                                    │
                         Argo CD (in EKS) ◄── watches
                                    │
                                    ▼
                         rolling update in namespace ecommerce
```

CI never talks to the cluster; it only writes to ECR and Git. Argo CD pulls
changes from inside the cluster.

## What it creates

| File | Creates |
|---|---|
| `network.tf` | VPC `10.30.0.0/16`, 2 public subnets in 2 AZs (tagged for ALBs), internet gateway. **No NAT gateway**: nodes get public IPs, which saves ~$32/month |
| `eks.tf` | EKS cluster, 3 × `t3.medium` managed nodes (AL2023, x86), add-ons `vpc-cni`, `coredns`, `kube-proxy`, `eks-pod-identity-agent`, `aws-ebs-csi-driver`. Whoever runs `apply` gets cluster-admin |
| `iam.tf` | IAM roles for the EBS CSI driver and the Load Balancer Controller, given to their pods with **EKS Pod Identity** (no OIDC/IRSA) |
| `lb-controller.tf` | AWS Load Balancer Controller (Helm): turns the app's Ingress into an ALB |
| `ecr.tf` | `dev/<service>` repositories for the 6 images. Tags are **immutable**, scan on push is on, and the newest 20 images are kept |
| `github-ci.tf` | GitHub OIDC provider and role `<cluster>-github-ci`: lets the shoplite-microservices workflow on `main` push to those ECR repos, with no AWS keys stored in GitHub |
| `argocd.tf` | Argo CD (Helm) and the Application `shoplite-eks`, which syncs `shoplite-gitops/overlays/eks` automatically (prune + self-heal) |
| `versions.tf` | Provider versions, the AWS default tags, local state |

## Prerequisites

- **Tools:** Terraform ≥ 1.6, AWS CLI v2, kubectl
- **AWS credentials** for an account where you can create VPC, EKS, IAM and ECR resources:
  `aws sts get-caller-identity` must work
- **shoplite-gitops cloned next to this repo** (`../shoplite-gitops`), with its
  five `secret.yaml` files filled in. They are git-ignored, so copy them from the templates:
  ```bash
  cd ../shoplite-gitops
  for d in mongodb-users mongodb-products mongodb-orders rabbitmq user-service; do
    cp base/$d/secret.yaml.example base/$d/secret.yaml    # then set real values
  done
  ```
  Use letters and digits only for the passwords, since they're embedded in connection
  URLs. For `JWT_SECRET`, use `openssl rand -hex 32`.
- **shoplite-gitops must be public** on GitHub, or registered in Argo CD with credentials.

## Create everything

```bash
cp terraform.tfvars.example terraform.tfvars   # optional: every value has a default
scripts/apply.sh
```

`scripts/apply.sh` runs `terraform init` and `apply` (shows the plan and asks
first), points kubectl at the cluster, creates the Secrets from
`../shoplite-gitops`, and prints the Argo CD status and what you need next.
The first run takes about 20 minutes. It's safe to re-run after changing
anything here.

Set `GITOPS_DIR=/path/to/shoplite-gitops` if your clone is elsewhere. See
[scripts/README.md](scripts/README.md) for what each script does, and why
`destroy.sh` is required while `apply.sh` is optional.

<details>
<summary>The same steps by hand</summary>

```bash
terraform init
terraform plan
terraform apply
$(terraform output -raw kubeconfig_command)

kubectl create namespace ecommerce
for d in mongodb-users mongodb-products mongodb-orders rabbitmq user-service; do
  kubectl apply -f ../shoplite-gitops/base/$d/secret.yaml
done
```
</details>

## After apply

```bash
kubectl get nodes                                    # 3 × Ready
kubectl -n argocd get applications                   # shoplite-eks  Synced  Healthy
kubectl -n ecommerce get pods
kubectl -n ecommerce get ingress frontends           # ALB hostname: open it in a browser
```

The ALB takes about 3 minutes after the first sync to get a hostname and pass health checks.

**Argo CD UI**

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443     # https://localhost:8080
$(terraform output -raw argocd_admin_password_command)       # password for user "admin"
```

## Connect CI (shoplite-microservices)

```bash
terraform output github_ci_role_arn
terraform output ecr_registry
```

In the GitHub Actions workflow:

```yaml
permissions:
  id-token: write      # lets the job request the OIDC token
  contents: read

steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: <github_ci_role_arn>
      aws-region: us-east-1
  - uses: aws-actions/amazon-ecr-login@v2
```

Only runs on `main` of `raghav2306/shoplite-microservices` can assume the role
(change it with `github_repo` and `github_branch`). Tag images with the commit
SHA: ECR tags are immutable, so pushing the same tag twice fails.

## Configuration

All variables have defaults; override them in `terraform.tfvars`.

| Variable | Default | Notes |
|---|---|---|
| `region` | `us-east-1` | |
| `cluster_name` | `ecommerce` | Also the prefix for the VPC and IAM role names |
| `environment` | `dev` | Also the ECR prefix (`dev/<service>`). `shoplite-gitops/overlays/eks` expects `dev`: change both together |
| `kubernetes_version` | `1.37` | Must be in AWS standard support, or the control plane costs 6× |
| `node_instance_type` | `t3.medium` | x86, matching the `linux/amd64` images. 17 pods per node |
| `node_desired_size` / `node_min_size` / `node_max_size` | `3` / `2` / `4` | Nothing autoscales: change `node_desired_size` to resize |
| `cluster_endpoint_public_access_cidrs` | `["0.0.0.0/0"]` | Who can reach the Kubernetes API. Narrow it to your IP |
| `gitops_repo_url` / `gitops_path` / `gitops_revision` | shoplite-gitops / `overlays/eks` / `main` | What Argo CD deploys |
| `github_repo` / `github_branch` | `raghav2306/shoplite-microservices` / `main` | Who may assume the CI role |
| `create_github_oidc_provider` | `true` | Set to `false` if the account already has the GitHub OIDC provider (only one per account) |
| `argocd_chart_version` | `10.17.2` | Argo CD v3.6.1 |
| `lb_controller_chart_version` | `3.6.3` | Changing it also needs that release's IAM policy in `policies/` |

## Tear down

```bash
scripts/destroy.sh
```

Don't use a plain `terraform destroy`. The ALB is created by the Load Balancer
Controller, not by Terraform, and a leftover ALB keeps the VPC from being
deleted. Deleting the Ingress with kubectl doesn't help either, because Argo CD's self-heal
puts it back. The script:

1. deletes the Argo CD Application; its finalizer removes everything it deployed, including the ALB
2. deletes the `ecommerce` namespace, so the EBS CSI driver deletes the MongoDB and RabbitMQ volumes
3. waits until no ALB is left for the cluster
4. runs `terraform destroy`

ECR repositories are deleted together with their images.

## Cost

Roughly **$200/month (about $6.5/day)** in us-east-1 with the defaults: EKS
control plane ($73), 3 × t3.medium (~$90), one ALB (~$20), 4 × 1 GiB gp3
volumes, ECR storage. Destroy the stack when you're not using it.

## State

State is local (`terraform.tfstate`, git-ignored). **Don't lose it**: without
it, Terraform can't update or destroy what it created, and you'd be deleting
resources by hand in the console. For a team, or to run Terraform from CI, switch to the
S3 backend sketched in `versions.tf`.

## Security notes (course setup)

- The Kubernetes API is reachable from the internet. Access still needs IAM
  credentials, but narrow `cluster_endpoint_public_access_cidrs` to your IP.
- Nodes are in public subnets. Inbound traffic is still limited by the EKS
  security groups to the cluster and the ALB.
- App Secrets are applied by hand and aren't managed by Argo CD. A next step is
  Sealed Secrets or External Secrets Operator.
