---
title: "Opanel — Implementation Pack"
type: "implementation-index"
status: "ready-for-human-review"
---

# Opanel — Implementation Pack

Este diretório é a camada entre a **especificação aprovada** (`docs/architecture/01..10`, `docs/annexes/A..I`) e o **código**. Ele existe para que qualquer agente — Claude Code, Codex ou humano — consiga executar a plataforma Story por Story sem redescobrir a arquitetura a cada sessão.

O Implementation Pack **não substitui a especificação**. Ele a decompõe. Em caso de divergência, vale a ordem de precedência de `docs/AGENT_RULES.md`.

## Como usar

| Preciso de… | Leia |
|---|---|
| Visão geral e ordem dos Milestones | [`ROADMAP.md`](ROADMAP.md) |
| DAG, caminho crítico e paralelização | [`DEPENDENCIES.md`](DEPENDENCIES.md) |
| Prova de cobertura da especificação | [`COVERAGE.md`](COVERAGE.md) |
| Conflitos encontrados na especificação | [`SPEC_CONFLICTS.md`](SPEC_CONFLICTS.md) |
| O que estou construindo agora | `M<XX>/README.md` + a Story atual |
| Condição de conclusão do Milestone | `M<XX>/GOAL.md` |
| Estado persistente do loop autônomo | `M<XX>/tasks.json` |
| Estado do handoff Implementer ↔ Reviewer | `M<XX>/review-state.json` |
| Máquina de estados entre agentes | [`AGENT_ORCHESTRATOR.md`](AGENT_ORCHESTRATOR.md) |
| Formato de ADR, Story Report, Milestone Report, dependência, review e blocker | [`../templates/`](../templates/README.md) |

## Estrutura de cada Milestone

```text
MXX/
├── README.md           # identidade, escopo, dependências, arquitetura, aceite, exit gate
├── GOAL.md             # condição de conclusão executável via /goal
├── tasks.json          # estado das Stories no Autonomous Development Loop
├── review-state.json   # estado do handoff Implementer ↔ Reviewer independente
└── stories/            # uma Story por arquivo, com Acceptance Criteria e Definition of Done
```

Artefatos produzidos **durante** a execução (não versionados neste Goal de planejamento):

```text
MXX/
├── MILESTONE_REPORT.md   # gerado ao final da implementação, com Status: READY_FOR_REVIEW
├── CODEX_REVIEW_<NN>.md  # verdict do reviewer independente — escrito SOMENTE pelo orquestrador
├── FIX_REPORT_<NN>.md    # correções dos findings bloqueantes de um review
├── BLOCKERS.md           # Stories BLOCKED com diagnóstico reproduzível
├── reports/<story>.md    # Story Report: evidências, decisões locais, dependências
├── review/<story>.md     # self-review por Story (qualidade de implementação)
└── evidence/<story>/     # saídas de testes e checks (não versionado)
```

O formato de cada um desses artefatos está em [`docs/templates/`](../templates/README.md).

## Ciclo de execução de uma Story

```text
Story READY
   ↓
ler Story completa + apenas as References declaradas
   ↓
inspecionar implementação existente
   ↓
plan (quando a Story exigir) → implementar a menor solução completa
   ↓
Local Quality Gate  (Anexo I §11)
   ↓
Reviewer Agent independente  (Anexo I §17)  → Critical = 0, High = 0
   ↓
Pre-commit Gate  (Anexo I §12) → commit → Post-commit Gate  (Anexo I §14)
   ↓
atualizar tasks.json (status + commit) → Story DONE
```

O self-review por Story é uma **verificação de qualidade da implementação**. Ele não substitui — e não pode simular — o review independente do Milestone.

## Handoff de review por Milestone

Papéis são fixos (`CLAUDE.md`, [`ADR-0003`](../decisions/ADR-0003-agent-review-orchestrator.md), [`AGENT_ORCHESTRATOR.md`](AGENT_ORCHESTRATOR.md)):

```text
Claude IMPLEMENTER  →  status: ready_for_review
        ↓
Codex REVIEWER (read-only, verdict independente)
        ↓
ACCEPTED     → human_acceptance   (somente um humano libera o próximo Milestone)
NOT_ACCEPTED → fix_required → Claude FIX → ready_for_review → novo review
        ↓
limite de tentativas excedido → blocked
```

Regras que o implementador precisa respeitar:

