terraform {
  required_version = ">= 1.6.0"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.11"       # was ~> 0.4
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"       # still current
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"       # still current
    }
  }
}