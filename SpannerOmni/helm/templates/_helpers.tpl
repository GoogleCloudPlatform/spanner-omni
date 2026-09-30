{{/*
Copyright 2026 Google LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/}}

{{/*
Name of the chart which would default name for the application: ``app.kubernetes.io/name``.
*/}}
{{- define "spanner-omni.name" -}}
{{- default $.Chart.Name $.Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Full name of the installation. This allows to install chart multiple times on the same cluster.
*/}}
{{- define "spanner-omni.fullname" -}}
{{- if $.Values.fullnameOverride -}}
{{- $.Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := include "spanner-omni.name" . -}}
{{- if contains $name $.Release.Name -}}
{{- $.Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" $.Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "spanner-omni.chart" -}}
{{- printf "%s-%s" $.Chart.Name $.Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels, these are used to select resources. This is to support multiple releases on the same K8s cluster.
*/}}
{{- define "spanner-omni.selectorLabels" -}}
app.kubernetes.io/name: {{ include "spanner-omni.name" . }}
app.kubernetes.io/instance: {{ $.Release.Name }}
{{- end }}

{{/*
Define spanner-omni.labels to carry common labels we apply to all the resources.
*/}}
{{- define "spanner-omni.labels" -}}
helm.sh/chart: {{ include "spanner-omni.chart" . }}
{{ include "spanner-omni.selectorLabels" . }}
{{- if $.Chart.AppVersion }}
app.kubernetes.io/version: {{ $.Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ $.Release.Service }}
{{- end }}

{{/*
Returns the correct spanner docker string supporting OCI SHA digest tags cleanly.
*/}}
{{- define "spanner-omni.image" -}}
{{- if $.Values.image.digest -}}
{{- printf "%s@%s" $.Values.image.repository $.Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" $.Values.image.repository ($.Values.image.tag | default $.Chart.AppVersion) -}}
{{- end -}}
{{- end -}}

{{/*
Allow the release namespace to be overridden for deployments in custom namespaces
*/}}
{{- define "spanner-omni.namespace" -}}
  {{- $ns := default $.Release.Namespace $.Values.namespaceOverride -}}
  {{- ternary "spanner-ns" $ns (eq $ns "default") -}}
{{- end -}}

{{/*
  UI port is base_port+12
*/}}
{{- define "spanner-omni.uiPort" -}}
  {{- add $.Values.deployment.basePort 12 -}}
{{- end -}}

{{/*
  UI Console port is base_port+26
*/}}
{{- define "spanner-omni.consolePort" -}}
  {{- add ($.Values.deployment.basePort | default 15000) 26 -}}
{{- end -}}

{{/*
Resolve effective values by merging defaults, platform overrides, and user overrides.
User overrides are set in .Values object. This takes highest precedence. If user provided platform,
then platform values are merged with .Values if no platform, default values are merged.
*/}}
{{- define "spanner-omni.PlatformValues" -}}
{{- $platformValues := dict -}}
{{- if .Values.global.platform -}}
  {{- $platformFile := printf "values-%s.yaml" .Values.global.platform -}}
  {{- $platformYaml := .Files.Get $platformFile -}}
  {{- if $platformYaml -}}
    {{- $platformValues = $platformYaml | fromYaml -}}
  {{- else -}}
    {{- fail (printf "Platform file %s not found" $platformFile) -}}
  {{- end -}}
{{- else -}}
  {{- $platformValues = .Values.defaults | default dict -}}
{{- end -}}
{{- $result := dict -}}
{{- range $key := keys (.Values.defaults | default dict) -}}
  {{- if hasKey $.Values $key -}}
    {{- $_ := set $result $key (get $.Values $key) -}}
  {{- else if hasKey $platformValues $key -}}
    {{- $_ := set $result $key (get $platformValues $key) -}}
  {{- else -}}
    {{- $_ := set $result $key (get $.Values.defaults $key) -}}
  {{- end -}}
{{- end -}}
{{- toYaml $result -}}
{{- end -}}

{{/*
Returns the full location object for the current location as YAML.
*/}}
{{- define "spanner-omni.currentLocation" -}}
  {{- $platformValues := include "spanner-omni.PlatformValues" . | fromYaml -}}
  {{- $currentLoc := dict -}}
  {{- if .Values.currentLocation -}}
    {{- range $loc := $platformValues.locations -}}
      {{- if eq $loc.name $.Values.currentLocation -}}
        {{- $currentLoc = $loc -}}
      {{- end -}}
    {{- end -}}
  {{- else if and $platformValues.locations (gt (len $platformValues.locations) 0) -}}
    {{- $currentLoc = index $platformValues.locations 0 -}}
  {{- end -}}
  {{- toYaml $currentLoc -}}
{{- end -}}

{{/*
Generate Spanner multi-server deployment configuration.
*/}}
{{- define "spanner-omni.deploymentConfig" -}}
{{- $platformValues := include "spanner-omni.PlatformValues" . | fromYaml -}}
name: {{ include "spanner-omni.name" . }}
{{- if $.Values.deployment.singleServer }}
single_server: true
zone:
  - name: default
    single_server: true
    root_server:
      - host: localhost
{{- else }}
location:
  {{- range $loc := $platformValues.locations }}
  - name: {{ $loc.name }}
  {{- end }}
zone:
  {{- range $loc := $platformValues.locations }}
  {{- range $zObj := $loc.zones }}
  {{- $zoneRootServers := $zObj.rootServers | default $.Values.deployment.rootServersPerZone | int }}
  {{- $hostPrefix := printf "spanner-%s" ($zObj.shortName | default $zObj.name) }}
  {{- $isZoneSingleServer := or $.Values.deployment.singleServer $zObj.singleServer }}
  {{- if and (include "spanner-omni.rootServers.dedicated" $) (not $isZoneSingleServer) }}
    {{- $hostPrefix = printf "%s-rt" $hostPrefix }}
  {{- end }}
  {{- $zoneNamespace := $loc.namespace | default (include "spanner-omni.namespace" $) }}
  - name: {{ $zObj.name }}
    location: {{ $loc.name }}
    single_server: {{ $zObj.singleServer | default false }}
    {{- if $zObj.replicaType }}
    replica_type: {{ $zObj.replicaType }}
    {{- end }}
    root_server:
      {{- range $i := until $zoneRootServers }}
      - host: {{ $hostPrefix }}-{{ $i }}.pod.{{ $zoneNamespace }}
      {{- end }}
  {{- end }}
  {{- end }}
{{- end }}
deployment_settings:
  security_settings:
    insecure_mode: {{ $.Values.global.insecureMode | default false }}
    {{- if not $.Values.global.insecureMode }}
    {{- if or $.Values.deployment.enableClientCertificateAuthentication $.Values.deployment.enablePasswordAuthentication }}
    authentication_methods:
      {{- if $.Values.deployment.enableClientCertificateAuthentication }}
      - AUTHENTICATION_METHOD_CLIENT_CERTIFICATE
      {{- end }}
      {{- if $.Values.deployment.enablePasswordAuthentication }}
      - AUTHENTICATION_METHOD_PASSWORD
      {{- end }}
    {{- end }}
    {{- if $.Values.deployment.enablePasswordAuthentication }}
    password_authentication_protocol: PASSWORD_AUTHENTICATION_PROTOCOL_OPAQUE
    {{- end }}
    {{- end }}
{{- end -}}
{{/*
Determine whether to support zonal rollout (zone by zone in sequential).
Returns "true" if supported, empty string otherwise.
*/}}
{{- define "spanner-omni.shouldSupportStaggeredRollout" -}}
  {{- $result := false }}
  {{- if and (not .Release.IsInstall) (not .Values.deployment.singleServer) .Values.rollout.staggered }}
    {{- $zones := (include "spanner-omni.currentLocation" . | fromYaml).zones -}}
    {{- if gt (len $zones) 1 }}
      {{- $result = true }}
    {{- end }}
  {{- end }}
  {{- if $result }}true{{- end }}
{{- end }}

{{- define "spanner-omni.uiReplicas" -}}
  {{- $replicas := 1 -}}
  {{- if .Values.console.replicas -}}
    {{- $replicas = .Values.console.replicas -}}
  {{- else if .Values.deployment.singleServer -}}
    {{- $replicas = 1 -}}
  {{- else -}}
    {{- $zones := (include "spanner-omni.currentLocation" . | fromYaml).zones -}}
    {{- $replicas = max (len $zones) 2 -}}
  {{- end -}}
  {{- $replicas -}}
{{- end -}}
{{- define "spanner-omni.uiImage" -}}
  {{- $repo := .Values.console.image.repository -}}
  {{- if not $repo -}}
    {{- $coreRepo := .Values.image.repository | trimSuffix "-server" -}}
    {{- $repo = printf "%s-ui" $coreRepo -}}
  {{- end -}}
  {{- if .Values.console.image.digest -}}
    {{- printf "%s@%s" $repo .Values.console.image.digest -}}
  {{- else -}}
    {{- printf "%s:%s" $repo (.Values.console.image.tag | default (.Values.image.tag | default .Chart.AppVersion)) -}}
  {{- end -}}
{{- end -}}

{{/*
Determine whether console is enabled. If user explicitly provided, use that
otherwise default to true for insecure mode false otherwise.
*/}}
{{- define "spanner-omni.consoleEnabled" -}}
  {{- if and (hasKey .Values.console "enabled") (ne .Values.console.enabled nil) -}}
    {{- .Values.console.enabled -}}
  {{- else -}}
    {{- .Values.global.insecureMode -}}
  {{- end -}}
{{- end -}}
{{/*
Determine whether dedicated StatefulSet should be used for root servers.
Defaults to auto-detecting cluster state (true for fresh installs). Returns "true" if dedicated StatefulSet should be used, empty string otherwise.
*/}}
{{- define "spanner-omni.rootServers.dedicated" -}}
  {{- $dedicated := "true" -}}
  {{- $namespace := include "spanner-omni.namespace" . -}}
  {{- range $zObj := (include "spanner-omni.currentLocation" . | fromYaml).zones -}}
    {{- if not (or $.Values.deployment.singleServer $zObj.singleServer) -}}
      {{- $suffix := $zObj.shortName | default $zObj.name -}}
      {{- $rtExists := lookup "apps/v1" "StatefulSet" $namespace (printf "spanner-%s-rt" $suffix) -}}
      {{- $stdExists := lookup "apps/v1" "StatefulSet" $namespace (printf "spanner-%s" $suffix) -}}
      {{- if and $stdExists (not $rtExists) -}}
        {{- /* Legacy cluster detected: 'spanner-%s' exists but 'spanner-%s-rt' does not */ -}}
        {{- $dedicated = "" -}}
        {{- break -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
  {{- $dedicated -}}
{{- end -}}


{{/*
Generate comma-separated list of root server pod addresses to join for a given zone.
Usage: include "spanner-omni.joinServers" (dict "zone" $zone "context" $)
*/}}
{{- define "spanner-omni.joinServers" -}}
  {{- if not (or .context.Values.deployment.singleServer .zone.singleServer) -}}
    {{- $isDedicated := eq (include "spanner-omni.rootServers.dedicated" .context) "true" -}}
    {{- $rootServersCount := int (.zone.rootServers | default .context.Values.deployment.rootServersPerZone | default 1) -}}
    {{- $shortName := .zone.shortName | default .zone.name -}}
    {{- $rtPrefix := printf "spanner-%s" $shortName -}}
    {{- if $isDedicated }}{{ $rtPrefix = printf "%s-rt" $rtPrefix }}{{ end -}}
    {{- $namespace := include "spanner-omni.namespace" .context -}}
    {{- $joinServers := list -}}
    {{- range $i := until $rootServersCount -}}
      {{- $joinServers = append $joinServers (printf "%s-%d.pod.%s" $rtPrefix $i $namespace) -}}
    {{- end -}}
    {{- join "," $joinServers -}}
  {{- end -}}
{{- end -}}

{{/*
Calculate maxUnavailable for a StatefulSet.
Root servers are always updated 1 at a time (fixed to 1).
Non-root servers use deployment.maxUnavailablePercentage (defaults to 5, minimum 1).
Usage: include "spanner-omni.maxUnavailable" (dict "replicas" $replicas "isRoot" $isRoot "context" $)
*/}}
{{- define "spanner-omni.maxUnavailable" -}}
{{- ternary 1 (max 1 (div (mul (int .replicas) (int (dig "maxUnavailablePercentage" 5 (default dict .context.Values.deployment)))) 100)) .isRoot -}}
{{- end -}}

{{/*
Generate ordered list of all StatefulSets to deploy for the current location.
Each item in the list is a dictionary containing:
  - name: StatefulSet name (e.g. spanner-a or spanner-a-rt)
  - zone: zone object (name, shortName, etc.)
  - replicas: number of replicas for this StatefulSet
  - isRoot: boolean indicating if this is the root StatefulSet
  - type: string ("root", "non-root", or "" if unified/single)
  - joinServers: comma-separated list of root server pod addresses to join
  - maxUnavailable: maximum unavailable replicas during rolling updates
Usage: include "spanner-omni.statefulSets" $ | fromYamlArray
*/}}
{{- define "spanner-omni.statefulSets" -}}
  {{- $isSingleServer := .Values.deployment.singleServer -}}
  {{- $zones := list -}}
  {{- if $isSingleServer -}}
    {{- $zones = list (dict "name" "default" "shortName" "a" "replicas" 1 "rootServers" 1) -}}
  {{- else -}}
    {{- $zones = (include "spanner-omni.currentLocation" . | fromYaml).zones -}}
  {{- end -}}
  {{- $isDedicated := and (not $isSingleServer) (eq (include "spanner-omni.rootServers.dedicated" .) "true") -}}
  {{- $stsList := list -}}
  {{- range $zone := $zones -}}
    {{- $replicaCount := int ($zone.replicas | default $.Values.deployment.replicasPerZone | default 1) -}}
    {{- $rootServersCount := int ($zone.rootServers | default $.Values.deployment.rootServersPerZone | default 1) -}}
    {{- $shortName := $zone.shortName | default $zone.name -}}
    {{- $isZoneSingleServer := or $isSingleServer $zone.singleServer -}}
    {{- if and $isDedicated (not $isZoneSingleServer) -}}
      {{- $joinServers := include "spanner-omni.joinServers" (dict "zone" $zone "context" $) -}}
      {{- $nonRootReplicas := sub $replicaCount $rootServersCount -}}
      {{- if gt $nonRootReplicas 0 -}}
        {{- $maxUnavailable := int (include "spanner-omni.maxUnavailable" (dict "replicas" $nonRootReplicas "isRoot" false "context" $)) -}}
        {{- $stsList = append $stsList (dict "name" (printf "spanner-%s" $shortName) "zone" $zone "replicas" $nonRootReplicas "isRoot" false "type" "non-root" "joinServers" $joinServers "maxUnavailable" $maxUnavailable) -}}
      {{- end -}}
      {{- $rootMaxUnavailable := int (include "spanner-omni.maxUnavailable" (dict "replicas" $rootServersCount "isRoot" true "context" $)) -}}
      {{- $stsList = append $stsList (dict "name" (printf "spanner-%s-rt" $shortName) "zone" $zone "replicas" $rootServersCount "isRoot" true "type" "root" "joinServers" "" "maxUnavailable" $rootMaxUnavailable) -}}
    {{- else -}}
      {{- $joinServers := include "spanner-omni.joinServers" (dict "zone" $zone "context" $) -}}
      {{- $maxUnavailable := int (include "spanner-omni.maxUnavailable" (dict "replicas" $replicaCount "isRoot" false "context" $)) -}}
      {{- $stsList = append $stsList (dict "name" (printf "spanner-%s" $shortName) "zone" $zone "replicas" $replicaCount "isRoot" false "type" "" "joinServers" $joinServers "maxUnavailable" $maxUnavailable) -}}
    {{- end -}}
  {{- end -}}
  {{- toYaml $stsList -}}
{{- end -}}
