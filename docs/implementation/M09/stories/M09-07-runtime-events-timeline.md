# M09-07 — Runtime event ingestion and unified operational timeline

## Objective
Construir a linha do tempo causal do que aconteceu com um recurso, unindo eventos de runtime, operações, deployments e drift em uma única sequência.

## Outcome
A página do Service mostra uma timeline única: deploy → tasks reiniciando → health degradado → autoscale → recuperação — com os IDs que permitem seguir cada item.

## References
- `docs/architecture/03-runtime-observability.md` §11 (eventos de runtime)
- `docs/architecture/07-internal-control-plane.md` §17.2, §18 (eventos de produto para a UI)
- `docs/architecture/10-ui-use-cases.md` §24 (Operations Center)

## Preconditions
`M09-01` done.

## Scope
- Ingestão dos eventos de runtime do doc 03 §11: `TASK_STARTED`, `TASK_FAILED`, `SERVICE_CONVERGED`, `NODE_DOWN`, `NODE_DRAINED`, `OOM_DETECTED`, `AUTOSCALE_APPLIED`, `HEALTH_DEGRADED`, `RECOVERED`.
- Unificação com eventos de Operation, Deployment e drift em uma timeline por recurso.
- Filtros por tipo, severidade e período; paginação por cursor.
- Correlação por `service_id`, `deployment_id`, `operation_id` e `node_id`.
- Retenção configurável, distinta da de logs.

## Out of Scope
- Alertas derivados de eventos (`M09-08`).
- Incidentes (`M09-10`).
- Logs (`M09-05`).

## Application Layer
- **Queries:** `OperationalTimeline`.
- **Jobs:** ingestão de eventos do Docker via Executor (reuso de `M02-12`).

## Security Requirements
- Eventos são **de produto**, sanitizados; nenhum payload cru do Docker chega ao usuário (doc 07 §18).
- A timeline respeita tenancy; um evento de outro Team não aparece nem por inferência.
- Eventos não carregam valor sensível.
- Conteúdo vindo do runtime é tratado como não confiável.

## Observability Requirements
Esta Story **é** a resposta operacional à pergunta “o que aconteceu?”. O critério: a partir da timeline deve ser possível formular a hipótese sem abrir os logs.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Stream de eventos interrompido | Lacuna sinalizada; o sweep periódico continua populando o estado (`M02-12`). |
| Evento duplicado | Deduplicado; não aparece duas vezes. |
| Evento fora de ordem | Ordenado por timestamp do fato, não de chegada. |
| Volume alto de eventos | Coalescing por tipo e recurso, com contagem. |
| Retenção expirada | Eventos antigos ausentes, com a data limite informada. |

## Acceptance Criteria
1. Os eventos do doc 03 §11 são ingeridos e normalizados como eventos de produto.
2. A timeline unifica eventos de runtime, Operation, Deployment e drift por recurso.
3. Os eventos são ordenados pelo timestamp do fato, não pelo de chegada.
4. Evento duplicado é deduplicado.
5. Volume alto é coalescido por tipo e recurso, com contagem.
6. Interrupção do stream é sinalizada como lacuna; o sweep continua populando o estado.
7. Nenhum payload cru do Docker chega ao usuário.
8. Nenhum evento carrega valor sensível.
9. A timeline respeita tenancy; negativo cross-team passa.
10. Filtros e paginação por cursor funcionam.
11. A partir da timeline é possível navegar para o deployment, a operação ou o node correspondente.
12. A retenção é configurável e a ausência por expiração é informada.

## Required Tests
- **unit**: normalização; ordenação por timestamp do fato; coalescing.
- **integration**: duplicados; lacuna sinalizada; retenção.
- **Docker/Swarm**: eventos reais de Task falhando e recuperando.
- **policy**: negativo cross-team.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, timeline unificada e correlacionável, Critical/High = 0.
