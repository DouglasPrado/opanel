# M08-01 — Platform Enrollment Token

## Objective
Esconder o join token de longa duração do Swarm atrás de um token próprio da plataforma: uso único, TTL curto e apenas hash persistido.

## Outcome
O operador gera um comando de enrollment com validade de minutos; o token é consumido no primeiro uso e não serve mais.

## References
- `docs/architecture/06-infrastructure-provisioning.md` §6.1 (não expor o join token), §6.2 (EnrollmentToken)
- `docs/architecture/09-data-model-apis-contracts.md` §4.3 (EnrollmentToken)
- `docs/architecture/10-ui-use-cases.md` UC-004, §16.4

## Preconditions
M04 aceito.

## Scope
- `EnrollmentToken`: clusterId, requestedRole, tokenHash, expiresAt, maxUses (1 por padrão), usedCount, usedAt, usedByNodeId, createdBy, revokedAt, status.
- Geração com entropia adequada; **apenas hash persistido**.
- TTL curto e configurável (default na ordem de 15 minutos).
- Consumo transacional: incremento de `usedCount` atômico, para que dois hosts simultâneos não usem o mesmo token.
- Revogação imediata pela UI.
- Exibição do comando de bootstrap com contagem regressiva.

## Out of Scope
- Script de bootstrap (`M08-02`) e fluxo completo (`M08-03`).
- Join token do Swarm e sua rotação (`M08-08`).
- Provisionamento por cloud provider (backlog).

## Domain Impact
**Entidade:** `EnrollmentToken`.
**Invariante:** `maxUses` é respeitado atomicamente; um token de uso único **nunca** é consumido duas vezes.

## Application Layer
- **Commands:** `CreateEnrollmentToken`, `RevokeEnrollmentToken`, `ConsumeEnrollmentToken`.
- **Policies:** criar exige ADMIN/`INSTANCE_ADMIN`; role `manager` exige privilégio maior (`M08-05`).

## Security Requirements
- **Somente o hash é persistido** (doc 06 §6.2). O valor bruto existe apenas na resposta da criação.
- O token nunca aparece em log, AuditLog ou métrica — apenas seu ID e o resultado.
- TTL curto: minutos, não horas. Um token vazado tem janela mínima.
- **Consumo atômico**: a validação e o incremento acontecem na mesma transação, com `SELECT ... FOR UPDATE` ou equivalente, para impedir uso simultâneo (doc 09 §24, “Consumir enrollment”).
- Revogação é imediata e o token deixa de funcionar na tentativa seguinte.
- Um token para `manager` é tratado com privilégio maior desde a criação.
- Criação, consumo e revogação geram AuditLog.

## Observability Requirements
Estado do token: pendente, usado, expirado, revogado — com quem criou e, quando usado, por qual node. Métrica de tokens criados e de tentativas rejeitadas.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Token expirado | Rejeitado; o bootstrap aborta **antes** do join. |
| Token já usado | Rejeitado. |
| Dois hosts usando o mesmo token simultaneamente | Apenas um consome; o outro é rejeitado — provado por teste concorrente. |
| Token revogado | Rejeitado imediatamente. |
| Token de outro cluster | Rejeitado. |
| Token bruto solicitado depois | Impossível: só o hash existe. |

## Acceptance Criteria
1. `EnrollmentToken` existe com todos os campos do doc 06 §6.2.
2. Apenas o **hash** é persistido; o valor bruto só aparece na resposta da criação.
3. O TTL default é curto (ordem de minutos) e configurável.
4. `maxUses` é 1 por padrão e respeitado **atomicamente**, provado por teste concorrente.
5. Token expirado, usado, revogado ou de outro cluster é rejeitado.
6. A revogação tem efeito imediato.
7. O token nunca aparece em log, AuditLog ou métrica.
8. Token para role `manager` exige privilégio maior desde a criação.
9. Criação, consumo e revogação geram AuditLog.
10. A UI mostra a contagem regressiva e a ação de revogar.
11. Criar token exige permissão; negativo cross-team passa.

## Required Tests
- **integration (concorrente)**: dois consumos simultâneos do mesmo token.
- **unit**: geração e hash; validade; estados.
- **security**: token ausente de todos os sinks; revogação imediata; token de outro cluster.
- **policy**: privilégio para role `manager`; negativo cross-team.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, consumo atômico provado por teste concorrente, token fora de todos os sinks, Critical/High = 0.