- terminar a implementação gerando `MILESTONE_REPORT.md` com `Status: READY_FOR_REVIEW` e colocando `review-state.json.status` em `ready_for_review`;
- **nunca** escrever `CODEX_REVIEW_<NN>.md`, emitir `ACCEPTED`/`NOT_ACCEPTED`, nem mover `review-state.json` para `reviewing`, `fix_required`, `accepted` ou `human_acceptance`;
- **nunca** substituir o review independente por subagente, contexto novo ou self-review;
- na fase `fixing`, corrigir apenas findings `Critical`/`High`, gerar `FIX_REPORT_<NN>.md` e voltar a `ready_for_review`.

Os estados válidos de `review-state.json` são `implementing`, `ready_for_review`, `reviewing`, `fix_required`, `fixing`, `accepted`, `human_acceptance` e `blocked`, validados por `scripts/schemas/review-state.schema.json`.

## Estados permitidos em `tasks.json`

`pending` · `ready` · `in_progress` · `review` · `fix_required` · `done` · `blocked`

Stories, gates e `MILESTONE_REPORT.md` verdes permitem ao implementer declarar
`ready_for_review`. Somente um verdict `ACCEPTED` do Codex move o Milestone para
`human_acceptance`. Nenhuma dessas transições inicia o Milestone seguinte.

Motivos de bloqueio devem usar os qualificadores de `docs/AGENT_RULES.md`:
`BLOCKED_FOR_PRODUCT_DECISION` · `BLOCKED_FOR_HUMAN_APPROVAL` · `BLOCKED_EXTERNAL_DEPENDENCY`.

## Milestones

| ID | Nome | Resultado observável |
|---|---|---|
| [M00](M00/README.md) | Foundation | Repositório executável com gates, CI e loop autônomo operando. |
| [M01](M01/README.md) | First Vertical Slice | Login → Service a partir de imagem OCI → Swarm Service 1/1 healthy → logs → scale 3/3. |
| [M02](M02/README.md) | Runtime Operations & Drift Control | Restart, resources, placement, health policy, drift revertido e Operations Center ao vivo. |
| [M03](M03/README.md) | Vault, Encryption & Secret Distribution | Secret versionada e cifrada chega ao workload via Swarm Secret; Recovery Key verificada. |
| [M04](M04/README.md) | Ingress, Default Domains & TLS | Service acessível por HTTPS em domínio default da plataforma. |
| [M05](M05/README.md) | Source, Build & Artifacts | `git push` privado vira Artifact OCI imutável por digest. |
| [M06](M06/README.md) | Release, Deployment, Rollback & Promotion | Deploy, rollback e promoção HML→PROD sem rebuild. |
| [M07](M07/README.md) | Custom Domains & DNS Providers | Domínio do cliente ativo com TLS válido e diagnóstico ponta a ponta. |
| [M08](M08/README.md) | Cluster Expansion, Node Lifecycle & HA | Cluster multi-node com 3 managers, ingress redundante e LB; HA Ready derivado. |
| [M09](M09/README.md) | Observability, Alerts, Incidents & Autoscaling | Diagnóstico sem SSH: métricas, logs históricos, alertas, incidentes e autoscaling. |
| [M10](M10/README.md) | Backup, Restore & Disaster Recovery | Plataforma reconstruída em infraestrutura nova com RPO/RTO medidos. |
| [M11](M11/README.md) | Governance, Instance Administration & Quotas | Time multiusuário governável: convites, ownership transfer, MFA, tokens, quotas, audit. |
| [M12](M12/README.md) | MCP & Agent Operations | Agente conectado por OAuth opera a plataforma dentro de scopes, boundaries e approvals. |
| [M13](M13/README.md) | Hardening, Performance, Chaos & SLO Validation | Comportamento provado sob abuso, carga, falha e concorrência. |
| [M14](M14/README.md) | Production Readiness & Release Candidate | Gate de Production Readiness executado como checklist objetivo. |

## Regras que valem para todas as Stories

1. **Segurança nasce junto da capacidade.** Não existe Milestone “de segurança no final”. M13 valida; ele não introduz o controle que deveria ter nascido com a feature.
2. **Observabilidade nasce junto da operação.** Toda Operation precisa de `request_id`, `operation_id` e escopo de tenancy desde M01.
3. **Reuso antes de criação.** Componentes React, adapters, políticas de retry e state machines existentes têm prioridade (Anexo I §6 e §20).
4. **Menor solução completa.** Não implementar Story futura, não criar abstração especulativa, não ampliar o diff além do boundary declarado.
5. **Gate não é editável.** Falhar um gate significa corrigir a implementação — nunca afrouxar o checker.
