# M06-07 — Manual rollback to a previous release

## Objective
Permitir voltar deliberadamente para uma release anterior conhecida, em segundos e sem reconstruir nada.

## Outcome
O usuário escolhe uma release anterior saudável, revisa as diferenças que serão restauradas, confirma, e o Service volta — com um novo Deployment do tipo rollback.

## References
- `docs/architecture/02-build-deploy.md` §14 (rollback), §14.1 (o que deve voltar)
- `docs/architecture/10-ui-use-cases.md` UC-018
- `docs/annexes/B-nfr-slos.md` §6 (rollback p95 ≤ 90 s quando a imagem está no Registry)

## Preconditions
`M06-05` done.

## Scope
- Listagem de **rollback candidates**: deployments anteriores saudáveis e elegíveis.
- Tela mostrando release atual × alvo e as diferenças relevantes que serão restauradas (doc 10 UC-018).
- Restauração conforme o doc 02 §14.1: artifact volta ao digest anterior; service spec conforme a release escolhida; secret bindings podem ser restaurados **com confirmação**; domains permanecem.
- Novo Deployment do tipo rollback; histórico append-only.
- Meta de tempo: p95 ≤ 90 s quando a imagem está disponível.

## Out of Scope
- Rollback automático (`M06-06`).
- Rollback de banco e de dados externos — explicitamente fora (doc 02 §14.1).
- Restauração de configuração completa de Environment (`M10-12`, restore de snapshot).

## Application Layer
- **Commands:** `Rollback`.
- **Queries:** `RollbackCandidates`, `RollbackDiff`.
- **Policies:** `deployment.rollback`.

## UI Impact
Diálogo mostrando current × target, o que será restaurado, e um aviso claro sobre o que **não** volta: banco, dados externos e migrations.

## Security Requirements
- Rollback exige permissão; em produção pode exigir mais.
- A restauração de secret bindings exige **confirmação explícita**: voltar a uma versão anterior de credencial pode ser exatamente o que se quer, ou exatamente o que não se quer.
- Artifact necessário coletado indevidamente bloqueia com aviso de retenção (`M06-13` previne).
- AuditLog com origem, destino e o que foi restaurado.

## Observability Requirements
Timeline do rollback e tempo total medido. Métrica de rollbacks manuais por período.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Artifact coletado | Bloquear e informar o problema de retenção (doc 10 UC-018). |
| `SecretVersion` necessária indisponível | Bloquear antes do rollout. |
| Release alvo incompatível com o Environment atual | Bloquear com o motivo (ex.: porta ou binding que não existe mais). |
| Rollback durante outro rollout | Serializado ou supersede conforme política. |
| Usuário espera que o banco volte | A UI avisa explicitamente que não volta. |

## Acceptance Criteria
1. A lista de rollback candidates mostra deployments anteriores saudáveis e elegíveis.
2. A tela mostra current × target e o que será restaurado.
3. O rollback reaplica a release anterior **sem rebuild**, com o digest anterior.
4. Um novo Deployment do tipo rollback é criado; o histórico não é reescrito.
5. Restaurar secret bindings exige confirmação explícita.
6. A UI avisa que banco, dados externos e migrations **não** são revertidos.
7. Artifact coletado bloqueia com aviso de retenção.
8. `SecretVersion` indisponível bloqueia antes do rollout.
9. Release alvo incompatível é bloqueada com o motivo.
10. Rollback durante outro rollout é serializado ou supersede conforme política.
11. O tempo total é medido e fica dentro da meta quando a imagem está disponível.
12. Rollback exige permissão, gera AuditLog e passa no negativo cross-team.

## Required Tests
- **Docker/Swarm/E2E**: rollback real com tempo medido; rollback durante outro rollout.
- **integration**: artifact coletado; `SecretVersion` indisponível; release incompatível.
- **unit**: elegibilidade de candidates; cálculo do diff.
- **policy**: negativo cross-team; permissão de produção.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm + E2E.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, rollback real dentro da meta de tempo, ausência de rebuild provada, Critical/High = 0.
