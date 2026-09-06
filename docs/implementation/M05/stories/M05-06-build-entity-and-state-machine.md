# M05-06 — Build entity, state machine and deduplication

## Objective
Modelar o build como recurso durável com estados explícitos, evitando reconstruir o mesmo commit com a mesma configuração sem necessidade.

## Outcome
Um build percorre `QUEUED → PREPARING → CHECKOUT → BUILDING → PUSHING → SUCCEEDED`, com falhas terminais explícitas; um segundo trigger idêntico reutiliza o resultado.

## References
- `docs/architecture/02-build-deploy.md` §17.1 (estados de Build), §16 (dedup por revision + config)
- `docs/architecture/09-data-model-apis-contracts.md` §8.1 (Build), §17 (state machines)
- `docs/annexes/B-nfr-slos.md` §7 (queue wait, overhead, cancelamento)

## Preconditions
`M05-05` done.

## Scope
- `Build`: serviceId, sourceRevisionId, strategy, status, builderNodeId, startedAt/finishedAt, logRef, cacheMetadata, `buildConfigHash`.
- State machine com falhas `FAILED`, `CANCELED`, `TIMED_OUT`.
- **Deduplicação** por `sourceRevisionId` + `buildConfigHash`: o mesmo commit com a mesma configuração não é reconstruído sem necessidade; um flag explícito permite forçar rebuild.
- Fila de builds com controle de concorrência por Team/cluster.
- Estados derivados de eventos duráveis, não de mensagens voláteis na fila.

## Out of Scope
- Execução do build (`M05-07`..`M05-09`).
- Logs (`M05-14`) e cancelamento (`M05-15`).
- Quotas por Team (`M11-10`) — aqui existe o controle de concorrência técnico, não a quota comercial.

## Domain Impact
**Entidade:** `Build`.
**Invariante:** o build é imutavelmente ligado a uma `SourceRevision`; ele nunca “muda de commit”.

## Application Layer
- **Commands:** `CreateBuild`, `TransitionBuild`.
- **Queries:** `BuildsForService`, `BuildDetail`.
- **Policies:** `build.create` conforme escopo.

## Async / Control Plane
O build é executado por worker, com Operation durável. Estados vêm de eventos persistidos: se o worker morrer, o estado não se perde e o build não fica “eternamente BUILDING” (o watchdog de `M01-14` cobre).

## Security Requirements
- `buildConfigHash` inclui **todos** os inputs que afetam a imagem: estratégia, `rootDir`, `dockerfilePath`, build args e a identidade (não o valor) dos build secrets. Um hash incompleto permitiria servir um artefato construído com configuração diferente — quebra de supply chain.
- Forçar rebuild é ação explícita e auditada.
- `build.create` exige permissão; negativo cross-team obrigatório.

## Observability Requirements
- Timeline por etapa com duração.
- Métricas do Anexo B §7: espera na fila (p95 ≤ 30 s; alertar acima de 2 min), overhead da plataforma antes do build (p95 ≤ 15 s).
- Duração comparada com a **baseline histórica do próprio Service** — não existe SLO único de duração de build.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Worker morre durante o build | Estado não se perde; watchdog marca e permite retomar ou falhar com causa. |
| Trigger duplicado do mesmo commit e config | Deduplicado; retorna o build existente. |
| Rebuild forçado | Permitido explicitamente e auditado. |
| Fila saturada | Backpressure e alerta; nunca perder o pedido. |
| Transição inválida | Rejeitada com `INVALID_STATE_TRANSITION`. |
| Build preso além do deadline | `TIMED_OUT` (`M05-15` implementa o corte). |

## Acceptance Criteria
1. `Build` existe com a state machine do doc 02 §17.1 e falhas terminais explícitas.
2. Transição inválida é rejeitada com `INVALID_STATE_TRANSITION`.
3. O build é imutavelmente ligado a uma `SourceRevision`.
4. `buildConfigHash` inclui todos os inputs que afetam a imagem, incluindo a **identidade** dos build secrets (nunca o valor).
5. O mesmo commit com a mesma configuração é deduplicado, retornando o build existente.
6. Forçar rebuild é ação explícita e auditada.
7. Estados são derivados de eventos duráveis; a morte do worker não perde o estado.
8. Build preso além do deadline é detectado (o corte é de `M05-15`).
9. A fila aplica backpressure sob saturação, sem perder pedidos.
10. Métricas de espera na fila e de overhead estão disponíveis, e a duração é comparada com a baseline do Service.
11. `build.create` exige permissão; negativo cross-team passa.

## Required Tests
- **unit**: state machine; cálculo do `buildConfigHash` incluindo todos os inputs.
- **integration**: dedup por revisão + config; rebuild forçado; morte do worker preservando estado; backpressure.
- **policy**: negativo cross-team.
- **security**: `buildConfigHash` não contém valor de build secret, apenas identidade.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, dedup e completude do hash provadas, estado resiliente à morte do worker, Critical/High = 0.
