# M06-04 — Rolling update policy

## Objective
Aplicar a nova Release ao Swarm com uma política de rollout que priorize disponibilidade e seja explícita sobre os trade-offs.

## Outcome
O Service é atualizado com `order`, `parallelism`, `delay`, `monitor`, `failureAction` e `maxFailureRatio` configuráveis, com `start-first` como default para workloads compatíveis.

## References
- `docs/architecture/02-build-deploy.md` §12 (rolling update), §12.1 (capacidade durante start-first)
- `docs/architecture/09-data-model-apis-contracts.md` §8.4 (strategy)
- `docs/annexes/B-nfr-slos.md` §6 (rolling update não reduz abaixo do mínimo saudável)

## Preconditions
`M06-03` done.

## Scope
- `UpdateConfig` do Swarm derivado da política do Service: `order` (`start-first` default), `parallelism`, `delay`, `monitor`, `failureAction`, `maxFailureRatio`.
- `failureAction: rollback` como default em `PRODUCTION`; `pause` disponível como opção avançada.
- **Detecção de headroom**: alertar quando o cluster não tem capacidade para `start-first` e sugerir `stop-first` ou paralelismo menor (doc 02 §12.1).
- Aplicação via `UpdateServiceSpec` do Executor, com re-inspeção.
- Presets de UI, sem esconder os valores técnicos.

## Out of Scope
- Verificação de health como gate (`M06-05`).
- Rollback automático (`M06-06`).
- Canary e blue-green (backlog).

## Application Layer
- **Commands:** `UpdateRolloutPolicy`.
- **Reconciler:** `DeploymentReconciler` aplicando a política.

## Async / Control Plane
A política é aplicada como parte da spec do Service. O reconciler **re-inspeciona** após aplicar; nunca assume que a chamada anterior determinou o estado final (doc 07 §11.3).

## Security Requirements
- `failureAction: rollback` em produção é uma escolha de **disponibilidade**: sem ela, um deploy ruim permanece servindo tráfego.
- A política não pode ser configurada de forma a deixar o Service sem réplica saudável quando há alternativa — a UI avisa quando a combinação escolhida permite isso.
- Alterar a política gera AuditLog.

## Observability Requirements
- Progresso do rollout: tasks atualizadas × total, com o lote atual.
- Aviso explícito quando o cluster não tem headroom para `start-first`.
- Métrica: duração do rollout separada da espera por health.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Sem headroom para `start-first` | Avisar antes; sugerir `stop-first` ou paralelismo menor; **não** falhar silenciosamente com Tasks `Pending`. |
| `parallelism` alto demais | Aviso de que pode reduzir a capacidade abaixo do mínimo saudável. |
| `monitor` curto demais | Aviso: uma janela curta declara estável cedo demais. |
| Update rejeitado pelo Swarm | Erro classificado; a release anterior continua. |
| Conflito de versão do Service | `CONFLICT`; reobservar e recalcular. |
| Política inválida | Rejeitada na validação. |

## Acceptance Criteria
1. A política de rollout é configurável nos seis parâmetros e aplicada ao Swarm Service.
2. `start-first` é o default para workloads compatíveis.
3. `failureAction: rollback` é o default em `PRODUCTION`.
4. Falta de headroom para `start-first` é detectada e avisada **antes** do rollout.
5. Combinações que permitem ficar sem réplica saudável geram aviso explícito.
6. `monitor` curto demais gera aviso.
7. Update rejeitado pelo Swarm produz erro classificado e a release anterior continua servindo.
8. Conflito de versão resulta em `CONFLICT`, reobservação e recálculo.
9. O progresso do rollout é observável (tasks atualizadas × total).
10. Política inválida é rejeitada na validação.
11. Alterar a política gera AuditLog; negativo cross-team passa.

## Required Tests
- **unit**: derivação do `UpdateConfig`; validação; detecção de headroom.
- **Docker/Swarm**: rolling update com múltiplas réplicas; `start-first` sem headroom; conflito de versão.
- **integration**: avisos emitidos nas combinações de risco.
- **policy**: negativo cross-team.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, rollout real com múltiplas réplicas verificado, avisos de risco emitidos, Critical/High = 0.
