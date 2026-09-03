# ----- Disaster Recovery: Velero (Opção A — Cross-Region Backup) -----
# Backup do estado do cluster (manifests + volumes) para um bucket S3 numa
# região diferente da do cluster (us-east-1) — se a região/cluster principal
# cair, o estado pode ser restaurado a partir daqui. RTO/RPO documentados
# em docs/PCN.md.

provider "aws" {
  alias  = "dr_region"
  region = "us-west-2"
}

# Reaproveita o módulo genérico de S3 (KMS + versionamento + bloqueio de
# acesso público) já usado para o state bucket do Terraform — mesmas
# garantias de segurança fazem sentido para backups de DR.
module "velero_backup_bucket" {
  source = "../modules/aws/s3"
  providers = {
    aws = aws.dr_region
  }
  s3_bucket_name = "solidarytech-velero-backups-${data.aws_caller_identity.current.account_id}"
}

data "aws_caller_identity" "current" {}

resource "helm_release" "velero" {
  name             = "velero"
  repository       = "https://vmware-tanzu.github.io/helm-charts"
  chart            = "velero"
  namespace        = "velero"
  create_namespace = true
  version          = "7.2.1"

  values = [
    <<-EOT
    initContainers:
      - name: velero-plugin-for-aws
        image: velero/velero-plugin-for-aws:v1.10.0
        volumeMounts:
          - mountPath: /target
            name: plugins

    configuration:
      backupStorageLocation:
        - name: default
          provider: aws
          bucket: ${module.velero_backup_bucket.bucket_id}
          config:
            region: us-west-2

      # Sem volumeSnapshotLocation: nesta fase não há PersistentVolumes
      # stateful no cluster (a stack de observabilidade usa emptyDir e os
      # bancos de dados são RDS/DynamoDB gerenciados, fora do cluster) —
      # o backup cobre os manifests/estado dos objetos Kubernetes.

    credentials:
      useSecret: true
      secretContents:
        cloud: |
          [default]
          aws_access_key_id=${var.aws_access_key}
          aws_secret_access_key=${var.aws_secret_key}
          aws_session_token=${var.aws_session_token}

    schedules:
      donation-service-daily:
        # donation-service é o caminho crítico (hot path) — prioridade de
        # backup diário, RPO alvo de 24h para o estado do cluster (ver PCN).
        schedule: "0 3 * * *"
        template:
          includedNamespaces:
            - donation-service
          ttl: "720h" # 30 dias de retenção
      full-cluster-weekly:
        schedule: "0 4 * * 0"
        template:
          includedNamespaces:
            - "*"
          ttl: "720h"
    EOT
  ]

  depends_on = [module.eks, module.velero_backup_bucket]
}
