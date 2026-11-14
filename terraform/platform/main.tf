locals {
  state_bucket = var.state_bucket != "" ? var.state_bucket : "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
  infra        = data.terraform_remote_state.infra.outputs
  cluster_name = local.infra.cluster_name

  # chave do Secret => chave do map database_urls exportado pelo stack infra
  database_secret_keys = {
    AUTH_DATABASE_URL      = "auth"
    FLAG_DATABASE_URL      = "flag"
    TARGETING_DATABASE_URL = "targeting"
  }
}

# ---------------------------------------------------------------------------
# Chaves da aplicação (antes hardcoded em texto puro)
# ---------------------------------------------------------------------------

resource "random_password" "master_key" {
  length  = 32
  special = false
}

resource "random_password" "service_api_key" {
  length  = 48
  special = false
}

locals {
  master_key           = var.master_key != "" ? var.master_key : random_password.master_key.result
  service_api_key      = var.service_api_key != "" ? var.service_api_key : "tm_key_${random_password.service_api_key.result}"
  service_api_key_hash = sha256(local.service_api_key)
}

# ---------------------------------------------------------------------------
# Namespace, Secret e ConfigMaps consumidos pelos manifests em ../../aws
# ---------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace

    labels = {
      "app.kubernetes.io/name"    = "toggle-master"
      "app.kubernetes.io/part-of" = "toggle-master"

      # Pod Security Admission: bloqueia pods privilegiados/hostPath (baseline)
      # e avisa sobre o que falta para o perfil restricted.
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/warn"    = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
    }
  }
}

resource "kubernetes_secret_v1" "toggle_master_secrets" {
  metadata {
    name      = "toggle-master-secrets"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  type = "Opaque"

  data = merge(
    # terraform_remote_state não propaga a marca sensitive (hashicorp/terraform#29544)
    { for secret_key, db_key in local.database_secret_keys : secret_key => sensitive(local.infra.database_urls[db_key]) },
    {
      REDIS_URL       = local.infra.redis_url
      AWS_SQS_URL     = local.infra.sqs_queue_url
      MASTER_KEY      = local.master_key
      SERVICE_API_KEY = local.service_api_key
    },
  )
}

resource "kubernetes_config_map_v1" "toggle_master_config" {
  metadata {
    name      = "toggle-master-config"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  data = {
    AWS_REGION            = local.infra.region
    AWS_DEFAULT_REGION    = local.infra.region
    AWS_DYNAMODB_TABLE    = local.infra.dynamodb_table_name
    AUTH_SERVICE_URL      = "http://auth-service:8001"
    FLAG_SERVICE_URL      = "http://flag-service:8002"
    TARGETING_SERVICE_URL = "http://targeting-service:8003"
  }
}

# SQL do Job auth-db-init: cria a tabela api_keys e semeia o hash da
# SERVICE_API_KEY gerada acima (o auth-service só guarda o SHA-256 da chave).
resource "kubernetes_config_map_v1" "auth_db_init_sql" {
  metadata {
    name      = "auth-db-init-sql"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  data = {
    "init.sql" = templatefile("${path.module}/templates/auth-init.sql.tftpl", {
      key_hash = local.service_api_key_hash
    })
  }
}

resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = var.monitoring_namespace

    labels = {
      "app.kubernetes.io/part-of" = "toggle-master"
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].labels, metadata[0].annotations]
  }
}

resource "kubernetes_secret_v1" "alertmanager_integrations" {
  metadata {
    name      = "alertmanager-integrations"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  type = "Opaque"

  data = {
    "pagerduty-routing-key" = var.pagerduty_routing_key
    "discord-webhook-url"   = var.discord_webhook_url
  }
}

# Chave de ingestão do APM lida pelo OTel Collector (aws/monitoring/otel-collector).
# Fica fora do Git: o valor vem do terraform.tfvars.
resource "kubernetes_secret_v1" "otel_apm_credentials" {
  metadata {
    name      = "otel-apm-credentials"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  type = "Opaque"

  data = {
    "new-relic-license-key" = var.new_relic_license_key
  }
}

# ---------------------------------------------------------------------------
# Add-ons do cluster (antes instalados manualmente)
# ---------------------------------------------------------------------------

resource "helm_release" "metrics_server" {
  count = var.install_metrics_server ? 1 : 0

  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.metrics_server_chart_version
  namespace  = "kube-system"

  wait    = true
  timeout = 600
}

# ingress-nginx foi aposentado pelo projeto Kubernetes em março/2026 e não
# recebe mais correções de segurança. Fica fixado no último release apenas
# para o laboratório; veja o README para o caminho de migração.
resource "helm_release" "ingress_nginx" {
  count = var.install_ingress_nginx ? 1 : 0

  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.ingress_nginx_chart_version
  namespace        = "ingress-nginx"
  create_namespace = true

  wait    = true
  timeout = 600

  values = [
    yamlencode({
      controller = {
        service = {
          type = "LoadBalancer"
          annotations = {
            "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
          }
        }
        # Métricas para o Prometheus (taxa de requisições no dashboard ToggleMaster).
        # ServiceMonitor fica no GitOps (CRD só existe após o kube-prometheus-stack);
        # as annotations bastam para o scrape via additionalScrapeConfigs / SM externo.
        metrics = {
          enabled = true
          service = {
            annotations = {
              "prometheus.io/scrape" = "true"
              "prometheus.io/port"   = "10254"
            }
          }
        }
      }
    })
  ]
}

data "kubernetes_service_v1" "ingress_nginx" {
  count = var.install_ingress_nginx ? 1 : 0

  metadata {
    name      = "ingress-nginx-controller"
    namespace = "ingress-nginx"
  }

  depends_on = [helm_release.ingress_nginx]
}

locals {
  argocd_root_app = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name       = "toggle-master-root"
      namespace  = "argocd"
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.gitops_repo_url
        targetRevision = var.gitops_target_revision
        path           = "aws/argocd/applications"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
      }
    }
  }
}

# StorageClass padrão (EBS CSI gp3). O cluster só traz a "gp2" in-tree, que não
# provisiona volumes no K8s 1.35 e não é default: os PVCs do Prometheus e do Loki
# (sem storageClassName) ficariam Pending.
resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  reclaim_policy         = "Delete"

  parameters = {
    type = "gp3"
  }
}

resource "helm_release" "argocd" {
  count = var.install_argocd ? 1 : 0

  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = "argocd"
  create_namespace = true

  wait    = true
  timeout = 900

  depends_on = [kubernetes_secret_v1.alertmanager_integrations]

  values = [
    yamlencode({
      crds = { install = true, keep = false }

      configs = {
        cm     = { "timeout.reconciliation" = "30s" }
        params = { "server.insecure" = true }
      }

      server         = { service = { type = "ClusterIP" } }
      dex            = { enabled = false }
      notifications  = { enabled = false }
      applicationSet = { replicas = 0 }
    })
  ]
}

# extraObjects no mesmo release falha: o Helm valida Application antes dos CRDs existirem.
resource "kubernetes_manifest" "argocd_root_app" {
  count = var.install_argocd ? 1 : 0

  manifest = local.argocd_root_app

  depends_on = [helm_release.argocd]
}
