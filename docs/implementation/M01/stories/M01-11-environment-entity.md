# M01-11 — Environment entity with cluster placement

## Objective
Criar o Environment como entidade de primeira classe que liga um Project a um Cluster, preservando a decisão arquitetural de que Project pertence ao negócio e Cluster à infraestrutura.

## Outcome
Um Project tem Environments tipados (`PRODUCTION`, `HOMOLOGATION`, ...), cada um apontando para o Cluster onde executa, com `desiredRevision`/`appliedRevision` e status derivado.

## References
- `docs/architecture/01-foundation.md` §5.1 (hierarquia), §5.3 (isolamento de environments)
- `docs/architecture/09-data-model-apis-contracts.md` §5.2 (Environment), §17 (state machines), §18 (constraints)
- `docs/architecture/10-ui-use-cases.md` UC-010, §8 (Environments)

## Preconditions
`M01-07` e `M01-08` done.

Esta Story herda o `AC5` da `M01-07` (`SC-18`): a dependência entre as duas é circular no pack — a `M01-07` precisa de Environments para provar o bloqueio de arquivamento e declara Environment fora de escopo; esta cria a entidade e exige a `M01-07` fechada. O critério migrou para cá, onde pode ser provado.

## Scope
- `Environment`: id, projectId, clusterId, name, slug, type (`PRODUCTION`, `HOMOLOGATION`, `DEVELOPMENT`, `PREVIEW`, `CUSTOM`), desiredRevision, appliedRevision, networkId?, autoPromoteSecrets (default `false` em Production), status (`PROVISIONING`, `READY`, `DEGRADED`, `PAUSED`, `DELETING`), timestamps.
- Constraint `UNIQUE(projectId, slug) WHERE deletedAt IS NULL`.
- Criação com escolha explícita do Cluster; validação de que o Cluster está utilizável.
- Status derivado, nunca booleano salvo.
- Badge persistente de `PRODUCTION` na UI.

## Out of Scope
- Criação da overlay network (`M01-17`) — aqui só o campo `networkId` e a intenção.
- Environment compare (M06 em diante).
- Snapshots (`M10-09`).
- Mover Environment entre Clusters (UC-011) — `M10-18`, quando existir mais de um Cluster e o Restore Engine.
- Deleção com cleanup (`M02-09`).

## Domain Impact
**Entidade:** `Environment`.
**Relacionamentos:** `Project 1—N Environment`, `Environment N—1 Cluster`.
**Invariante estrutural (doc 01 §5.1):** o Project **não** é filho hierárquico do Cluster. É o Environment que referencia onde executa.
**Transições:** `PROVISIONING → READY ↔ DEGRADED | PAUSED → DELETING → DELETED`.
**Default de segurança:** `autoPromoteSecrets = false` em `PRODUCTION` (doc 09 §5.2), preparando a regra de pinning de M03.

## Application Layer
- **Commands:** `CreateEnvironment`, `UpdateEnvironment`.
- **Queries:** `EnvironmentsForProject`, `EnvironmentOverview` (versão mínima).
- **Policies:** criar exige ADMIN (ou DEVELOPER conforme escopo); operar em `PRODUCTION` pode ter restrição adicional — o caminho fica pronto, é exercido em `M11-08`.

## API Impact
Mutações retornam o recurso atualizado e, quando geram trabalho de infraestrutura, o `operationId` (doc 09 §20). A criação de Environment gera Operation a partir de `M01-17`, quando a network passa a existir.

## UI Impact
Criação de Environment com nome, tipo e Cluster. Header com switcher de Environment e badge visual persistente para `PRODUCTION` (doc 10 §8.1).

## Security Requirements
- Toda query parte do Team via Project; nenhuma busca por ID sem escopo.
- Criar Environment em Cluster de outro Team é **negado**, e o teste cobre esse caso específico (é um caminho de vazamento entre tenants).
- `PRODUCTION` recebe tratamento diferenciado desde já: badge persistente e ações destrutivas com confirmação reforçada.
- Criação e alteração geram AuditLog.

## Observability Requirements
Logs com `team_id`, `project_id`, `environment_id`, `cluster_id`, `actor_id` e `request_id`.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Cluster `DEGRADED` | Warning ou bloqueio conforme policy; nunca criar em silêncio um Environment que não pode executar. |
| Cluster de outro Team | Negado, e o motivo não revela a existência do Cluster. |
| Slug duplicado no Project | Validação inline. |
| Falha ao provisionar a network (a partir de `M01-17`) | Environment fica `DEGRADED` com ação de retry, não some. |

## Acceptance Criteria
1. Um Project ativo recebe Environments com tipo e Cluster escolhidos explicitamente.
2. `UNIQUE(projectId, slug) WHERE deletedAt IS NULL` existe no banco e é provado por caso negativo.
3. O Environment referencia o Cluster; o Project **não** depende hierarquicamente do Cluster.
4. Criar Environment apontando para Cluster de outro Team é negado sem revelar a existência do Cluster.
5. `autoPromoteSecrets` é `false` por padrão em `PRODUCTION`.
6. `desiredRevision` e `appliedRevision` existem e a revisão desejada incrementa a cada alteração relevante.
7. O status é derivado; nenhuma coluna booleana de saúde é gravada manualmente.
8. `PRODUCTION` tem badge visual persistente na UI.
9. Cluster `DEGRADED` produz warning ou bloqueio conforme policy, com mensagem explícita.
10. Criação e alteração geram AuditLog e passam por Policy, com negativo cross-team.
11. Arquivar um Project que tenha Environment ativo é bloqueado com erro explicativo, provado com o caso negativo plantado — o `AC5` da `M01-07`, que não podia ser provado antes desta Story existir (`SC-18`).

## Required Tests
- **unit**: transições de status; incremento de revisão; default de `autoPromoteSecrets`.
- **integration**: constraint de slug; criação com Cluster de outro Team negada.
- **policy**: matriz de roles + negativo cross-team.
- **unit (frontend)**: badge de `PRODUCTION`.

## Quality Gates
Local Quality Gate (Ruby/Rails, Database, React/TypeScript) + suíte cross-team.

## Definition of Done
Os 10 Acceptance Criteria satisfeitos, constraint provada, caminho cross-Team de Cluster negado, Critical/High = 0.
