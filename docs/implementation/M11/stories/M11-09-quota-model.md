# M11-09 — Plan, entitlements, quotas and usage counters

## Objective
Modelar limites por Team como **proteção operacional**, para que um erro de configuração não consuma o cluster inteiro.

## Outcome
`Plan`, `TeamEntitlement`, `TeamQuota` e `UsageCounter` existem; a proximidade do limite é visível antes de ele ser atingido.

## References
- `docs/architecture/04-identity-teams-security.md` §13 (quotas e guardrails), §13.1 (hard limit × warning)
- `docs/architecture/09-data-model-apis-contracts.md` §16 (quotas, limites e billing readiness)

## Preconditions
M01 e M03 aceitos.

## Scope
- `Plan` com um conjunto padrão de limites; `TeamEntitlement` com feature flags efetivas; `TeamQuota` com os limites do doc 04 §13; `UsageCounter` com o uso atual ou agregado.
- Dimensões: clusters, nodes, projects/environments, services, replicas por Service e total, CPU/RAM solicitáveis, builds concorrentes, frequência de deploy, retenção e volume de logs, secrets e versões.
- Quatro níveis do doc 04 §13.1: `warning`, `soft limit`, `hard limit`, `safety limit`.
- Modelagem que evita espalhar `if premium` pelos módulos (doc 09 §16).
- Contadores atualizados de forma consistente.

## Out of Scope
- Enforcement (`M11-10`).
- Billing e cobrança — o modelo é `billing readiness`, não billing.
- Cost optimization (backlog).

## Domain Impact
**Invariante:** `safety limit` **não** pode ser ultrapassado nem por OWNER sem alteração administrativa explícita (doc 04 §13.1).

## Application Layer
- **Commands:** `SetTeamQuota`, `AssignPlan`, `GrantEntitlement`.
- **Queries:** `TeamUsage`, `QuotaHeadroom`.

## Security Requirements
- Quotas **não são apenas billing**; são proteção operacional (doc 04 §13, regra explícita): impedem que um erro consuma memória, réplicas ou builds de todos.
- `safety limit` é inviolável sem ação administrativa — nem o OWNER o ultrapassa.
- Alterar quota é ação privilegiada e auditada.
- Contadores não podem ser manipulados pelo cliente; são derivados do estado real.
- Entitlements não substituem autorização: ter a feature habilitada não dispensa a Policy.

## Observability Requirements
Uso × limite por dimensão, com proximidade visível **antes** do bloqueio. Histórico de quando um limite foi atingido.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Contador divergindo do estado real | Reconciliação periódica; a fonte é o estado, não o contador. |
| Limite alterado para baixo do uso atual | Permitido, mas o excesso é sinalizado; nada é destruído automaticamente. |
| Plano sem limite definido para uma dimensão | Default seguro, nunca ilimitado por omissão. |
| Entitlement ausente | A feature fica indisponível, com a razão. |
| Tentativa de ultrapassar `safety limit` | Bloqueada mesmo para OWNER. |

## Acceptance Criteria
1. `Plan`, `TeamEntitlement`, `TeamQuota` e `UsageCounter` existem.
2. As dimensões do doc 04 §13 são representáveis.
3. Os quatro níveis (`warning`, `soft`, `hard`, `safety`) existem.
4. `safety limit` **não** pode ser ultrapassado nem por OWNER, provado por teste.
5. Dimensão sem limite definido usa **default seguro**, nunca ilimitado por omissão.
6. Contadores são derivados do estado real e reconciliados periodicamente.
7. Contadores **não** podem ser manipulados pelo cliente.
8. Reduzir um limite abaixo do uso atual sinaliza o excesso sem destruir nada automaticamente.
9. Entitlement ausente torna a feature indisponível com a razão, mas **não** substitui a Policy.
10. Uso × limite é visível com a proximidade **antes** do bloqueio.
11. Alterar quota é privilegiado e gera AuditLog; negativo cross-team passa.
12. A modelagem evita espalhar condicionais de plano pelos módulos.

## Required Tests
- **unit**: níveis de limite; default seguro; cálculo de headroom.
- **integration**: reconciliação de contador; redução de limite abaixo do uso.
- **security**: `safety limit` inviolável; contador não manipulável; entitlement não substituindo Policy.
- **policy**: negativo cross-team.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, `safety limit` inviolável provado, defaults seguros verificados, Critical/High = 0.
