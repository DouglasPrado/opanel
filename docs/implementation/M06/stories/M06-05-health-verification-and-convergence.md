# M06-05 — Health verification as the condition of success

## Objective
Fazer o deployment concluir **somente** quando o runtime e a política de health confirmarem — eliminando o falso sucesso de “o Docker aceitou o update”.

## Outcome
Um deployment cujas Tasks sobem mas não ficam saudáveis termina em `FAILED`/`ROLLED_BACK` com causa, nunca em `HEALTHY`.

## References
- `docs/architecture/07-internal-control-plane.md` §13 (health verification), §17.1 (HEALTHY exige applied = desired + health)
- `docs/architecture/02-build-deploy.md` §13 (health checks e elegibilidade)
- `docs/annexes/B-nfr-slos.md` §6 (falha de rollout chega a FAILED/BLOCKED com causa observável)
- `docs/architecture/10-ui-use-cases.md` §1 (“Sem falso sucesso”)

## Preconditions
`M06-04` done.

## Scope
- Etapa `VERIFYING` observando: tasks atualizadas, running, healthy, e `appliedRevision` alcançando `desiredRevision`.
- Timeout de verificação configurável, com desfecho explícito ao expirar.
- Health agregado de `M02-04` como fonte; `Running ≠ Healthy` continua valendo.
- Separação de medição: tempo de infraestrutura × tempo esperando a aplicação (doc B §6).
- Watchdog: deployment sem progresso além do limiar vira `STALLED` e dispara recovery/alerta.

## Out of Scope
- Rollback automático (`M06-06`) — esta Story decide **que falhou**; aquela decide **o que fazer**.
- Probe externa ao cluster (`M09`).

## Application Layer
- **Reconciler:** `DeploymentReconciler` na etapa de verificação.

## Async / Control Plane
Esta é a Story que materializa a regra do Anexo A §5 M6: “Falha no rollout não marca sucesso apenas porque o Docker aceitou o update.” A confirmação vem de **reler o estado**, não do retorno da chamada.

## Security Requirements
- Um falso `HEALTHY` é um risco operacional real: leva o operador a acreditar que a correção foi aplicada. A verificação é obrigatória e não pode ser desligada por configuração.
- `NONE` como health policy (permitido em `M02-04` com aviso) reduz a verificação a “tasks running”; a UI deixa explícito que o rollout perdeu a checagem — e isso é registrado no Deployment.

## Observability Requirements
- Timeline com `TASK_HEALTHY` e `DEPLOYMENT_HEALTHY`.
- Duração separada: infraestrutura × espera por health.
- Meta do Anexo B §6: deploy de artefato existente p95 ≤ 2 min até `HEALTHY` para apps com health check ≤ 30 s.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Docker aceita, tasks não sobem | `FAILED`/`ROLLED_BACK` com causa; **nunca** `HEALTHY`. Teste obrigatório. |
| Tasks sobem, health falha | Idem. |
| Timeout de verificação | Desfecho explícito conforme política; nunca ficar em `VERIFYING` para sempre. |
| Health `NONE` | Verificação reduzida, com aviso registrado no Deployment. |
| Réplicas parcialmente saudáveis | Estado degradado explícito (`n/m`), com decisão conforme `maxFailureRatio`. |
| Observação velha durante a verificação | Não conclui com dado velho; aguarda observação recente ou reporta indisponibilidade. |

## Acceptance Criteria
1. Um deployment só vira `HEALTHY` quando `appliedRevision` alcança `desiredRevision` **e** a política de health é satisfeita.
2. Docker aceitar o update **não** marca sucesso, provado por teste que impede as tasks de ficarem saudáveis.
3. Timeout de verificação produz desfecho explícito; nunca `VERIFYING` indefinido.
4. Watchdog marca `STALLED` um deployment sem progresso além do limiar.
5. Health `NONE` reduz a verificação **com aviso registrado** no Deployment.
6. Réplicas parcialmente saudáveis produzem estado degradado explícito com `n/m`.
7. A verificação não conclui com observação velha.
8. A duração é medida separando infraestrutura de espera por health.
9. A verificação **não** pode ser desabilitada por configuração.
10. Eventos `TASK_HEALTHY` e `DEPLOYMENT_HEALTHY` são emitidos.

## Required Tests
- **Docker/Swarm**: tasks impedidas de subir; health falhando durante rollout; réplicas parcialmente saudáveis; timeout.
- **unit**: cálculo da condição de sucesso; detecção de observação velha.
- **integration**: watchdog marcando `STALLED`; medição separada de duração.
- **security**: impossibilidade de desabilitar a verificação.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm. **Story crítica: é o gate de veracidade do Milestone.**

## Definition of Done
Os 10 Acceptance Criteria satisfeitos, ausência de falso sucesso provada em três cenários distintos, Critical/High = 0.
