# M12-08 — Safe write tools (rollout phase F2)

## Objective
Liberar as mutações reversíveis e de baixo risco: criar projetos e ambientes, configurar serviços em homologação, escalar dentro da política e disparar builds.

## Outcome
O agente cria e configura recursos em homologação; toda mutação retorna `operationId` e passa pelos mesmos Commands da UI.

## References
- `docs/annexes/F-mcp-platform-agents.md` §7.2, §7.3, §7.4 (builds), §6.1 (níveis R0/R1), §21 (fase F2)
- `docs/annexes/F-mcp-platform-agents.md` §9.1 (Operation como contrato canônico)

## Preconditions
`M12-06` done.

## Scope
- `projects.create/update/delete`, `environments.create/update/delete`.
- `services.create/update/scale/restart/pause/resume`.
- `builds.create/cancel/retry`.
- `sources.connect` iniciando a autorização do provider.
- `secrets.create/set_value/bind` — **write-only**, sem leitura posterior.
- Todas retornam `operationId` quando o trabalho é assíncrono.
- Nível de risco R1 do Anexo F §6.1: consentimento do host + RBAC.
- **Gate da fase F2**: idempotência, audit e rollback.

## Out of Scope
- Deploy, rollback e promoção (`M12-10`).
- Operações de cluster (`M12-11`).
- Reveal e exec (`M12-12`).

## Application Layer
Reuso integral dos Commands existentes. O MCP **não** cria Command novo nem valida regra de negócio própria.

## Security Requirements
- **Caminho feliz de secret é write-only** (Anexo F §7.6, regra explícita): o agente configura e usa secrets **sem precisar lê-los**. `secrets.set_value` grava; nenhuma leitura posterior devolve o valor.
- Toda mutação passa pelos Commands existentes, com Policy, quota e audit.
- Mutação em produção respeita `prodMode`; com read-only, é negada.
- `Idempotency-Key` é usada, reaproveitando `M02-13`: retry do agente não duplica.
- Nenhum valor sensível aparece em result, log ou audit.
- Erros são estruturados e **não induzem bypass** (Anexo F §22, AC-MCP-21).
- Ações destrutivas em produção não pertencem a esta fase.

## Observability Requirements
`mcp_operation_started_total`; operações iniciadas por agente identificadas como tal no audit e na timeline.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Mutação em produção com read-only | Negada com a razão. |
| Retry do agente | `Idempotency-Key` deduplica. |
| Quota excedida | `QUOTA_EXCEEDED` estruturado. |
| Operação concorrente | `OPERATION_IN_PROGRESS`; acompanhar a existente. |
| Argumentos inválidos | `VALIDATION_ERROR` com campos estruturados. |
| Tentativa de ler secret depois de escrever | Não existe caminho de leitura. |

## Acceptance Criteria
1. As tools de escrita do escopo existem e reutilizam os Commands existentes.
2. **Nenhum Command novo nem validação de negócio própria** foi criado para o MCP.
3. Toda mutação assíncrona retorna `operationId`.
4. `secrets.set_value` e `secrets.bind` funcionam **write-only**; nenhuma leitura posterior devolve o valor, provado por teste.
5. Mutação em produção com `prodMode` read-only é negada com a razão.
6. `Idempotency-Key` deduplica retries do agente.
7. Quota excedida retorna `QUOTA_EXCEEDED` estruturado.
8. Operação concorrente retorna `OPERATION_IN_PROGRESS` com referência à existente.
9. Argumentos inválidos retornam `VALIDATION_ERROR` com campos.
10. Nenhum valor sensível aparece em result, log ou audit.
11. Operações iniciadas por agente são identificadas como tal no audit e na timeline.
12. Erros estruturados **não** induzem bypass operacional.

## Required Tests
- **security**: write-only de secret; ausência de leitura; produção read-only.
- **integration**: `Idempotency-Key`; quota; operação concorrente.
- **contract**: schemas e taxonomia de erro.
- **E2E**: MCP-03, MCP-04, MCP-05, MCP-09, MCP-11 do Anexo F §15.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, write-only de secret provado, reuso de Commands verificado, Critical/High = 0.
