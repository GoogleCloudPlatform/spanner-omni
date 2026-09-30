#!/bin/bash

# Copyright 2025 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#

# This script configures DNS for a multi-cluster Spanner deployment.
# Spanner deployment requires pod to pod communication.
# Spanner uses hostname (stable hostname) for the communication.
# This requires name resolution to work for establishing TCP connection.
#

# Global variables
CONTEXTS=()
EXPLICIT_NAMESPACES=()
NAMESPACE_PREFIX=""
SPANNER_DNS_LB_FILE=""
declare -A DOMAIN_TO_NAME_SERVERS=()
declare -A CONTEXT_TO_SPANNER_NAMESPACE=()

# --- Usage function ---
function usage() {
  echo "Usage: $0 [-n <ns1,ns2...>] [-p <namespace_prefix>] [-d <spanner-dns-lb.yaml>] <context1> <context2> ..."
  echo "Configures DNS for multi-cluster Spanner deployments."
  echo ""
  echo "OPTIONS:"
  echo "  -n <namespaces>       : Optional. Comma-separated list of explicit namespaces (e.g. spanner-east,spanner-central)."
  echo "  -p <namespace_prefix> : Optional. Prefix of the namespaces (e.g. spanner-ns). Used if -n is not provided."
  echo "  -d <spanner-dns-lb.yaml>    : Optional. Path to spanner-dns-lb.yaml. If provided, applies the file to all clusters."
  echo "  -h                    : Display this help."
  echo ""
  echo "ARGUMENTS:"
  echo "  <context...>: Two or more Kubernetes context names for the Kubernetes clusters."
  exit 1
}

# --- Parse the command-line options ---
function parse_options() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -p|--namespace-prefix)
        NAMESPACE_PREFIX="$2"
        shift # past argument
        shift # past value
        ;;
      -n|--namespaces)
        IFS=',' read -r -a EXPLICIT_NAMESPACES <<< "$2"
        shift # past argument
        shift # past value
        ;;
      -d|--dns-lb-file)
        SPANNER_DNS_LB_FILE="$2"
        shift # past argument
        shift # past value
        ;;
      -h|--help)
        usage
        ;;
      *)
        CONTEXTS+=("$1") # Save the remaining arguments as contexts
        shift # past argument
        ;;
    esac
  done
}

