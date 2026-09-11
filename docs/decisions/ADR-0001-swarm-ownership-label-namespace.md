---
title: "ADR-0001 — Namespace das labels de ownership no Swarm"
status: "accepted"
date: "2026-09-06"
decision-required-before: "M01-16"
accepted-date: "2026-09-08"
accepted-by: "repository owner"
---

# ADR-0001 — Namespace das labels de ownership no Swarm

**Status:** `Accepted` — aceito em 2026-09-08 pelo dono do repositório.

## Context

`docs/architecture/07-internal-control-plane.md` §7 define as labels que identificam recursos criados pela plataforma no Docker Swarm:

```text
com.platform.managed=true
com.platform.team_id=team_01...
com.platform.project_id=prj_01...
com.platform.environment_id=env_01...
com.platform.service_id=svc_01...
com.platform.release_id=rel_01...
com.platform.desired_revision=42
```

`docs/architecture/02-build-deploy.md` §11.1 descreve o mesmo conceito com outro formato, **sem prefixo de domínio**:

```text
platform.team_id=...
platform.project_id=...
platform.environment_id=...
platform.service_id=...
```

Três fatos tornam isso uma decisão, e não um detalhe:

1. A especificação já é **internamente inconsistente** entre as Partes 2 e 7.
2. O produto foi nomeado **Opanel** depois que esses documentos foram escritos.
3. Estas labels são a **identidade de ownership em runtime**. O doc 07 §7 estabelece que a plataforma só reconcilia recursos com ownership explícito e nunca adota nem apaga Services desconhecidos. Se o prefixo mudar depois do primeiro deploy real, todo recurso já existente deixa de ser reconhecido: a reconciliação passa a ver `CREATE` onde deveria ver `NOOP`, o drift detection para de funcionar e recursos órfãos ficam fora do Clean Rebuild (doc 05 §7.3).

`docs/decisions/pending-documentation-updates.md` §4 já sinalizou que a decisão é necessária e deve ocorrer **antes do M01**.

## Decision

Adotar o namespace **`com.opanel.*`** para todas as labels de ownership de recursos gerenciados no Docker Swarm — Services, networks, secrets e configs criados pela plataforma:

```text
com.opanel.managed=true
com.opanel.team_id=<id>
com.opanel.project_id=<id>
com.opanel.environment_id=<id>
com.opanel.service_id=<id>
com.opanel.release_id=<id>
com.opanel.desired_revision=<n>
```

Regras que acompanham a decisão:

- O conjunto de chaves permanece **exatamente** o do doc 07 §7. Este ADR muda somente o namespace, não a semântica nem o inventário de labels.
- O formato do doc 02 §11.1 (`platform.*`, sem domínio reverso) é descartado: labels sem namespace de domínio colidem com labels de terceiros no mesmo daemon Docker.
- Node labels de **placement** (`platform.role`, `platform.zone`, `platform.workloads`, …, doc 03 §6 e doc 06 §9.1) seguem a mesma migração para `opanel.*`, mantendo as chaves existentes.
- O namespace é constante única no código, nunca string literal repetida, para que uma futura migração seja mecanicamente localizável.

## Consequences

**Positivas**
- Ownership passa a refletir a identidade real do produto.
- Elimina a inconsistência entre as Partes 2 e 7.
- Reduz risco de colisão com labels de outros sistemas no mesmo Swarm.

**Negativas / custo**
- As Partes 2, 3, 6 e 7 precisam ser corrigidas por Story documental.
- Se a decisão for adiada para depois do primeiro deploy real, passa a exigir uma migração de labels com janela e reconciliação assistida — por isso o ADR é `Proposed` **antes** de M01.

**Neutro**
- Não há sistema em produção hoje. O custo de decidir agora é apenas documental.

## Alternatives considered

| Alternativa | Avaliação |
|---|---|
| Manter `com.platform.*` | Funciona tecnicamente e evita corrigir documentos. Mas fixa permanentemente um nome genérico que não é o do produto e deixa a inconsistência com a Parte 2 sem resolver. |
| Adotar `platform.*` (formato da Parte 2) | Rejeitado. Labels sem domínio reverso não têm garantia de unicidade em um daemon compartilhado com workloads externos, cenário explicitamente previsto no doc 07 §7. |
| Decidir depois, no primeiro deploy | Rejeitado. É exatamente o momento em que a mudança deixa de ser gratuita. |

## Affected docs

- `docs/architecture/02-build-deploy.md` §11.1
- `docs/architecture/03-runtime-observability.md` §6
- `docs/architecture/06-infrastructure-provisioning.md` §9.1
- `docs/architecture/07-internal-control-plane.md` §7
- `docs/decisions/pending-documentation-updates.md` §4 (remover a pendência ao aceitar)
- `docs/implementation/SPEC_CONFLICTS.md` SC-04

## Affected modules

Swarm Executor, Service Reconciler, Network Reconciler, Secret Reconciler, Ingress Reconciler, drift detection, Clean Rebuild e as fitness functions que verificam presença de ownership.
