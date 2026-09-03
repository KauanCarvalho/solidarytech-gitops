# 🚀 SolidaryTech — GitOps/Infra (Hackathon Fase 5)

Turma: **2DCLT** — DevOps e Arquitetura Cloud Pós Tech.

## Integrantes do Grupo

| Nome | RM |
| :--- | :--- |
| Guilherme Correa Camargo | 369954 |
| Kauan Carvalho Calasans | 370203 |
| Pedro Henrique Coittinho Marcondes de Andrade | 369367 |

Repositório de aplicação (código-fonte, CI, containers): [solidarytech-app](https://github.com/KauanCarvalho/solidarytech-app)
Vídeo de demonstração: _(adicionar link antes da entrega)_

---

## 1. Visão geral

Repositório de GitOps/Infra da **SolidaryTech**: Terraform (IaC), manifestos Kubernetes, definições ArgoCD, stack de observabilidade (Prometheus/Loki/Grafana/OTel/Datadog), self-healing, e os artefatos das 4 frentes novas do Hackathon Fase 5 — SRE (SLO/Error Budget), FinOps (tagging/rightsizing/forecast), ITSM/AIOps (Watchdog + ciclo de vida de incidente) e Disaster Recovery (Velero).

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    REPOSITÓRIO DE APLICAÇÃO                             │
│          github.com/KauanCarvalho/solidarytech-app                      │
│  CI: build → lint → Trivy SCA → SonarCloud SAST → Docker → Trivy image  │
│      scan → push ECR → commit automático no repo abaixo ↓               │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │ commit automático (GitHub App)
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    ESTE REPOSITÓRIO (GitOps)                            │
│  ├── terraform/  → IaC (VPC, EKS, RDS ×2, DynamoDB, SQS, ECR ×3,        │
│  │                  monitoring.tf, self-healing.tf, dr.tf)              │
│  ├── k8s/apps/   → Manifestos Kubernetes (fonte de verdade)             │
│  ├── argocd/     → ArgoCD Application definitions                       │
│  └── docs/       → PCN, ciclo de vida de incidente, forecast FinOps     │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │ monitoramento contínuo (pull)
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          AWS EKS CLUSTER                                │
│  ArgoCD (selfHeal: true, prune: true) · 3 microsserviços                │
│  External Secrets Operator → AWS Secrets Manager                        │
│  OTel Collector → Prometheus + Loki + Datadog → Grafana (geral + SRE)   │
│  Alertmanager → Discord + PagerDuty + Lambda (self-healing)             │
│  Velero → backup cross-region (us-west-2) do estado do cluster          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Decisões tomadas

- **2 repositórios separados (app + gitops)** — mesma justificativa do repo de aplicação: espelha o padrão já avaliado nas Fases 1-4.
- **Sem ElastiCache/Redis** — diferente do ToggleMaster, nenhum dos 3 serviços da SolidaryTech (ngo, donation, volunteer) precisa de cache; provisionar Redis mesmo assim seria custo sem uso real, contrariando o próprio requisito de FinOps do edital.
- **DR via Velero (Opção A)**, cross-region (`us-east-1` cluster → backup em `us-west-2`) — menor custo/esforço que Ativo-Passivo (Opção B) dentro do AWS Academy Lab, com evidência prática de restore possível (ver `docs/PCN.md`).
- **Backup automático do RDS (`donation-service-db`) além do Velero** — Velero só cobre o estado do cluster Kubernetes, não bancos de dados gerenciados; sem isso, os dados de doação em si não teriam RPO nenhum, o que invalidaria a estratégia de DR pro caminho crítico. Gap identificado nesta implementação e corrigido (o módulo RDS reutilizado do ToggleMaster não tinha essa opção).
- **`tfsec` adicionado às pipelines de Terraform** — o repositório de referência não tinha nenhum scan de segurança na infra (só `fmt`/`validate`); como DevSecOps é requisito obrigatório da Fundação (item 0), isso precisava ser fechado aqui.
- **`targetRevision: main`** nos Applications do ArgoCD (não uma branch de feature fixa) — o repositório de referência tinha isso hardcoded para uma branch específica de release por engano; corrigido desde o início aqui para não repetir a pendência.
- **AWS Academy Learner Lab mantido** e **Datadog mantido como APM** — mesma justificativa do repo de aplicação (reuso de credenciais/config já validada).

---

## 3. Estrutura do repositório

```
.
├── argocd/                    # 5 Application manifests (core-infra, monitoring, 3 serviços)
├── docs/
│   ├── PCN.md                 # Plano de Continuidade de Negócios (RTO/RPO)
│   ├── sla.md                 # SLA formal com as ONGs parceiras (donation-service)
│   ├── incident-lifecycle.md  # Ciclo de vida de incidente (ITSM/AIOps)
│   └── finops-forecast.md     # Forecast de custo + recomendação de otimização
├── k8s/
│   ├── apps/
│   │   ├── 00-namespaces.yaml
│   │   ├── cluster-secret-store.yaml
│   │   ├── ingress.yaml
│   │   ├── monitoring/        # alert-rules.yaml (SLO burn-rate), 2 dashboards Grafana
│   │   └── <ngo|donation|volunteer>-service/  # configmap/deployment/external-secret/hpa/service
│   └── templates/              # deployment.tmpl.yaml (usado pelo CI via envsubst)
└── terraform/
    ├── bootstrap/               # S3 + DynamoDB para o state remoto
    ├── modules/aws/              # vpc, eks, rds, dynamodb, sqs, ecr, sg, s3 (reutilizáveis)
    └── production/                # main.tf, monitoring.tf, external-secrets.tf, self-healing.tf, dr.tf
```

---

## 4. Requisitos técnicos implementados

### 4.1. Fundação (item 0 — obrigatório)

- **IaC**: VPC, EKS, 2× RDS (Postgres, um por serviço com banco próprio), 1× DynamoDB (voluntários), 1× SQS (doações), 3× ECR — tudo em módulos Terraform reutilizáveis, com as 5 tags obrigatórias em todo recurso.
- **CI/DevSecOps**: pipelines no repo de aplicação (Trivy SCA + SonarCloud SAST, bloqueantes) + `tfsec` aqui na infra.
- **GitOps**: ArgoCD com `selfHeal`/`prune`, nunca `kubectl apply` manual.
- **Observabilidade**: OTel Collector (DaemonSet) → Prometheus + Loki + Datadog, com Distributed Tracing ponta a ponta.

### 4.2. SRE (item 1)

SLIs/SLOs formais do `donation-service` (disponibilidade e latência), dashboard exclusivo de SLO/Error Budget, burn-rate alerts multi-janela — ver `k8s/apps/monitoring/` e a tabela de critérios abaixo.

### 4.3. FinOps (item 2)

Tagging obrigatório, rightsizing por papel de serviço, forecast de custo mensal — ver `docs/finops-forecast.md`.

### 4.4. ITSM/AIOps (item 3)

Datadog Watchdog + ciclo de vida de incidente documentado — ver `docs/incident-lifecycle.md`.

### 4.5. DR/Segurança (item 4)

PCN com RTO/RPO + Velero (cross-region) + backup automático do RDS crítico — ver `docs/PCN.md`.

---

## 5. Configuração de variáveis (GitHub Secrets)

- **AWS Academy**: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`
- **Bancos de dados**: `DB_PASSWORD_NGO`, `DB_PASSWORD_DONATION`
- **APM**: `DATADOG_API_KEY`, `DATADOG_APP_KEY`
- **ChatOps/Incident Management**: `DISCORD_WEBHOOK_URL`, `PAGERDUTY_INTEGRATION_KEY`
- **Self-Healing**: `GH_DISPATCH_TOKEN`, `SELF_HEALING_WEBHOOK_TOKEN`

---

## 6. Guia de implantação

1. **Terraform Bootstrap** (workflow `terraform-bootstrap.yml`, `action=apply`) — cria o bucket S3 + tabela DynamoDB do state remoto.
2. **Terraform Production** (workflow `terraform-production.yml`, `action=apply`) — provisiona VPC/EKS/RDS/DynamoDB/SQS/ECR, ArgoCD, ESO, stack de observabilidade, self-healing e Velero.
3. **Kubeconfig**: `aws eks update-kubeconfig --name solidarytech-cluster --region us-east-1`.
4. **Publicação de imagens**: workflow `deploy.yml` do [solidarytech-app](https://github.com/KauanCarvalho/solidarytech-app) builda, escaneia e faz push pro ECR, e commita a nova tag aqui em `k8s/apps/<service>/deployment.yaml` — o ArgoCD sincroniza sozinho.
5. **Validação**: `make check-all ENV=prod` no repo de aplicação, contra o hostname do Ingress (`terraform output ingress_load_balancer_hostname`).

---

## 7. Critérios de aceite atendidos

Itens cuja evidência principal vive neste repositório (itens 0.1/0.3 do app-repo estão documentados lá). ✅ = implementado nesta entrega; ⏳ = depende de execução real em nuvem (fora do escopo deste ambiente de desenvolvimento local).

| # | Requisito (PDF) | Status | Evidência | Por quê |
|---|---|---|---|---|
| 0.2 | IaC via Terraform (cluster, DBs, mensageria, rede) | ✅ | `terraform/` — 9 módulos validados (`terraform validate`), bootstrap + production | Reuso de módulos genéricos já avaliados, consistência entre projetos |
| 0.4 | GitOps via ArgoCD, sem `kubectl apply` manual | ✅ | `argocd/*.yaml`, `reusable-deploy.yml` do app-repo só faz commit-back | Exigência literal da "Regra de Ouro" |
| 0.5 (parcial) | Stack de observabilidade completa + APM | ✅ | `terraform/production/monitoring.tf` — kube-prometheus-stack, Loki, OTel Collector DaemonSet, Datadog | Coleta centralizada via OTel evita instrumentar cada backend direto nos serviços |
| 1.1 | ≥2 SLIs baseados em Golden Metrics (donation-service) | ✅ | Disponibilidade + Latência, `docs/finops-forecast.md`/dashboards; SLO 99.9%/95% | Golden Metrics mais ligadas à experiência do doador no hot path |
| 1.2 | SLO por SLI | ✅ | 99.9% disponibilidade (30d), 95% requisições <300ms — `k8s/apps/monitoring/alert-rules.yaml` | Alvo numérico é o que torna o SLI acionável |
| 1.3 | SLA formal com as ONGs parceiras | ✅ | `docs/sla.md` — 99.5% disponibilidade mensal, créditos por nível de violação, exclusões e cadência de relatório | Edital pede SLI **e** SLO **e** SLA; SLA externo deliberadamente mais frouxo que o SLO interno (99.9%), dando margem de reação antes de violação contratual |
| 1.4 | Dashboard SRE exclusivo (SLO + Error Budget) | ✅ | `k8s/apps/monitoring/grafana-sre-dashboard.yaml` (`solidarytech-sre`, separado do dashboard geral) | Edital exige painel **exclusivo**, não misturado |
| 1.5 | Evidência de redução de MTTR | ⏳ | Self-healing (`self-healing.yml` + Lambda) configurado; número real de teste a coletar no vídeo | Precisa de execução real do rollout restart pra medir tempo |
| 2.1 | Tags obrigatórias no Terraform | ✅ | `Project/Environment/CostCenter/ManagedBy` em todo módulo (`terraform/modules/aws/*`) | Requisito nomeado literalmente no edital |
| 2.2 | Rightsizing baseado em métrica real | ✅ | `k8s/apps/*/deployment.yaml` — donation-service com requests/limits maiores (hot path), justificativa em `docs/finops-forecast.md` | Análise por papel de serviço, não valor uniforme "no chute" |
| 2.3 | Forecast de custo mensal + recomendação | ✅ | `docs/finops-forecast.md` — ~$230-240/mês, recomendação de agendar desligamento do node group fora do horário de uso | Orçamento limitado da ONG é a premissa do cenário |
| 3.1 | AIOps ativo (Watchdog) | ⏳ | `helm_release.datadog` provisiona o Agent; ativação/evidência de anomalia depende de tráfego real | Watchdog precisa de dados reais fluindo pra detectar padrão |
| 3.2 | Fluxo de vida de incidente desenhado | ✅ | `docs/incident-lifecycle.md` — diagrama completo detecção→post-mortem | Processo repetível, não reação ad hoc |
| 4.1 | PCN com RTO/RPO | ✅ | `docs/PCN.md` — RTO 1h / RPO 24h pro donation-service, com justificativa | Números concretos tornam o plano auditável |
| 4.2 | DR prático (Velero) evidenciado | ⏳ | `terraform/production/dr.tf` configurado (backup diário + semanal); restore de teste a gravar no vídeo | Edital exige mostrar operando, não só configurado |

### Entregáveis finais (ambos os repositórios)

1. **Código-fonte**: `solidarytech-app` + `solidarytech-gitops`.
2. **Vídeo (até 20 min)**: pitch executivo (arquitetura, PCN, estratégia financeira) + demo técnica (pipelines, ArgoCD, Terraform, traces, dashboard SRE, Velero em ação).
3. **Relatório PDF**: time/RMs/links + as 4 seções obrigatórias com evidências visuais.

---

## 8. Links

- Repositório de aplicação: https://github.com/KauanCarvalho/solidarytech-app
- Código-fonte base fornecido: https://github.com/dougls/hackathon-DCLT
- Vídeo de demonstração: _(adicionar antes da entrega)_