function populate_context_to_spanner_namespace() {
  for i in "${!CONTEXTS[@]}"; do
    context=${CONTEXTS[$i]}
    if [[ ${#EXPLICIT_NAMESPACES[@]} -gt 0 ]]; then
      CONTEXT_TO_SPANNER_NAMESPACE["$context"]="${EXPLICIT_NAMESPACES[$i]}"
    else
      CONTEXT_TO_SPANNER_NAMESPACE["$context"]="${NAMESPACE_PREFIX}$((i+1))"
    fi
  done
}

function apply_spanner_dns_lb_file() {
  for context in "${CONTEXTS[@]}"; do
    echo "Applying $SPANNER_DNS_LB_FILE to cluster with context ${context} ..."
    kubectl apply -f "$SPANNER_DNS_LB_FILE" --context "$context"
    if [[ $? -ne 0 ]]; then
        echo "ERROR: Failed to apply $SPANNER_DNS_LB_FILE for context $KUBECTL_CONTEXT_NAME. Skipping IP retrieval for this cluster." >&2
        return 1
    fi
  done
  for context in "${CONTEXTS[@]}"; do
    echo "Waiting for External IP for Service: spanner-dns in namespace: kube-system"
    kubectl wait service/spanner-dns -n "kube-system" \
      --for=jsonpath='{.status.loadBalancer.ingress[0]}' \
      --timeout=5m --context "$context"
    if [[ $? -ne 0 ]]; then
      echo "ERROR: Timed out waiting for External IP for Service: spanner-dns in namespace: kube-system for context: $context"
      return 1
    fi
  done
}
# Function to fetch the property of the spanner-dns service with retries.
# This function retries fetching the property 10 times with a 10 second delay.
# If the property is not found after 10 retries, the function returns 1.
function get_spanner_dns_service_ip_with_retries() {
  local context=$1
  local retries=10
  while [[ $retries -gt 0 ]]; do
    # Get the IP address of the spanner-dns service.
    local ip_address
    ip_address=$(kubectl get service "spanner-dns" -n "kube-system" --context "$context" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    if [[ $? -eq 0 && -n "$ip_address" ]]; then
      echo "\"$ip_address\"" # Only echo the value to stdout for capture
      return 0
    fi
    local hostname
    hostname=$(kubectl get service "spanner-dns" -n "kube-system" --context "$context" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    if [[ $? -eq 0 && -n "$hostname" ]]; then
      echo "Obtained DNS service hostname: $hostname, resolving to IPs..." >&2
      echo "$(resolve_hostname_to_ips_with_retries "$hostname")"
      return 0
    fi
    echo "Failed to get IP or hostname for service spanner-dns in namespace: kube-system for context: $context, retrying in 10 seconds..." >&2
    sleep 10
    retries=$((retries-1))
  done
  echo "Failed to get IP or hostname for service spanner-dns in namespace: kube-system for context: '$context' after multiple retries." >&2
  return 1
}

# Function to resolve the hostname to IPs with retries.
function resolve_hostname_to_ips_with_retries() {
  local hostname=$1
  local retries=100
  while [[ $retries -gt 0 ]]; do
    local dig_output
    dig_output=$(dig +short A "$hostname")
    if [[ $? -eq 0 && -n "$dig_output" ]]; then
      # Format to comma-separated JSON array elements: "1.2.3.4", "5.6.7.8"
      echo "$dig_output" | awk '{print "\""$0"\""}' | paste -sd, - | sed 's/,/, /g'
      return 0
    fi
    echo "Failed to resolve hostname: $hostname to IPs, retrying in 5 seconds..." >&2
    retries=$((retries-1))
    sleep 5
  done
  echo "Failed to resolve hostname: $hostname to IPs after multiple retries." >&2
  return 1
}

# Function to fetch the external IPs of the spanner-dns service in each cluster.
# This function populates the DOMAIN_TO_NAME_SERVERS global variable with
# the external IPs for each cluster. External endpoint in case of NLBs in EKS
# will not be IP, it would have endpoint but nameservers needs to be 
# IP addresses, so it also resolves the hostname to get the IP addresses.
function fetch_spanner_dns_lb_ips() {
  for context in "${CONTEXTS[@]}"; do
    local external_ips
    external_ips=$(get_spanner_dns_service_ip_with_retries "$context")
    if [[ $? -ne 0 ]]; then
      echo "ERROR: Failed to get external IPs for context $context. Skipping DNS configuration for this cluster." >&2
      continue
    fi
    local dns_suffix="${CONTEXT_TO_SPANNER_NAMESPACE["$context"]}.svc.cluster.local"
    DOMAIN_TO_NAME_SERVERS["$dns_suffix"]="$external_ips"
  done
  echo "Fetched all the name servers for all the contexts."
  for key in "${!DOMAIN_TO_NAME_SERVERS[@]}"; do
    echo "  $key: ${DOMAIN_TO_NAME_SERVERS[$key]}"
  done
}

# Function to configure kube-dns using stubDomains for kube-dns in each cluster.
# This function adds the new stubDomains for each cluster in the list of
# stubDomains for kube-dns in each cluster.

# Constructs the stub domains JSON and patch them like below:
# {
#   "us-central1.svc.cluster.local": ["1.2.3.4", "5.6.7.8"],
#   "us-east1.svc.cluster.local": ["9.10.11.12", "13.14.15.16"]
# }
function configure_kubedns() {
  local namespace="kube-system"
  local configmap_name="kube-dns"
  for context in "${CONTEXTS[@]}"; do
    kubectl get configmap "$configmap_name" -n "$namespace" --context "$context" > /dev/null
    if [[ $? -ne 0 ]]; then
        echo "Cluster $context does not have kube-dns configmap. Skipping kube-dns configuration for this cluster." >&2
        continue
    else
      echo "Cluster $context has kube-dns configmap. Updating the stub domains." >&2
    fi
    # Extract the existing stub domains from the configmap.
    local new_stub_domains_str="{"
    local first=true
    existing_stub_domains=$(kubectl get configmap "$configmap_name" -n "$namespace" -o jsonpath='{.data.stubDomains}' --context "$context")
    if [[ -z "$existing_stub_domains" ]]; then
      echo "No existing stub domains found. Creating a new stub domains file."
    else 
      echo "Existing stub domains: $existing_stub_domains found. Updating the stub domains file."
      # Remove } as that will be added after populating everything.
      new_stub_domains_str=$(echo "$existing_stub_domains"| tr -d '}' )
      first=false
    fi
    # Append the new stub domains to the existing stub domains.
    for key in "${!DOMAIN_TO_NAME_SERVERS[@]}"; do
    #  skip for current context namespace
      if [[ "$key" == "${CONTEXT_TO_SPANNER_NAMESPACE["$context"]}.svc.cluster.local" ]]; then
        continue
      fi
      if $first; then
        first=false
      else
        new_stub_domains_str+=", "
      fi

      new_stub_domains_str+="\"$key\": [${DOMAIN_TO_NAME_SERVERS[$key]}]"
    done
    new_stub_domains_str+="}"
    # Create a patch file with the new stub domains and apply it.
    local patch_file
    patch_file=$(mktemp)
    echo "data:" > "$patch_file"
    echo "  stubDomains: |" >> "$patch_file"
    echo "    $new_stub_domains_str" >> "$patch_file"
    echo "Updating the cluster $context with stub domain patch: $patch_file"
    kubectl patch configmap "$configmap_name" -n "$namespace" --patch-file "$patch_file" --context "$context"
    if [[ $? -ne 0 ]]; then
      echo "Error: Failed to update stub domains for cluster $context."
      exit 1
    fi
    rm "$patch_file"
    echo "Restarting kube-dns deployment in cluster $context to pick up stubDomain changes."
    kubectl -n "$namespace" rollout restart deployment kube-dns --context "$context"
    if [[ $? -ne 0 ]]; then
      echo "Error: Failed to restart kube-dns deployment for cluster $context."
      exit 1
    fi
    echo "Waiting for kube-dns deployment to be ready in cluster $context."
    kubectl -n "$namespace" rollout status deployment kube-dns --context "$context" --timeout=5m
    if [[ $? -ne 0 ]]; then
      echo "Error: kube-dns deployment failed to become ready in cluster $context."
      exit 1
    fi
  done
  return 0
}

# Function to patch the default coredns configmap.
# This function patches the default coredns configmap with the given
# corefile patch.
function patch_default_coredns_configmap() {
  local context=$1
  local configmap_name=$2
  local corefile_patch=$3
  local namespace="kube-system"
  # Create a patch file with the new forward domains.
  local patch_file
  patch_file=$(mktemp)
  cat <<EOF > "$patch_file"
data:
  Corefile: |
$(kubectl get configmap "$configmap_name" -n "$namespace" -o jsonpath='{.data.Corefile}' --context "$context" | sed 's/^/    /')
$corefile_patch
EOF
  echo "Updating the cluster $context with coredns patch: $patch_file"
  kubectl patch configmap "$configmap_name" -n "$namespace" --patch-file "$patch_file" --context "$context"
  if [[ $? -ne 0 ]]; then
    echo "Error: Failed to update coredns for cluster $context."
    exit 1
  fi
  rm "$patch_file"
}

# Function to patch the custom coredns configmap.
# This function patches the custom coredns configmap with the given
# corefile patch.
function patch_custom_coredns_configmap() {
  local context=$1
  local configmap_name=$2
  local corefile_patch=$3
  local namespace="kube-system"
  # Create a temporary file for the coredns-custom ConfigMap.
  local patch_file
  patch_file=$(mktemp)
  cat <<EOF > "$patch_file"
apiVersion: v1
kind: ConfigMap
metadata:
  name: $configmap_name
  namespace: $namespace
data:
  spanner.server: |
$corefile_patch
EOF

  echo "Applying coredns-custom configmap to cluster $context"
  kubectl apply -f "$patch_file" --context "$context"
  if [[ $? -ne 0 ]]; then
    echo "Error: Failed to apply $configmap_name for cluster $context."
    return 1
  fi
  rm "$patch_file"

  echo "Restarting coredns deployment in cluster $context"
  kubectl -n "$namespace" rollout restart deployment coredns --context "$context"
  if [[ $? -ne 0 ]]; then
    echo "Error: Failed to restart coredns deployment for cluster $context."
    return 1
  fi
  return 0
}

# Function to create the corefile patch for the given context.
# This function creates the corefile patch for the given context by iterating
# through the DOMAIN_TO_NAME_SERVERS global variable and adding the forward
# domains for each cluster in the list of forward domains for CoreDNS in each
# cluster.
function create_corefile_patch() {
  context=$1
    local corefile_patch=""
    for key in "${!DOMAIN_TO_NAME_SERVERS[@]}"; do
      #  skip for current context namespace
      if [[ "$key" == "${CONTEXT_TO_SPANNER_NAMESPACE["$context"]}.svc.cluster.local" ]]; then
        continue
      fi
      local name_servers=${DOMAIN_TO_NAME_SERVERS[$key]//\"/} # remove quotes
      name_servers=${name_servers//,/ } # convert commas to spaces
      corefile_patch+="
    $key:53 {
      forward . ${name_servers}
    }"
    done
    echo "$corefile_patch"
}
# Function to configure CoreDNS using the forward plugin.
# This function adds the new forward domains for each cluster in the list of
# forward domains for CoreDNS in each cluster.

# Constructs the forward domains and patch them like below:
# domain1.svc.cluster.local {
#   forward . 1.2.3.4 5.6.7.8
# }
# domain2.svc.cluster.local {
#   forward . 9.10.11.12 13.14.15.16
# }
function configure_coredns() {
  local namespace="kube-system"
  for context in "${CONTEXTS[@]}"; do
    corefile_patch=$(create_corefile_patch "$context")
    if [[ -z "$corefile_patch" ]]; then
      echo "No cross cluster DNS configuration needed for context $context"
      continue
    fi
    # Check if the cluster is an AKS cluster by inspecting the providerID of a node.
    local provider_id
    provider_id=$(kubectl get nodes -o jsonpath='{.items[0].spec.providerID}' --context "$context" 2>/dev/null)
    if [[ "$provider_id" == "azure"* ]]; then
        echo "Cluster $context is an AKS cluster. Configuring coredns-custom."
        patch_custom_coredns_configmap "$context" "coredns-custom" "$corefile_patch"
        if [[ $? -ne 0 ]]; then
            echo "Error: Failed to patch coredns-custom for cluster $context."
        fi
    else
        kubectl get configmap "coredns" -n "$namespace" --context "$context" > /dev/null
        if [[ $? -ne 0 ]]; then
            echo "Cluster $context does not have coredns configmap. Skipping CoreDNS configuration for this cluster." >&2
            continue
        fi
        echo "Cluster $context is not an AKS cluster. Configuring default coredns."
        patch_default_coredns_configmap "$context" "coredns" "$corefile_patch"
    fi
  done
  return 0
}

function validate_options() {
# --- Validation ---
if [[ ${#EXPLICIT_NAMESPACES[@]} -eq 0 ]] && [[ -z "$NAMESPACE_PREFIX" ]]; then
    echo "Error: Either explicit namespaces (-n) or namespace prefix (-p) is required." >&2
    usage
fi
if [[ ${#EXPLICIT_NAMESPACES[@]} -gt 0 ]] && [[ ${#EXPLICIT_NAMESPACES[@]} -ne ${#CONTEXTS[@]} ]]; then
    echo "Error: The number of explicit namespaces provided (-n) must match the number of contexts." >&2
    usage
fi
if [[ -n "$SPANNER_DNS_LB_FILE" ]]; then
  if [[ ! -f "$SPANNER_DNS_LB_FILE" ]]; then
        error "$SPANNER_DNS_LB_FILE not found. Please ensure it exists or update the path."
  fi
fi
if [[ ${#CONTEXTS[@]} -lt 2 ]]; then
    echo "Error: At least two Kubernetes context must be provided." >&2
    usage
fi
}

# --- Main execution ---
parse_options "$@"
validate_options
populate_context_to_spanner_namespace
if [[ -n "$SPANNER_DNS_LB_FILE" ]]; then
  apply_spanner_dns_lb_file
fi
fetch_spanner_dns_lb_ips
# configure_ methods skips clusters which don't have the required configmaps.
configure_kubedns
configure_coredns
echo "DNS setup script completed."
