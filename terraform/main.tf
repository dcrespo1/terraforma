provider "kind" {}

# Create the cluster first
resource "kind_cluster" "this" {
  name           = var.cluster_name
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      extra_port_mappings {
        container_port = 30080
        host_port      = 8080
        protocol       = "TCP"
      }

      extra_port_mappings {
        container_port = 30443
        host_port      = 8443
        protocol       = "TCP"
      }
    }

    node { role = "worker" }
    node { role = "worker" }
  }
}

# Wire helm provider to the live cluster output
provider "helm" {
  kubernetes {
    host                   = kind_cluster.this.endpoint
    cluster_ca_certificate = kind_cluster.this.cluster_ca_certificate
    client_certificate     = kind_cluster.this.client_certificate
    client_key             = kind_cluster.this.client_key
  }
}

provider "kubernetes" {
  host                   = kind_cluster.this.endpoint
  cluster_ca_certificate = kind_cluster.this.cluster_ca_certificate
  client_certificate     = kind_cluster.this.client_certificate
  client_key             = kind_cluster.this.client_key
}

# Namespace
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.argocd_namespace
  }

  depends_on = [kind_cluster.this]
}

# Argo CD Helm release
resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version

  wait    = true
  timeout = 300

  set {
    name  = "configs.params.server\\.insecure"
    value = "true"
  }

  set {
    name  = "server.service.type"
    value = "NodePort"
  }

  set {
    name  = "server.service.nodePortHttp"
    value = "30080"
  }

  depends_on = [kubernetes_namespace.argocd]
}

# Bootstrap root Argo CD Application
resource "null_resource" "root_app" {
  depends_on = [helm_release.argocd]

  provisioner "local-exec" {
    command = "kubectl apply -f ${path.module}/../bootstrap/root-app.yaml --kubeconfig ${kind_cluster.this.kubeconfig_path}"
  }
}

resource "null_resource" "ingress_label" {
  depends_on = [null_resource.root_app]

  provisioner "local-exec" {
    command = "kubectl label node argocd-local-control-plane ingress-ready=true --kubeconfig ${kind_cluster.this.kubeconfig_path}"
  }
}

resource "null_resource" "argocd_cleanup" {
  depends_on = [null_resource.root_app]

  triggers = {
    kubeconfig = kind_cluster.this.kubeconfig_path
  }

  provisioner "local-exec" {
    when    = destroy
    command = "kubectl delete applications --all -n argocd --kubeconfig ${self.triggers.kubeconfig} || true"
  }
}