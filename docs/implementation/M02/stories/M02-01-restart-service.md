# M02-01 — Restart Service as an auditable FORCE_ROLLOUT operation

## Objective
Permitir reiniciar um Service sem alterar o artifact, usando o mecanismo nativo do Swarm em vez de um supervisor paralelo.

## Outcome
O operador clica em Restart; a plataforma cria uma Operation `FORCE_ROLLOUT`; as Tasks são recriadas conforme a update policy; a UI só declara sucesso após a convergência.

## References
- `docs/architecture/03-runtime-observability.md` §4.2 (restart manual), §21 (Swarm é o reconciliador)
- `docs/architecture/07-internal-control-plane.md` §5 (Operation), §24 (API operacional)
- `docs/architecture/10-ui-use-cases.md` UC-022, §12.1

## Preconditions
M01 aceito.

## Scope
- Operation `FORCE_ROLLOUT`: força recriação das Tasks sem mudar imagem, env ou configuração funcional.
- Serialização por `serviceId` usando o lease de `M01-15`.
- Ação na UI com estado de operação em andamento.
- AuditLog com actor, Service e motivo opcional.

## Out of Scope
- Restart de uma Task específica (`M09` — depende da visão de tasks completa).
- Rolling update com verificação de health e rollback automático (`M06-04`..`M06-06`).
- Restart policy do Swarm (`M02-05`).

## Application Layer
- **Commands:** `RestartService`.
- **Policies:** `service.restart` para ADMIN/DEVELOPER conforme escopo.

## Async / Control Plane
Restart é Operation durável como qualquer outra mutação de infraestrutura: intenção persistida, worker executa, reconciler confirma. A requisição HTTP retorna `operationId` imediatamente.

## API Impact
Retorna `operationId`. Restart durante outra operação mutante no mesmo Service é serializado ou rejeitado com `OPERATION_IN_PROGRESS`.

## UI Impact
Botão Restart no Service, com confirmação leve (é reversível) e feedback de operação em andamento.

## Security Requirements
- Exige permissão; gera AuditLog (doc 03 §18: restart é ação auditável).
- Negativo cross-team obrigatório.
- Não permite alterar configuração por baixo do pano: um restart que mudasse spec seria um `UPDATE`, não um restart.

## Observability Requirements
Timeline com: requisitado, update aceito pelo Swarm, tasks recriadas, health satisfeito, terminal. Log com `service_id` e `operation_id`.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Outra operação mutante ativa | Serializado ou `OPERATION_IN_PROGRESS`, nunca concorrente. |
| Tasks não voltam a ficar saudáveis | Operation vai para degradado/falho com causa; **não** `SUCCEEDED`. |
| Service pausado ou em zero réplicas | Restart é `NOOP` com explicação, não erro obscuro. |
| Executor perde a resposta | Re-inspeção decide; nunca repetir cegamente. |

## Acceptance Criteria
1. Restart recria as Tasks sem alterar imagem, env ou configuração funcional.
2. A operação é durável, retorna `operationId` e só vira `SUCCEEDED` após convergência observada.
3. Restart concorrente com outra mutação é serializado ou rejeitado com erro estável.
4. Tasks que não voltam a ficar saudáveis levam a estado falho com causa, não a sucesso.
5. Restart em Service pausado ou com zero réplicas é `NOOP` explicado.
6. AuditLog registra actor, Service, `operationId` e resultado.
7. Negativo cross-team e teste de role sem permissão passam.

## Required Tests
- **unit**: classificação da operação; `NOOP` para service parado.
- **integration**: serialização com outra operação; ausência de falso sucesso.
- **Docker/Swarm**: restart real com recriação de Tasks observada.
- **policy**: negativo cross-team; role sem permissão.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm.

## Definition of Done
Os 7 Acceptance Criteria satisfeitos contra Swarm real, ausência de falso sucesso provada, Critical/High = 0.
