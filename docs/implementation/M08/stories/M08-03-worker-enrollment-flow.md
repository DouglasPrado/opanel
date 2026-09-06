# M08-03 — End-to-end worker enrollment

## Objective
Fechar o fluxo de adicionar capacidade: da geração do token na UI até o node aparecer `READY` no painel, com labels aplicadas.

## Outcome
O operador clica em Add Node, executa o comando no host, e acompanha `REQUESTED → ENROLLING → JOINED → READY` sem tocar em Docker CLI.

## References
- `docs/architecture/06-infrastructure-provisioning.md` §6.1 (fluxo de enrollment), §7.1 (estados do node)
- `docs/architecture/10-ui-use-cases.md` UC-004
- `docs/annexes/E-operational-runbooks.md` RB-26 (adicionar worker)

## Preconditions
`M08-02` done.

## Scope
- Endpoint de enrollment autenticado pelo token, entregando o material de join.
- Consumo transacional do token e invalidação imediata.
- Observação do node novo pelo `NodeReconciler` e transição de estados.
- **Aplicação de labels somente após o node estar `READY`** (doc 04 §14.2).
- Tarefa canário: agendar uma Task simples no node novo e verificar comunicação pela overlay, antes de habilitar placement geral (RB-26).
- Registro completo: node ID, hostname, role, labels, endereços e status.

## Out of Scope
- Roles ingress/builder/manager (`M08-04`, `M08-05`).
- Readiness de rede detalhada (`M08-09`).
- Remoção (`M08-07`).

## Application Layer
- **Commands:** `EnrollNode`.
- **Reconciler:** `NodeReconciler` observando o node novo.

## Security Requirements
- O material de join é entregue **uma vez**, para o portador do token válido, sobre HTTPS.
- O token é invalidado no consumo, atomicamente (`M08-01`).
- Um node que entra no Swarm mas não completa a readiness fica `DEGRADED` com remediation — **não** é silenciosamente aceito (doc 10 UC-004).
- Labels e placement só depois de `READY`: aplicar antes agendaria workload em um node não verificado.
- O material de join não é registrado em log nem em AuditLog.
- O AuditLog registra o enrollment com actor, cluster, node e role.

## Observability Requirements
Transição de estados observável; a tarefa canário e seu resultado registrados. Métrica de enrollments por resultado.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Token expirado/revogado | Bootstrap aborta antes do join (`M08-02`). |
| Node entra mas não fica `READY` | `DEGRADED` com remediation; sem placement. |
| Canário não comunica pela overlay | Node não habilitado para workload; diagnóstico de rede (`M08-09`). |
| Enrollment concorrente com o mesmo token | Apenas um consegue. |
| Node com hostname duplicado | Aceito (a identidade é o `swarmNodeId`), mas sinalizado para evitar confusão operacional. |
| Perda de conectividade durante o enrollment | Estado permanece `ENROLLING` com timeout; nada fica ambíguo. |

## Acceptance Criteria
1. O operador gera o comando na UI, executa no host, e o node aparece `READY`.
2. O material de join é entregue uma única vez, sobre HTTPS, ao portador do token válido.
3. O token é consumido e invalidado atomicamente.
4. As transições `REQUESTED → ENROLLING → JOINED → READY` são observáveis.
5. Labels e placement são aplicados **somente após** `READY`.
6. Um node que entra mas não completa a readiness fica `DEGRADED` com remediation.
7. A tarefa canário valida agendamento e comunicação pela overlay antes de habilitar workload geral.
8. Canário que não comunica impede a habilitação e aponta o diagnóstico de rede.
9. Enrollment concorrente com o mesmo token só sucede uma vez.
10. O material de join não aparece em log nem AuditLog.
11. O enrollment gera AuditLog com actor, cluster, node e role.
12. Perda de conectividade durante o enrollment resulta em timeout com estado explícito.

## Required Tests
- **Docker/Swarm**: enrollment real de worker; canário agendado; node que não fica `READY`.
- **integration (concorrente)**: mesmo token usado por dois hosts.
- **security**: material de join fora dos sinks; labels só após `READY`.
- **E2E**: fluxo completo pela UI.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm + E2E.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos contra cluster real, canário validado antes do placement, Critical/High = 0.
