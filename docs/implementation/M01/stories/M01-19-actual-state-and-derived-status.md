# M01-19 — Actual state observation and derived Service status

## Objective
Observar o estado real do Swarm e derivar dele o status que a UI apresenta — para que “Healthy” signifique *observado saudável*, não *gravei no banco*.

## Outcome
`ServiceObservation` registra réplicas desejadas/rodando/saudáveis, digest observado e `observedAt`; o status do Service é calculado a partir de `appliedRevision` + observação; dado velho é sinalizado.

## References
- `docs/architecture/07-internal-control-plane.md` §3.2 (actual state), §17.1 (status de Service derivado)
- `docs/architecture/03-runtime-observability.md` §2.2 (estado operacional), §3 (health model), §3.3 (readiness e liveness)
- `docs/architecture/09-data-model-apis-contracts.md` §10 (actual state e observações)
- `docs/architecture/10-ui-use-cases.md` §25 (stale actual state, partial failure)

## Preconditions
`M01-18` done.

## Scope
- `ServiceObservation`: serviceId, swarmServiceId, desiredTasks, runningTasks, healthyTasks, failedTasks, observedImageDigest, updateStatus, nodes, `observedAt`, `dockerVersionIndex`.
- Cálculo de status **derivado** conforme doc 07 §17.1: `PENDING`, `DEPLOYING`, `HEALTHY`, `DEGRADED`, `FAILED`, `PAUSED`. (`DRIFTED` chega em `M02-06`.)
- Health agregado do doc 03 §3.1 no que existe em M01: estado da Task, health do container quando a imagem declara, e convergência desired × running.
- Distinção explícita entre **Running** e **Healthy** (doc 03 §3, regra normativa).
- Marcação de dado velho: observação além do limiar → UI mostra “last observed …” e **não** declara Healthy.
- Falha parcial exibida como `7/8 healthy`, não como “failed” (doc 10 §25).

## Out of Scope
- Probe HTTP/TCP própria da plataforma e health policy configurável (`M02-04`).
- Métricas de CPU/memória (`M09`).
- Crash loop detection (`M02-05`).
- Ingress health (`M04-13`).

## Domain Impact
**Entidade:** `ServiceObservation` — derivada, reconstruível, com retenção menor que o desired state.
**Invariante (doc 09 §10):** actual state **não** compete com desired state no mesmo conjunto de colunas.
**Invariante (doc 07 §17.1):** o status apresentado é derivado, nunca um booleano salvo manualmente.

## Application Layer
- **Commands:** `ObserveService` (via job periódico e após cada Operation).
- **Queries:** `ServiceRuntimeView` completa — desired × actual, com divergência explícita.

## Async / Control Plane
A observação alimenta o reconciler e a UI. A corretude vem de **reler o estado**, não de confiar em um fluxo ininterrupto de eventos (doc 07 §11.2). Em M01 a fonte é o sweep periódico; Docker Events entram como acelerador em `M02-12`.

## Security Requirements
- A observação é somente leitura e passa pelo Executor.
- Nenhum dado de observação vaza entre Teams; a query parte do escopo de tenancy.
- A observação não registra variáveis de ambiente nem conteúdo de secret do Service.

## Observability Requirements
- `observedAt` sempre presente; a UI mostra a idade do dado.
- Divergência entre desired e actual é **exibida**, não escondida (doc 03 §2.1: “A UI deve sempre mostrar os dois lados”).
- Logs com `service_id`, `operation_id` e o resumo da observação.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Falha ao observar | Mantém a última observação; marca como velha; **não** declara Healthy. |
| Task running mas unhealthy | Status `DEGRADED`; Running ≠ Healthy. |
| Parte das réplicas saudável | Exibir `n/m healthy`, não “failed”. |
| Digest observado diferente do desejado | Divergência exibida; a correção ativa é de `M02-06`. |
| Observação chegando fora de ordem | Uma observação mais antiga **não** sobrescreve uma mais recente (Anexo D §18, “Node event atrasado”). |

## Acceptance Criteria
1. `ServiceObservation` registra desired/running/healthy/failed tasks, digest observado e `observedAt`.
2. O status do Service é derivado de `appliedRevision` + observação; nenhuma coluna booleana de saúde é gravada manualmente.
3. Um Service com Task running mas unhealthy aparece como `DEGRADED`, não `HEALTHY`.
4. Falha parcial é exibida como `n/m healthy`.
5. Uma observação além do limiar é marcada como velha e o Service **não** é exibido como `HEALTHY`.
6. Falha ao observar preserva a última observação com sua idade original.
7. Uma observação mais antiga não sobrescreve uma mais recente, provado por teste.
8. A divergência entre desired e actual é exibida explicitamente.
9. A observação não registra variável de ambiente nem conteúdo de secret.
10. Um usuário de outro Team não lê observações, provado por teste cross-team.
11. `ServiceObservation` não escreve em nenhuma coluna de desired state.

## Required Tests
- **unit**: derivação de status; detecção de dado velho; ordenação de observações.
- **integration**: observação persistida; falha de leitura preservando a anterior; observação fora de ordem.
- **Docker/Swarm**: Service real com réplica saudável e com réplica falhando; divergência de digest.
- **policy**: negativo cross-team.
- **security**: ausência de env/secret na observação.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, Running ≠ Healthy provado contra runtime real, observação fora de ordem tratada, Critical/High = 0.
