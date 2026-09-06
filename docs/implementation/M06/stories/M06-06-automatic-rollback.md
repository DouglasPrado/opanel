# M06-06 — Automatic rollback on rollout failure

## Objective
Reverter automaticamente para a release anterior quando o rollout falha, conforme a política do Environment — priorizando disponibilidade sobre a nova versão.

## Outcome
Em produção, um deploy cuja verificação de health falha volta sozinho para a release anterior, com a reversão registrada e observável.

## References
- `docs/architecture/02-build-deploy.md` §12 (failureAction: rollback em Produção), §14 (rollback)
- `docs/architecture/07-internal-control-plane.md` §13 (task failed → policy/rollback)
- `docs/architecture/03-runtime-observability.md` §17 (deploy ruim → pause ou rollback conforme política)

## Preconditions
`M06-05` done.

## Scope
- Rollback automático disparado por `failureAction: rollback`, após a verificação de health falhar.
- Criação de um **novo** `Deployment` do tipo rollback apontando para a release anterior — o histórico não é reescrito.
- Restauração do artifact anterior e do spec correspondente; bindings de secret restaurados conforme a release alvo.
- Registro claro na timeline: `ROLLBACK_STARTED`, motivo e release de destino.
- Limite: se o rollback também falhar, o Service fica `FAILED` com causa — **não** entra em loop.

## Out of Scope
- Rollback manual (`M06-07`).
- Rollback de migrations de banco — **não existe** rollback genérico seguro (doc 02 §14.1, regra explícita).
- Rollback de dados externos.

## Application Layer
- **Reconciler:** `DeploymentReconciler` disparando a reversão.

## Security Requirements
- O rollback automático **não** reverte migrations de banco nem dados externos; a UI deixa isso explícito, porque acreditar o contrário causa perda de dados.
- A reversão é registrada em AuditLog com `actorType: SYSTEM`, o motivo e a release de destino.
- O rollback usa o artifact existente por digest; nenhum rebuild.
- Se a `SecretVersion` da release anterior estiver indisponível, o rollback é **bloqueado antes** de aplicar (doc 10 UC-018).

## Observability Requirements
Evento `ROLLBACK_STARTED` com origem e destino; motivo classificado. Métrica: rollbacks automáticos por período — uma taxa crescente é sinal de qualidade de release.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Rollback também falha | `FAILED` com causa; **não** entrar em loop de reversão. |
| Artifact anterior coletado | Bloqueado com aviso de retenção — e `M06-13` impede que isso aconteça. |
| `SecretVersion` anterior indisponível | Bloquear antes de aplicar. |
| Sem release anterior | Não há rollback possível; `FAILED` com causa explícita. |
| Migration aplicada pela versão nova | A UI avisa que o schema não é revertido; a decisão é do time da aplicação. |
| Rollback concorrente com novo deploy | Serializado; o mais novo pode superar. |

## Acceptance Criteria
1. `failureAction: rollback` dispara reversão automática após falha na verificação de health.
2. O rollback cria um **novo** Deployment; nenhum histórico é reescrito.
3. O rollback usa o artifact anterior por digest, **sem rebuild**.
4. `SecretVersion` da release anterior indisponível **bloqueia antes** de aplicar.
5. Sem release anterior, o resultado é `FAILED` com causa explícita.
6. Rollback que também falha resulta em `FAILED`; **nenhum loop**, provado por teste.
7. A UI avisa explicitamente que migrations e dados externos **não** são revertidos.
8. A reversão gera AuditLog com `actorType: SYSTEM`, motivo e destino.
9. O evento `ROLLBACK_STARTED` registra origem e destino.
10. Rollback concorrente com novo deploy é serializado.
11. Métrica de rollbacks automáticos está disponível.

## Required Tests
- **Docker/Swarm**: deploy com health falhando disparando reversão; rollback que também falha; ausência de loop.
- **integration**: bloqueio por `SecretVersion` indisponível; ausência de release anterior.
- **unit**: política de disparo; elegibilidade de destino.
- **security**: AuditLog de reversão; ausência de rebuild.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, reversão automática provada contra Swarm real, ausência de loop verificada, Critical/High = 0.
