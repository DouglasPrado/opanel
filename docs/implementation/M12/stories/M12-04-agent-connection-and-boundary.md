# M12-04 — AgentConnection, policy and resource boundary

## Objective
Modelar a conexão de um agente como uma identidade delegada com **fronteira de recursos explícita**, para que ele nunca alcance mais do que o usuário decidiu conceder.

## Outcome
Uma conexão pertence a um Team e a um usuário/service account, tem um boundary de projetos/environments/clusters, e políticas próprias para produção e capabilities sensíveis.

## References
- `docs/annexes/F-mcp-platform-agents.md` §13 (modelo de dados), §13.1 (constraints), §14.2 (wizard)
- `docs/architecture/04-identity-teams-security.md` §9 (identidades de automação)

## Preconditions
`M12-03` done.

## Scope
- `AgentConnection`: id, teamId, userId/serviceAccountId, name, preset, status, expiresAt, lastUsedAt.
- `AgentResourceBoundary`: connectionId, projectId/environmentId/clusterId, accessMode.
- `AgentPolicy`: prodMode, política de approvals, tools permitidas/negadas, flags de exec e reveal.
- Constraints do Anexo F §13.1: uma conexão pertence a **exatamente um** Team e a um usuário/service account; boundaries **não** apontam para recursos de outro Team; grant revogado não é reutilizável.
- Expiração da conexão e revogação imediata.

## Out of Scope
- Presets e cálculo de autorização efetiva (`M12-05`).
- Approvals (`M12-09`).
- UI (`M12-15`).

## Domain Impact
**Invariante:** o boundary é um **teto adicional**, nunca uma concessão: ele restringe, jamais amplia o que o RBAC do usuário já permite.

## Application Layer
- **Commands:** `CreateAgentConnection`, `UpdateAgentPolicy`, `RevokeAgentConnection`.
- **Queries:** `AgentConnections`, `EffectiveBoundary`.

## Security Requirements
- **Boundary não pode apontar para recursos de outro Team** (Anexo F §13.1, regra explícita), garantido no banco.
- O boundary **restringe**, nunca amplia: um agente jamais alcança o que o usuário que o autorizou não alcança.
- `prodMode` permite produção read-only mesmo com write em homologação (Anexo F §22, AC-MCP-04).
- Capabilities sensíveis (`exec`, `secret:reveal`, `owner:transfer`, `instance:admin`) nascem **off** e não entram em presets comuns.
- Revogar a conexão bloqueia chamadas seguintes rapidamente e de forma auditável.
- Expiração obrigatória por política da instalação.
- Se o usuário que autorizou perde a permissão, o agente perde junto — a autorização é sempre recalculada.
- Criar, alterar e revogar geram AuditLog.

## Observability Requirements
Conexões com preset, boundary, `prodMode`, último uso e expiração. Uso recente por conexão.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Boundary apontando para outro Team | Rejeitado pela constraint. |
| Usuário perde permissão | O agente perde junto na próxima chamada. |
| Conexão expirada | Chamadas rejeitadas. |
| Conexão revogada | Chamadas seguintes bloqueadas rapidamente. |
| Boundary tentando ampliar acesso | Impossível: o boundary só restringe. |
| Capability sensível em preset comum | Rejeitada. |

## Acceptance Criteria
1. `AgentConnection`, `AgentResourceBoundary` e `AgentPolicy` existem com os campos do Anexo F §13.
2. Uma conexão pertence a **exatamente um** Team e a um usuário/service account.
3. Boundary apontando para recurso de outro Team é **rejeitado pelo banco**, provado por teste.
4. O boundary **restringe e nunca amplia**: um agente não alcança o que o autorizador não alcança, provado por teste.
5. `prodMode` permite produção read-only com write em homologação.
6. Capabilities sensíveis nascem desabilitadas e não entram em presets comuns.
7. Perder a permissão do autorizador tira o acesso do agente na chamada seguinte.
8. Conexão expirada tem chamadas rejeitadas.
9. Revogar bloqueia chamadas seguintes rapidamente e de forma auditável.
10. Expiração é obrigatória conforme a política da instalação.
11. Criar, alterar e revogar geram AuditLog; negativo cross-team passa.

## Required Tests
- **integration**: boundary cross-team rejeitado; expiração; revogação com efeito rápido.
- **policy**: boundary restringindo e não ampliando; perda de permissão do autorizador.
- **security**: capabilities sensíveis fora de presets comuns; `prodMode` read-only.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, boundary como teto provado, revogação efetiva, Critical/High = 0.
