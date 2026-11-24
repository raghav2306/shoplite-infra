# IAM roles for the two add-ons, handed to their pods with EKS Pod Identity
# (the eks-pod-identity-agent add-on). No OIDC provider or IRSA annotations needed.

data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

# ---------- EBS CSI driver ----------

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.cluster_name}-ebs-csi-driver"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# The StorageClass in shoplite-gitops/overlays/eks encrypts volumes with the default
# aws/ebs key; this managed policy already covers that.

# ---------- AWS Load Balancer Controller ----------

resource "aws_iam_policy" "lb_controller" {
  name        = "${var.cluster_name}-aws-load-balancer-controller"
  description = "aws-load-balancer-controller ${var.lb_controller_chart_version} (docs/install/iam_policy.json)"
  policy      = file("${path.module}/policies/aws-load-balancer-controller-v${var.lb_controller_chart_version}.json")
}

resource "aws_iam_role" "lb_controller" {
  name               = "${var.cluster_name}-aws-load-balancer-controller"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  role       = aws_iam_role.lb_controller.name
  policy_arn = aws_iam_policy.lb_controller.arn
}

resource "aws_eks_pod_identity_association" "lb_controller" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.lb_controller.arn
}
