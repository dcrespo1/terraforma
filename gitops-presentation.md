---
theme: dark
author: Dylan Crespo
date: April 03, 2026
paging: "%d / %d"
---

# Local Kubernetes Development Workflow

---

## The Stack

Four tools, one workflow:

- **Terraform** — provisions the cluster and bootstraps Argo CD
- **kind** — runs Kubernetes locally inside Docker
- **Argo CD** — GitOps controller, syncs cluster state from Git
- **Config Repo** — the single source of truth for everything running in the cluster

---

## Why GitOps?

Traditional approach:

```
developer → kubectl apply → cluster
```

GitOps approach:

```
developer → git push → Argo CD → cluster
```

Benefits:

- Every change is a git commit — full audit trail
- Drift detection — Argo CD reconciles if cluster diverges from Git
- Rollback = `git revert`
- No manual `kubectl apply` in production

---

## Step 1: Terraform Provisions the Cluster

Terraform manages two things and nothing else:

1. The **kind cluster** (via `tehcyx/kind` provider)
2. **Argo CD** (via the `helm` provider)

```hcl
resource "kind_cluster" "this" {
  name           = var.cluster_name
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node { role = "control-plane" }
    node { role = "worker" }
    node { role = "worker" }
  }
}
```

---

## Step 1: Terraform Provisions the Cluster

Argo CD is deployed via Helm — provider config is wired directly
to the kind cluster outputs so there's no kubeconfig file dependency:

```hcl
provider "helm" {
  kubernetes {
    host                   = kind_cluster.this.endpoint
    cluster_ca_certificate = kind_cluster.this.cluster_ca_certificate
    client_certificate     = kind_cluster.this.client_certificate
    client_key             = kind_cluster.this.client_key
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "9.4.17"
  ...
}
```

---

## Step 2: Terraform Bootstraps the Root App

The final Terraform resource applies a single Argo CD `Application`
manifest — the root app. This hands control over to Git.

```hcl
resource "kubernetes_manifest" "root_app" {
  manifest   = yamldecode(file("${path.module}/bootstrap/root-app.yaml"))
  depends_on = [helm_release.argocd]
}
```

After this point **Terraform is done**. Everything else is driven
from the config repo.

---

## Step 3: Argo CD Takes Over

The root app points at the config repo:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/you/your-config-repo
    targetRevision: HEAD
    path: root-app # a Helm chart
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

Argo CD renders the Helm chart and creates child `Application`
resources for every enabled app — this is the **App-of-Apps** pattern.

---

## The App-of-Apps Pattern

```
root Application  (managed by Terraform, once)
│
├── kube-prometheus-stack Application  (managed by root app)
│     └── deploys: Prometheus, Alertmanager, Grafana
│
├── cert-manager Application
│     └── deploys: cert-manager + CRDs
│
└── my-api Application
      └── deploys: deployment, service
```

Each child `Application` is a Helm template in the config repo.
Argo CD owns the full lifecycle — create, update, prune.

---

## The Config Repo Structure

```
bootstrap/
  root-app.yaml            # applied once by Terraform

root-app/                  # Helm chart — the App-of-Apps root
  Chart.yaml
  values.yaml              # toggle file — on/off per app
  templates/
    kube-prometheus-stack.yaml
    grafana.yaml
    cert-manager.yaml
    my-api.yaml

apps/
  my-api/                  # raw manifests for in-repo apps
    deployment.yaml
    service.yaml
```

---

## Toggling Apps On and Off

`root-app/values.yaml` is the control plane for what runs in the cluster:

```yaml
apps:
  kubePrometheusStack:
    enabled: true # deployed
  grafana:
    enabled: false # not deployed
  certManager:
    enabled: false # not deployed
  myApi:
    enabled: false # not deployed
```

Flip `enabled`, push — Argo CD detects the diff on the root app
and creates or prunes the child `Application` accordingly.

---

## Pruning: What Happens When You Disable an App

With `prune: true` set on the root app, disabling an app cascades:

```
values.yaml: grafana.enabled = false
  → root app re-renders Helm templates
    → grafana Application resource is removed
      → Argo CD prunes grafana workloads from the cluster
```

The `resources-finalizer` annotation on each child app ensures
the workloads are cleaned up, not just the `Application` resource.

```yaml
metadata:
  finalizers:
    - resources-finalizer.argocd.argoproj.io
```

---

## Adding a New App

Three steps:

**1.** Add a toggle to `root-app/values.yaml`:

```yaml
apps:
  myNewApp:
    enabled: true
    namespace: my-new-app
```

**2.** Add a template at `root-app/templates/my-new-app.yaml`:

```yaml
{{- if .Values.apps.myNewApp.enabled }}
apiVersion: argoproj.io/v1alpha1
kind: Application
...
{{- end }}
```

**3.** Push — Argo CD picks it up on the next root app sync.

---

## Sync Waves: Controlling Deployment Order

Some apps must be ready before others (e.g. CRDs before workloads
that use them). Sync waves enforce ordering:

```yaml
# Wave 1 — operators and CRDs first
annotations:
  argocd.argoproj.io/sync-wave: "1"   # cert-manager, kube-prometheus-stack

# Wave 2 — platform tooling
  argocd.argoproj.io/sync-wave: "2"   # grafana

# Wave 3+ — application workloads
  argocd.argoproj.io/sync-wave: "3"   # my-api
```

Argo CD will not proceed to the next wave until all resources
in the current wave are healthy.

---

## The Full Flow: Zero to Running Cluster

```
terraform apply
  │
  ├── kind cluster created
  │
  ├── Argo CD deployed via Helm
  │
  └── root Application applied
        │
        └── Argo CD syncs root-app/ from Git
              │
              ├── renders Helm templates with values.yaml
              │
              └── creates enabled child Applications
                    │
                    ├── wave 1: kube-prometheus-stack, cert-manager
                    ├── wave 2: grafana
                    └── wave 3: my-api
```

---

## Key Takeaways

- **Terraform** owns the cluster and Argo CD bootstrap — nothing else
- **Git** is the source of truth for all cluster state
- **values.yaml** is your toggle file — one place to control what's deployed
- **Prune + finalizers** ensure disabling an app cleans up after itself
- **Sync waves** handle dependency ordering between apps
- Adding a new app = two files + a git push

---

# Thank You

```
terraform apply && git push
```

> "The cluster is a reflection of the repo."
