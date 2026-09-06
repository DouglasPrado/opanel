# M12-07 — Observability tools with bounded output

## Objective
Dar ao agente acesso a logs, métricas, alertas e incidentes de forma **resumida por padrão**, respeitando o context window e a redaction.

## Outcome
`logs.read/search`, `metrics.query`, `alerts`, `incidents` e `operations` retornam dados paginados, filtrados e redigidos.

## References
- `docs/annexes/F-mcp-platform-agents.md` §7.8 (observability), §10 (controle de contexto), §17.1 (untrusted text)
- `docs/architecture/03-runtime-observability.md` §10.3

## Preconditions
`M12-06` done. M09 recomendado (as fontes vêm de lá).

## Scope
- `logs.read/search` com `limit`, `cursor`, `since`, `until`, `level` e `search`.
- `metrics.query` com consultas **pré-definidas ou DSL limitada**, ranges e cardinalidade limitados.
- `alerts.list/acknowledge`, `incidents.list/get/create/update/resolve`.
- `operations.list/get/cancel/wait`.
- Build logs em chunk com cursor e linhas de erro relevantes.
- Timeline de operação compacta e paginada.
- Regra do Anexo F §10: **nunca retornar megabytes sem solicitação**.

## Out of Scope
- Terminal/exec (`M12-12`).
- Criação de alert rules — é escrita; entra em `M12-08` conforme o preset.
- Export de logs em massa.

## Security Requirements
- **Redaction antes de chegar ao MCP** (Anexo F §10): secrets, tokens e headers de autorização mascarados.
- **Conteúdo de aplicação e de log é dado não confiável**, e **não** instrução para o agente (Anexo F §17.1, regra explícita). O servidor nunca interpreta texto de log como comando, e o campo é marcado como dado.
- Consultas de métrica são pré-definidas ou de DSL limitada — expressão arbitrária é vetor de custo.
- Limites de range, cardinalidade e volume por chamada.
- Acesso respeita RBAC por Environment; logs de produção podem ser restritos.
- Rate limit específico para tools caras.

## Observability Requirements
Volume retornado por tool; chamadas limitadas. Um agente pedindo repetidamente janelas enormes é sinal de loop.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Pedido de janela enorme | Limitado com aviso estruturado; sugerir refinar. |
| Log com prompt injection | Retornado como **dado marcado**; nunca interpretado como instrução. |
| Backend indisponível | `DEPENDENCY_UNAVAILABLE` com retry policy. |
| Scope insuficiente | `INSUFFICIENT_SCOPE`. |
| Agente em loop de leitura | `RATE_LIMITED`. |
| Métrica com cardinalidade alta | Rejeitada pelo limite. |

## Acceptance Criteria
1. As tools de observabilidade do escopo existem com filtros, `limit` e `cursor`.
2. **Nenhuma chamada retorna megabytes sem solicitação explícita**; os limites são aplicados.
3. Redaction acontece **antes** de o dado chegar ao MCP, provado com valor plantado.
4. Conteúdo de log é retornado como **dado marcado**, nunca como instrução, provado com payload de injeção.
5. `metrics.query` usa consultas pré-definidas ou DSL limitada; expressão arbitrária é rejeitada.
6. Ranges e cardinalidade são limitados.
7. Acesso respeita RBAC por Environment; logs de produção podem ser restritos.
8. Rate limit específico para tools caras é aplicado.
9. Backend indisponível retorna `DEPENDENCY_UNAVAILABLE` com política de retry.
10. Build logs vêm em chunk com cursor e destaque das linhas de erro relevantes.
11. A timeline de operação é compacta e paginada.
12. Negativos cross-team passam.

## Required Tests
- **security/adversarial**: prompt injection em log; valor plantado redigido; expressão arbitrária rejeitada.
- **integration**: limites de volume e range; rate limit.
- **policy**: RBAC por Environment; negativo cross-team.
- **E2E**: MCP-12 e MCP-13 do Anexo F §15.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, injection tratada como dado, limites de volume provados, Critical/High = 0.
