# ----- Namespace de Monitoramento -----
resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"
  }
  depends_on = [module.eks]
}

# O webhook do Discord aceita o payload do Slack através do sufixo
# "/slack" na URL. "title"/"text" só existem no schema do slack_configs
# do Alertmanager (webhook_configs genérico não tem esses campos).
locals {
  discord_slack_webhook_url = can(regex("/slack/?$", var.discord_webhook_url)) ? var.discord_webhook_url : "${var.discord_webhook_url}/slack"
}

# ----- AlertManager Config Secret (Injeção dinâmica de Webhook e Chaves) -----
resource "kubernetes_secret_v1" "alertmanager_config" {
  metadata {
    name      = "alertmanager-config"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  type = "Opaque"

  data = {
    "alertmanager.yaml" = <<-EOT
      global:
        resolve_timeout: 5m

      route:
        group_by: ['alertname', 'namespace', 'service']
        group_wait: 30s
        group_interval: 5m
        repeat_interval: 1h
        receiver: 'null'
        routes:
          - matchers:
              - alertname =~ "DonationServiceHighErrorRate|DonationServiceSLOBurnRateFast|DonationServiceSLOBurnRateSlow|ServiceUnavailable|DonationServiceHighLatency|NodeHighCPU|NodeLowMemory"
            receiver: 'discord'
            continue: true
          - matchers:
              - alertname =~ "DonationServiceHighErrorRate|DonationServiceSLOBurnRateFast|DonationServiceSLOBurnRateSlow|ServiceUnavailable|DonationServiceHighLatency|NodeHighCPU|NodeLowMemory"
            receiver: 'pagerduty'
            continue: true
          - matchers:
              - alertname =~ "DonationServiceHighErrorRate|DonationServiceSLOBurnRateFast|ServiceUnavailable|DonationServiceHighLatency"
            receiver: 'self_healing'

      receivers:
        # Alertas padrão do kube-prometheus-stack (InfoInhibitor, Watchdog,
        # TargetDown, etc.) não são nossos alertas customizados e caem
        # aqui, num receiver sem integrações — evita "alert fatigue"
        # notificando Discord/PagerDuty com ruído irrelevante à demo.
        - name: 'null'

        - name: 'discord'
          slack_configs:
            - api_url: "${local.discord_slack_webhook_url}"
              send_resolved: true
              title: '{{ if eq .Status "firing" }}🔥 ALERTA DISPARADO{{ else }}✅ RESOLVIDO{{ end }}'
              text: |
                **{{ .CommonAnnotations.summary }}**
                {{ range .Alerts }}
                - **Serviço:** {{ .Labels.service }}
                - **Namespace:** {{ .Labels.namespace }}
                - **Severidade:** {{ .Labels.severity }}
                - **Descrição:** {{ .Annotations.description }}
                {{ end }}

        - name: 'pagerduty'
          pagerduty_configs:
            - routing_key: "${var.pagerduty_integration_key}"
              description: '{{ .CommonAnnotations.summary }}'
              details:
                namespace: '{{ .CommonLabels.namespace }}'
                service: '{{ .CommonLabels.service }}'
                severity: '{{ .CommonLabels.severity }}'

        - name: 'self_healing'
          webhook_configs:
            - url: "${aws_apigatewayv2_api.self_healing.api_endpoint}?token=${var.self_healing_webhook_token}"
              send_resolved: false
    EOT
  }

  depends_on = [
    kubernetes_namespace_v1.monitoring,
    aws_apigatewayv2_api.self_healing,
  ]
}

# ----- kube-prometheus-stack (Prometheus + Grafana + AlertManager) -----
resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = kubernetes_namespace_v1.monitoring.metadata[0].name
  create_namespace = false
  version          = "61.3.2"
  timeout          = 600

  values = [
    <<-EOT
    grafana:
      enabled: true
      service:
        type: LoadBalancer
      adminPassword: "solidarytech@2026"
      sidecar:
        dashboards:
          enabled: true
          label: grafana_dashboard
          searchNamespace: monitoring
        datasources:
          enabled: true
      additionalDataSources:
        - name: Loki
          type: loki
          uid: loki
          url: http://loki:3100
          access: proxy
          isDefault: false

    prometheus:
      prometheusSpec:
        enableRemoteWriteReceiver: true
        serviceMonitorSelectorNilUsesHelmValues: false
        podMonitorSelectorNilUsesHelmValues: false
        ruleSelectorNilUsesHelmValues: false
        storageSpec:
          emptyDir:
            medium: ""

    alertmanager:
      alertmanagerSpec:
        configSecret: alertmanager-config
        storageSpec:
          emptyDir:
            medium: ""

    kubeStateMetrics:
      enabled: true

    nodeExporter:
      enabled: true
    EOT
  ]

  depends_on = [
    kubernetes_namespace_v1.monitoring,
    kubernetes_secret_v1.alertmanager_config
  ]
}

