variable "cluster_name" {
  description = "Name of the kind cluster"
  type        = string
  default     = "argocd-local"
}

variable "argocd_namespace" {
  description = "Namespace to deploy Argo CD into"
  type        = string
  default     = "argocd"
}

variable "argocd_chart_version" {
  description = "Argo CD Helm chart version"
  type        = string
  default     = "9.4.17"       # was 7.3.4
}