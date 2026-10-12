# Spanner Omni

This repository provides Helm charts, sample configurations, and operational scripts for deploying and operating [**Spanner Omni**](https://docs.cloud.google.com/spanner-omni) on Kubernetes.

Here you will find templates, sample deployment configurations, and guidance to automate your Spanner Omni lifecycle operations—from single-server development instances to multi-zone and multi-region high-availability production clusters with integrated observability.

Learn more about Spanner Omni at [https://docs.cloud.google.com/spanner-omni](https://docs.cloud.google.com/spanner-omni).

## Supported Platforms

The Spanner Omni Helm chart includes built-in configuration profiles tailored for major cloud Kubernetes environments. Pass `--set global.platform=<platform>` during Helm installation to automatically load the platform-specific defaults:

- **Google Kubernetes Engine (`gke`)**: Uses [`SpannerOmni/helm/values-gke.yaml`](SpannerOmni/helm/values-gke.yaml).
- **Amazon Elastic Kubernetes Service (`eks`)**: Uses [`SpannerOmni/helm/values-eks.yaml`](SpannerOmni/helm/values-eks.yaml).
- **Azure Kubernetes Service (`aks`)**: Uses [`SpannerOmni/helm/values-aks.yaml`](SpannerOmni/helm/values-aks.yaml).

## Sample Configurations

Sample configurations for **single-server**, **regional**, **scaleout**, **multi-region**, and **multi-cloud** topologies are available under [`SpannerOmni/samples/`](SpannerOmni/samples/), with a 1-to-1 mapping between the Helm values ([`SpannerOmni/samples/helm/`](SpannerOmni/samples/helm/)) and the corresponding Spanner deployment configurations ([`SpannerOmni/samples/deployment_configs/`](SpannerOmni/samples/deployment_configs/)). When deploying with Helm (`-f SpannerOmni/samples/helm/values-<topology>.yaml`), the chart automatically renders the deployment configuration into the `spanner-deployment-config` ConfigMap for the bootstrap job:

| Topology | Sample Helm Values ([`SpannerOmni/samples/helm/`](SpannerOmni/samples/helm/)) | Sample Deployment Config ([`SpannerOmni/samples/deployment_configs/`](SpannerOmni/samples/deployment_configs/)) | Description |
| :--- | :--- | :--- | :--- |
| **Single-Server** | [`values-single-server.yaml`](SpannerOmni/samples/helm/values-single-server.yaml) | [`spanner-single-server.yaml`](SpannerOmni/samples/deployment_configs/spanner-single-server.yaml) | Single-pod development/testing instance (`deployment.singleServer: true`). |
| **Regional** | [`values-regional.yaml`](SpannerOmni/samples/helm/values-regional.yaml) | [`spanner-regional.yaml`](SpannerOmni/samples/deployment_configs/spanner-regional.yaml) | 3-zone regional deployment (`us-east1-b`, `us-east1-c`, `us-east1-d`) with 1 server per zone. |
| **Scaleout (HA)** | [`values-scaleout.yaml`](SpannerOmni/samples/helm/values-scaleout.yaml) | [`spanner-scaleout.yaml`](SpannerOmni/samples/deployment_configs/spanner-scaleout.yaml) | 3-zone regional HA deployment with 5 servers (`3` dedicated root servers and `2` non-root servers) per zone. |
| **Multi-Region** | [`values-multi-region.yaml`](SpannerOmni/samples/helm/values-multi-region.yaml) | [`spanner-multi-region.yaml`](SpannerOmni/samples/deployment_configs/spanner-multi-region.yaml) | Multi-region topology across 3 clusters (`us-west1`, `us-west2`, and `us-west3` with a witness replica). |
| **Multi-Cloud** | [`values-multi-cloud.yaml`](SpannerOmni/samples/helm/values-multi-cloud.yaml) | [`spanner-multi-cloud.yaml`](SpannerOmni/samples/deployment_configs/spanner-multi-cloud.yaml) | Cross-cloud multi-cluster topology spanning Amazon EKS (`us-east-1`) and Google Kubernetes Engine (`us-central1`). |

## Quickstart

### Prerequisites

- A running Kubernetes cluster (**GKE**, **EKS**, or **AKS**) with `kubectl` configured.
- [Helm v3.8+](https://helm.sh/docs/intro/install/) installed.
- *(Optional)* Spanner Omni ships with an optional, fully-integrated observability stack (Prometheus, Grafana, and Jaeger) deployed via a Helm dependency subchart. Append `--set monitoring.enabled=true` to any installation command to deploy the monitoring components alongside your Spanner instance. When enabled, Spanner automatically discovers and routes trace exports to the local Jaeger OTLP collector.

> [!IMPORTANT]
> **Namespace Requirements:**
>
> - **Spanner Omni**: Deploys into the target namespace declared via the `--namespace` flag (e.g., `spanner-ns`). If this namespace does not exist, include `--create-namespace` in your Helm command so Kubernetes provisions it automatically.
> - **Observability Stack**: By default, the monitoring stack deploys into a dedicated `monitoring` namespace. Helm's `--create-namespace` flag only provisions the core release's namespace, so you **must** pre-create the `monitoring` namespace (`kubectl create namespace monitoring`) before installing with `--set monitoring.enabled=true`. Alternatively, override its target namespace using `--set monitoring.namespace=<custom-namespace>`.
> - **Platform Selection**: Replace `global.platform=gke` with `eks` or `aks` in the commands below to match your target Kubernetes environment.

### 1. Deploying Single-Server Mode (Development / Testing)

Deploy a lightweight, single-pod Spanner Omni instance (`deployment.singleServer=true`) for development and functional testing using [`SpannerOmni/samples/helm/values-single-server.yaml`](SpannerOmni/samples/helm/values-single-server.yaml) (corresponding deployment config: [`SpannerOmni/samples/deployment_configs/spanner-single-server.yaml`](SpannerOmni/samples/deployment_configs/spanner-single-server.yaml)):

```bash
# Pre-create the monitoring namespace if enabling the observability stack
kubectl create namespace monitoring

helm upgrade --install spanner-omni \
  oci://us-docker.pkg.dev/spanner-omni/charts/spanner-omni --version 1.1.0 \
  -f SpannerOmni/samples/helm/values-single-server.yaml \
  --set monitoring.enabled=true \
  --namespace spanner-ns \
  --create-namespace
```

- `deployment.listenAddresses`: A comma-separated list of IP addresses to listen on in single-server mode (`deployment.singleServer=true`). If not set, it uses the backend default (`localhost`). [`values-single-server.yaml`](SpannerOmni/samples/helm/values-single-server.yaml) sets `0.0.0.0,[::]` to allow cluster and external network access (e.g., for Kubernetes probes and external clients). *(Note: `--listen-addresses` requires Spanner Omni server image `2026.r4-lts` or later; if testing with an earlier image such as `2026.r3-beta.2`, append `--set deployment.listenAddresses=""`.)*

### 2. Deploying to a Single Zone

To deploy a native multi-server Spanner instance restricted to **one zone** (no cross-zone topology), override the `locations` array using `--set-json`:

```bash
# Pre-create the monitoring namespace if enabling the observability stack
kubectl create namespace monitoring

helm upgrade --install spanner-omni \
  oci://us-docker.pkg.dev/spanner-omni/charts/spanner-omni --version 1.1.0 \
  --set global.platform=gke \
  --set deployment.replicasPerZone=2 \
  --set deployment.rootServersPerZone=1 \
  --set-json 'locations=[{"name":"us-central1","zones":[{"name":"us-central1-a","shortName":"a"}]}]' \
  --set monitoring.enabled=true \
  --namespace spanner-ns \
  --create-namespace
```

### 3. Deploying Regional & Scaleout High Availability (Production)

To deploy a fault-tolerant, multi-zone Spanner Omni instance across a 3-zone regional Kubernetes cluster, use [`SpannerOmni/samples/helm/values-regional.yaml`](SpannerOmni/samples/helm/values-regional.yaml) (1 server per zone; deployment config: [`SpannerOmni/samples/deployment_configs/spanner-regional.yaml`](SpannerOmni/samples/deployment_configs/spanner-regional.yaml)) or [`SpannerOmni/samples/helm/values-scaleout.yaml`](SpannerOmni/samples/helm/values-scaleout.yaml) (5 servers with 3 root servers per zone; deployment config: [`SpannerOmni/samples/deployment_configs/spanner-scaleout.yaml`](SpannerOmni/samples/deployment_configs/spanner-scaleout.yaml)):

```bash
# Pre-create the monitoring namespace if enabling the observability stack
kubectl create namespace monitoring

# Regional deployment (3 zones, 1 server per zone)
helm upgrade --install spanner-omni \
  oci://us-docker.pkg.dev/spanner-omni/charts/spanner-omni --version 1.1.0 \
  -f SpannerOmni/samples/helm/values-regional.yaml \
  --set-json 'extraEnvVars=[{"name":"SPANNER_ROOT_SERVERS_COUNT","value":"1"}]' \
  --set monitoring.enabled=true \
  --namespace spanner-ns \
  --create-namespace

# Or Scaleout HA deployment (3 zones, 5 servers & 3 root servers per zone)
helm upgrade --install spanner-omni \
  oci://us-docker.pkg.dev/spanner-omni/charts/spanner-omni --version 1.1.0 \
  -f SpannerOmni/samples/helm/values-scaleout.yaml \
  --set monitoring.enabled=true \
  --namespace spanner-ns \
  --create-namespace
```

> [!NOTE]
> Ensure the zone names in `locations[].zones[].name` match your cluster's node zones (`topology.kubernetes.io/zone` label). For example, [`values-regional.yaml`](SpannerOmni/samples/helm/values-regional.yaml) defaults to `us-east1-{b,c,d}`, while [`values-gke.yaml`](SpannerOmni/helm/values-gke.yaml) (used by [`values-scaleout.yaml`](SpannerOmni/samples/helm/values-scaleout.yaml)) defaults to `us-west1-{a,b,c}`. Refer to [`SpannerOmni/helm/values.yaml`](SpannerOmni/helm/values.yaml) and [`SpannerOmni/helm/values-gke.yaml`](SpannerOmni/helm/values-gke.yaml) for additional configuration options, including storage classes (`dataStorageClass` / `logsStorageClass`, e.g. `hyperdisk-balanced-rwo` on GKE N4 nodes).

### 4. Deploying Multi-Cluster / Multi-Region & Multi-Cloud Spanner Omni

To deploy Spanner Omni across multiple Kubernetes clusters—such as spanning 3 regions using [`SpannerOmni/samples/helm/values-multi-region.yaml`](SpannerOmni/samples/helm/values-multi-region.yaml) ([`spanner-multi-region.yaml`](SpannerOmni/samples/deployment_configs/spanner-multi-region.yaml)) or spanning multiple cloud providers using [`SpannerOmni/samples/helm/values-multi-cloud.yaml`](SpannerOmni/samples/helm/values-multi-cloud.yaml) ([`spanner-multi-cloud.yaml`](SpannerOmni/samples/deployment_configs/spanner-multi-cloud.yaml))—apply the Helm chart to each participating cluster with its target `--kube-context`, `--set currentLocation=`, and matching `--namespace`.

**Important:**
- Install the chart in the same order as the locations defined in your values file.
- The Spanner deployment bootstrap job is installed in the final location and automatically triggers only when the final location cluster applies the chart, waiting for reachability across all nodes.
- Pods across clusters must be able to resolve each other by FQDN. Use [`SpannerOmni/scripts/dns-setup.sh`](SpannerOmni/scripts/dns-setup.sh) to configure cross-cluster DNS forwarding (`kube-dns` / `CoreDNS`).
- The example below assumes 3 Kubernetes clusters with `kubectl` contexts `ctx-usw1`, `ctx-usw2`, and `ctx-usw3`.
- Enable `--set monitoring.enabled=true` on your primary cluster if you want a centralized monitoring dashboard.

```bash
# Pre-create the monitoring namespace on the primary cluster hosting the observability stack
kubectl create namespace monitoring --context ctx-usw1

# 1. Install chart in us-west1 (with monitoring enabled)
helm upgrade --install spanner-omni \
  oci://us-docker.pkg.dev/spanner-omni/charts/spanner-omni --version 1.1.0 \
  -f SpannerOmni/samples/helm/values-multi-region.yaml \
  --namespace spanner-ns-usw1 \
  --set currentLocation=us-west1 \
  --set monitoring.enabled=true \
  --create-namespace \
  --kube-context ctx-usw1

# 2. Install chart in us-west2
helm upgrade --install spanner-omni \
  oci://us-docker.pkg.dev/spanner-omni/charts/spanner-omni --version 1.1.0 \
  -f SpannerOmni/samples/helm/values-multi-region.yaml \
  --namespace spanner-ns-usw2 \
  --set currentLocation=us-west2 \
  --create-namespace \
  --kube-context ctx-usw2

# 3. Install chart in us-west3
helm upgrade --install spanner-omni \
  oci://us-docker.pkg.dev/spanner-omni/charts/spanner-omni --version 1.1.0 \
  -f SpannerOmni/samples/helm/values-multi-region.yaml \
  --namespace spanner-ns-usw3 \
  --set currentLocation=us-west3 \
  --create-namespace \
  --kube-context ctx-usw3

# Configure cross-cluster DNS resolution so the bootstrap job can reach all servers
./SpannerOmni/scripts/dns-setup.sh -n spanner-ns-usw1,spanner-ns-usw2,spanner-ns-usw3 ctx-usw1 ctx-usw2 ctx-usw3
```

For a **Multi-Cloud** deployment across Amazon EKS (`us-east-1`) and Google Kubernetes Engine (`us-central1`), pass `-f SpannerOmni/samples/helm/values-multi-cloud.yaml` and override `--set global.platform=eks` on the EKS cluster and `--set global.platform=gke` on the GKE cluster:

```bash
# 1. Install chart on Amazon EKS cluster (us-east-1)
helm upgrade --install spanner-omni \
  oci://us-docker.pkg.dev/spanner-omni/charts/spanner-omni --version 1.1.0 \
  -f SpannerOmni/samples/helm/values-multi-cloud.yaml \
  --namespace spanner-ns-use1 \
  --set global.platform=eks \
  --set currentLocation=us-east-1 \
  --create-namespace \
  --kube-context ctx-eks-use1

# 2. Install chart on GKE cluster (us-central1)
helm upgrade --install spanner-omni \
  oci://us-docker.pkg.dev/spanner-omni/charts/spanner-omni --version 1.1.0 \
  -f SpannerOmni/samples/helm/values-multi-cloud.yaml \
  --namespace spanner-ns-usc1 \
  --set global.platform=gke \
  --set currentLocation=us-central1 \
  --create-namespace \
  --kube-context ctx-gke-usc1

# Configure cross-cluster DNS resolution between EKS and GKE
./SpannerOmni/scripts/dns-setup.sh -n spanner-ns-use1,spanner-ns-usc1 ctx-eks-use1 ctx-gke-usc1
```

### 5. Verifying the Deployment & Connecting

1. **Watch Pod Startup**:
   ```bash
   kubectl get pods -n spanner-ns -w
   ```
2. **Monitor the Bootstrap Job (Multi-Server Deployments)**:
   In single-zone, multi-zone, and multi-cluster deployments, a background Kubernetes Job (`spanner-bootstrap-job`) initializes the Spanner topology once all server pods are reachable (in multi-cluster deployments, check the final location's namespace, e.g., `spanner-ns-usw3` or `spanner-ns-usc1`):
   ```bash
   kubectl get job spanner-bootstrap-job -n spanner-ns -w
   kubectl logs -n spanner-ns -l app.kubernetes.io/component=bootstrap -f
   ```
3. **Verify Database Creation & SQL Execution (`spanner` CLI)**:
   Once the bootstrap job completes (or the pod is `1/1 Running` in single-server mode), verify the cluster using the bundled `spanner` CLI inside the root server pod (`spanner-a-0` for single-server or regional single-server-per-zone topologies; `spanner-a-rt-0` for scaleout, multi-region, and multi-cloud topologies with dedicated root servers):
   ```bash
   # Single-Server / Regional (1 server per zone): use pod spanner-a-0
   # Scaleout / Multi-Region / Multi-Cloud: use pod spanner-a-rt-0
   POD=spanner-a-0

   kubectl exec -n spanner-ns $POD -c spanner -- /google/spanner/bin/spanner databases list
   kubectl exec -n spanner-ns $POD -c spanner -- /google/spanner/bin/spanner databases create testdb
   kubectl exec -n spanner-ns $POD -c spanner -- /google/spanner/bin/spanner databases execute-sql testdb --sql="SELECT 1 AS ok"
   ```
4. **Retrieve the Spanner Service Endpoint**:
   Inspect the `spanner` Kubernetes Service for the client connection endpoint:
   ```bash
   kubectl get service spanner -n spanner-ns
   ```
5. **Access the Bundled Observability Dashboards (if enabled)**:
   Port-forward the Grafana service in the `monitoring` namespace to view pre-provisioned Spanner Omni dashboards:
   ```bash
   kubectl port-forward svc/grafana -n monitoring 3000:3000
   ```

## Enabling TLS and mTLS

Spanner Omni supports TLS for secure communication. By default, it uses plaintext gRPC (`global.insecureMode=true`). To enable TLS, provide certificates in a Kubernetes Secret named `tls-certs` in the target namespace and update the Helm configuration.

### 1. Create the `tls-certs` Secret

Example commands to generate self-signed certificates using the `spanner` CLI and create the `tls-certs` Secret in `spanner-ns`:

```bash
ns=spanner-ns
spanner certificates create-ca --ca-certificate-directory=certs --overwrite
cp certs/ca.crt certs/ca-api.crt
spanner certificates create-server --hostnames=*.pod.$ns --ca-certificate-directory certs --output-directory certs
endpoint="spanner.$ns.svc"
spanner certificates create-server --filename-prefix=api --hostnames=${endpoint} --ca-certificate-directory certs --output-directory certs
USERNAME=admin
spanner certificates create-client $USERNAME --output-directory clientcerts --ca-certificate-directory certs --generate-pkcs8-key

kubectl create secret generic tls-certs \
  --from-file=ca.crt="certs/ca.crt" \
  --from-file=ca-api.crt="certs/ca-api.crt" \
  --from-file=server.crt="certs/server.crt" \
  --from-file=server.key="certs/server.key" \
  --from-file=api.crt="certs/api.crt" \
  --from-file=api.key="certs/api.key" \
  -n spanner-ns
```

### 2. Configure TLS & Authentication Options

- `global.insecureMode=false`: Disables insecure mode and enables TLS.
- `deployment.enableClientCertificateAuthentication=true`: Enables client certificate authentication (mTLS).
- `deployment.enablePasswordAuthentication=true`: Enables password authentication (enabled by default).
- `deployment.adminPasswordSecret`: Name of a pre-created Kubernetes Secret containing the initial `admin` user password under the `password` key (8–32 characters, including uppercase, lowercase, number, and special character):
  ```bash
  kubectl create secret generic spanner-admin-password \
    --from-file=password=/path/to/password.txt \
    -n spanner-ns
  ```

Example installation command with TLS, mTLS, and custom admin password enabled:

```bash
helm upgrade --install spanner-omni \
  oci://us-docker.pkg.dev/spanner-omni/charts/spanner-omni --version 1.1.0 \
  --set global.platform=gke \
  --set global.insecureMode=false \
  --set deployment.enableClientCertificateAuthentication=true \
  --set deployment.adminPasswordSecret=spanner-admin-password \
  --namespace spanner-ns \
  --create-namespace
```

## Upgrading Spanner Omni

Spanner Omni uses an asynchronous, **multi-phase rollout state machine** to guarantee safe, zero-downtime upgrades:
- **Prepare phase**: Applies schema migrations to internal metadata and system tables using the target binary.
- **Binary phase**: Updates the container image across all pods via rolling restarts.
- **Subsequent / Finalize phases**: Tracked by the rollout state machine, with `finalize` as the final phase that seals the new binary version.

### Multi-Server Deployment (Production / HA)

For multi-server deployments (`deployment.singleServer=false`), `helm upgrade` automatically executes the `prepare` pre-upgrade hook Job and staggered zone rolling updates:

```bash
helm upgrade spanner-omni \
  oci://us-docker.pkg.dev/spanner-omni/charts/spanner-omni --version 1.1.0 \
  -n spanner-ns --reuse-values --set image.tag=2026.r5 --timeout 30m
```

Monitor the staggered rollout job progress:

```bash
kubectl logs -n spanner-ns -l app.kubernetes.io/component=spanner-rollout -f
```

### Single-Server Deployment (Development / Testing)

In single-server mode (`deployment.singleServer=true`), Spanner binds internal services to loopback (`127.0.0.1`), so the chart skips the external pre-upgrade hook job. Upgrade in 2 steps:

1. **Run Prepare Phase via Ephemeral Debug Container**:
   ```bash
   kubectl debug pod/spanner-a-0 -n spanner-ns \
     --image=us-docker.pkg.dev/spanner-omni/images/spanner-omni-server:2026.r5 \
     --container=upgrade-prepare -i \
     -- /google/spanner/bin/spanner_server prepare_for_upgrade --root_server=127.0.0.1
   ```
2. **Run Binary Phase via Helm**:
   ```bash
   helm upgrade spanner-omni \
     oci://us-docker.pkg.dev/spanner-omni/charts/spanner-omni --version 1.1.0 \
     -n spanner-ns --reuse-values --set image.tag=2026.r5 --timeout 30m
   ```

### Tracking Rollout Status & Progressing Phases

1. **Inspect active rollouts and phase status**:
   ```bash
   kubectl exec -n spanner-ns spanner-a-0 -c spanner -- /google/spanner/bin/spanner deployment rollouts list
   kubectl exec -n spanner-ns spanner-a-0 -c spanner -- /google/spanner/bin/spanner deployment rollouts describe <ROLLOUT_ID>
   ```
2. **Schedule the next phase (e.g., `finalize`) once `binary` transitions to `SUCCEEDED`**:
   ```bash
   kubectl exec -n spanner-ns spanner-a-0 -c spanner -- \
     /google/spanner/bin/spanner deployment rollouts phases schedule finalize --rollout=<ROLLOUT_ID>
   ```
   > [!WARNING]
   > Finalization permanently seals the target binary version; binary rollback is not possible once finalization begins.

## Production Security & Customizing Configuration

### EKS Zero-Privilege Pattern (`/dev/vmclock0`)

On AWS EKS, Spanner Omni requires read-only access to `/dev/vmclock0` for high-precision clock synchronization. To run Spanner pods fully unprivileged without the default `vmclock-chmod` root init container:

1. Configure your EKS Node Group's launch template UserData to set `0644` permissions on `/dev/vmclock0` at node boot:
   ```bash
   #!/bin/bash
   echo 'KERNEL=="vmclock0", MODE="0644"' > /etc/udev/rules.d/99-vmclock.rules
   udevadm control --reload-rules && udevadm trigger
   ```
2. Deploy the Helm chart with unprivileged overrides:
   ```yaml
   extraInitContainers: []
   forcePrivilegedContainer: false
   ```

### Customizing Spanner Configuration (`spanner.cfg` Overrides)

You can customize `spanner.cfg` using one of two **mutually exclusive** options:

1. **Option 1: Helm-Native Configuration Overrides (`deployment.spannerConfig`)**
   - Inline in `values.yaml`:
     ```yaml
     deployment:
       spannerConfig: |
         sample_property=value
     ```
   - Or from a local file at install/upgrade time:
     ```bash
     helm upgrade --install spanner-omni \
       oci://us-docker.pkg.dev/spanner-omni/charts/spanner-omni --version 1.1.0 \
       --set-file deployment.spannerConfig=path/to/local/spanner.cfg \
       --namespace spanner-ns \
       --create-namespace
     ```
2. **Option 2: Pre-Created ConfigMap (`deployment.featureFlagsConfigMap`)**
   Pre-create a `ConfigMap` containing a `spanner.cfg` key in the target namespace and pass `--set deployment.featureFlagsConfigMap=<configmap-name>`.

### Storage Classes

Creation of `StorageClass` objects is automatically enabled when platform templates use custom storage classes (e.g., `eks`). Override this behavior manually with `--set createStorageClasses=true` (or `false`).

## Repository Structure

```text
spanner-omni/
├── SpannerOmni/
│   ├── helm/
│   │   ├── Chart.yaml                  # Main Spanner Omni Helm chart definition
│   │   ├── values.yaml                 # Default Helm chart configuration values
│   │   ├── values-gke.yaml             # Google Kubernetes Engine (GKE) platform overrides
│   │   ├── values-eks.yaml             # Amazon EKS platform overrides
│   │   ├── values-aks.yaml             # Azure AKS platform overrides
│   │   ├── templates/                  # Kubernetes manifests (StatefulSets, Jobs, Services, RBAC)
│   │   └── charts/
│   │       └── monitoring/             # Optional observability subchart (Prometheus, Grafana, Jaeger)
│   ├── samples/
│   │   ├── deployment_configs/
│   │   │   ├── spanner-multi-region.yaml
│   │   │   ├── spanner-multi-cloud.yaml
│   │   │   ├── spanner-regional.yaml
│   │   │   ├── spanner-scaleout.yaml
│   │   │   └── spanner-single-server.yaml
│   │   └── helm/
│   │       ├── values-multi-region.yaml
│   │       ├── values-multi-cloud.yaml
│   │       ├── values-regional.yaml
│   │       ├── values-scaleout.yaml
│   │       └── values-single-server.yaml
│   └── scripts/
│       └── dns-setup.sh                # Cross-cluster DNS forwarding setup (kube-dns / CoreDNS)
├── CODE_OF_CONDUCT.md
├── CONTRIBUTING.md
├── LICENSE
└── README.md
```

- [`SpannerOmni/helm/`](SpannerOmni/helm/): Official Helm chart for deploying Spanner Omni (`spanner-omni`), including StatefulSets, bootstrap/rollout jobs, web console, and the optional [`monitoring`](SpannerOmni/helm/charts/monitoring/) subchart (Prometheus, pre-provisioned Grafana dashboards and alert rules, and Jaeger tracing).
- [`SpannerOmni/samples/`](SpannerOmni/samples/): Sample configurations for Spanner Omni, including sample Helm values ([`SpannerOmni/samples/helm/`](SpannerOmni/samples/helm/)) and sample Spanner deployment configurations ([`SpannerOmni/samples/deployment_configs/`](SpannerOmni/samples/deployment_configs/)) for single-server, regional, scaleout, multi-region, and multi-cloud topologies.
- [`SpannerOmni/scripts/`](SpannerOmni/scripts/): Operational helper scripts, including `dns-setup.sh` for configuring cross-cluster DNS resolution (`kube-dns` / `CoreDNS`) in multi-cluster deployments.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for details. Also see our [Code of Conduct](CODE_OF_CONDUCT.md).

## License

Apache 2.0; see [LICENSE](LICENSE) for details.

## Security

Eligibility for the [Google Open Source Software Vulnerability Rewards Program](https://bughunters.google.com/open-source-security) is determined by the [Google Open Source Software Vulnerability Reward Program Rules](https://bughunters.google.com/about/rules/open-source/google-open-source-software-vulnerability-reward-program-rules).
