# M02-13 — Idempotency-Key on repeatable mutations

## Objective
Garantir que um retry de cliente — humano, CLI, webhook ou agente — não produza duas mutações lógicas.

## Outcome
Repetir a mesma requisição com a mesma `Idempotency-Key` no mesmo escopo retorna a Operation original em vez de criar uma segunda.

## References
- `docs/architecture/07-internal-control-plane.md` §6.1 (API idempotente)
- `docs/architecture/09-data-model-apis-contracts.md` §20 (convenções da API), §18 (`UNIQUE(scope, idempotencyKey)`)
- `docs/annexes/D-test-strategy.md` §18 (concorrência e idempotência)
- `docs/annexes/B-nfr-slos.md` §12 (retenção de idempotency keys: 24–72 h)

## Preconditions
M01 aceito (`M01-13` criou a coluna e a constraint).

## Scope
- Header `Idempotency-Key` aceito nas mutações repetíveis: deploy (futuro), create, scale, restart, promote, rotate e demais operações externas críticas.
- Escopo da chave: Team + endpoint semântico. A mesma chave em endpoints diferentes é independente.
- Retorno da Operation original quando a chave se repete, com o mesmo `operationId`.
- **Conflito de payload**: mesma chave com corpo diferente é rejeitada com erro estável, não silenciosamente ignorada.
- Retenção configurável de 24–72 h conforme o endpoint (Anexo B §12).
- Chave ausente: a requisição funciona normalmente, mas sem garantia de deduplicação — e isso é documentado.

## Out of Scope
- Deduplicação de webhook por `deliveryId` (`M05-04`) — é um mecanismo diferente, com chave natural.
- Idempotência interna do executor (`M01-09`) — já entregue.
- Idempotência de tools MCP (`M12-08`) — reutiliza este mecanismo.

## Domain Impact
Reuso de `Operation.idempotencyKey` e da constraint `UNIQUE(scope, idempotencyKey)` criada em `M01-13`.

## API Impact
Contrato do doc 09 §20: `Idempotency-Key` em deploy, create, promote, rotate e operações externas críticas. Resposta repetida devolve o recurso e o `operationId` originais.

## Security Requirements
- A chave é fornecida pelo cliente e **não** é usada como identificador de recurso nem exposta como se fosse.
- Uma chave não pode ser usada para acessar a Operation de outro Team: o escopo inclui o Team, e o teste cross-team comprova.
- Chave com formato inválido é rejeitada, não normalizada silenciosamente.
- Conflito de payload com a mesma chave é um sinal de erro do cliente e é registrado.

## Observability Requirements
- Métrica: requisições deduplicadas por endpoint.
- Log registra quando uma requisição foi resolvida por idempotência, com o `operationId` original.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Retry por timeout do cliente | Retorna a Operation original; nenhuma segunda mutação. |
| Duas requisições concorrentes com a mesma chave | Uma cria, a outra recebe a original; garantido pela constraint. |
| Mesma chave com payload diferente | Rejeitada com erro estável. |
| Chave de outro Team | Não resolve; escopo inclui o Team. |
| Chave expirada pela retenção | Tratada como chave nova; documentado. |
| Chave malformada | Rejeitada com erro de validação. |

## Acceptance Criteria
1. `Idempotency-Key` é aceita nas mutações repetíveis existentes.
2. A mesma chave no mesmo escopo retorna a Operation original com o mesmo `operationId`.
3. Duas requisições **concorrentes** com a mesma chave produzem uma única operação lógica, provado por teste com barreira.
4. A mesma chave com payload diferente é rejeitada com erro estável.
5. Uma chave de outro Team não resolve para a Operation existente, provado por teste cross-team.
6. Chave malformada é rejeitada por validação.
7. Chave expirada pela retenção é tratada como nova, e o comportamento está documentado.
8. Requisição sem a chave funciona, sem garantia de deduplicação, e isso está documentado.
9. Métrica de requisições deduplicadas está disponível.
10. O log registra a resolução por idempotência com o `operationId` original.

## Required Tests
- **unit**: validação de formato; escopo da chave.
- **integration (concorrente)**: duas requisições simultâneas com a mesma chave; conflito de payload; expiração.
- **contract**: comportamento documentado do header em todos os endpoints repetíveis.
- **policy/security**: chave de outro Team não resolve.

## Quality Gates
Local Quality Gate + suíte de concorrência.

## Definition of Done
Os 10 Acceptance Criteria satisfeitos, teste concorrente verde, conflito de payload rejeitado, Critical/High = 0.
