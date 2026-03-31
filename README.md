# Terraforma

- A local kubernetes env using terraform and ArgoCD for an `App-of-Apps` style of application management.
- The idea here is that you can leverage this repo to stand up a local kube cluster, toggle on and off applications, and clean everything up when you are done.
- Learning, experimenting, testing

## Structure

```
bootstrap/
  root-app.yaml          # Applied once by Terraform to bootstrap everything
root-app/
  Chart.yaml
  values.yaml            # Toggle apps on/off here
  templates/
    kube-prometheus-stack.yaml
    grafana.yaml
    cert-manager.yaml
    my-api.yaml
apps/
  my-api/                # Raw manifests for in-repo apps
    deployment.yaml
    service.yaml
```

## Adding a new app

1. Add a toggle to `root-app/values.yaml`:

   ```yaml
   apps:
     myNewApp:
       enabled: true
       namespace: my-new-app
   ```

2. Add a template to `root-app/templates/my-new-app.yaml`

3. Push — Argo CD picks it up automatically via the root app sync.

## Toggling apps

Edit `root-app/values.yaml` and set `enabled: false` for any app you don't want
deployed. Push the change. Argo CD will detect the diff on the root app and prune
the `Application` resource, which cascades to removing the workloads from the cluster.

## Bootstrap (first time)

Terraform applies `bootstrap/root-app.yaml` after deploying Argo CD.
Everything after that is driven from this repo.
