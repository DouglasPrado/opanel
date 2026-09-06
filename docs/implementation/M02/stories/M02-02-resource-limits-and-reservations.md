# M02-02 — CPU and memory limits, reservations and UI presets

## Objective
Dar controle explícito sobre recursos por Service, protegendo o cluster de noisy neighbor sem esconder os valores técnicos do usuário.

## Outcome
O usuário escolhe um preset ou valores customizados de CPU/RAM; a mudança gera rollout controlado; um Service sem limites explícitos é sinalizado.

## References
- `docs/architecture/03-runtime-observability.md` §5 (CPU, memória e capacidade), §5.2 (presets de UI), §5.3 (proteção contra saturação)
- `docs/annexes/B-nfr-slos.md` §10 (resource isolation e scheduling)
- `docs/architecture/10-ui-use-cases.md` UC-014, §10.2

## Preconditions
M01 aceito.

## Scope
- `cpuReservation`, `cpuLimit`, `memoryReservation`, `memoryLimit` editáveis no desired state.
- Presets de UI do doc 03 §5.2 (Nano, Small, Medium, Large, Custom), sem esconder os valores.
- `max replicas per node` como configuração de placement básica.
- Alteração gera diff `ROLLOUT` (recria Tasks) e converge.
- **Aviso** para Service em produção sem limites explícitos (Anexo B §10).
- Validação: reservation ≤ limit; valores dentro do que o cluster pode agendar.

## Out of Scope
- Quotas por Team que limitam o máximo solicitável (`M11-10`).
- Headroom real do cluster com métricas (`M09-04`).
- Autoscaling (`M09-12`).
- Placement avançado por zona/classe (`M02-03`).

## Application Layer
- **Commands:** `UpdateServiceResources`.
- **Policies:** `service.update` conforme escopo.

## Async / Control Plane
Mudança de recursos é `ROLLOUT`: recria Tasks. O reconciler aplica a menor mutação segura e re-inspeciona antes de avançar `appliedRevision`.

## UI Impact
Seção Resources com presets e campos técnicos visíveis; aviso persistente quando não há limite definido em Environment de produção.

## Security Requirements
- Limites são um controle de **disponibilidade**: impedem que um workload esgote o node (Anexo C §9, “Resource limits”).
- Validação de entrada rigorosa: valores negativos, absurdos ou malformados são rejeitados antes de chegar ao Swarm.
- Alteração gera AuditLog com valores anterior e novo.

## Observability Requirements
Log e timeline registram os valores anterior e novo. Evento de produto emitido para a mudança de desired state.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Reservation acima da capacidade do cluster | Task fica `Pending`; a UI mostra `Capacity Exhausted`, distinguindo de falha da aplicação. |
| Reservation > limit | Rejeitado na validação. |
| Redução de limit abaixo do uso atual | Permitido com aviso explícito de risco de OOM. |
| Rollout falha | Estado degradado com causa; a configuração anterior permanece servindo quando a update policy permitir. |

## Acceptance Criteria
1. CPU e memória (reservation e limit) são editáveis e persistidos no desired state.
2. A alteração gera `ROLLOUT` e converge, com `appliedRevision` avançando só após confirmação.
3. Presets existem e **não** escondem os valores técnicos.
4. `reservation > limit` é rejeitado na validação.
5. Reservation acima da capacidade resulta em Tasks `Pending` e `Capacity Exhausted` visível.
6. Service em Environment de produção sem limites explícitos recebe aviso persistente.
7. Reduzir o limit abaixo do uso atual é permitido **com aviso** de risco de OOM.
8. `max replicas per node` é configurável e respeitado.
9. AuditLog registra valores anterior e novo; negativo cross-team passa.

## Required Tests
- **unit**: validação de valores; conversão de preset; regra reservation ≤ limit.
- **integration**: rollout convergindo; aviso de service sem limites.
- **Docker/Swarm**: aplicação real de limits/reservations; Task `Pending` por reservation excessiva.
- **policy**: negativo cross-team.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm.

## Definition of Done
Os 9 Acceptance Criteria satisfeitos, `Capacity Exhausted` distinguível de falha da aplicação, Critical/High = 0.
