# M09-08 — Alert rules and evaluation engine

## Objective
Converter condições observáveis em regras de alerta com escopo, janela e severidade — cobrindo as condições que a especificação já definiu como relevantes.

## Outcome
O usuário cria uma regra por Service, Environment ou Cluster; o motor a avalia periodicamente; a condição satisfeita gera um alerta.

## References
- `docs/architecture/03-runtime-observability.md` §12 (alertas e incidentes), §12.1 (regras iniciais)
- `docs/architecture/09-data-model-apis-contracts.md` §13.1 (AlertRule)
- `docs/architecture/05-backup-restore-dr.md` §17.2 (condições que geram alerta)
- `docs/annexes/B-nfr-slos.md` §16 (severidade operacional)

## Preconditions
`M09-03` e `M09-07` done.

## Scope
- `AlertRule`: scopeType/scopeId, métrica ou expressão provider-neutral, threshold, janela, severidade (`INFO`, `WARNING`, `CRITICAL`), status (`ENABLED`, `MUTED`, `DISABLED`), notificationPolicyId.
- Motor de avaliação periódica sobre o `MetricProvider` e sobre os eventos de `M09-07`.
- **Regras iniciais pré-provisionadas** do doc 03 §12.1: `ServiceUnavailable`, `ReplicaMismatch`, `NodeDown`, `IngressTargetDown`, `HighCPU`, `HighMemory`, `OOMLoop`, `DeploymentFailed`, `CertificateExpiring`.
- Contrato de extensão para as condições de proteção do doc 05 §17.2, preenchidas por `M10-17`.
- Severidade mapeada para as classes do Anexo B §16.

## Out of Scope
- Deduplicação e silenciamento (`M09-09`).
- Incidentes (`M09-10`) e notificações (`M09-11`).
- Alertas baseados em log (evolução).

## Application Layer
- **Commands:** `CreateAlertRule`, `UpdateAlertRule`, `DisableAlertRule`.
- **Queries:** `AlertRules`, `AlertRuleEvaluation`.
- **Policies:** `alert.write` para ADMIN/DEVELOPER conforme escopo.

## Security Requirements
- A expressão é **provider-neutral e limitada** — não é uma DSL arbitrária que o usuário injeta no backend (mesmo princípio de `M09-03`).
- Regras respeitam tenancy: uma regra só alcança recursos do próprio Team.
- Uma regra não pode ser usada para inferir a existência de recursos de outro Team.
- Criar e alterar regras gera AuditLog.
- Limite de regras por Team, para que a avaliação não vire vetor de custo.

## Observability Requirements
Última avaliação por regra, com resultado e valor observado. Regras que nunca dispararam e regras que disparam constantemente são igualmente sinal de problema — ambas visíveis.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Métricas indisponíveis | A regra **não** dispara nem resolve às cegas: estado `indeterminado` com causa. |
| Expressão inválida | Rejeitada na criação. |
| Janela muito curta | Aviso: ruído garantido. |
| Regra sobre recurso removido | Desativada automaticamente e sinalizada. |
| Muitas regras | Limite por Team aplicado. |
| Avaliação lenta | Timeout com causa; a regra fica `indeterminada`, não `ok`. |

## Acceptance Criteria
1. `AlertRule` existe com os campos do doc 09 §13.1.
2. As nove regras iniciais do doc 03 §12.1 são pré-provisionáveis.
3. A avaliação é periódica e usa o `MetricProvider` e os eventos de `M09-07`.
4. Com métricas indisponíveis, a regra fica **`indeterminada` com causa** — nunca dispara nem resolve às cegas.
5. Expressão inválida é rejeitada na criação.
6. Janela muito curta gera aviso.
7. Regra sobre recurso removido é desativada automaticamente e sinalizada.
8. O limite de regras por Team é aplicado.
9. A expressão é provider-neutral e limitada; nenhuma DSL arbitrária chega ao backend.
10. Regras respeitam tenancy e não permitem inferir recursos de outro Team.
11. Existe contrato de extensão para as condições de proteção do doc 05 §17.2.
12. Criar e alterar regras exige permissão e gera AuditLog.

## Required Tests
- **unit**: avaliação por janela e threshold; estado indeterminado; validação de expressão.
- **integration**: métricas indisponíveis; recurso removido; limite por Team.
- **policy**: negativo cross-team; inferência de recurso alheio.
- **security**: expressão limitada; ausência de DSL arbitrária.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, estado indeterminado provado, tenancy garantida, Critical/High = 0.