# ----- Loki (log aggregation) -----
resource "helm_release" "loki" {
  name             = "loki"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki"
  namespace        = kubernetes_namespace_v1.monitoring.metadata[0].name
  create_namespace = false
  version          = "6.6.4"
  timeout          = 300

  values = [
    <<-EOT
    deploymentMode: SingleBinary
    loki:
      useTestSchema: true
      commonConfig:
        replication_factor: 1
      storage:
        type: filesystem
      auth_enabled: false
    singleBinary:
      replicas: 1
      persistence:
        enabled: false
      extraVolumes:
        - name: loki-data
          emptyDir: {}
      extraVolumeMounts:
        - name: loki-data
          mountPath: /var/loki
    minio:
      enabled: false
    backend:
      replicas: 0
    read:
      replicas: 0
    write:
      replicas: 0
    chunksCache:
      enabled: false
    resultsCache:
      enabled: false
    EOT
  ]

  depends_on = [kubernetes_namespace_v1.monitoring]
}

# ----- OpenTelemetry Collector (DaemonSet) -----
resource "helm_release" "otel_collector" {
  name             = "otel-collector"
  repository       = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart            = "opentelemetry-collector"
  namespace        = kubernetes_namespace_v1.monitoring.metadata[0].name
  create_namespace = false
  version          = "0.97.1"
  timeout          = 300

  values = [
    <<-EOT
    mode: daemonset

    image:
      repository: otel/opentelemetry-collector-contrib

    presets:
      logsCollection:
        enabled: true
        includeCollectorLogs: false

    config:
      receivers:
        otlp:
          protocols:
            grpc:
              endpoint: 0.0.0.0:4317
            http:
              endpoint: 0.0.0.0:4318
        prometheus:
          config:
            scrape_configs:
              - job_name: otel-collector
                static_configs:
                  - targets: ['localhost:8888']

      processors:
        batch:
          timeout: 5s
          send_batch_size: 512
        memory_limiter:
          check_interval: 1s
          limit_mib: 400
          spike_limit_mib: 100
        resource:
          attributes:
            - action: insert
              key: cluster
              value: solidarytech-cluster
            # Datadog deriva a tag "env" (usada para filtrar o Service Map e
            # o APM) do atributo semconv deployment.environment. Sem isso, os
            # traces chegam com env:none e o Service Map some/fica vazio.
            - action: insert
              key: deployment.environment
              value: production
            # O receiver filelog (parser "container") já extrai k8s.namespace.name
            # a partir do caminho do arquivo de log dos containers; copiamos para
            # "namespace" para unificar com o atributo que as apps já enviam via
            # OTLP (OTEL_RESOURCE_ATTRIBUTES), usado pelo dashboard e pelas regras
            # de alerta. O "insert" não sobrescreve se "namespace" já existir.
            - action: insert
              key: namespace
              from_attribute: k8s.namespace.name
            - action: insert
              key: loki.resource.labels
              value: "namespace,cluster,service.name"

      exporters:
        prometheusremotewrite:
          endpoint: http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090/api/v1/write
          resource_to_telemetry_conversion:
            enabled: true
        loki:
          endpoint: http://loki-gateway.monitoring.svc.cluster.local/loki/api/v1/push
        otlp/datadog:
          endpoint: datadog.monitoring.svc.cluster.local:4317
          tls:
            insecure: true
        debug:
          verbosity: basic

      service:
        pipelines:
          traces:
            receivers: [otlp]
            processors: [memory_limiter, batch, resource]
            exporters: [otlp/datadog, debug]
          metrics:
            receivers: [otlp, prometheus]
            processors: [memory_limiter, batch, resource]
            exporters: [prometheusremotewrite, debug]
          logs:
            receivers: [otlp]
            processors: [memory_limiter, batch, resource]
            exporters: [loki, debug]

    ports:
      otlp:
        enabled: true
        containerPort: 4317
        servicePort: 4317
        hostPort: 0
        protocol: TCP
      otlp-http:
        enabled: true
        containerPort: 4318
        servicePort: 4318
        hostPort: 0
        protocol: TCP
    EOT
  ]

  depends_on = [
    kubernetes_namespace_v1.monitoring,
    helm_release.kube_prometheus_stack,
    helm_release.loki,
    helm_release.datadog,
  ]
}

