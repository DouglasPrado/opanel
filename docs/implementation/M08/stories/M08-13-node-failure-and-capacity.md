# M08-13 — Node failure handling and capacity accounting

## Objective
Reagir corretamente à perda de um node e distinguir, de forma inequívoca, falta de capacidade de falha da aplicação.

## Outcome
Um worker perdido tem suas Tasks reagendadas; a plataforma mostra a capacidade restante e, quando não há onde agendar, diz `Capacity Exhausted` em vez de deixar o usuário procurar um bug inexistente.

## References
- `docs/architecture/03-runtime-observability.md` §17 (cenários de falha), §5.3 (proteção contra saturação)
- `docs/architecture/01-foundation.md` §4.4 (falha de node)
- `docs/architecture/06-infrastructure-provisioning.md` §21 (cenários de falha)
- `docs/annexes/E-operational-runbooks.md` RB-04

## Preconditions
`M08-06` done.

## Scope
- Detecção de node `DOWN` e observação do reagendamento feito pelo Swarm.
- Contabilidade de capacidade: CPU e memória totais, reservados, utilizados e **headroom**.
- Cálculo de headroom **após a perda de um node** — a pergunta que importa para HA.
- `Capacity Exhausted` como estado explícito, distinto de falha da aplicação.
- Evento `NODE_DOWN` e impacto na readiness (`M08-12`).
- Regra: a plataforma **não** tenta substituir o scheduler do Swarm; ela observa, contabiliza e explica.

## Out of Scope
- Autoscaling de réplicas (`M09-12`) e de nodes (backlog).
- Métricas históricas de capacidade (`M09-04`).
- Substituição automática de node.

## Application Layer
- **Queries:** `ClusterCapacity`, `HeadroomAfterNodeLoss`.
- **Reconciler:** `NodeReconciler` observando; `ClusterReconciler` recalculando readiness.

## Security Requirements
- Capacidade e topologia são informação de infraestrutura: a view respeita tenancy e o detalhe exige permissão adequada.
- Não expor endereços internos nem inventário completo a quem só tem acesso a Services.
- A distinção entre falta de capacidade e falha da aplicação é um requisito de **diagnóstico**, e diagnóstico errado leva a ação errada em incidente.

## Observability Requirements
- Capacidade total, reservada, utilizada e headroom; e o headroom projetado após perda de um node.
- Evento `NODE_DOWN` com impacto: quantas Tasks foram afetadas e quantas foram reagendadas.
- Tasks `Pending` com o motivo: constraint, capacidade ou imagem.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Worker cai | Swarm reagenda; a plataforma mede a perda de capacidade e registra. |
| Sem capacidade para reagendar | Tasks `Pending`; `Capacity Exhausted` explícito, distinto de falha da aplicação. |
| Node volta | Capacidade recontabilizada; o Swarm redistribui conforme sua política. |
| Node intermitente | Marcar para manutenção; evitar oscilar o estado a cada observação. |
| Perda que quebra `Compute HA` | Readiness degrada e o evento é emitido. |
| Capacidade calculada com dado velho | Marcada como estimativa com a idade da observação. |

## Acceptance Criteria
1. Node `DOWN` é detectado e o reagendamento das Tasks é observado.
2. A capacidade total, reservada, utilizada e o headroom são calculados e expostos.
3. O headroom **após a perda de um node** é calculado e exibido — é o número que define `Compute HA`.
4. Falta de capacidade produz `Capacity Exhausted` explícito, distinto de falha da aplicação, provado por teste.
5. Tasks `Pending` mostram o motivo: constraint, capacidade ou imagem.
6. Node que volta tem a capacidade recontabilizada.
7. Node intermitente não faz o estado oscilar a cada observação.
8. Perda que quebra `Compute HA` degrada a readiness e emite evento.
9. Capacidade calculada com observação velha é marcada como estimativa, com a idade.
10. A plataforma **não** implementa um scheduler concorrente; ela observa e explica.
11. A view respeita tenancy; detalhe de infraestrutura (host, capacidade por nó, labels) exige `INSTANCE_ADMIN` ou `OPERATOR`, com negativo cross-team verde.

## Required Tests
- **Docker/Swarm**: kill de worker sob tráfego com reagendamento observado; sem capacidade para reagendar; node voltando.
- **unit**: cálculo de headroom; headroom após perda de node; anti-oscilação.
- **integration**: `Capacity Exhausted` distinto de falha da aplicação; readiness degradando.
- **policy**: tenancy da view de capacidade.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, kill de worker sob tráfego provado, distinção capacidade × aplicação verificada, Critical/High = 0.
