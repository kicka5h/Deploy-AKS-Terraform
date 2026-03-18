# Helm releases for AKS clusters

# Namespace for ingress - Primary
resource "kubernetes_namespace" "ingress_primary" {
  provider = kubernetes.primary
  metadata {
    name = "ingress-nginx"
  }
  depends_on = [azurerm_kubernetes_cluster.aks]
}

# NGINX Ingress Controller - Primary cluster
resource "helm_release" "nginx_ingress_primary" {
  provider   = helm.primary
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = var.helm_nginx_ingress_version
  namespace  = kubernetes_namespace.ingress_primary.metadata[0].name

  set {
    name  = "controller.replicaCount"
    value = "2"
  }

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/azure-load-balancer-health-probe-request-path"
    value = "/healthz"
  }

  set {
    name  = "controller.metrics.enabled"
    value = "true"
  }

  set {
    name  = "controller.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution"
    value = "true"
  }

  depends_on = [azurerm_kubernetes_cluster.aks]
}

# Namespace for ingress - DR
resource "kubernetes_namespace" "ingress_dr" {
  count    = var.enable_dr ? 1 : 0
  provider = kubernetes.dr
  metadata {
    name = "ingress-nginx"
  }
  depends_on = [azurerm_kubernetes_cluster.aks_dr]
}

# NGINX Ingress Controller - DR cluster
resource "helm_release" "nginx_ingress_dr" {
  count      = var.enable_dr ? 1 : 0
  provider   = helm.dr
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = var.helm_nginx_ingress_version
  namespace  = kubernetes_namespace.ingress_dr[0].metadata[0].name

  set {
    name  = "controller.replicaCount"
    value = "2"
  }

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/azure-load-balancer-health-probe-request-path"
    value = "/healthz"
  }

  set {
    name  = "controller.metrics.enabled"
    value = "true"
  }

  depends_on = [azurerm_kubernetes_cluster.aks_dr]
}
