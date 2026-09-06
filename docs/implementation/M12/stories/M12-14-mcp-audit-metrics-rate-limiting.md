# M12-14 — MCP audit, metrics and rate limiting

## Objective
Tornar a atividade dos agentes auditável e mensurável, e proteger a plataforma de loops e abuso — porque um agente errado repete rápido.

## Outcome
Cada tool call gera um registro de auditoria correlacionável; as métricas do Anexo F §19 existem; loops de agente são limitados.

## References
- `docs/annexes/F-mcp-platform-agents.md` §12 (auditoria e identidade do agente), §12.1 (evento mínimo), §19 (observabilidade), §22 (AC-MCP-17, AC-MCP-19)
- `docs/annexes/C-threat-model-security-hardening.md` §19

## Preconditions
`M12-06` done.

## Scope
- `McpExecutionAudit` com os campos do Anexo F §12.1: `actor_user_id`, `mcp_client_id`, `agent_connection_id`, `tool`, `scope_set`, `resource`, `arguments_digest`, `approval_id`, `operation_id`, `result`, ip/user agent/client info, `trace_id`.
- Métricas do Anexo F §19.
- Rate limit por conexão, por tool e global, com limites maiores para tools caras.
- Detecção de loop: chamadas repetidas idênticas em janela curta.
- `trace_id` atravessando Gateway → Command → Operation → Reconciler → Executor.

## Out of Scope
- Rate limit geral da API (`M11-14`) — este é específico do MCP e compõe com aquele.
- SIEM externo.
- Detecção comportamental sofisticada.

## Security Requirements
- **Secret plaintext, bearer tokens e credenciais nunca entram no audit log** (Anexo F §12.1, regra explícita).
- `arguments_digest` é o hash do payload **após** redaction — ele permite correlacionar sem armazenar os argumentos.
- A auditoria correlaciona **usuário humano, cliente MCP, conexão, tool, approval e Operation** — sem isso, uma ação do agente é anônima.
- Rate limit protege contra loops de agente, que são mais rápidos e mais persistentes que humanos.
- A detecção de loop é um sinal de segurança e de qualidade, e é registrada.
- Métricas não carregam valores sensíveis nem labels de alta cardinalidade.

## Observability Requirements
As oito métricas do Anexo F §19. Atividade por conexão consultável na UI (`M12-15`).

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Agente em loop | `RATE_LIMITED`; loop registrado. |
| Tool cara chamada repetidamente | Limite específico aplicado. |
| Audit sem `operation_id` em mutação assíncrona | Defeito detectado por teste. |
| Argumentos com secret | `arguments_digest` calculado após redaction; nenhum valor armazenado. |
| Métrica com alta cardinalidade | Rejeitada pela política. |
| Falha ao auditar | A chamada **não** é considerada bem-sucedida. |

## Acceptance Criteria
1. `McpExecutionAudit` registra todos os campos do Anexo F §12.1.
2. **Nenhum secret, bearer token ou credencial entra no audit**, provado com valor plantado.
3. `arguments_digest` é calculado **após** redaction; nenhum argumento sensível é armazenado.
4. A auditoria correlaciona usuário humano, cliente, conexão, tool, approval e Operation.
5. Mutação assíncrona sem `operation_id` no audit é detectada como defeito.
6. Falha ao auditar impede considerar a chamada bem-sucedida.
7. As oito métricas do Anexo F §19 existem.
8. Métricas não carregam valores sensíveis nem alta cardinalidade.
9. Rate limit por conexão, por tool e global é aplicado, com limites específicos para tools caras.
10. Loops de agente são detectados, limitados e **registrados**.
11. `trace_id` atravessa Gateway → Command → Operation → Reconciler → Executor.
12. A atividade por conexão é consultável.

## Required Tests
- **security**: valor plantado ausente do audit; digest após redaction; loop limitado.
- **integration**: correlação completa; falha de audit bloqueando sucesso; rate limit por tool.
- **unit**: cálculo do digest; política de cardinalidade.

## Quality Gates
Local Quality Gate + `bin/security` + `bin/fitness` (AF-06, AF-08).

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, correlação completa provada, ausência de credencial no audit verificada, Critical/High = 0.
