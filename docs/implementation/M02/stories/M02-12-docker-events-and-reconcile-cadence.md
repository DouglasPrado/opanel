# M02-12 — Docker Events as reconcile accelerator, sweeps as the guarantee

## Objective
Usar o stream de eventos do Docker para reagir rápido, **sem** transformá-lo em ledger — a corretude continua vindo de reler o estado.

## Outcome
Uma Task que falha dispara reconcile em segundos; com o stream desligado, o sweep periódico ainda converge o recurso. Os dois caminhos são testados.

## References
- `docs/architecture/07-internal-control-plane.md` §11.2 (event-driven + periodic), §23 (reconciliation cadence)
- `docs/architecture/03-runtime-observability.md` §11 (eventos de runtime)
- `docs/annexes/D-test-strategy.md` §7 (Events: consume, reconnect, duplicate/replay, resync)
- `docs/annexes/B-nfr-slos.md` §5 (detecção de evento Docker p95 ≤ 3 s; drift por sweep ≤ 60 s)

## Preconditions
`M02-06` done.

## Scope
- Consumo do stream de Docker Events pelo Executor, com reconexão e resync após queda.
- Mapeamento para eventos de produto do doc 03 §11: `TASK_STARTED`, `TASK_FAILED`, `SERVICE_CONVERGED`, `NODE_DOWN`, `OOM_DETECTED`, `HEALTH_DEGRADED`, `RECOVERED`.
- Evento **dispara** reconcile do recurso afetado; não altera estado diretamente.
- Cadência de sweep por objeto conforme doc 07 §23: Service em rollout em segundos, estável em minutos; Node curto em manutenção, regular em readiness.
- Deduplicação e tolerância a replay.
- **Resync obrigatório após reconexão**: eventos perdidos durante a queda não podem deixar o sistema divergente.

## Out of Scope
- Timeline de eventos para o usuário final (`M09-07`).
- Alertas baseados em eventos (`M09-08`).
- Eventos de build (`M05-14`) e de edge (`M04-13`).

## Async / Control Plane
Esta Story materializa a regra normativa do doc 07 §11.2: **“A corretude vem de reler o estado, não de confiar em um stream ininterrupto de eventos.”** O teste que prova isso — reconciliar com o stream desligado — é critério de saída do Milestone.

## Security Requirements
- O stream de eventos vem do Docker via Executor; nenhum outro componente o consome.
- Payload de evento do Docker é **dado não confiável**: validado e normalizado antes de virar evento de produto.
- Nenhum conteúdo de evento é interpretado como comando.
- Eventos não carregam valor sensível para o pipeline de produto.

## Observability Requirements
- Métrica: latência entre evento Docker e início do reconcile; reconexões do stream; eventos descartados por duplicidade.
- Estado do consumidor de eventos visível na triagem operacional (RB kit universal, Anexo E §2.3: “Executor: event stream connectivity”).

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Stream de eventos cai | Reconecta e faz **resync**; o sweep garante convergência no intervalo. |
| Evento duplicado | Deduplicado; reconcile idempotente absorve a repetição. |
| Evento fora de ordem | O reconcile relê o estado; ordem do evento não determina o resultado. |
| Flood de eventos | Coalescing por recurso; não enfileirar um reconcile por evento. |
| Docker indisponível | Consumidor marcado como degradado; o sweep continua tentando e o estado é reportado. |
| Evento com payload inesperado | Descartado com log; nunca desserializado às cegas. |

## Acceptance Criteria
1. Eventos do Docker são consumidos pelo Executor e disparam reconcile do recurso afetado.
2. A latência entre evento e início do reconcile fica dentro do limiar configurado.
3. **Com o stream desligado, o sweep periódico converge o recurso** — teste obrigatório e critério de saída do Milestone.
4. Após queda e reconexão, o resync corrige o que foi perdido.
5. Evento duplicado não produz efeito duplicado.
6. Evento fora de ordem não altera o resultado, porque o reconcile relê o estado.
7. Flood de eventos é coalescido por recurso, sem enfileirar um reconcile por evento.
8. Evento com payload inesperado é descartado com log, nunca desserializado às cegas.
9. A cadência de sweep é diferenciada por objeto e por situação (rollout vs estável).
10. O estado de conectividade do stream é observável para triagem.
11. Nenhum componente fora do Executor consome o stream do Docker.

## Required Tests
- **unit**: normalização de evento; coalescing; deduplicação.
- **integration**: resync após reconexão; flood coalescido; payload inesperado descartado.
- **Docker/Swarm**: **reconcile com stream desligado**; evento real de Task falhando disparando reconcile; queda e reconexão do stream.
- **security**: payload de evento tratado como não confiável; AF-02 (só o Executor consome).

## Quality Gates
Local Quality Gate + suíte Docker/Swarm com fault injection no stream.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, convergência **sem** eventos comprovada, resync após reconexão verificado, Critical/High = 0.
