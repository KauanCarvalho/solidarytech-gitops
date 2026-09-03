# SLA — Acordo de Nível de Serviço com as ONGs Parceiras — SolidaryTech

**Documento executivo** — para a diretoria da SolidaryTech e para o relatório de entrega do Hackathon Fase 5 (item 1 — SRE: definição formal de SLI, SLO **e** SLA do `donation-service`).

Este documento formaliza o compromisso **externo e contratual** com as ONGs parceiras. Ele é derivado dos SLIs/SLOs internos (ver `k8s/apps/monitoring/alert-rules.yaml` e `k8s/apps/monitoring/grafana-sre-dashboard.yaml`), mas não se confunde com eles — SLI/SLO são metas de engenharia; SLA é o que a SolidaryTech assina com terceiros e pelo qual responde formalmente.

## 1. Por que o SLA é mais frouxo que o SLO interno

| | Alvo | Janela | Papel |
|---|---|---|---|
| **SLI** | % de requisições com status < 500 (disponibilidade); % de requisições < 300ms (latência) | contínua | O que é medido |
| **SLO** (interno) | 99.9% disponibilidade / 95% latência < 300ms | 30 dias | Meta de engenharia — aciona alertas e burn-rate (`DonationServiceSLOBurnRateFast/Slow`) |
| **SLA** (externo, este documento) | **99.5% de disponibilidade mensal** do `donation-service` | mensal (calendário) | Compromisso contratual com as ONGs |

O SLO (99.9%) é deliberadamente mais rígido que o SLA (99.5%): a diferença entre os dois é o **error budget de margem operacional** — a equipe reage a violações do SLO (error budget interno) bem antes de qualquer risco de violar o SLA firmado com as ONGs. Um SLA tão rígido quanto o SLO não deixaria margem para investigação/correção antes de gerar uma obrigação contratual.

## 2. Escopo e objeto do acordo

- **Serviço coberto**: `donation-service` (processamento de doações — caminho crítico do negócio). `ngo-service` e `volunteer-service` **não têm SLA formal** nesta fase — indisponibilidade neles não interrompe o fluxo financeiro (ver `docs/PCN.md`, seção 1).
- **Métrica contratual**: disponibilidade mensal, calculada como:

  ```
  disponibilidade_mensal (%) = 1 - (requisições com status 5xx no mês / total de requisições no mês)
  ```
  (mesma fonte de dados do SLI de disponibilidade — `http_requests_total`, coletado via Prometheus/OTel.)

## 3. Compromisso e créditos

| Disponibilidade mensal real | Classificação | Ação contratual |
|---|---|---|
| ≥ 99.5% | Dentro do SLA | Nenhuma ação — relatório mensal informativo |
| 99.0% – 99.49% | Violação — Nível 1 | Crédito de 5% sobre a taxa de processamento do mês + comunicação formal em até 5 dias úteis |
| 95.0% – 98.99% | Violação — Nível 2 | Crédito de 15% + Post-Mortem obrigatório compartilhado com a ONG afetada |
| < 95.0% | Violação — Nível 3 (crítica) | Crédito de 30% + Post-Mortem + reunião executiva com a diretoria da ONG parceira |

Créditos são cumulativos por mês (não por incidente) e aplicados sobre o próximo ciclo de repasse/custo operacional atribuído à ONG, nunca sobre o valor doado em si — a SolidaryTech nunca retém ou desconta o valor da doação do doador final.

## 4. Exclusões (o que não conta contra o SLA)

- Janelas de manutenção programada, comunicadas com **48h de antecedência** via canal oficial às ONGs (máx. 4h/mês, fora do horário de pico histórico de doações).
- Indisponibilidade causada por falha de serviço de terceiros fora do controle da SolidaryTech (ex.: interrupção da AWS na região, confirmada por status page oficial).
- Picos de acesso que excedam o dimensionamento contratado sem aviso prévio da ONG (ex.: campanha viral não comunicada com antecedência à equipe técnica) — mitigado na prática pelo HPA (`minReplicas: 2, maxReplicas: 5`), mas listado aqui como exclusão formal.

## 5. Medição, relatório e revisão

- **Fonte de verdade**: dashboard SRE exclusivo (`k8s/apps/monitoring/grafana-sre-dashboard.yaml`, painel "SLI Disponibilidade 30d") — mesma métrica usada para o SLO interno, sem ambiguidade entre o que a engenharia mede e o que é reportado à ONG.
- **Relatório mensal**: enviado às ONGs parceiras nos primeiros 5 dias úteis do mês seguinte, com a disponibilidade real do mês anterior e, se houver violação, o resumo executivo do Post-Mortem correspondente (ver `docs/incident-lifecycle.md`, etapa 7 — Comunicação aos Stakeholders).
- **Revisão do SLA**: anual, ou antecipada caso o padrão de uso da plataforma mude de forma estrutural (ex.: volume de doações crescer uma ordem de grandeza).

## 6. Relação com o plano de continuidade

Em caso de acionamento do PCN (`docs/PCN.md`) com o RTO de 1h para o `donation-service`, o tempo de indisponibilidade durante a recuperação **conta normalmente** para o cálculo mensal do SLA — o RTO define o teto operacional de resposta da equipe, não uma exclusão contratual. Isso mantém o incentivo de manter o RTO real abaixo do praticado, em vez de tratá-lo como uma tolerância automática perante as ONGs.
