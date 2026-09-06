# M01-15 — Resource locks, leases and fencing tokens

## Objective
Serializar mutações sobre o mesmo recurso e impedir que um worker atrasado aplique um resultado obsoleto depois de perder o lease.

## Outcome
Duas operações mutantes no mesmo Service não executam concorrentemente; um worker cujo lease expirou **não consegue** commitar resultado, porque o fencing token avançou.

## References
- `docs/architecture/07-internal-control-plane.md` §2.3 (execução ativa e redundância), §14 (locks e leases)
- `docs/annexes/D-test-strategy.md` §18 (concorrência, idempotência e falhas distribuídas)
- `docs/annexes/C-threat-model-security-hardening.md` §16 (stale worker)
- `docs/annexes/I-engineering-playbook-quality-gates.md` §5 (Lease + Fencing: quando usar)

## Preconditions
`M01-13` done.

## Scope
- `resource_locks`: scopeKey, owner, leaseUntil, fencingToken (monotônico), timestamps.
- Escopos do doc 07 §14.1 aplicáveis a M01: **Resource Lock** por `serviceId`, `nodeId` e `networkId`; **Cluster Lock** por `clusterId` para operação global.
- Aquisição com TTL, heartbeat de renovação durante a execução, e liberação **apenas após persistir o resultado da tentativa**.
- Fencing token monotônico: quem aplica precisa apresentar o token; um token menor que o atual é **rejeitado**.
- Retomada após expiração: o sucessor sempre **revalida o actual state antes de agir**.
- Política do doc 07 §2.3: leituras podem ser concorrentes; mutação de um Service é serial.

## Out of Scope
- Build slots e deployment slots (`M05`, `M06`).
- Locks distribuídos entre clusters (M08+).
- Cancelamento de operação em execução (`M02-10`).

## Domain Impact
**Entidade:** `resource_locks`.
**Invariante:** um recurso mutável tem no máximo uma operação mutante ativa. A garantia é do banco (constraint + TTL), não de coordenação em memória.

## Async / Control Plane
Sem esta Story, o Outbox e o sweep de `M01-14` criam um risco real: um worker considerado morto pode voltar e aplicar um efeito obsoleto. O fencing token é o que torna a recuperação segura — é a diferença entre “reenfileirar” e “aplicar duas vezes”.

## Security Requirements
- O lease impede que um executor atrasado mute infraestrutura com base em decisão obsoleta — é um controle de **integridade**, não apenas de performance (Anexo C §16, “Stale worker”).
- O owner do lock é uma identidade de worker, não um valor fornecido pelo cliente.
- Nenhuma operação privilegiada é aplicada sem lease válido; o teste comprova o caminho negativo.

## Observability Requirements
- Cada aquisição, renovação, expiração e liberação registra `scopeKey`, `owner`, `fencingToken` e `operationId`.
- Lock órfão detectado pelo sweep é registrado com a razão.
- Métrica: tempo médio de espera por lock e número de expirações.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Worker morre durante a execução | O lease expira; o sucessor observa o actual state antes de agir. |
| Worker atrasado volta e tenta commitar | Fencing token menor → **rejeitado**. Este é o teste central da Story. |
| Duas operações no mesmo Service | Serializadas; a mais nova pode virar `SUPERSEDED`. |
| Heartbeat falha por lentidão de rede | O lease expira e outro worker assume; o antigo é fenced ao voltar. |
| Lock nunca liberado por bug | TTL garante liberação; o sweep registra a ocorrência. |

## Acceptance Criteria
1. Uma mutação sobre um Service só executa com lease válido.
2. Duas mutações concorrentes no mesmo Service são serializadas ou a mais antiga vira `SUPERSEDED`, provado por teste concorrente com barreira.
3. O fencing token é monotônico por escopo.
4. Um worker com lease expirado **não** consegue persistir resultado: o token menor é rejeitado. Teste obrigatório.
5. O lease é liberado **somente após** persistir o resultado da tentativa.
6. Um worker que assume após expiração **revalida o actual state antes de agir**, provado por teste.
7. O TTL garante liberação mesmo quando o worker some sem liberar.
8. Leituras concorrentes não são bloqueadas por locks de mutação.
9. Aquisição, renovação, expiração e liberação são observáveis com `scopeKey`, `owner` e `fencingToken`.
10. O owner do lock não pode ser fornecido pelo cliente.

## Required Tests
- **unit**: monotonicidade do fencing token; cálculo de TTL e expiração com relógio controlado.
- **integration (PostgreSQL real, concorrente)**: serialização de duas mutações; **worker fenced após expiração**; TTL liberando lock órfão; revalidação do actual state pelo sucessor.
- **security**: operação privilegiada sem lease válido é rejeitada; owner não é aceito do cliente.

## Quality Gates
Local Quality Gate + suíte de concorrência com barreiras explícitas (nunca “tentar várias vezes até acontecer”, Anexo D §18).

## Definition of Done
Os 10 Acceptance Criteria satisfeitos, teste de fencing verde e determinístico, revalidação do sucessor comprovada, Critical/High = 0.
