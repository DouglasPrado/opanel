# M01-14 — Outbox dispatcher and periodic recovery sweep

## Objective
Publicar os OutboxEvents na fila depois do commit e garantir, por varredura periódica, que nenhuma Operation fique parada porque uma mensagem se perdeu.

## Outcome
Eventos são publicados e marcados como entregues; Operations `QUEUED`/`RUNNING` sem lease válido são reenfileiradas; a durabilidade do produto não depende do broker.

## References
- `docs/architecture/07-internal-control-plane.md` §9.2 (a fila não é fonte de verdade), §10.2 (dispatcher), §22 (falhas que o desenho precisa tolerar)
- `docs/architecture/09-data-model-apis-contracts.md` §9.3 (OutboxEvent)
- `docs/annexes/B-nfr-slos.md` §5 (início de operação após enqueue), §14 (degradação)
- `docs/implementation/SPEC_CONFLICTS.md` SC-02

## Preconditions
`M01-13` done.

## Scope
- **Dispatcher** do Outbox: lê eventos não publicados por `(publishedAt, occurredAt)`, publica na fila lógica correta e marca `publishedAt`.
- **Sweep de recuperação**: encontra Operations `QUEUED`/`RUNNING` sem lease válido, sem progresso além do limite, e as reenfileira.
- **Inbox/dedup** para consumidores que podem receber a mesma mensagem mais de uma vez (doc 07 §10.2): `inbox_events(source, externalId, processedAt)`.
- Cadência configurável por tipo, seguindo o doc 07 §23.
- Watchdog: Operation presa além do limiar é marcada `STALLED` e gera alerta (Anexo B §6).
- Backpressure: se a fila satura, a criação de operações não essenciais desacelera em vez de perder trabalho.

## Out of Scope
- Locks e fencing na execução (`M01-15`).
- Reconcilers (`M01-17`, `M01-18`).
- Alertas e incidentes formais (`M09-08`, `M09-10`) — aqui o watchdog apenas marca e loga.
- Cancelamento pela UI (`M02-10`).

## Domain Impact
**Entidade:** `inbox_events` para deduplicação de consumo.
**Invariante:** publicar duas vezes é aceitável; **processar** duas vezes com efeito duplicado não é.

## Application Layer
- **Commands:** `PublishPendingOutboxEvents`, `RecoverStalledOperations`.
- **Queries:** `PendingOutboxEvents`, `StalledOperations`.

## Async / Control Plane
Este é o mecanismo que sustenta a afirmação do doc 07 §9.2: “Se a fila perder uma mensagem, um sweep periódico encontra Operations sem lease válido e as reenfileira. A durabilidade do produto não pode depender exclusivamente do broker.” Como Solid Queue vive no mesmo PostgreSQL (SC-02), a garantia **não** relaxa: o sweep continua obrigatório, porque a falha coberta é de processamento e de lease, não só de broker.

## Observability Requirements
- Métricas base: profundidade da fila, idade do evento não publicado mais antigo, contagem de Operations recuperadas pelo sweep, contagem de `STALLED`.
- Cada recuperação registra por que a Operation foi considerada órfã.
- Meta do Anexo B §5: início da operação após enqueue com p95 ≤ 5 s sem saturação.

## Security Requirements
- O dispatcher não desserializa payload arbitrário; valida `schemaVersion` antes de publicar.
- Nenhum payload publicado contém secret.
- O sweep **não** pode “consertar” status manualmente: uma Operation `FAILED` exige nova tentativa auditada, nunca `UPDATE` direto de status (RB-03).

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Broker indisponível | Eventos acumulam no outbox; nada se perde; alerta por idade do evento mais antigo. |
| Mensagem perdida | Sweep encontra a Operation sem lease e reenfileira. |
| Evento publicado duas vezes | Consumidor idempotente via inbox/dedup; efeito lógico único. |
| Operation presa em `RUNNING` | Watchdog marca `STALLED` após o limiar, com diagnóstico. |
| Fila saturando continuamente | Backpressure na criação de operações não essenciais; nunca descartar trabalho. |
| Sweep concorrente com o worker legítimo | O lease e o fencing de `M01-15` impedem dupla aplicação; o sweep só reenfileira o que está sem lease **válido**. |

## Acceptance Criteria
1. Eventos do outbox são publicados após o commit e marcados com `publishedAt`.
2. Com o broker indisponível, nenhum evento é perdido e a idade do evento mais antigo é observável.
3. Uma Operation `QUEUED` cuja mensagem foi perdida é reenfileirada pelo sweep, provado por teste que descarta a mensagem deliberadamente.
4. Um evento publicado duas vezes produz efeito lógico único, garantido pelo inbox/dedup.
5. Uma Operation presa além do limiar é marcada `STALLED` com diagnóstico.
6. O sweep nunca altera status manualmente de uma Operation `FAILED`.
7. A saturação da fila produz backpressure, não perda de operação.
8. O dispatcher rejeita payload com `schemaVersion` desconhecida.
9. Nenhum payload publicado contém secret.
10. Métricas de profundidade de fila, idade do evento mais antigo e recuperações do sweep estão disponíveis.
11. O sweep é idempotente: duas execuções concorrentes não reenfileiram duas vezes a mesma Operation.

## Required Tests
- **unit**: seleção de eventos pendentes; detecção de Operation órfã; watchdog.
- **integration**: mensagem descartada e recuperada pelo sweep; broker indisponível sem perda; dedup de consumo; sweep concorrente idempotente.
- **security**: payload sem secret; recusa de `schemaVersion` desconhecida.

## Quality Gates
Local Quality Gate + suíte de integração com fault injection na fila.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, recuperação de mensagem descartada provada, dedup verificada, Critical/High = 0.
