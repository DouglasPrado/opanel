# M12-03 — Stateless MCP Gateway

## Objective
Criar o adapter de protocolo: um gateway **stateless** que traduz tools, resources e prompts do MCP em chamadas aos mesmos Application Services usados pela UI e pela API.

## Outcome
O endpoint `/mcp` responde JSON-RPC sobre HTTP, escala horizontalmente sem sticky session, e **não contém nenhuma regra de negócio**.

## References
- `docs/annexes/F-mcp-platform-agents.md` §2.1 (MCP Gateway é adapter de protocolo), §2.2 (stateless e HA), §3 (baseline do protocolo), §18.2 (regra de dependência)
- `docs/annexes/I-engineering-playbook-quality-gates.md` §16.2 (AF-05)

## Preconditions
`M12-01` done.

## Scope
- Endpoint HTTPS único `/mcp`, JSON-RPC sobre HTTP, com a revisão de protocolo alvo do Anexo F §3.1.
- **Stateless**: nenhum estado de sessão MCP em memória; estado durável vive no banco (Operation, Approval, OAuthGrant).
- Discovery de capabilities.
- Catálogo de tools **determinístico** para uma dada combinação de versão + policy.
- Erros estruturados conforme a taxonomia do Anexo F §11.2.
- `structuredContent` estável em toda tool relevante.
- **Regra de dependência**: `MCP Tool → Command/Query → Domain/Application → DB/Operation`. Nunca `MCP Tool → Docker`, nunca SQL ad hoc, nunca lógica duplicada.

## Out of Scope
- Tools concretas (`M12-06` em diante).
- Approvals (`M12-09`).
- MCP Apps e extensões opcionais críticas.

## Application Layer
O gateway **não** contém lógica de deploy, TLS, Vault ou cluster. Ele valida contrato, autentica, autoriza, chama a camada correta e serializa o resultado (Anexo F §2.1).

## Security Requirements
- **AF-05 passa a avaliar código real**: o adapter MCP **não** chama o Swarm Executor diretamente; ele passa pela Application Layer.
- Nenhuma regra de negócio existe apenas no MCP — a duplicação criaria dois lugares onde a autorização pode divergir.
- Headers de protocolo são observados para telemetria e rate limit, mas a **autorização final acontece no Gateway**, nunca no edge (Anexo F §3.2).
- Erros estruturados **não** vazam detalhe interno nem confirmam existência de recursos fora do boundary.
- Stateless elimina fixation de sessão MCP e permite revogação imediata via grant.

## Observability Requirements
`mcp_requests_total` por method/tool/status; duração por tool; `trace_id` atravessando Gateway → Command → Operation → Reconciler → Executor.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Request inválido | Erro estruturado de validação com campos. |
| Versão de protocolo não suportada | Erro claro indicando as versões suportadas. |
| Catálogo oscilando | Proibido: tool indisponível retorna erro de capability/estado, e não some do catálogo a cada segundo (Anexo F §3.3). |
| Estado de sessão exigido | Não existe: o core é stateless. |
| Tool chamando Docker diretamente | Reprovado por AF-05. |
| Erro interno | Código estável + `trace_id`, sem stack trace. |

## Acceptance Criteria
1. `/mcp` responde JSON-RPC sobre HTTP na revisão de protocolo alvo.
2. O core é **stateless**; nenhum estado de sessão MCP vive em memória.
3. Qualquer réplica atende qualquer request, sem sticky session, provado por teste com duas réplicas.
4. O catálogo de tools é determinístico para uma dada versão + policy.
5. Tool temporariamente indisponível retorna **erro de capability/estado**, sem fazer o catálogo oscilar.
6. Os erros seguem a taxonomia do Anexo F §11.2 e não vazam detalhe interno.
7. Toda tool relevante retorna `structuredContent` estável.
8. **AF-05 avalia código real** e reprova, em caso negativo, um adapter chamando o Executor diretamente.
9. Nenhuma regra de negócio existe apenas no MCP, verificado por revisão e teste estrutural.
10. A autorização final acontece no Gateway, não no edge.
11. `trace_id` atravessa Gateway → Command → Operation → Reconciler → Executor.
12. Versão de protocolo não suportada retorna erro claro.

## Required Tests
- **contract/protocol**: conformance; request inválido; versão não suportada.
- **integration**: duas réplicas atendendo qualquer request; catálogo determinístico.
- **security**: AF-05 com caso negativo; erros sem detalhe interno.

## Quality Gates
Local Quality Gate + `bin/fitness` (AF-05 significativa) + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, stateless e HA provados, AF-05 avaliando código real, Critical/High = 0.
