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
Resolve effective values for monitoring subchart by merging subchart values and platform overrides.
*/}}
{{- define "monitoring.PlatformValues" -}}
{{- $base := dict -}}
{{- if and .Values.global .Values.global.platform -}}
  {{- $platformFile := printf "values-%s.yaml" .Values.global.platform -}}
  {{- $platformContent := .Files.Get $platformFile -}}
  {{- if $platformContent -}}
    {{- $base = $platformContent | fromYaml -}}
  {{- end -}}
{{- end -}}
{{- $result := deepCopy .Values -}}
{{- $result = merge $result $base -}}
{{- toYaml $result -}}
{{- end -}}

{{/*
Whether the bundled Jaeger serves OTLP gRPC over TLS: jaeger.tls.enabled if it
is set, otherwise on in secure mode (global.insecureMode=false). Renders "true"
or "false".
*/}}
{{- define "monitoring.jaegerTlsEnabled" -}}
{{- $enabled := (.Values.jaeger.tls | default dict).enabled -}}
{{- if kindIs "invalid" $enabled -}}
{{- eq (.Values.global | default dict).insecureMode false -}}
{{- else -}}
{{- $enabled -}}
{{- end -}}
{{- end -}}
