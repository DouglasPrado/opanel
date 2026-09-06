---
title: "Opanel — Roadmap de Implementação"
type: "implementation-roadmap"
status: "ready-for-human-review"
---

# Opanel — Roadmap

Visão consolidada dos Milestones. A ordem deriva de **dependências arquiteturais e de produto**, não de calendário. Datas só devem ser estimadas depois do breakdown técnico por equipe (Anexo A §1).

Este roadmap **substitui operacionalmente** a numeração M0–M13 do Anexo A. A justificativa da nova decomposição está em [`SPEC_CONFLICTS.md`](SPEC_CONFLICTS.md#sc-06--numeração-e-agrupamento-de-milestones) e o mapeamento Anexo A → este pack está na seção 4 abaixo.

## 1. Tabela consolidada

| Milestone | Capability | Depends On | Human Gate |
|---|---|---|---|
| **M00** Foundation | Base de engenharia: Rails 8.1 + PostgreSQL + Solid Queue + Inertia/React/TS/Vite/Tailwind, testes, lint, security scan, CI, quality gates, fitness functions, hooks do Autonomous Loop, evidence/report. | — | Aceitação do ambiente de engenharia antes de qualquer domínio |
| **M01** First Vertical Slice | Auth → Team → Project → Cluster → Environment → Service (imagem OCI existente) → Desired State → Operation → Swarm Executor → Docker Service → Actual State → Healthy → Logs → Scale 1→3. | M00 | **Sim** — espinha dorsal da arquitetura |
| **M02** Runtime Operations & Drift Control | Restart, resources, placement, health/restart policy, status derivado, drift + Platform Wins, adopt runtime, deleção com cleanup, Operations Center, SSE, Docker Events, Idempotency-Key. | M01 | Sim |
| **M03** Vault, Encryption & Secret Distribution | Envelope encryption, Recovery Key, Secret/SecretVersion imutável, bindings pinados, Swarm Secrets, reveal com step-up, redaction. | M01, M02 | **Sim** — Security Gate |
| **M04** Ingress, Default Domains & TLS | **Introdução do Edge.** Traefik global em ingress nodes, DomainBinding, domínio default wildcard, Certificate Manager, ACME DNS-01, distribuição versionada com ACK, políticas de edge. | M02, M03 | Sim |
| **M05** Source, Build & Artifacts | **Introdução do Build Pipeline.** SourceConnection/GitHub App, webhooks assinados, SourceRevision, Railpack + BuildKit em builders isolados, Registry provider, Artifact por digest. | M02, M03 | Sim |
| **M06** Release, Deployment, Rollback & Promotion | Release imutável, Deployment state machine, rolling update com health verification, rollback, promoção HML→PROD sem rebuild, auto-deploy por webhook. | M05 (+M02, M03) | **Sim** — Delivery Gate |
| **M07** Custom Domains & DNS Providers | Onboarding de domínio do cliente, verificação DNS, certificados por hostname/SAN, políticas de edge por domínio, diagnóstico ponta a ponta, IPv6 capability. | M04 (+M06 soft) | Sim |
| **M08** Cluster Expansion, Node Lifecycle & HA | **Introdução de HA.** EnrollmentToken, bootstrap de node, roles worker/ingress/builder/manager, drain/promote/demote/remove, LoadBalancerProvider, quorum guardrails, Cluster Readiness. | M02, M04 | **Sim** — HA Gate |
| **M09** Observability, Alerts, Incidents & Autoscaling | **Introdução de Observability avançada.** Coletores, backend de métricas, logs históricos, timeline de eventos, alert rules, incidentes, notificações, autoscaling, terminal auditado, SLI/SLO. | M02, M06 (+M08 soft) | Sim |
| **M10** Backup, Restore & Disaster Recovery | **Introdução de DR.** BackupStorageProvider, políticas/retention, backup do Platform DB, Vault, certificados e Swarm state, snapshots lógicos, Restore Engine, Clean Rebuild, drills, Protection Readiness. | M03, M06 (+M08 soft) | **Sim** — DR Gate |
| **M11** Governance, Instance Administration & Quotas | Convites, membership lifecycle, ownership transfer atômica, MFA, sessões, API tokens/service accounts, permissões por Environment, quotas/entitlements, audit UI, área de Instance Admin, rate limiting. | M01, M03 | Sim |
| **M12** MCP & Agent Operations | **Introdução do MCP.** OAuth resource server, MCP Gateway stateless, catálogo de tools por fase F1–F5, presets, resource boundaries, approvals R2/R3, audit e UI de Agents & MCP, bridge stdio. | M06, M11 (+M09, M10 soft) | **Sim** — Security review específica |
| **M13** Hardening, Performance, Chaos & SLO Validation | Suites de segurança consolidadas, SSRF, isolamento de builder, secret leakage, concorrência/fault injection, Performance Lab, pisos de teste GA, chaos, abuse controls, upgrade N/N-1, validação de SLO. | M05, M06, M08, M10 (+M09, M11, M12 soft) | **Sim** — Scale Gate |
| **M14** Production Readiness & Release Candidate | E2E de todas as jornadas críticas, instalação limpa, upgrade/rollback da plataforma, exercício dos Runbooks RB-01..RB-30, DR drill final, checklist de go-live, gate do Anexo B §19, documentação e release process. | M13 (+ todos) | **Sim** — Release Gate / Go-live |

## 2. Marcos explicitamente identificados

| Marco pedido | Milestone | Story âncora |
|---|---|---|
| Primeiro vertical slice | **M01** | `M01-23-vertical-slice-e2e-acceptance` |
| Introdução do Build Pipeline | **M05** | `M05-08-railpack-automatic-build` |
| Introdução do Edge | **M04** | `M04-01-ingress-role-and-traefik-deployment` |
| Introdução do Vault | **M03** | `M03-01-encryption-envelope-and-key-management` |
| Introdução de HA | **M08** | `M08-12-cluster-readiness-and-ha-claim` |
| Introdução de Observability | **M09** | `M09-03-metrics-backend-abstraction` |
| Introdução de DR | **M10** | `M10-13-clean-rebuild-orchestration` |
| Introdução de MCP | **M12** | `M12-03-mcp-gateway-skeleton` |
| Production Readiness | **M14** | `M14-07-production-readiness-gate` |

## 3. Sequência do caminho principal

```text
M00 Foundation
 ↓
M01 First Vertical Slice          ← espinha dorsal provada
 ↓
M02 Runtime Operations & Drift
 ↓
M03 Vault & Secret Distribution   ← desbloqueia TLS, Registry, Git e Providers
 ├──────────────┬──────────────────┐
 ↓              ↓                  ↓
M04 Edge/TLS   M05 Build          M11 Governance
 ↓              ↓                  ↓
M07 Custom     M06 Delivery       M12 MCP
Domains         ↓                  ↑
 ↓             M09 Observability   │
M08 HA          ↓                  │
 └──────────→  M10 Backup/DR ──────┘
                ↓
               M13 Hardening & Scale
                ↓
               M14 Production Readiness
```

## 4. Mapeamento Anexo A → Implementation Pack

O Anexo A continua válido como **intenção**; este pack é a decomposição executável.

| Anexo A | Neste pack | Observação |
|---|---|---|
| M0 Foundation | M00 | Stack congelada em Rails + Inertia + React (não Next.js) — ver SC-01. |
| M1 Identity & Team | M01 (identidade base) + M11 (governança) | Autorização nasce em M01; convites/ownership transfer/MFA vão para M11. |
| M2 Swarm Bootstrap | M01 | Cluster single-node + Swarm Executor entram no vertical slice. |
| M3 Core Product Model | M01 | Project/Environment/Service no vertical slice. |
| M4 Runtime Reconcile | M01 (create/scale) + M02 (restart/resources/drift) | Divisão para manter Stories revisáveis. |
| M5 Build & Artifact | M05 | Depende de M03 por causa das credenciais de Registry/Git. |
| M6 Deployment Lifecycle | M06 | — |
| M7 Networking & TLS | M04 (default domain) + M07 (custom domain) | Certificate Manager em M04 porque exige o envelope de M03. |
| M8 Vault & Secrets | M03 | **Antecipado**: TLS e providers dependem do envelope. Ver SC-05. |
| M9 Observability | M09 | Observabilidade mínima já nasce em M01/M02. |
| M10 HA & Nodes | M08 | — |
| M11 Backup & DR | M10 | — |
| M12 Hardening | M13 | Controles essenciais nascem com a feature; M13 valida. |
| M13 Release Candidate | M14 | — |
| (ausente no Anexo A) | M12 MCP | Anexo F + Anexo G §18 posicionam MCP após Command/Query madura. |
| (ausente no Anexo A) | M11 Governance | Extraído de M1 para não inflar o vertical slice. |

## 5. Feature flags de rollout

Herdadas do Anexo A §10, com o Milestone que as habilita:

| Flag | Habilitada em | Regra |
|---|---|---|
| `builds.enabled` | M05 | Só após image deploy estável (M01/M02). |
| `domains.default.enabled` | M04 | Após routing default validado. |
| `domains.custom.enabled` | M07 | Após default routing e Certificate Manager estáveis. |
| `vault.enabled` | M03 | Só quando Recovery Key estiver verificável e rotacionável. |
| `ha.enrollment.enabled` | M08 | Após runtime single-node estável. |
| `autoscaling.enabled` | M09 | Após metrics confiáveis e manual scale estável. |
| `backup.restore.enabled` | M10 | Restore pode ficar staff-only antes de self-service. |
| `terminal.enabled` | M09 | Restrito até RBAC/audit hardening. |
| `mcp.enabled` | M12 | Por fase F1→F5, nunca tudo de uma vez. |

## 6. Backlog explicitamente pós-core

Compatível com a arquitetura, **fora** deste roadmap (Anexo A §12). Nenhum Milestone deste pack pode implementá-los:
multi-cluster federation / multi-region ativo-ativo · managed PostgreSQL/Redis/storage próprios · Kubernetes runtime provider · marketplace público · Enterprise SSO/SCIM · canary/blue-green avançado e traffic splitting · service mesh e mTLS automático · billing/metering comercial · cost optimization automática · build farm multi-região · AI assistant operacional.
