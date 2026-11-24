# AWS Load Balancer Controller: creates the ALB for the "frontends" Ingress
# (shoplite-gitops/overlays/eks/ingress.yaml). The ALB itself is managed by the
# controller, not by Terraform, so tear down with scripts/destroy.sh rather than
# a plain `terraform destroy`: a leftover ALB keeps the VPC from being deleted.

resource "helm_release" "lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.lb_controller_chart_version
  namespace  = "kube-system"

  # Wait until the controller (and its webhook) is ready, so the app can be
  # applied right after `terraform apply`
  wait    = true
  timeout = 600

  set = [
    { name = "clusterName", value = module.eks.cluster_name },
    { name = "region", value = var.region },
    { name = "vpcId", value = module.vpc.vpc_id },
    # The chart creates the ServiceAccount; Pod Identity gives it the IAM role
    { name = "serviceAccount.create", value = "true" },
    { name = "serviceAccount.name", value = "aws-load-balancer-controller" },
  ]

  depends_on = [
    module.eks, # nodes and the pod identity agent must be running
    aws_eks_pod_identity_association.lb_controller,
    aws_iam_role_policy_attachment.lb_controller,
  ]
}
