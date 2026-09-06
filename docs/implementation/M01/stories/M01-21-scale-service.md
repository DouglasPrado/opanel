# M01-21 — Scale Service and convergence to the desired replica count

## Objective
Fechar o vertical slice com a operação mais representativa do Control Plane: alterar réplicas e acompanhar a convergência real até `3/3 Healthy`.

## Outcome
O usuário altera as réplicas de 1 para 3; a operação é assíncrona e durável; a UI só declara sucesso quando o actual state converge — ou mostra um estado degradado explicável.

## References
- `docs/architecture/07-internal-control-plane.md` §12 (fluxo completo de scale)
- `docs/architecture/03-runtime-observability.md` §7 (scaling manual), §5.3 (proteção contra saturação)
- `docs/architecture/10-ui-use-cases.md` UC-020, §12.2 (scale dialog)
- `docs/annexes/B-nfr-slos.md` §5 (scale simples 1→N: p95 ≤ 60 s)

## Preconditions
`M01-19` done.

## Scope
- Command `ScaleService` com `expectedRevision`, criando Operation `SCALE` no boundary transacional de `M01-13`.
- Reconciliação até convergência, com re-inspeção; `appliedRevision` avança só depois.
- Serialização por `serviceId` (lease de `M01-15`); operação concorrente é serializada ou `SUPERSEDED`.
- UI: diálogo de scale mostrando réplicas atuais e o impacto, não apenas um input numérico (doc 10 §12.2).
- Estado `Capacity Exhausted` quando não há capacidade para agendar: Tasks ficam `Pending` e isso é **mostrado**, não escondido.

## Out of Scope
- Autoscaling (`M09-12`).
- Scale to zero (`M02-08`).
- Headroom calculado do cluster com métricas reais (`M09-04`) — em M01 o diálogo mostra a informação disponível pela observação.
- Quotas de réplicas (`M11-10`).

## Application Layer
- **Commands:** `ScaleService`.
- **Queries:** `ServiceRuntimeView` com desired × running × healthy.
- **Policies:** `service.scale` para ADMIN/DEVELOPER conforme escopo.

## Async / Control Plane
O fluxo canônico do doc 07 §12, ponta a ponta:
```text
POST scale → auth + policy → transação (desiredReplicas, desiredRevision++, Operation SCALE, OutboxEvent)
→ queue → worker → lease → Executor UpdateServiceSpec
→ Swarm converge tasks → Reconciler verifica → appliedRevision = N, Operation SUCCEEDED
→ UI atualiza
```

## API Impact
Retorna `operationId` imediatamente. `expectedRevision` desatualizada retorna `REVISION_CONFLICT`.

## UI Impact
Diálogo com réplicas atuais, novo valor e impacto conhecido. Após confirmar, a ação principal fica em estado de operação em andamento; a UI **não** mostra “concluído” antes da convergência (doc 10 §1, “Sem falso sucesso”).

## Security Requirements
- Scale exige permissão e gera AuditLog com valor anterior e novo.
- Negativo cross-team obrigatório.
- Scale não pode ser usado para contornar limites: o caminho para quotas fica preparado (`M11-10`).

## Observability Requirements
- Timeline da Operation com marcos: requisitada, revisão criada, update aceito, tasks convergindo, health satisfeito, terminal.
- Meta do Anexo B §5: convergência p95 ≤ 60 s para scale simples com imagem já presente, medida separando **tempo de infraestrutura** de **tempo esperando a aplicação ficar saudável**.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Capacidade insuficiente | Tasks `Pending`; a UI mostra `Capacity Exhausted` explicitamente, distinguindo de falha da aplicação (doc 03 §17). |
| Scale concorrente com outra operação no mesmo Service | Serializado ou `SUPERSEDED`; nunca aplicação concorrente. |
| Docker aceita o update mas as tasks não sobem | A Operation **não** vira `SUCCEEDED`; vai para degradado/falho com causa. |
| `expectedRevision` desatualizada | `REVISION_CONFLICT` com o que mudou. |
| Control Plane reinicia no meio | A intenção sobrevive; o sweep retoma; a convergência continua. |
| Scale para o mesmo valor atual | `NOOP` sem rollout desnecessário. |

## Acceptance Criteria
1. Alterar réplicas de 1 para 3 converge para `3/3` e a UI reflete o estado real.
2. A requisição retorna `operationId` imediatamente; nenhuma requisição fica aberta esperando convergência.
3. A Operation só vira `SUCCEEDED` após a re-inspeção confirmar as réplicas saudáveis.
4. Docker aceitar o update **não** é suficiente para declarar sucesso, provado por teste que impede as tasks de subirem.
5. Capacidade insuficiente resulta em `Capacity Exhausted` visível, distinguível de falha da aplicação.
6. Duas operações concorrentes no mesmo Service são serializadas ou a antiga vira `SUPERSEDED`, provado por teste concorrente.
7. `expectedRevision` desatualizada retorna `REVISION_CONFLICT`.
8. Scale para o valor atual resulta em `NOOP`.
9. Reiniciar o Control Plane no meio da operação não perde a intenção; a convergência continua.
10. Scale exige permissão, gera AuditLog com valor anterior e novo, e tem negativo cross-team.
11. A timeline da Operation separa tempo de infraestrutura de tempo esperando a aplicação ficar saudável.

## Required Tests
- **unit**: cálculo do diff de réplicas; `NOOP` para valor igual.
- **integration**: `REVISION_CONFLICT`; restart do Control Plane no meio da operação.
- **Docker/Swarm**: convergência real 1→3; tasks impedidas de subir; capacidade insuficiente; scale concorrente.
- **policy**: negativo cross-team; role sem permissão.
- **E2E**: scale pela UI com estado de operação em andamento e conclusão só após convergência.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm + concorrência.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos contra Swarm real, ausência de falso sucesso provada, restart do Control Plane coberto, Critical/High = 0.
