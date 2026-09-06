# M02-06 — Drift detection and the Platform Wins policy

## Objective
Detectar quando o runtime foi alterado fora do Control Plane e restaurar o Desired State por padrão — tornando a autoridade do PostgreSQL uma propriedade verificável, não uma afirmação.

## Outcome
Um `docker service scale` manual é detectado, registrado como `DriftRecord` e **revertido**; recursos sem ownership da plataforma continuam intocados.

## References
- `docs/architecture/07-internal-control-plane.md` §8 (drift detection), §8.1 (alteração manual), §11.4 (classe DRIFT), §17.1 (status DRIFTED)
- `docs/architecture/09-data-model-apis-contracts.md` §10 (DriftRecord)
- `docs/AGENT_RULES.md` — “Reconciliation”, drift policy Platform Wins

## Preconditions
`M02-03` e `M02-04` done.

## Scope
- Classe de diff `DRIFT` no Service Reconciler e no Network Reconciler.
- `DriftRecord`: recurso, campo divergente, valor desejado, valor observado, severidade, `firstSeenAt`, `lastSeenAt`, resolução.
- **Política padrão Platform Wins**: para recursos gerenciados, o desired state é restaurado.
- Status `DRIFTED` exibido enquanto a divergência existe.
- Evento de produto e AuditLog para cada drift detectado e para cada reversão.
- **Boundary**: recursos sem ownership da plataforma **nunca** são revertidos, adotados ou apagados (`M01-16`).

## Out of Scope
- Adopt runtime state (`M02-07`) — é o caminho **oposto**, e é explícito.
- Drift de certificados, domínios e secrets (`M03`, `M04` trazem os seus reconcilers).
- Política de drift configurável por recurso — não há requisito; Platform Wins é o padrão do doc 07 §8.1.

## Domain Impact
**Entidade:** `DriftRecord`.
**Invariante:** drift é uma **condição normal** do sistema, não uma exceção. O desenho trata falha parcial e alteração externa como esperadas (doc 07 §26).

## Async / Control Plane
A detecção acontece no sweep periódico e é acelerada por Docker Events (`M02-12`). A correção passa pelo ciclo normal: Operation → lease → Executor → re-inspeção. **Nunca** uma mutação direta fora do fluxo.

## UI Impact
Badge `DRIFTED` no recurso, com o que divergiu e desde quando. Histórico de drifts no recurso.

## Security Requirements
- Drift detection é um controle **detectivo** de integridade: uma alteração não autorizada no runtime fica registrada com actor desconhecido e vira evidência (Anexo C §2, integridade).
- A reversão automática é limitada a recursos com ownership da plataforma. Um falso positivo aqui destruiria workload de terceiro — por isso o predicado de `M01-16` exige `managed=true` **e** IDs consistentes.
- Cada reversão gera AuditLog com `actorType: SYSTEM`, o valor observado e o valor restaurado.

## Observability Requirements
- `DriftRecord` com severidade e resolução.
- Métrica: drifts detectados por janela e tempo até reversão.
- Meta do Anexo B §5: detecção de drift por sweep ≤ 60 s.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| `docker service scale` manual | Detectado, registrado e revertido para o desired state. |
| Recurso de terceiro alterado | **Ignorado** — sem ownership, sem reversão. |
| Drift durante uma operação legítima em andamento | Não confundir rollout com drift: o reconciler compara contra a revisão alvo, não contra a anterior. |
| Drift recorrente no mesmo campo | Registrado como padrão; não entrar em loop agressivo de reversão. |
| Reversão falha | `BLOCKED` com causa; o recurso permanece `DRIFTED` e visível. |
| Ownership ambíguo | Não reverter; registrar anomalia para revisão humana. |

## Acceptance Criteria
1. Uma alteração manual em um Service gerenciado é detectada como `DRIFT`.
2. A reversão restaura o desired state pelo ciclo normal de Operation, nunca por mutação direta.
3. `DriftRecord` registra campo divergente, valores desejado e observado, severidade e timestamps.
4. Um recurso **sem** ownership da plataforma alterado manualmente **não** é revertido, provado contra Swarm real.
5. Ownership ambíguo não gera reversão; gera anomalia registrada.
6. Um rollout legítimo em andamento **não** é confundido com drift.
7. O status `DRIFTED` é exibido enquanto a divergência existe.
8. Drift recorrente é registrado como padrão sem loop agressivo de reversão.
9. Falha na reversão deixa `BLOCKED` com causa e o recurso visivelmente `DRIFTED`.
10. Cada detecção e cada reversão geram AuditLog com `actorType: SYSTEM`.
11. A detecção por sweep ocorre dentro do limiar configurado.

## Required Tests
- **unit**: classificação `DRIFT` vs `ROLLOUT` em andamento; severidade.
- **integration**: `DriftRecord` persistido; AuditLog de reversão; drift recorrente sem loop.
- **Docker/Swarm**: `docker service scale` manual revertido; recurso de terceiro intocado; ownership ambíguo não revertido; reversão falhando.
- **security**: nenhuma reversão fora do ownership da plataforma.

## Quality Gates
Local Quality Gate + `bin/fitness` (AF-03) + suíte Docker/Swarm. **Story crítica: exige plan mode** — reconciliação com efeito destrutivo potencial.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos contra Swarm real, recurso de terceiro comprovadamente intocado, Critical/High = 0.
