# Run the password fetch at apply time so it's ready immediately
data "kubernetes_secret" "argocd_initial_password" {
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = var.argocd_namespace
  }

  depends_on = [helm_release.argocd]
}

output "kubeconfig_path" {
  description = "Path to the generated kubeconfig"
  value       = kind_cluster.this.kubeconfig_path
}

output "argocd_url" {
  description = "Local Argo CD UI URL"
  value       = "http://localhost:8080"
}

output "argocd_username" {
  description = "Argo CD admin username"
  value       = "admin"
}

output "argocd_initial_password" {
  description = "Argo CD initial admin password"
  value       = base64decode(data.kubernetes_secret.argocd_initial_password.data.password)
  sensitive   = true
}

output "argocd_login_command" {
  description = "Log in via the argocd CLI"
  value       = "argocd login localhost:8080 --username admin --password $(terraform output -raw argocd_initial_password) --insecure"
}

output "kubectl_context" {
  description = "Set kubeconfig context for this cluster"
  value       = "export KUBECONFIG=${kind_cluster.this.kubeconfig_path}"
}