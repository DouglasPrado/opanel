# M10-14 — Fast Swarm Restore

## Objective
Oferecer o caminho de recuperação rápida quando o cluster existente pode ser preservado, sem transformá-lo em uma alternativa banal ao Clean Rebuild.

## Outcome
Com um backup consistente de manager e a unlock key quando aplicável, o operador restaura o estado do Swarm em um manager compatível e valida antes de readmitir workers.

## References
- `docs/architecture/05-backup-restore-dr.md` §7.1 (dois modos), §7.2 (Fast Swarm Restore)
- `docs/annexes/E-operational-runbooks.md` RB-25, RB-06
- `docs/annexes/B-nfr-slos.md` §11 (fast restore ≤ 30 min; clean rebuild ≤ 60 min)

## Preconditions
`M10-08` e `M10-11` done.

## Scope
- Procedimento do doc 05 §7.2: backup do manager → manager novo/recuperado → restaurar o estado → iniciar Docker → validar nodes/services/secrets → readmitir/substituir workers.
- Pré-condições verificadas **antes**: versão de Docker compatível, unlock key disponível quando autolock estiver habilitado, backup consistente, e **nenhum cluster concorrente usando a mesma identidade**.
- Execução **isolada da rede de produção** inicialmente, conforme RB-25.
- Reconcile com o Platform DB após o retorno do controle, sem conflitos.
- Backup imediato do novo estado após a recuperação.
- Orientação explícita sobre quando escolher Fast Restore × Clean Rebuild.

## Out of Scope
- Recuperação de quorum sem backup (RB-06, operacional).
- `force-new-cluster` automatizado — **jamais**; é operação de desastre com decisão humana.
- Clean Rebuild (`M10-13`).

## Application Layer
- **Commands:** `PlanFastSwarmRestore`, `ExecuteFastSwarmRestore`.
- **Policies:** exige `INSTANCE_ADMIN` + step-up.

## Security Requirements
- **Nenhum cluster concorrente pode usar a mesma identidade/estado** (RB-25): dois clusters com o mesmo estado é corrupção lógica.
- O procedimento roda **isolado da rede de produção** inicialmente.
- A unlock key **não** vem do backup; sem ela, com autolock habilitado, o restore não é possível — e isso é dito antes de começar.
- O backup original é **preservado**; nunca sobrescrito pelo procedimento.
- `force-new-cluster` permanece fora de qualquer automação: ele consolida estado antigo e pode causar perda lógica se usado no manager errado (RB-06).
- A operação exige `INSTANCE_ADMIN` + step-up e é auditada.

## Observability Requirements
Progresso por etapa; RTO medido; validação de nodes, services e secrets antes de readmitir workers.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Versão de Docker incompatível | Bloquear antes de iniciar. |
| Unlock key indisponível com autolock | Bloquear e informar que o restore não é possível. |
| Backup inconsistente | Bloquear na validação. |
| Cluster concorrente com a mesma identidade | Bloquear; é o cenário que corrompe. |
| Validação pós-restore falha | Não readmitir workers; escalar para Clean Rebuild. |
| Dúvida entre Fast Restore e Clean Rebuild | Escalar para decisão humana (RB-25). |

## Acceptance Criteria
1. O procedimento segue as etapas do doc 05 §7.2.
2. Versão de Docker incompatível bloqueia **antes** de iniciar.
3. Unlock key indisponível com autolock habilitado bloqueia, com a explicação.
4. A unlock key **não** vem do backup.
5. Backup inconsistente é bloqueado na validação.
6. Um cluster concorrente usando a mesma identidade **bloqueia** a operação.
7. A execução é isolada da rede de produção inicialmente.
8. O backup original é preservado e nunca sobrescrito.
9. A validação de nodes, services e secrets acontece **antes** de readmitir workers.
10. Validação falha escala para Clean Rebuild em vez de insistir.
11. Um backup do novo estado é realizado imediatamente após a recuperação.
12. `force-new-cluster` **não** é executado por nenhuma automação, verificado por teste estático.
13. A operação exige `INSTANCE_ADMIN` + step-up e é auditada; o RTO é medido.

## Required Tests
- **DR Lab**: restore real em manager isolado; validação antes de readmitir.
- **security**: ausência de `force-new-cluster` no código; unlock key fora do backup; bloqueio por cluster concorrente.
- **integration**: versão incompatível; backup inconsistente; escalonamento para Clean Rebuild.
- **policy**: `INSTANCE_ADMIN` + step-up.

## Quality Gates
Local Quality Gate + DR Lab + `bin/security`. **Story crítica: exige plan mode.**

## Definition of Done
Os 13 Acceptance Criteria satisfeitos, bloqueios prévios provados, ausência de `force-new-cluster` automatizado verificada, Critical/High = 0.
