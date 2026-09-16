# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

GitOps/Infra repository for **SolidaryTech** (FIAP Fase 5 hackathon, turma 2DCLT). It owns Terraform IaC,
Kubernetes manifests (source of truth for the cluster), ArgoCD `Application` definitions, and the
observability/SRE/FinOps/DR documentation. The application source code lives in the sibling
`solidarytech-app` repo — see the parent directory's `CLAUDE.md` for how the two connect.

**Golden rule: this repo never receives `kubectl apply` by hand.** `k8s/apps/**` is the source of truth;
ArgoCD (`syncPolicy.automated.selfHeal: true, prune: true` on every `Application` in `argocd/`) pulls from
it continuously. Manual cluster edits get reverted automatically — don't fight self-heal, edit the manifest
and let ArgoCD converge. The app repo's CI commits image-tag bumps into `k8s/apps/<service>/deployment.yaml`
(rendered from `k8s/templates/<service>/deployment.tmpl.yaml` via `envsubst`); this repo does not generate
those tags itself.

## Commands

There is no Makefile or root build system — verification runs through the two GitHub Actions workflows, and
the same steps can be run locally from `terraform/bootstrap/` or `terraform/production/`:

```bash
terraform fmt -check -recursive   # formatting gate (CI fails on drift)
tfsec .                           # policy-as-code security scan (CI: soft_fail=false, blocking)
terraform init                    # bootstrap: local backend config; production: needs -backend-config (see below)
terraform validate
terraform plan
```

- **`terraform/bootstrap/`** — provisions the S3 bucket + DynamoDB lock table for remote state. Uses a plain
  `backend "s3" {}` block with no config; local `terraform init` works as-is. Workflow:
  `.github/workflows/terraform-bootstrap.yml` (`workflow_dispatch`, `action: plan|apply`).
- **`terraform/production/`** — provisions everything else (VPC, EKS, RDS ×2, DynamoDB, SQS, ECR ×3, ArgoCD,
  External Secrets, the observability stack, self-healing Lambda, Velero). Its S3 backend is configured only
  via `-backend-config` flags at init time (bucket name is `solidarytech-terraform-state-${ACCOUNT_ID}`,
  resolved from `aws sts get-caller-identity` — see the `Terraform Init` step in
  `.github/workflows/terraform-production.yml`), so `terraform init` will fail here without passing those
  flags explicitly. Workflow: `.github/workflows/terraform-production.yml` — runs plan on every PR touching
  `terraform/production/**`, and `plan|apply|destroy` via `workflow_dispatch`.
- Required `TF_VAR_*` values (DB passwords, AWS creds/session token for the AWS Academy Lab, Datadog keys,
  Discord webhook, PagerDuty key, GitHub dispatch token, self-healing webhook token) are wired from GitHub
  Secrets in the workflow `env:` block — see `variables.tf` in `terraform/production/` for the full list.
- A `terraform apply` of `production` from a fresh runner needs the self-healing Lambda zip rebuilt first
  (`zip -j lambda/self-healing/main.zip lambda/self-healing/main.py`) — `archive_file` produces it as a side
  effect of `plan`, which doesn't survive across the plan/apply artifact boundary.
- No app-level tests live in this repo. Post-deploy validation is `make check-all ENV=prod` in the
  `solidarytech-app` repo, run against `terraform output ingress_load_balancer_hostname`.

## Architecture

```
terraform/
├── bootstrap/     # S3 (state) + DynamoDB (lock) — apply once, before production
├── modules/aws/   # reusable modules: vpc, eks, rds, dynamodb, sqs, ecr, sg, s3
└── production/    # root module composing the modules above + helm_release/kubernetes_*/aws_* resources
                    #   main.tf              VPC, EKS, RDS ×2, DynamoDB, SQS, ECR, SGs
                    #   helm.tf              ArgoCD, metrics-server
                    #   external-secrets.tf  Secrets Manager entries + External Secrets Operator
                    #   monitoring.tf        kube-prometheus-stack, Loki, OTel Collector, Datadog
                    #   self-healing.tf      Lambda + API Gateway (rollout-restart on alert)
                    #   dr.tf                Velero (cross-region backup to us-west-2)
                    #   ingress.tf           ingress-nginx
k8s/
├── apps/          # source of truth ArgoCD syncs from — namespaces, per-service manifests, monitoring/alerts
└── templates/     # deployment.tmpl.yaml per service — CI in solidarytech-app renders these via envsubst
                    # into k8s/apps/<service>/deployment.yaml and commits back
argocd/            # 5 Application manifests: core-infra (syncs k8s/apps/*.yaml at top level), monitoring,
                    # and one per microservice (ngo, donation, volunteer)
docs/              # PCN.md (RTO/RPO), sla.md, incident-lifecycle.md, finops-forecast.md
```

- `terraform/production` is one flat root module — there's no per-environment directory split; "production"
  is the only environment.
- Almost every `aws_*` resource tag block is repeated by hand per-module (`Name/Project/Environment/CostCenter/ManagedBy`)
  rather than centralized. `provider "aws"` in `terraform/production/terraform.tf` has **no `default_tags`
  block**, so any resource that forgets its own `tags = {}` (or any resource type without a `tags` argument
  at all, e.g. `aws_db_subnet_group`, `aws_security_group_rule`, subnets/IGW/route table inside
  `modules/aws/vpc/vpc.tf`, and everything in `external-secrets.tf`/`self-healing.tf`) silently has no
  `CostCenter` tag and won't show up filtered by `CostCenter=NGO-Core` in Cost Explorer. This is a known,
  tracked gap — see the "2.1" row in this repo's `README.md` acceptance-criteria table and
  `docs/finops-forecast.md` §3. The fix path already decided (not yet applied) is to move the 3 non-`Name`
  tags into a `default_tags` block on `provider "aws"`.
- `donation-service` is the hot path throughout this repo, not just in the app repo: it's the only RDS
  instance with `backup_retention_period = 7` (main.tf), the only deployment with elevated resource
  requests/limits (`k8s/apps/donation-service/deployment.yaml` / `k8s/templates/donation-service/deployment.tmpl.yaml`),
  and the subject of the formal SLO/SLA (`k8s/apps/monitoring/alert-rules.yaml`, `docs/sla.md`). Changes
  touching it should keep `docs/sla.md`, `docs/PCN.md`, and the alert rules consistent with each other.
- Observability is centralized through an OTel Collector DaemonSet (`monitoring.tf`) fanning out to
  Prometheus + Loki + Datadog, rather than instrumenting each backend service directly.
- DR strategy is Velero cross-region backup (`us-east-1` cluster → `us-west-2` bucket), chosen over an
  active-passive setup for cost/effort reasons inside the AWS Academy Lab — see `docs/PCN.md`.

## Key project decisions (don't relitigate without reason)

- Two separate repos (app + gitops) mirrors the pattern already validated in earlier project phases.
- No ElastiCache/Redis — none of the 3 services need caching; provisioning it anyway would be FinOps waste
  with no functional benefit.
- `tfsec` was added to both Terraform workflows because the reference repo this was adapted from
  (`dougls/hackathon-DCLT`) had no infra security scanning at all.
- ArgoCD `Applications` pin `targetRevision: main` deliberately — the reference repo hardcoded a stale
  feature-release branch by mistake; keep this on `main`.
- AWS Academy Learner Lab and Datadog-as-APM are kept for credential/config reuse already validated in the
  app repo — don't swap these without a reason that outweighs that reuse.
