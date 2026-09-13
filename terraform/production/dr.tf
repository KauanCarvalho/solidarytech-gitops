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
  aws_region     = "us-west-2"
}

data "aws_caller_identity" "current" {}

# ----- CRDs do Velero aplicadas fora do chart (bypass do hook quebrado) -----
# O chart tem um Job de hook "pre-install" (upgrade-crds) que copia os
# binários `sh` e `kubectl` da imagem docker.io/bitnami/kubectl para dentro
# do container principal (imagem velero/velero) via um volume compartilhado,
# e então roda `velero install --crds-only --dry-run -o yaml | kubectl apply
# -f -`. Isso quebrou depois que a Bitnami trocou a imagem de base da tag
# "latest" (única tag pública restante, ver comentário antigo removido
# acima): o `sh` copiado agora é linkado dinamicamente contra
# libreadline.so.8, que não existe na imagem velero/velero — o container
# falha imediatamente com "error while loading shared libraries:
# libreadline.so.8" e o Job esgota o backoffLimit. Confirmado rodando o Job
# isolado manualmente fora do Helm (kubectl logs no container "velero").
#
# Em vez de caçar uma combinação de imagens compatível com esse truque
# fragil de copiar binário entre containers, desabilitamos o hook
# (upgradeCRDs: false, nos values abaixo) e aplicamos as CRDs do Velero
# diretamente via AWS CLI + kubectl, no mesmo espírito do workaround já
# usado no módulo de S3 (ver terraform/modules/aws/s3/s3.tf).
resource "null_resource" "velero_crds" {
  triggers = {
    velero_version = "v1.14.1"
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}
      for crd in backuprepositories backups backupstoragelocations deletebackuprequests \
                 downloadrequests podvolumebackups podvolumerestores restores schedules \
                 serverstatusrequests volumesnapshotlocations; do
        kubectl apply --server-side --force-conflicts -f \
          "https://raw.githubusercontent.com/vmware-tanzu/velero/v1.14.1/config/crd/v1/bases/velero.io_$${crd}.yaml"
      done
    EOT
  }

  depends_on = [module.eks]
}

resource "helm_release" "velero" {
  name             = "velero"
  repository       = "https://vmware-tanzu.github.io/helm-charts"
  chart            = "velero"
  namespace        = "velero"
  create_namespace = true
  version          = "7.2.1"

  values = [
    <<-EOT
    # CRDs já aplicadas por fora (null_resource.velero_crds) — ver comentário
    # acima. Desabilita o Job de hook pre-install quebrado.
    upgradeCRDs: false

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

  depends_on = [module.eks, module.velero_backup_bucket, null_resource.velero_crds]
}
