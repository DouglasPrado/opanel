# M12-06 — Read-only tools (rollout phase F1)

## Objective
Entregar a primeira fase do MCP: descoberta e leitura, para que o agente encontre contexto sem que o usuário copie IDs — e sem qualquer capacidade de mutação.

## Outcome
`platform.whoami`, `teams/projects/environments/services`, `operations` e leituras básicas funcionam, com zero vazamento cross-team.

## References
- `docs/annexes/F-mcp-platform-agents.md` §7.2 (contexto), §7.3 (services, parte de leitura), §7.8 (operations), §21 (fase F1), §15 (MCP-01, MCP-02)
- `docs/annexes/D-test-strategy.md` §17 (adversarial: enumeração cross-team)

## Preconditions
`M12-05` done.

## Scope
- `platform.whoami`: identidade, memberships, scopes e boundaries efetivos.
- `platform.capabilities`: capabilities da plataforma e features habilitadas.
- `teams.list/get`, `projects.list/get`, `environments.list/get`, `services.list/get`.
- `operations.list/get/wait`: acompanhamento de trabalho em andamento.
- `structuredContent` estável com IDs e estados canônicos.
- Paginação e limites em todas as listagens.

## Out of Scope
- Qualquer mutação (`M12-08` em diante).
- Observabilidade (`M12-07`).
- Resources e Prompts (`M12-13`).

## Application Layer
Reuso integral das Queries existentes. **Nenhuma query nova de domínio** é criada para o MCP.

## Security Requirements
- **Gate da fase F1** (Anexo F §21): zero vazamento cross-team; OAuth e RBAC completos antes de liberar.
- Toda leitura respeita boundary e tenancy; um ID de outro Team responde como inexistente.
- `platform.whoami` mostra o que o agente **efetivamente** pode, não o que o preset sugere — é a ferramenta de transparência do usuário.
- Nenhuma resposta contém secret, credencial ou material sensível.
- Listagens têm limite e paginação: um agente em loop não pode extrair a base inteira nem derrubar o Control Plane.
- Respostas passam por redaction.

## Observability Requirements
`mcp_requests_total` por tool; leituras por conexão. Uma sequência de listagens anormalmente ampla é sinal de enumeração.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| ID de outro Team | Responde como inexistente; não confirma existência. |
| Listagem sem limite | Limite aplicado; cursor obrigatório. |
| Agente em loop | Rate limit (`M12-14`). |
| Scope insuficiente | `INSUFFICIENT_SCOPE`. |
| Recurso removido | `NOT_FOUND` consistente. |
| Backend degradado | `DEPENDENCY_UNAVAILABLE` estruturado, sem induzir bypass. |

## Acceptance Criteria
1. As tools de contexto e leitura do escopo existem com JSON Schema de entrada e saída.
2. `platform.whoami` reporta a permissão **efetiva**, não o preset nominal.
3. Toda leitura respeita boundary e tenancy.
4. Um ID de outro Team responde como inexistente, **sem** confirmar existência, provado por teste.
5. Nenhuma resposta contém secret, credencial ou material sensível, provado com valor plantado.
6. Todas as listagens têm limite e paginação por cursor.
7. `structuredContent` é estável, com IDs e estados canônicos.
8. `operations.wait` faz polling bounded e não mantém conexão longa obrigatória.
9. Scope insuficiente retorna `INSUFFICIENT_SCOPE`.
10. Backend degradado retorna `DEPENDENCY_UNAVAILABLE` estruturado, sem induzir bypass.
11. **Nenhuma query de domínio nova** foi criada para o MCP; as existentes são reutilizadas.
12. Zero vazamento cross-team na suíte adversarial.

## Required Tests
- **security/adversarial**: enumeração cross-team; valor plantado ausente das respostas.
- **contract**: schemas estáveis; `structuredContent`.
- **integration**: paginação e limites; `operations.wait` bounded.
- **E2E**: MCP-01 e MCP-02 do Anexo F §15.

## Quality Gates
Local Quality Gate + `bin/security` + `bin/fitness`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, zero vazamento cross-team provado, reuso das Queries verificado, Critical/High = 0.
