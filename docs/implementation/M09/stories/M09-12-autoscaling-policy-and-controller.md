# M09-12 — Autoscaling policy and reactive controller

## Objective
Ajustar réplicas automaticamente a partir de métricas, com política explícita e decisões **explicáveis** — sem construir um scheduler concorrente ao Swarm.

## Outcome
O usuário define min/max, métrica, thresholds, steps e cooldown; o controller altera `desiredReplicas` pelo mesmo caminho de qualquer outra mutação, e registra por que decidiu.

## References
- `docs/architecture/03-runtime-observability.md` §8 (autoscaling da plataforma), §8.1 (política inicial), §21 (autoscaling é nosso)
- `docs/architecture/09-data-model-apis-contracts.md` (AutoscalingPolicy, doc 03 §19)
- `docs/architecture/10-ui-use-cases.md` §12.3 (autoscaling UI com timeline de decisões)
- `docs/annexes/A-implementation-roadmap.md` §9 (não criar autoscaling antes de métricas confiáveis)

## Preconditions
`M09-03` done. Scale manual (`M01-21`) estável.

## Scope
- `AutoscalingPolicy`: enabled, min/max replicas, métrica (CPU/memória), thresholds de scale up e down, steps, cooldowns, modo (`MANUAL`, `AUTO`, `PAUSED`).
- Controller periódico avaliando a política sobre o `MetricProvider`.
- Decisão aplicada como `desiredReplicas` pelo ciclo normal: Operation → lease → Executor → reconcile. **Nunca** mutação direta.
- **Registro de cada decisão**: métrica observada, janela, política aplicada, valor anterior e novo.
- Scale down mais conservador que scale up (doc 03 §8.2).
- Timeline de decisões na UI, explicando por que escalou.

## Out of Scope
- Regras de segurança do autoscaler (`M09-13`) — esta Story entrega o mecanismo; aquela, os guardrails.
- Métricas de negócio, requests/s, queue depth (doc 03 §8.3, evolução).
- Autoscaling de nodes (backlog).
- Autoscaling preditivo (fora de escopo, doc 03 §1.2).

## Application Layer
- **Commands:** `UpdateAutoscalingPolicy`, `ApplyAutoscalingDecision`.
- **Queries:** `AutoscalingDecisions`.
- **Providers:** consome `MetricProvider` — o controller **não** depende de um backend específico (doc 03 §8.3).

## Async / Control Plane
O autoscaler é um controller que altera **desired state**. Ele não fala com o Docker diretamente e não contorna lease, supersession nem quota. Para o resto do sistema, uma decisão de autoscaling é uma mutação como qualquer outra — com `actorType: SYSTEM`.

## Security Requirements
- O autoscaler **não** pode contornar limites: min/max são obrigatórios e a quota do Team (`M11-10`) prevalece.
- Toda decisão gera AuditLog com `actorType: SYSTEM` e a justificativa — um aumento de custo precisa ser atribuível.
- O controller **não** aumenta limite de memória após OOM automaticamente (doc 03 §17, regra explícita).
- Min/max e cooldown são guardrails contra abuso e oscilação (Anexo C §19).

## Observability Requirements
- Timeline de decisões com métrica observada, política, valor anterior e novo.
- Evento `AUTOSCALE_APPLIED`.
- Métrica: decisões por tipo, decisões suprimidas por cooldown, tempo em min e em max.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Métrica indisponível | Modo seguro (`M09-13`): não decidir. |
| Oscilação | Cooldown e assimetria up/down; medida como flapping. |
| Decisão durante rollout | Suprimida (`M09-13`). |
| Limite max atingido | Manter no max e **sinalizar** que a demanda excede o teto. |
| Quota do Team excedida | Decisão bloqueada pela quota, com registro. |
| Controller reiniciado | Sem estado em memória: a próxima avaliação recomeça do estado persistido. |

## Acceptance Criteria
1. `AutoscalingPolicy` existe com todos os campos do doc 03 §8.1 e os três modos.
2. O controller avalia periodicamente usando o `MetricProvider`, sem depender de backend específico.
3. A decisão altera `desiredReplicas` pelo **ciclo normal** de Operation; nenhuma mutação direta no Docker.
4. **Cada decisão registra** métrica observada, janela, política, valor anterior e novo.
5. Scale down é mais conservador que scale up.
6. Min e max são respeitados sempre.
7. Atingir o max mantém no max e **sinaliza** que a demanda excede o teto.
8. Quota do Team prevalece sobre a decisão do autoscaler.
9. O controller **não** aumenta limite de memória após OOM.
10. Cada decisão gera AuditLog com `actorType: SYSTEM` e justificativa.
11. O controller não guarda estado em memória; reiniciá-lo não altera o comportamento.
12. A timeline de decisões é visível na UI.

## Required Tests
- **unit**: decisão por threshold e janela; assimetria up/down; cooldown.
- **integration**: decisão aplicada pelo ciclo de Operation; quota prevalecendo; reinício do controller.
- **Docker/Swarm**: escala real disparada por métrica sintética.
- **security**: ausência de aumento automático de memória; AuditLog de decisão.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, decisões explicáveis e auditadas, ciclo normal respeitado, Critical/High = 0.
