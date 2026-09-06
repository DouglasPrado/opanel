# M06-14 — Service lineage across Environments

## Objective
Estabelecer a correspondência entre o “mesmo” Service em Environments diferentes, para que a promoção saiba qual é o destino sem depender de nomes iguais.

## Outcome
`api` em homologação e `api` em produção compartilham um `serviceLineageId`; a promoção usa essa ligação para encontrar o destino automaticamente.

## References
- `docs/architecture/09-data-model-apis-contracts.md` §8.3 (`serviceLineageId` identifica o serviço lógico entre Environments)
- `docs/architecture/10-ui-use-cases.md` UC-019 (lineage ausente → pedir target manual ou bloquear), §10.2 (service lineage em General)

## Preconditions
`M06-01` done.

## Scope
- `ServiceLineage`: identidade lógica do serviço, compartilhada por Services correspondentes em Environments diferentes do mesmo Project.
- Atribuição automática ao criar um Environment clonando outro, e ao criar um Service com o mesmo papel.
- Edição manual do lineage em Service Settings, para corrigir correspondências.
- Uso pela promoção (`M06-09`) e, futuramente, pela comparação entre Environments.
- Validação: um lineage não pode ter dois Services no **mesmo** Environment.

## Out of Scope
- Comparação completa entre Environments (doc 10 §8.3; parcialmente atendida pelo diff de promoção).
- Lineage entre Projects diferentes — não faz sentido no modelo.
- Clonagem de Environment (`M10-12` traz restore de snapshot; clonagem direta é backlog).

## Domain Impact
**Entidade:** `ServiceLineage`.
**Invariante:** no máximo um Service por lineage por Environment.

## Application Layer
- **Commands:** `AssignServiceLineage`, `DetachServiceLineage`.
- **Queries:** `ServicesInLineage`.

## Security Requirements
- Um lineage é **interno ao Project**, portanto ao Team: não é possível ligar Services de Teams diferentes, e a tentativa é negada sem revelar existência.
- Alterar o lineage muda para onde uma promoção aponta — é ação sensível e gera AuditLog.
- Ambiguidade **nunca** é resolvida por heurística silenciosa: sem lineage claro, a promoção pede o destino explicitamente.

## Observability Requirements
A UI mostra o lineage no Service Settings e quais Services o compartilham, em quais Environments.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Dois Services do mesmo Environment no mesmo lineage | Rejeitado por validação. |
| Lineage ausente na promoção | Pedir target manual ou bloquear; **nunca** adivinhar. |
| Services de Teams diferentes | Negado sem revelar existência. |
| Lineage alterado com promoções históricas | As `Promotion` anteriores permanecem íntegras; o histórico não muda. |
| Service deletado | O lineage permanece com os demais; não é apagado. |

## Acceptance Criteria
1. `ServiceLineage` existe e é compartilhado por Services correspondentes de Environments diferentes do mesmo Project.
2. No máximo um Service por lineage por Environment, garantido por constraint.
3. A atribuição é automática quando o contexto é inequívoco e editável manualmente.
4. A promoção usa o lineage para encontrar o destino.
5. Sem lineage, a promoção pede o destino explicitamente ou bloqueia; **nunca** adivinha.
6. Ligar Services de Teams diferentes é negado sem revelar existência.
7. Alterar o lineage gera AuditLog.
8. Promoções históricas permanecem íntegras após alteração do lineage.
9. Deletar um Service não apaga o lineage dos demais.
10. A UI mostra o lineage e quem o compartilha; negativo cross-team passa.

## Required Tests
- **unit**: constraint de unicidade por Environment; atribuição automática.
- **integration**: promoção usando o lineage; ausência de lineage; alteração preservando histórico.
- **policy**: negativo cross-team.

## Quality Gates
Local Quality Gate.

## Definition of Done
Os 10 Acceptance Criteria satisfeitos, ausência de heurística silenciosa provada, Critical/High = 0.
