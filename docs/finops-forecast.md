# FinOps — Forecast de Custos e Otimização — SolidaryTech

Requisito do edital (item 2 — FinOps): projeção de custos mensais + pelo menos 1 recomendação prática de otimização nativa de nuvem. Preços de referência: AWS `us-east-1`, sob demanda (`on-demand`), tabela pública AWS em 2026 — estimativa, não fatura real (ambiente roda em AWS Academy Learner Lab, sem cobrança direta ao time).

## 1. Projeção de custo mensal (arquitetura atual)

| Recurso | Configuração | Custo unitário estimado | Qtde | Custo mensal estimado |
|---|---|---|---|---|
| EKS (control plane) | 1 cluster | $0,10/h | 1 | ~$73 |
| EC2 (nodes EKS) | 3x `t3.medium` (desired_size) | ~$0,0416/h cada | 3 | ~$90 |
| RDS PostgreSQL | 2x `db.t3.micro` (ngo, donation) | ~$0,017/h cada | 2 | ~$25 |
| RDS backup storage | `donation-service-db`, retenção 7d | ~$0,095/GB-mês | ~5GB | ~$0,50 |
| Load Balancers (NLB/ELB) | Ingress-nginx + ArgoCD UI | ~$16,20/mês cada | 2 | ~$32 |
| DynamoDB | `SolidaryTechVolunteers`, PAY_PER_REQUEST | uso variável | 1 | ~$1–5 |
| SQS | `solidary-donations`, Standard Queue | uso variável | 1 | < $1 |
| ECR | 3 repositórios, lifecycle mantém últimas 5 imagens | ~$0,10/GB-mês | 3 | ~$1 |
| S3 (Terraform state + Velero backups, cross-region) | versionado + KMS | ~$0,023/GB-mês | 2 buckets | ~$1–2 |
| Data transfer (cross-AZ, cross-region p/ Velero) | variável | — | — | ~$5–10 |
| **Total estimado** | | | | **~$230–240/mês** |

## 2. Rightsizing aplicado (baseado em métrica observada, não em chute)

Requests/limits dos manifests (`k8s/apps/*/deployment.yaml`) foram dimensionados por papel, não uniformemente:

| Serviço | requests (cpu/mem) | limits (cpu/mem) | Justificativa |
|---|---|---|---|
| `donation-service` (hot path) | 150m / 128Mi | 600m / 256Mi | Observado maior consumo de CPU sob carga no smoke test (`scripts/check/donation-service.sh` em loop) por processar SQS de forma assíncrona (`go a.sendNotificationEvent`) além do request HTTP síncrono. |
| `ngo-service` / `volunteer-service` | 100m / 128Mi | 500m / 256Mi | Serviços CRUD simples, sem processamento assíncrono — consumo observado consistentemente abaixo do hot path nos mesmos testes. |

Todos os 3 usam HPA (`minReplicas: 2, maxReplicas: 5`, alvo 70% CPU / 80% memória) — evita superprovisionar réplicas fixas para picos que só acontecem ocasionalmente (ex: campanha de doação viral, cenário citado no edital).

## 3. Tagging para chargeback (evidência)

Todo recurso Terraform carrega as 4 tags obrigatórias, via `default_tags` no `provider "aws"`
(`terraform/production/terraform.tf`) — cobre 100% dos recursos automaticamente, inclusive os que não
suportam um bloco `tags = {}` explícito por módulo (subnets/IGW/route table da VPC, `aws_db_subnet_group`,
os secrets do Secrets Manager, o Lambda/API Gateway do self-healing):

```hcl
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "SolidaryTech"
      Environment = "Production"
      CostCenter  = "NGO-Core"
      ManagedBy   = "terraform"
    }
  }
}
```

Validado via Resource Groups Tagging API — `aws resourcegroupstaggingapi get-resources --tag-filters
Key=CostCenter,Values=NGO-Core` retorna os 33 recursos da stack.

**Limitação de conta (AWS Academy Learner Lab)**: o Cost Explorer filtrado por tag (`GroupBy TAG=CostCenter`)
não funciona nesta conta — `aws ce list-cost-allocation-tags` retorna `AccessDeniedException: Linked account
doesn't have access to cost allocation tags`. Contas linked de uma AWS Organization (o modelo do Academy
Learner Lab) não podem ativar Cost Allocation Tags; isso é controlado pela conta de management/payer da
instituição, fora do alcance do time. O console **Resource Groups & Tag Editor** também não é viável — a UI
atual roteia a busca via Resource Explorer (`resource-explorer-2:Search`), barrado por uma SCP explícita da
mesma Organization (`AccessDeniedException`, sem contorno possível pelo usuário). A evidência de chargeback
por tag usa a **AWS CLI** direto (`aws resourcegroupstaggingapi get-resources --tag-filters
Key=CostCenter,Values=NGO-Core`), que não passa pelo Resource Explorer e funciona normalmente — tecnicamente
equivalente para provar que o isolamento de custo por tag está pronto, mesmo sem acesso ao billing agregado
por tag nem ao console de tagging.

## 4. Recomendação prática de otimização nativa de nuvem

**Recomendação: separar os node groups do EKS por perfil de risco — capacidade On-Demand dedicada ao `donation-service` (hot path), e Spot Instances para `ngo-service`/`volunteer-service` (CRUD simples, tolera uma interrupção ocasional de minutos).**

Por quê essa e não outra:
- O cenário do edital é explícito: **"se a nuvem cair, as doações não podem parar"**. Qualquer recomendação que reduza disponibilidade do `donation-service` — inclusive desligar nodes fora de um "horário de uso" arbitrário — contradiz esse requisito; a SolidaryTech já "ganhou destaque em rede nacional", ou seja, pode receber doação a qualquer hora. A otimização precisa respeitar isso, não ignorá-lo.
- EC2 dos nodes (~$90/mês) é a maior linha do orçamento, à frente do control plane do EKS (~$73/mês) — é onde a otimização tem mais efeito.
- **Spot Instances** para todo o cluster foram descartadas numa primeira análise por arriscarem o hot path durante uma demo ao vivo — mas esse risco é do `donation-service`, não do cluster inteiro. Isolando o risco por node group, `ngo-service`/`volunteer-service` capturam o desconto de Spot (~60-70%) sem expor o caminho crítico a interrupção nenhuma.
- **Savings Plans/Reserved Instances** continuam descartados: não se aplicam a um compromisso de 2 meses nem a uma conta AWS Academy Lab (sem cartão de crédito/compromisso de longo prazo).
- É nativo de nuvem (Managed Node Groups com `capacity_type = "SPOT"` no Terraform, `nodeSelector`/taints no Kubernetes pra garantir que o `donation-service` só agende no node group On-Demand), sem ferramenta terceira.
- Efeito estimado: 1 node On-Demand dedicado ao `donation-service` (~$30/mês) + 2 nodes Spot pros outros dois serviços a ~35% do preço On-Demand (~$21/mês) ≈ **$51/mês**, uma economia de **~$38/mês (≈42%)** sobre os ~$90/mês atuais — sem reduzir a disponibilidade do caminho crítico em nenhum momento, e sem tocar no EKS control plane nem nos dados (RDS/DynamoDB continuam ativos e intactos).

## 5. Evidência visual

📸 **Evidência visual:**
![aws resourcegroupstaggingapi get-resources filtrado por CostCenter=NGO-Core — 33 recursos retornados](evidencias/finops-tags-cost-explorer.png)
