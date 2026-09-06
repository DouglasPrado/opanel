# M12-05 — Permission presets and effective authorization

## Objective
Tornar a autorização do agente a **interseção** de tudo que a restringe, e oferecer presets que não escondam o que está sendo concedido.

## Outcome
`ALLOW` só acontece quando scope, membership, RBAC, boundary, política de Environment, entitlement, approval e estado do recurso concordam.

## References
- `docs/annexes/F-mcp-platform-agents.md` §5.3 (presets), §5.5 (autorização efetiva), §22 (AC-MCP-03)
- `docs/architecture/04-identity-teams-security.md` §6 (RBAC por escopo)

## Preconditions
`M12-04` done.

## Scope
- Presets do Anexo F §5.3: Observer, Developer, Deployer, Operator, Admin, Custom — com produção read-only por padrão nos três primeiros.
- Cálculo de autorização efetiva do Anexo F §5.5:
  `ALLOW = token_scope AND team_membership AND RBAC_role AND resource_boundary AND environment_policy AND feature_entitlement AND approval_policy AND current_resource_state`.
- Explicação do que **falta** quando a chamada é negada, sem vazar informação de fora do boundary.
- Tools proibidas por configuração podem ser omitidas do catálogo; indisponibilidade temporária retorna erro (`M12-03`).

## Out of Scope
- Tools concretas.
- Approvals em si (`M12-09`) — aqui apenas a dimensão no cálculo.

## Application Layer
- **Policies:** reuso do avaliador de `M01-04` e `M11-08`, com as dimensões adicionais de scope e boundary.

## Security Requirements
- **A permissão efetiva é a interseção**, nunca a união. Um preset generoso **não** concede o que o RBAC nega.
- Uma tool pode aparecer no catálogo e ainda ser negada para um recurso específico (Anexo F §5.5).
- A explicação da negação diz **qual requisito falta**, sem revelar informação sobre recursos fora do Team.
- Presets comuns **nunca** incluem `secret:reveal`, `owner:transfer`, `instance:admin` ou `runtime.exec`.
- Produção é read-only por padrão em Observer, Developer e Deployer, salvo policy explícita.
- O cálculo é feito no Gateway, com o contexto carregado; nada é inferido do cliente.

## Observability Requirements
`mcp_tool_denied_total` por motivo: scope, RBAC, boundary, environment, entitlement, approval, estado. Isso permite distinguir configuração errada de tentativa de abuso.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Scope suficiente, RBAC insuficiente | Negado; explica que falta permissão de produto. |
| RBAC suficiente, scope insuficiente | `INSUFFICIENT_SCOPE`; orienta novo consentimento. |
| Recurso fora do boundary | `NOT_FOUND` de forma que não confirme existência. |
| Produção com `prodMode` read-only | Mutação negada; leitura permitida. |
| Entitlement ausente | Negado com a razão. |
| Estado do recurso impede | `CONFLICT`/`DRIFT_BLOCKED` conforme o caso. |

## Acceptance Criteria
1. Os seis presets do Anexo F §5.3 existem, com produção read-only por padrão em Observer, Developer e Deployer.
2. A autorização efetiva é a **interseção** das oito dimensões do Anexo F §5.5.
3. Um preset generoso **não** concede o que o RBAC nega, provado por teste.
4. Uma tool no catálogo pode ser negada para um recurso específico.
5. A negação explica **qual requisito falta**, sem vazar informação de fora do boundary.
6. Recurso fora do boundary responde de forma que **não** confirme sua existência.
7. `INSUFFICIENT_SCOPE` orienta novo consentimento; `FORBIDDEN` explica o limite sem repetir.
8. Presets comuns **nunca** incluem `secret:reveal`, `owner:transfer`, `instance:admin` ou `runtime.exec`.
9. `prodMode` read-only nega mutação e permite leitura.
10. Entitlement ausente nega com a razão.
11. Estado do recurso que impede a ação retorna o erro estruturado correspondente.
12. `mcp_tool_denied_total` registra o motivo da negação.

## Required Tests
- **policy**: matriz completa scopes × RBAC × boundary × environment policy.
- **security**: preset não ampliando RBAC; enumeração cross-team; capabilities sensíveis fora dos presets.
- **contract**: taxonomia de erros por motivo de negação.

## Quality Gates
Local Quality Gate + `bin/security`. **Story crítica: exige plan mode.**

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, interseção provada por matriz, ausência de enumeração verificada, Critical/High = 0.
