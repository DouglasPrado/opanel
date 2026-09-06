# M02-09 — Deletion lifecycle with runtime cleanup and tombstones

## Objective
Encerrar Service, Environment e Project de forma que o runtime seja realmente limpo, o histórico seja preservado e nenhum recurso órfão permaneça no Swarm.

## Outcome
Deletar um Service remove o Swarm Service e a Task; deletar um Environment remove também a overlay network; o registro entra em `DELETING → DELETED` com tombstone e auditoria preservada.

## References
- `docs/architecture/09-data-model-apis-contracts.md` §25 (exclusão, retenção e GC), §17 (state machines)
- `docs/architecture/07-internal-control-plane.md` §11.4 (classe `DELETE`)
- `docs/architecture/10-ui-use-cases.md` §26 (ações destrutivas e confirmações)
- `docs/annexes/E-operational-runbooks.md` RB-17 (nunca usar prune destrutivo genérico)

## Preconditions
`M02-08` done.

## Scope
- Lifecycle `ACTIVE → DELETING → (reconcile do runtime) → DELETED/tombstone`.
- Classe de diff `DELETE` no Service Reconciler e no Network Reconciler, removendo **somente** recursos com ownership da plataforma.
- Ordem de dependência: Service antes de network; Environment antes de Project.
- Bloqueio quando há dependências ativas, com explicação do que precisa acontecer antes.
- Tombstone: o registro some da UI operacional mas o histórico e a auditoria permanecem durante a retenção.
- Confirmação proporcional ao risco: digitar o nome para Environment e para recursos de `PRODUCTION`.

## Out of Scope
- GC de Artifacts e Releases (`M06-13`).
- Retenção/purga definitiva após a janela (M13/M14 definem a política operacional).
- Deleção de Team e de User (`M11`, com regras de compliance).
- Deleção de Cluster (`M08`, operação perigosa com gate humano).

## Domain Impact
**Transições:** `DELETING` é um estado observável, não um `DELETE` imediato. O recurso continua visível com status enquanto o runtime converge.
**Invariante:** nenhum recurso sem ownership da plataforma é removido (`M01-16`).

## Application Layer
- **Commands:** `DeleteService`, `DeleteEnvironment`, `DeleteProject`.
- **Policies:** deleção exige ADMIN; em `PRODUCTION`, política adicional pode exigir mais (caminho pronto para `M11-08`).

## Async / Control Plane
Deleção é assíncrona e durável como qualquer mutação: Operation → reconcile → confirmação. O registro só vira tombstone quando o runtime confirma a remoção. Delete de recurso já ausente é tratado como convergido (doc 07 §6.2).

## UI Impact
Danger Zone com impacto listado antes da confirmação: Services afetados, domínios (a partir de M04), snapshots recomendados (a partir de M10).

## Security Requirements
- Confirmação proporcional ao risco; `PRODUCTION` exige digitar o nome (doc 10 §26).
- **Nunca** usar comandos destrutivos genéricos do Docker (`prune -a --volumes`) — RB-17 é explícito. A remoção é por recurso identificado por ownership.
- Auditoria preservada após a deleção; o tombstone não apaga a trilha.
- Deleção exige permissão e gera AuditLog com o inventário do que foi removido.

## Observability Requirements
- Operation de deleção com timeline por recurso removido.
- Ao final, uma verificação explícita de que não restou recurso órfão com ownership daquele Environment/Service.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Recurso já removido no Swarm | Tratado como convergido, não erro. |
| Remoção falha parcialmente | Estado permanece `DELETING` com o que falta; nunca marcar `DELETED` sem confirmação. |
| Dependência ativa | Bloqueado com a lista do que precisa ser tratado antes. |
| Recurso sem ownership com nome parecido | **Não** removido; o predicado de ownership decide, não o nome. |
| Deleção concorrente com outra operação | Serializada pelo lease. |
| Control Plane reinicia no meio | A intenção de deleção sobrevive; o sweep retoma. |

## Acceptance Criteria
1. Deletar um Service remove o Swarm Service correspondente e o registro vira tombstone.
2. Deletar um Environment remove seus Services e a overlay network, na ordem correta de dependência.
3. Nenhum recurso órfão com ownership da plataforma permanece, verificado explicitamente ao final.
4. Recurso **sem** ownership da plataforma nunca é removido, mesmo com nome semelhante.
5. Remoção parcial mantém `DELETING` com o que falta; nunca `DELETED` prematuro.
6. Delete de recurso já ausente é tratado como convergido.
7. Dependência ativa bloqueia com a lista do que precisa acontecer antes.
8. Auditoria e histórico permanecem após o tombstone.
9. `PRODUCTION` exige digitar o nome para confirmar.
10. Nenhum comando destrutivo genérico do Docker é usado; a remoção é por recurso identificado.
11. Reiniciar o Control Plane no meio não perde a intenção de deleção.
12. Deleção exige permissão, gera AuditLog com o inventário removido, e passa no negativo cross-team.

## Required Tests
- **unit**: ordem de dependência; transições; tratamento de recurso ausente.
- **integration**: tombstone preservando auditoria; restart do Control Plane no meio; bloqueio por dependência.
- **Docker/Swarm**: deleção real de Service e network; verificação de ausência de órfãos; recurso de terceiro com nome parecido intocado.
- **policy**: negativo cross-team; role sem permissão.
- **security**: ausência de comando destrutivo genérico no código, verificada por teste estático.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm. **Story crítica: exige plan mode** — operação destrutiva.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, ausência de órfãos verificada, recurso de terceiro comprovadamente intocado, Critical/High = 0.
