# M01-04 — Authorization foundation: policies, deny-by-default and tenancy scoping

## Objective
Estabelecer o mecanismo de autorização que **toda** mutação e leitura de domínio do produto vai usar, com deny by default, escopo de tenancy carregado explicitamente e teste negativo cross-team obrigatório.

## Outcome
Existe uma camada de Policy avaliada server-side; nenhuma query de domínio busca recurso apenas por ID; um usuário de outro Team recebe negação em qualquer rota.

## References
- `docs/architecture/04-identity-teams-security.md` §6 (RBAC por escopo), §6.2 (matriz inicial)
- `docs/annexes/C-threat-model-security-hardening.md` §7.2 (RBAC e tenancy), §7.3 (anti-IDOR)
- `docs/AGENT_RULES.md` — “Policies”, “Security”
- `docs/annexes/I-engineering-playbook-quality-gates.md` §16.2 (AF-07)

## Preconditions
`M01-02` e `M01-03` done.

## Scope
- Camada de Policy: `authorize(actor, action, resource)` avaliando membership ativo → role → escopo → restrições de Environment → política.
- **Deny by default**: ausência de regra explícita resulta em negação. Uma ação sem Policy registrada é erro de programação detectado em teste, não permissão implícita.
- Escopos do doc 04 §6.1 modelados: `TEAM`, `CLUSTER`, `PROJECT`, `ENVIRONMENT`, `SERVICE`, `VAULT` (o último declarado, exercido em M03).
- Matriz inicial de permissões do doc 04 §6.2 para as ações que existem em M01.
- **Scoping obrigatório na query**: helper que exige o boundary de tenancy; buscar por ID sem escopo é reprovado por lint/fitness.
- Envelope de erro estável: `FORBIDDEN` e `NOT_FOUND` usados de forma a não revelar existência de recurso fora do Team.
- Harness de teste de autorização: gera automaticamente, para cada rota de mutação registrada, o caso negativo cross-team.

## Out of Scope
- Step-up authentication (`M03-04`).
- Permissões por Environment configuráveis pelo usuário (`M11-08`).
- Scopes OAuth do MCP (`M12-05`).
- Quotas (`M11-09`) — são guardrail operacional, não autorização.

## Application Layer
- **Policies:** `TeamPolicy`, `ProjectPolicy`, `EnvironmentPolicy`, `ServicePolicy`, `ClusterPolicy`.
- **Queries:** helper de escopo de tenancy usado por todas as Queries de domínio.
- **Commands:** todo Command chama a Policy antes de mutar; a Policy **não** executa a operação (Anexo I §4.1).

## API Impact
Respostas de negação usam o envelope do doc 09 §28. Recurso de outro Team responde de forma que **não** confirme sua existência.

## UI Impact
A UI esconde ou desabilita ação incompatível com o papel atual — mas isso é ergonomia, não controle. O backend nega de qualquer forma (doc 10 §1, “Least privilege”).

## Security Requirements
- **Anti-IDOR**: nenhuma query busca recurso só por ID confiando na rota. O boundary de tenancy entra na query ou é validada a cadeia de ownership.
- IDs opacos reduzem enumeração mas **não substituem** autorização.
- Toda nova mutação exige teste negativo cross-team — regra que vale para todos os Milestones seguintes.
- AF-07 passa a avaliar código real: mutação crítica sem caminho de autorização server-side reprova o build.
- Um membership suspenso perde acesso na requisição seguinte, sem depender de expirar a sessão.

## Observability Requirements
Negação registra `actor_id`, `action`, `resource_type`, `resource_id`, `team_id` e motivo classificado (sem membership / role insuficiente / fora do escopo). Vira AuditLog com `result: DENIED` em `M01-05`.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Ação sem Policy registrada | Negada por default **e** detectada por teste como erro de programação. |
| Acesso a recurso de outro Team | Negado sem revelar existência do recurso. |
| Membership suspenso durante a sessão | Próxima requisição é negada. |
| Query esquecendo o escopo de tenancy | Lint/fitness reprova antes do merge. |
| Role suficiente mas Environment restrito | Negado pelo escopo — o caminho fica pronto aqui, é exercido em `M11-08`. |

## Acceptance Criteria
1. `authorize(actor, action, resource)` existe e é avaliada server-side em toda mutação de domínio.
2. Uma ação sem Policy registrada é **negada** e um teste detecta a ausência como defeito.
3. Um usuário de outro Team é negado em **todas** as rotas de mutação existentes, comprovado por suíte gerada automaticamente.
4. Um usuário de outro Team não consegue distinguir “não existe” de “não posso ver”.
5. Toda Query de domínio usa o helper de escopo de tenancy; o lint/fitness reprova busca por ID sem escopo, provado por caso negativo.
6. A matriz de roles do doc 04 §6.2 está coberta por teste para as ações existentes em M01.
7. Membership suspenso perde acesso na requisição seguinte.
8. AF-07 avalia código real e reprova uma mutação crítica sem caminho de autorização, provado por caso negativo.
9. Negações são registradas com motivo classificado.
10. Existe um mecanismo que **falha o build** quando uma rota de mutação nova não tem teste negativo cross-team.

## Required Tests
- **unit**: avaliação de Policy por role, escopo e estado de membership.
- **policy/authorization**: matriz completa de roles; suíte cross-team gerada para todas as mutações.
- **integration**: membership suspenso perdendo acesso; scoping de query.
- **security**: indistinguibilidade entre `NOT_FOUND` e `FORBIDDEN` para recurso de outro Team; caso negativo de AF-07.

## Quality Gates
Local Quality Gate + `bin/fitness` (AF-07 significativa). A partir desta Story, **toda** Story com mutação declara `policy` em `Required Tests`.

## Definition of Done
Os 10 Acceptance Criteria satisfeitos, suíte cross-team verde e obrigatória, AF-07 avaliando código real, Critical/High = 0.