# ----- OpenTelemetry Collector Service -----
resource "kubernetes_service_v1" "otel_collector" {
  metadata {
    name      = "otel-collector"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }
  spec {
    selector = {
      "app.kubernetes.io/name"     = "opentelemetry-collector"
      "app.kubernetes.io/instance" = "otel-collector"
    }
    port {
      name        = "otlp-grpc"
      port        = 4317
      target_port = 4317
      protocol    = "TCP"
    }
    port {
      name        = "otlp-http"
      port        = 4318
      target_port = 4318
      protocol    = "TCP"
    }
    type = "ClusterIP"
  }
  depends_on = [helm_release.otel_collector]
}

# ----- Datadog Agent -----
resource "helm_release" "datadog" {
  name             = "datadog"
  repository       = "https://helm.datadoghq.com"
  chart            = "datadog"
  namespace        = kubernetes_namespace_v1.monitoring.metadata[0].name
  create_namespace = false
  version          = "3.69.3"
  timeout          = 300

  values = [
    <<-EOT
    datadog:
      apiKey: ${var.datadog_api_key}
      appKey: ${var.datadog_app_key}
      site: datadoghq.com
      logs:
        enabled: true
        containerCollectAll: true
      apm:
        portEnabled: true
      processAgent:
        enabled: true
      otlp:
        receiver:
          protocols:
            grpc:
              enabled: true
              endpoint: 0.0.0.0:4317
    clusterAgent:
      enabled: true
    EOT
  ]

  depends_on = [
    kubernetes_namespace_v1.monitoring,
    module.eks
  ]
}

# ----- Datadog Log Pipelines (corrige status "ERROR" falso-positivo) -----
# O Agent tageia logs coletados via stderr como status=error por padrão,
# quando não há pipeline para o source. Loki (Go/logfmt) e o nginx do
# loki-gateway escrevem em stderr, então logs de sucesso (level=info,
# HTTP 2xx/3xx) chegam marcados como ERROR. Estes pipelines extraem o
# nível/status real da mensagem e remapeiam o status do log.
resource "datadog_logs_custom_pipeline" "loki_status" {
  name       = "Loki - remap status from logfmt level"
  is_enabled = true

  filter {
    query = "source:loki"
  }

  processor {
    grok_parser {
      name       = "Parse logfmt level"
      is_enabled = true
      source     = "message"
      grok {
        match_rules   = "loki_level_rule level=%%{word:level}"
        support_rules = ""
      }
    }
  }

  processor {
    status_remapper {
      name       = "Remap status from level attribute"
      is_enabled = true
      sources    = ["level"]
    }
  }

  depends_on = [helm_release.datadog, helm_release.loki]
}

resource "datadog_logs_custom_pipeline" "loki_gateway_nginx_status" {
  name       = "Loki Gateway (nginx) - remap status from HTTP status code"
  is_enabled = true

  filter {
    query = "source:nginx-unprivileged"
  }

  processor {
    grok_parser {
      name       = "Parse HTTP status code from access log"
      is_enabled = true
      source     = "message"
      grok {
        match_rules   = <<-EOT
          nginx_access_rule \[%%{notSpace:timestamp}\] %%{number:http.status_code} "%%{word:http.method} %%{notSpace:http.url} HTTP/%%{notSpace:http.version}"
        EOT
        support_rules = ""
      }
    }
  }

  processor {
    category_processor {
      name       = "Categorize by HTTP status code"
      is_enabled = true
      target     = "nginx_status_category"

      category {
        name = "error"
        filter {
          query = "@http.status_code:[500 TO 599]"
        }
      }
      category {
        name = "warn"
        filter {
          query = "@http.status_code:[400 TO 499]"
        }
      }
      category {
        name = "info"
        filter {
          query = "@http.status_code:[100 TO 399]"
        }
      }
    }
  }

  processor {
    status_remapper {
      name       = "Remap status from HTTP status category"
      is_enabled = true
      sources    = ["nginx_status_category"]
    }
  }

  depends_on = [helm_release.datadog, helm_release.loki]
}

# Saída do Grafana LoadBalancer
output "grafana_url" {
  description = "Grafana LoadBalancer hostname"
  value       = "http://${data.kubernetes_service.grafana.status[0].load_balancer[0].ingress[0].hostname}"
}

data "kubernetes_service" "grafana" {
  metadata {
    name      = "kube-prometheus-stack-grafana"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }
  depends_on = [
    kubernetes_namespace_v1.monitoring,
    helm_release.kube_prometheus_stack
  ]
}
