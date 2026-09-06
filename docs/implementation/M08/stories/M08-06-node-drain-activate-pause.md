# M08-06 — Node drain, activate and pause with impact analysis

## Objective
Permitir manutenção sem perda não planejada de workload, mostrando **antes** o que sai, o que fica bloqueado e por quê.

## Outcome
O operador pede drain; a plataforma lista tasks movíveis e bloqueadas com o motivo; após confirmar, acompanha a evacuação até zero tasks elegíveis.

## References
- `docs/architecture/03-runtime-observability.md` §13.1 (Active, Pause, Drain), §13.2 (fluxo de manutenção)
- `docs/architecture/06-infrastructure-provisioning.md` §7.2 (ações por estado), §8.1 (manutenção de worker)
- `docs/architecture/10-ui-use-cases.md` UC-006, §17 (cluster maintenance)
- `docs/annexes/E-operational-runbooks.md` RB-28

## Preconditions
`M08-04` done.

## Scope
- `drain`, `activate` e `pause` como operações duráveis via Executor.
- **Análise de impacto antes de executar**: tasks no node, quais são movíveis, quais estão bloqueadas e por qual constraint ou falta de capacidade.
- Acompanhamento da evacuação até zero tasks elegíveis ou até estado bloqueado.
- **“Safe for maintenance”** só é declarado quando não há tasks de workload gerenciado presas ao node (doc 03 §13.2).
- Para ingress: retirar do LB **antes** de drenar (`M08-11` fornece o mecanismo).
- Pause como bloqueio de novas tasks sem evacuar as existentes.

## Out of Scope
- Remoção (`M08-07`).
- Upgrade de SO/Docker (`M14-03` e RB-30 operacional).
- Autoscaling reagindo à capacidade (`M09-13`).

## Application Layer
- **Commands:** `DrainNode`, `ActivateNode`, `PauseNode`.
- **Queries:** `NodeImpactAnalysis`.
- **Policies:** exige ADMIN/`INSTANCE_OPERATOR`.

## Security Requirements
- **Não esconder constraints que impedem a evacuação** (doc 10 §17, regra explícita): a UI diz qual Service não sai e por quê.
- Drain de manager exige a mesma avaliação de quorum de `M08-05`.
- Ingress precisa sair do LB antes de drenar; drenar antes derruba conexões em curso.
- “Drain anyway” só existe como opção explícita, com aviso do que será perdido — e desabilitada quando o impacto é inaceitável.
- Operações de manutenção geram AuditLog com quem, quando e o impacto calculado.

## Observability Requirements
Progresso da evacuação: tasks restantes, quais e por quê. Evento `NODE_DRAINED`. Métrica de tempo de evacuação.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Task presa por constraint | Listada com a constraint que a prende; a UI explica o que precisa mudar. |
| Sem capacidade nos demais nodes | Listada como bloqueada por capacidade, distinta de bloqueio por constraint. |
| Manager crítico | Bloqueado se o quorum ficaria inseguro. |
| Ingress ainda no LB | Bloquear o drain até o target sair. |
| Evacuação não termina | Estado bloqueado com a lista; nunca declarar “safe for maintenance”. |
| Activate em node `DOWN` | Rejeitado com causa. |

## Acceptance Criteria
1. `drain`, `activate` e `pause` existem como operações duráveis.
2. A análise de impacto é exibida **antes** de executar, separando tasks movíveis de bloqueadas.
3. Tasks bloqueadas mostram o motivo específico: constraint ou capacidade.
4. Bloqueio por constraint é distinguível de bloqueio por capacidade.
5. “Safe for maintenance” só é declarado com zero tasks de workload gerenciado presas.
6. Drain de manager é bloqueado quando o quorum ficaria inseguro.
7. Drain de ingress é bloqueado enquanto o target estiver no LB.
8. “Drain anyway” é explícito, avisa o que será perdido e é desabilitado quando o impacto é inaceitável.
9. Pause bloqueia novas tasks sem evacuar as existentes.
10. `activate` em node `DOWN` é rejeitado com causa.
11. O progresso da evacuação é observável; o evento `NODE_DRAINED` é emitido.
12. As operações exigem permissão e geram AuditLog com o impacto calculado.

## Required Tests
- **unit**: análise de impacto; distinção constraint × capacidade.
- **Docker/Swarm**: drain real com evacuação; task presa por constraint; sem capacidade nos demais nodes; activate.
- **integration**: bloqueio por quorum; bloqueio por target no LB.
- **policy**: permissão; negativo cross-team.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, impacto exibido antes de executar, constraints não escondidas, Critical/High = 0.
