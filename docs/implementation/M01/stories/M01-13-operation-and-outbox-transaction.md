# M01-13 — Operation, OperationAttempt and the transactional Outbox

## Objective
Tornar toda mutação de infraestrutura uma **Operation durável**, gravada na mesma transação da mudança de Desired State e de um OutboxEvent — eliminando a janela entre “salvei a intenção” e “publiquei o trabalho”.

## Outcome
Alterar o desired state de um Service grava, atomicamente, a mudança + `Operation` + `OutboxEvent`. A requisição HTTP retorna rapidamente com `operationId`. Nenhuma chamada de rede acontece dentro da transação.

## References
- `docs/architecture/07-internal-control-plane.md` §5 (Operation Engine e state machine), §6 (idempotência), §10 (Transactional Outbox), §16 (cancelamento e supersession)
- `docs/architecture/09-data-model-apis-contracts.md` §9 (Operations, attempts, outbox), §24 (transaction boundaries)
- `docs/AGENT_RULES.md` — “Async Operations”
- `docs/annexes/B-nfr-slos.md` §4 (writes assíncronos), §5 (reconciliation)

## Preconditions
`M01-12` done.

## Scope
- `Operation`: id, teamId, resourceType, resourceId, type, status, desiredRevision, idempotencyKey?, leaseOwner?, leaseUntil?, fencingToken, attemptCount, payload (JSONB sanitizado + `schemaVersion`), errorCode?, timestamps.
- State machine do doc 07 §5.2: `PENDING → QUEUED → RUNNING → (WAITING_RUNTIME → VERIFYING) → SUCCEEDED | RETRYABLE → QUEUED`, com terminais `FAILED`, `CANCELED`, `SUPERSEDED`, `TIMED_OUT`.
- `OperationAttempt`: cada tentativa preserva início, fim, executor, erro categorizado e telemetria. **Não** se sobrescreve tentativa anterior.
- `OutboxEvent`: id, aggregateType, aggregateId, eventType, schemaVersion, payload sem secrets, occurredAt, publishedAt, partitionKey.
- **Boundary transacional obrigatório** (doc 09 §24): desired state + Operation + OutboxEvent no mesmo `COMMIT`. Publicação na fila acontece **depois**.
- `UNIQUE(scope, idempotencyKey)` quando a chave não é nula.
- Supersession: revisão mais nova marca a anterior `SUPERSEDED` em vez de aplicar configuração obsoleta.
- Índices: `INDEX(publishedAt, occurredAt)` no outbox; `INDEX(resourceType, status, nextAttemptAt)` em operations.

## Out of Scope
- Dispatcher e sweep (`M01-14`).
- Locks, leases e fencing na execução (`M01-15`) — os **campos** nascem aqui, o mecanismo lá.
- Cancelamento pela UI (`M02-10`).
- Idempotency-Key na borda HTTP (`M02-13`) — a coluna e a constraint nascem aqui.

## Domain Impact
**Entidades:** `Operation`, `OperationAttempt`, `OutboxEvent`.
**Invariante central:** o PostgreSQL é a fonte de verdade da Operation. A fila é mecanismo de entrega e pode perder mensagem sem que a intenção se perca.

## Application Layer
- **Commands:** todo Command que afeta runtime passa a criar Operation + OutboxEvent no mesmo boundary.
- **Queries:** `OperationById`, `OperationsForResource`.

## Async / Control Plane
Esta é a Story que define o contrato do Control Plane inteiro:
- request HTTP **registra intenção** e retorna `operationId`;
- worker executa;
- reconciler confirma realidade.
Nenhuma requisição fica aberta esperando deploy, scale ou drain (doc 07, decisão central).

## API Impact
Mutação assíncrona retorna `operationId` e **não** promete conclusão síncrona (contrato do Anexo D §6.1). `GET` da Operation retorna estado, steps, erro normalizado e timestamps.

## Security Requirements
- **Payload de Operation nunca contém plaintext de secret** — apenas IDs e referências de versão (doc 07 §21). Regra verificada por AF-06.
- Payload é versionado por `schemaVersion` e validado; nunca desserializar classe arbitrária (Anexo C §16).
- `errorCode` é estável e a mensagem humana fica separada; a resposta ao usuário não vaza detalhe interno.
- Toda Operation carrega `requestId`, `actor` e `correlationId` para correlação forense.

## Observability Requirements
- Timeline da Operation: criada, enfileirada, executando, verificando, terminal, com duração — o formato do doc 07 §17.2.
- Cada `OperationAttempt` preserva a linha do tempo de retries.
- Métrica-alvo do Anexo B §5: detecção da mudança desejada ≤ 2 s após o commit em 95% dos casos.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Crash entre `COMMIT` e publicação | A intenção sobrevive; o sweep de `M01-14` recupera. Este é **o** teste que justifica o Outbox. |
| Mesma `idempotencyKey` no mesmo escopo | Retorna a Operation original; não cria uma segunda. |
| Revisão mais nova chega antes da anterior executar | A anterior vira `SUPERSEDED`; o executor reconcilia direto para a mais nova. |
| Chamada de rede dentro da transação | Proibida; teste comprova que nenhuma chamada externa ocorre no boundary. |
| Payload com campo desconhecido | Rejeitado na validação, não desserializado às cegas. |

## Acceptance Criteria
1. Alterar o desired state grava, na **mesma transação**, a mudança + `Operation` + `OutboxEvent`.
2. Nenhuma chamada de rede (Docker, HTTP, DNS) ocorre dentro da transação, provado por teste com instrumentação.
3. A requisição HTTP retorna `operationId` rapidamente e não aguarda o runtime.
4. A state machine da Operation rejeita transições inválidas.
5. `UNIQUE(scope, idempotencyKey)` existe; a mesma chave no mesmo escopo produz **uma** operação lógica, provado por teste concorrente.
6. Uma revisão mais nova marca a anterior como `SUPERSEDED` em vez de aplicar configuração obsoleta.
7. Cada tentativa cria um `OperationAttempt` novo; nenhuma tentativa anterior é sobrescrita.
8. O payload da Operation é validado por `schemaVersion` e rejeita campo desconhecido.
9. Nenhum payload de Operation ou OutboxEvent contém plaintext de secret, provado com valor plantado e por AF-06.
10. Os índices `(publishedAt, occurredAt)` e `(resourceType, status, nextAttemptAt)` existem e são usados.
11. `errorCode` é estável e a resposta ao usuário não contém detalhe interno.
12. Um crash simulado entre `COMMIT` e publicação **não** perde a intenção.

## Required Tests
- **unit**: state machine; supersession; validação de payload por `schemaVersion`.
- **integration (PostgreSQL real)**: atomicidade das três gravações; **crash entre commit e publish**; idempotency key concorrente; ausência de chamada de rede na transação; índices exercitados.
- **contract**: mutação assíncrona retornando `operationId`; envelope de erro.
- **security**: AF-06 sobre payloads; valor sensível plantado não persiste.

## Quality Gates
Local Quality Gate + `bin/fitness` (AF-06, AF-08). **Story crítica: exige plan mode** — schema, concorrência e boundary transacional.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, teste de crash entre commit e publish verde, ausência de chamada de rede na transação comprovada, Critical/High = 0.
