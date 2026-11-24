# Argo CD, plus the one Application that points it at shoplite-gitops.
# After `terraform apply` the cluster deploys itself from Git: Argo CD syncs
# overlays/eks, and every later commit there (e.g. CI bumping an image tag)
# rolls out on its own.
#
# The app's Secrets are NOT in Git: create them in the "ecommerce" namespace
# (see the shoplite-gitops README) or its pods stay in CreateContainerConfigError.
#
# UI:       kubectl -n argocd port-forward svc/argocd-server 8080:443   -> https://localhost:8080
# Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = "argocd"
  create_namespace = true

  wait    = true
  timeout = 600

  set = [
    # Not needed here and each costs a pod (t3.medium nodes are pod-limited):
    # dex = SSO login, notifications = alerts on sync events (the chart enables both by default)
    { name = "dex.enabled", value = "false" },
    { name = "notifications.enabled", value = "false" },
  ]

  depends_on = [module.eks]
}

resource "helm_release" "argocd_apps" {
  name      = "argocd-apps"
  namespace = "argocd"

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version

  values = [yamlencode({
    applications = {
      (var.argocd_app_name) = {
        namespace = "argocd"
        project   = "default"
        # Deleting the Application also deletes everything it deployed,
        # including the Ingress and therefore the ALB (see scripts/destroy.sh)
        finalizers = ["resources-finalizer.argocd.argoproj.io"]
        source = {
          repoURL        = var.gitops_repo_url
          targetRevision = var.gitops_revision
          path           = var.gitops_path
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "ecommerce"
        }
        syncPolicy = {
          automated = {
            prune    = true # remove what was deleted from Git
            selfHeal = true # undo manual kubectl changes
          }
          syncOptions = ["CreateNamespace=true"]
        }
      }
    }
  })]

  depends_on = [
    helm_release.argocd,
    # The app's Ingress needs the controller's webhook to be up
    helm_release.lb_controller,
  ]
}
