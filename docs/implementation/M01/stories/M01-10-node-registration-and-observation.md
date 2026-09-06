# M01-10 — Node registration and observation

## Objective
Persistir os nodes do cluster como recurso de produto e manter uma observação do runtime que a UI e os reconcilers possam usar sem consultar o Docker a cada leitura.

## Outcome
O Manager do bootstrap aparece como `Node` com role, availability, endereço e status derivado; a observação tem `lastSeenAt` e a UI sinaliza quando o dado está velho.

## References
- `docs/architecture/09-data-model-apis-contracts.md` §4.2 (Node), §10 (actual state e observações)
- `docs/architecture/06-infrastructure-provisioning.md` §5.2 (modelo de IP), §7.1 (estados do node)
- `docs/architecture/03-runtime-observability.md` §13.1 (Active, Pause, Drain)
- `docs/architecture/10-ui-use-cases.md` §16.3 (Nodes)

## Preconditions
`M01-09` done.

## Scope
- `Node`: id, clusterId, swarmNodeId (UNIQUE por cluster), hostname, role (`MANAGER`, `WORKER`), capabilities, availability (`ACTIVE`, `PAUSE`, `DRAIN`), status (`JOINING`, `READY`, `DEGRADED`, `DOWN`, `REMOVING`), publicAddress?, privateAddress?, advertiseAddress, labels, lastSeenAt.
- `NodeObservation` como actual state separado do desired state: status, availability, recursos, versão da Engine, `observedAt`.
- Leitura periódica via `ListNodes`/`InspectNode` do executor, com cadência configurável.
- Status do Node **derivado** da observação, com marcação de dado velho.
- Tela de listagem de nodes com role, availability, status, capacidade e `lastSeenAt`.

## Out of Scope
- Drain/activate/promote/demote/remove (`M08-05`, `M08-06`, `M08-07`).
- Enrollment de novos nodes (`M08-01`..`M08-03`).
- Labels de placement gerenciadas (`M02-03`).
- Métricas de host (`M09-02`).

## Domain Impact
**Entidades:** `Node`, `NodeObservation`.
**Separação obrigatória (doc 09 §10):** actual state **não** compete com desired state no mesmo conjunto de colunas. `NodeObservation` é derivado e reconstruível, e pode ter retenção menor.

## Application Layer
- **Commands:** `ObserveClusterNodes` (invocado por job periódico).
- **Queries:** `NodesForCluster` com status derivado.
- **Policies:** leitura exige membership no Team dono do Cluster.

## Async / Control Plane
Job periódico chama o executor, persiste `NodeObservation` e recalcula o status derivado. A cadência segue o doc 07 §23: curta durante manutenção, regular para readiness. O job é idempotente e não guarda estado em memória de processo.

## UI Impact
Lista de nodes na área de Cluster, com badge de `lastSeenAt`. Um node sem observação recente **não** é exibido como saudável (doc 10 §25, “Stale actual state”).

## Security Requirements
- A observação é somente leitura; nenhuma mutação de node existe em M01.
- Endereços privados e labels não são expostos a quem não tem membership no Team.
- Nenhuma credencial ou token de join aparece na observação ou na UI.

## Observability Requirements
- `cluster_id` e `node_id` nos logs.
- `observedAt`/`lastSeenAt` sempre presentes.
- Falha ao observar registra causa classificada e degrada o status do Cluster, sem apagar a última observação válida.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Falha ao consultar o Docker | Mantém a última observação com `observedAt` antigo; marca o dado como velho; degrada o Cluster. |
| Node desaparece do Swarm | Status vai para `DOWN`; o registro **não** é apagado automaticamente. |
| Node com role alterado fora da plataforma | A observação reflete a realidade; a divergência é registrada (a correção de drift é de `M02-06`). |
| Job de observação concorrente | Idempotente; duas execuções produzem o mesmo estado. |

## Acceptance Criteria
1. O Manager criado no bootstrap aparece como `Node` com `swarmNodeId`, role, availability e endereços.
2. `swarmNodeId` é único por cluster.
3. `NodeObservation` é uma entidade separada e não escreve em colunas de desired state.
4. O status exibido é derivado da observação, com `observedAt`.
5. Um node sem observação recente é marcado como dado velho e **não** é exibido como saudável.
6. Falha ao observar mantém a última observação válida e degrada o Cluster com causa classificada.
7. Um node que sai do Swarm vira `DOWN` sem ser apagado.
8. Duas execuções concorrentes do job de observação produzem o mesmo resultado.
9. Um usuário de outro Team não lê os nodes, provado por teste cross-team.
10. Nenhum token ou credencial aparece na observação, na resposta ou no log.

## Required Tests
- **unit**: derivação de status; detecção de dado velho.
- **integration**: observação persistida; falha de leitura preservando a última observação.
- **Docker/Swarm**: leitura real de nodes; node removido virando `DOWN`.
- **policy**: negativo cross-team.
- **security**: ausência de credencial na observação.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm.

## Definition of Done
Os 10 Acceptance Criteria satisfeitos, separação desired/actual respeitada, dado velho sinalizado, Critical/High = 0.
