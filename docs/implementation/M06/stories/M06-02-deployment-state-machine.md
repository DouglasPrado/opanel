# M06-02 — Deployment entity and state machine

## Objective
Modelar a tentativa de fazer um Environment convergir para uma Release como recurso durável com estados explícitos e proveniência do gatilho.

## Outcome
Um `Deployment` percorre `QUEUED → RESOLVING_CONFIG → MATERIALIZING_SECRETS → UPDATING_SERVICE → ROLLING_OUT → VERIFYING → HEALTHY`, com falhas terminais e registro de quem/o que o disparou.

## References
- `docs/architecture/02-build-deploy.md` §17.2 (estados de Deployment), §5 (triggers)
- `docs/architecture/09-data-model-apis-contracts.md` §8.4 (Deployment), §17
- `docs/architecture/07-internal-control-plane.md` §13 (fluxo de deploy)

## Preconditions
`M06-01` done.

## Scope
- `Deployment`: environmentId, serviceId, releaseId, status, strategy, previousDeploymentId, operationId, requestedBy, trigger, timestamps.
- State machine do doc 02 §17.2, com terminais `FAILED`, `ROLLED_BACK`, `CANCELED`.
- Gatilhos do doc 02 §5: manual, push, redeploy, rollback, promote, API.
- **Append-only do ponto de vista operacional**: rollback e redeploy criam **novos** Deployments; histórico nunca é reescrito.
- Boundary transacional: Deployment + Operation + refs de Release + OutboxEvent na mesma transação (doc 09 §24).
- Estados derivados de eventos duráveis, não de mensagens voláteis.

## Out of Scope
- Resolução de configuração e materialização de secrets (`M06-03`).
- Rollout e health (`M06-04`, `M06-05`).
- Concorrência (`M06-10`).

## Domain Impact
**Entidade:** `Deployment`.
**Invariante:** o histórico é append-only operacionalmente (doc 02 §5): nenhum registro é reescrito para “corrigir” um desfecho.

## Application Layer
- **Commands:** `RequestDeployment`.
- **Queries:** `DeploymentsForService`, `DeploymentDetail`.
- **Policies:** `deployment.create`; produção pode exigir mais.

## API Impact
Mutação assíncrona retorna `operationId` e o `deploymentId`. Aceita `Idempotency-Key` (`M02-13`).

## Security Requirements
- Deploy exige permissão no escopo do Environment; produção pode exigir role mais alta.
- O gatilho é registrado com o actor real: usuário, webhook, sistema ou API token — a atribuição é obrigatória (Anexo C §1.1).
- AuditLog para cada Deployment criado.
- Nenhuma requisição HTTP fica aberta esperando o rollout.

## Observability Requirements
Timeline por etapa com duração; `operationId` correlacionando com a Operation. Métrica de deployments por resultado e por gatilho.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Transição inválida | `INVALID_STATE_TRANSITION`. |
| Worker morre no meio | Estado preservado; watchdog e reconciler retomam. |
| Release indisponível | Bloqueado antes de qualquer mutação no runtime. |
| Deployment travado | `STALLED` pelo watchdog; nunca indefinidamente em `DEPLOYING`. |
| Tentativa de reescrever histórico | Impossível: rollback e redeploy criam novos registros. |

## Acceptance Criteria
1. `Deployment` existe com a state machine do doc 02 §17.2 e terminais explícitos.
2. Transição inválida é rejeitada com `INVALID_STATE_TRANSITION`.
3. Deployment + Operation + OutboxEvent são gravados na mesma transação.
4. A requisição retorna `operationId` e `deploymentId` imediatamente.
5. O gatilho e o actor real são registrados.
6. Rollback e redeploy criam **novos** Deployments; nenhum histórico é reescrito.
7. Release indisponível bloqueia antes de qualquer mutação no runtime.
8. Morte do worker preserva o estado; o reconciler retoma.
9. Deployment travado é marcado `STALLED`; nunca fica indefinidamente em `DEPLOYING`.
10. Deploy exige permissão; produção pode exigir mais; negativo cross-team passa.
11. `Idempotency-Key` é aceita e deduplica.

## Required Tests
- **unit**: state machine; classificação de gatilho.
- **integration**: boundary transacional; morte do worker; `STALLED`; `Idempotency-Key` concorrente.
- **contract**: mutação assíncrona retornando `operationId`.
- **policy**: negativo cross-team; permissão de produção.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, boundary transacional e ausência de estado perdido provados, Critical/High = 0.
