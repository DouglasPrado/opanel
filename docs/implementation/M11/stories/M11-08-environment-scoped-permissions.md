# M11-08 — Environment-scoped permissions and the production boundary

## Objective
Permitir que o mesmo papel tenha alcance diferente por Environment — em especial, que produção seja um boundary adicional mesmo para quem tem papel alto.

## Outcome
Um DEVELOPER com deploy em homologação **não** herda acesso a secrets de produção; um ADMIN pode ter reveal negado em produção por policy.

## References
- `docs/architecture/04-identity-teams-security.md` §6 (RBAC por escopo), §6.1 (escopos), §11.1 (Production como boundary adicional)
- `docs/annexes/C-threat-model-security-hardening.md` §7.2, T04
- `docs/architecture/10-ui-use-cases.md` §8.1 (danger context em produção)

## Preconditions
`M11-02` done.

## Scope
- `EnvironmentPermission`: concessões e restrições por membership e Environment.
- Avaliação combinada do doc 04 §6: membership ativo → papel → escopo → restrições de Environment → step-up → policy.
- Produção com restrições adicionais configuráveis: deploy, reveal de secret, exec, deleção.
- Defaults seguros: `vault.reveal` em produção **negado por padrão** a DEVELOPER (doc 04 §6.2).
- Reflexo na UI: ações indisponíveis não aparecem como disponíveis — e o backend nega de qualquer forma.

## Out of Scope
- Papéis customizados definidos pelo usuário.
- ABAC completo.
- Scopes OAuth do MCP (`M12-05`), que **compõem** com estas permissões.

## Application Layer
- **Policies:** extensão do avaliador de `M01-04` com a dimensão de Environment.
- **Commands:** `GrantEnvironmentPermission`, `RevokeEnvironmentPermission`.

## Security Requirements
- **Produção é boundary adicional** (doc 04 §11.1, regra explícita): permissão em homologação **nunca** implica permissão em produção.
- `vault.reveal` em produção é negado por padrão a DEVELOPER.
- Restrições de Environment se aplicam **mesmo a ADMIN** quando a policy do Team assim definir.
- A avaliação é server-side; a UI é ergonomia.
- Conceder permissão em produção é ação sensível, auditada, e pode exigir step-up.
- Negações registram o motivo classificado (`M01-04`).
- Nenhuma permissão de Environment pode contornar o `safety limit` de quotas nem a exigência de step-up.

## Observability Requirements
Matriz efetiva por membro e Environment, consultável — “o que esta pessoa pode fazer em produção?” precisa ser respondível sem ler código.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| DEVELOPER com deploy em HML tentando revelar secret de PROD | Negado e auditado. |
| ADMIN com restrição de produção | Negado conforme a policy. |
| Permissão concedida em produção | Auditada; step-up quando a policy exigir. |
| Permissão revogada durante a sessão | Efeito na requisição seguinte. |
| Environment sem policy explícita | Herda o default seguro, não o permissivo. |
| Conflito entre concessão e restrição | A restrição prevalece. |

## Acceptance Criteria
1. Permissões por Environment existem e são avaliadas server-side.
2. **Permissão em homologação não implica permissão em produção**, provado por teste.
3. `vault.reveal` em produção é negado por padrão a DEVELOPER.
4. Restrições de Environment se aplicam **mesmo a ADMIN** quando a policy define.
5. Environment sem policy explícita herda o **default seguro**.
6. Conflito entre concessão e restrição resolve a favor da **restrição**.
7. Permissão revogada tem efeito na requisição seguinte.
8. Conceder permissão em produção é auditado e pode exigir step-up.
9. A UI não mostra ação indisponível como disponível, e o backend nega de qualquer forma.
10. Nenhuma permissão contorna `safety limit` de quota nem exigência de step-up.
11. A matriz efetiva por membro e Environment é consultável.
12. Negativos cross-team passam.

## Required Tests
- **policy**: matriz completa por papel × Environment; DEVELOPER em HML sem acesso a PROD; ADMIN restrito.
- **integration**: revogação com efeito imediato; conflito concessão × restrição.
- **security**: default seguro; impossibilidade de contornar step-up e safety limit.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, boundary de produção provado, default seguro verificado, Critical/High = 0.
