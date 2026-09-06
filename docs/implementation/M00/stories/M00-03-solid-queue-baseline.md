# M00-03 — Solid Queue and asynchronous job baseline

## Objective
Instalar e configurar o Solid Queue como mecanismo de entrega de trabalho assíncrono, deixando explícito desde o início que a fila **não é fonte de verdade**.

## Outcome
Um job de exemplo é enfileirado, executado por um worker separado e observável; a documentação do diretório de jobs declara que durabilidade pertence ao PostgreSQL e que todo trabalho crítico precisará de sweep de recuperação.

## References
- `docs/architecture/07-internal-control-plane.md` §9 (filas e serialização), §10 (Transactional Outbox)
- `docs/AGENT_RULES.md` — “Async Operations”, “Jobs”
- `docs/implementation/SPEC_CONFLICTS.md` SC-02

## Preconditions
`M00-02` done.

## Scope
- Solid Queue instalado com suas tabelas e um processo de worker executável separado do servidor web.
- Definição das **filas lógicas** do doc 07 §9.1 como configuração nomeada, ainda sem consumidores: `deployments`, `runtime`, `cluster`, `certificates`, `backup-dr`, `system`.
- Política de retry/backoff base parametrizável por classe de job (não uma política global cega).
- Job de exemplo que prova enfileiramento, execução, retry e falha terminal.
- `README.md` em `app/jobs/` declarando: job faz handoff para a Application Layer e não duplica regra de negócio (Anexo I §4.1).

## Out of Scope
- Operation Engine, Outbox e sweep de recuperação (`M01-14`, `M01-15`).
- Locks, leases e fencing (`M01-16`).
- Qualquer job de domínio.

## Async / Control Plane
Esta Story entrega **apenas o mecanismo de entrega**. O contrato que ela precisa deixar explícito, por escrito e em teste, é: se uma mensagem for perdida, nenhum dado de intenção pode ser perdido — a recuperação virá do PostgreSQL em `M01-15`. Nenhum job de M00 pode assumir entrega exatamente-uma-vez.

## Security Requirements
- Payload de job é tipado e validado; nunca desserializar classe arbitrária (Anexo C §16).
- Payload de job não carrega segredo — regra registrada agora, verificada por AF-06 em `M00-13`.

## Observability Requirements
- Cada execução de job registra `job_class`, `queue`, `attempt`, `duration` e o `correlation_id` propagado de quem enfileirou (integrado em `M00-15`).
- Falha de job registra erro classificado, não apenas a mensagem da exceção.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Job levanta exceção transitória | Retry com backoff + jitter até o limite da classe; depois falha terminal registrada. |
| Worker morre no meio da execução | O job volta a ficar elegível; o teste comprova que não há duplicação de efeito no job idempotente de exemplo. |
| Payload inválido | Falha antes de executar efeito, com erro de validação. |

## Acceptance Criteria
1. O worker do Solid Queue sobe como processo separado do servidor web.
2. Um job enfileirado é executado e o resultado é observável no log com `correlation_id`.
3. As seis filas lógicas do doc 07 §9.1 existem como configuração nomeada.
4. Um job com falha transitória é reexecutado conforme a política da sua classe e para no limite definido, sem retry infinito.
5. Um job com payload inválido falha na validação sem executar efeito.
6. Existe teste que mata o worker no meio da execução e prova que o job idempotente de exemplo não duplica efeito.
7. `app/jobs/README.md` declara a regra de handoff e a de não-durabilidade do broker.

## Required Tests
- **unit**: política de retry/backoff por classe; validação de payload.
- **integration**: enfileirar → executar → observar; falha transitória com retry; worker morto no meio da execução.
- **security**: payload de job rejeita objeto arbitrário; nenhum segredo em payload serializado.

## Quality Gates
Local Quality Gate classes Ruby/Rails e Database.

## Definition of Done
Os 7 Acceptance Criteria satisfeitos, teste de crash de worker verde, README de boundary escrito, Critical/High = 0.
