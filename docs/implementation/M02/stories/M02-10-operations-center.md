# M02-10 — Operations Center: visibility, cancellation and supersession

## Objective
Dar ao operador um lugar único para ver o que a plataforma está fazendo, por que uma operação está bloqueada, e cancelar quando for seguro.

## Outcome
O Operations Center lista operações running, failed e blocked com causa; cada uma abre uma timeline; o cancelamento é oferecido apenas quando a state machine permite.

## References
- `docs/architecture/10-ui-use-cases.md` §24 (Operations Center e notificações), §24.2 (toasts vs persistent)
- `docs/architecture/07-internal-control-plane.md` §16 (cancelamento e supersession), §17.2 (timeline)
- `docs/annexes/F-mcp-platform-agents.md` §9.3 (semântica de cancelamento, reaproveitada por M12)

## Preconditions
`M02-01` done.

## Scope
- Feed de operações por Team com filtros: estado, recurso, ator, período.
- Detalhe da Operation: tipo, recurso, revisão alvo, tentativas, erro normalizado, timeline com duração por etapa.
- **Cancelamento**: `PENDING`/`QUEUED` podem ser cancelados diretamente; `RUNNING` só quando a operação define ponto seguro de interrupção.
- **Supersession** visível: mostrar que a operação foi superada por uma revisão mais nova, com link para ela.
- Estado `BLOCKED` com a razão: dependência, lock, condição de runtime.
- Distinção do doc 10 §24.2: toast para aceite imediato, badge para progresso, notificação persistente para falha.

## Out of Scope
- Realtime por SSE (`M02-11`) — aqui a atualização é por navegação/polling.
- Notificações externas (`M09-11`).
- Incidentes (`M09-10`).
- Retentativa manual sofisticada — o botão de retry só existe onde é comprovadamente seguro.

## Application Layer
- **Commands:** `CancelOperation`.
- **Queries:** `OperationsFeed`, `OperationDetail`.
- **Policies:** ver operações exige membership; cancelar exige a permissão da operação original.

## Async / Control Plane
Cancelar é **pedir** cancelamento: a intenção é registrada e a state machine decide se o ponto atual é cancelável (doc 07 §16.1). Depois de uma mutação no Swarm, muitas operações precisam completar ou reconciliar até um estado consistente antes de aceitar outra intenção.

## API Impact
`POST /operations/:id/cancel` conceitual; `GET /operations/:id` com estado, steps, erro normalizado e timestamps.

## UI Impact
Item no header com contagem de operações ativas e falhas não reconhecidas. Nenhum botão “parece travado”: toda ação assíncrona tem estado observável (doc 10 §1).

## Security Requirements
- Ver e cancelar operações respeita tenancy: um usuário só vê operações dos recursos que pode ler.
- Cancelar exige a mesma permissão da operação original — cancelar um deploy não pode ser mais fácil do que fazê-lo.
- O erro exibido é o **normalizado**; detalhes internos não são expostos ao usuário (doc 09 §28).
- Cancelamento gera AuditLog.

## Observability Requirements
- Timeline com duração por etapa, reconstruível do histórico persistido.
- Motivo de bloqueio classificado e legível.
- Métrica: operações por estado, tempo em fila, tempo de execução.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Cancelamento de operação já terminal | Rejeitado com erro claro; sem efeito. |
| Cancelamento em ponto não interrompível | Registrado como intenção; a operação segue até o ponto seguro e então encerra. |
| Operação `BLOCKED` sem causa clara | É um defeito: toda razão de bloqueio precisa ser classificada. |
| Feed com muitas operações | Paginação por cursor; sem carregamento não paginado. |
| Erro interno na operação | Exibir o código estável e o `requestId`; nunca stack trace. |

## Acceptance Criteria
1. O feed lista operações running, failed e blocked com filtros e paginação por cursor.
2. O detalhe mostra tipo, recurso, revisão alvo, tentativas, erro normalizado e timeline com duração por etapa.
3. `PENDING`/`QUEUED` podem ser cancelados; a operação encerra sem efeito no runtime.
4. `RUNNING` só é cancelável no ponto seguro; fora dele o pedido é registrado e aplicado quando possível.
5. Cancelamento de operação terminal é rejeitado com erro claro.
6. Operações superadas aparecem como `SUPERSEDED` com link para a que as substituiu.
7. Toda operação `BLOCKED` apresenta razão classificada.
8. O usuário só vê operações dos recursos que pode ler, provado por teste cross-team.
9. Cancelar exige a mesma permissão da operação original.
10. Nenhum erro exibido contém stack trace, SQL ou caminho interno.
11. Cancelamento gera AuditLog.
12. A timeline é reconstruída do histórico persistido, não de estado volátil.

## Required Tests
- **unit**: elegibilidade de cancelamento por estado; classificação de razão de bloqueio.
- **integration**: cancelamento em cada estado; supersession exibida; timeline reconstruída após restart.
- **policy**: feed filtrado por tenancy; permissão de cancelamento.
- **E2E**: acompanhar uma operação até o fim pelo Operations Center.

## Quality Gates
Local Quality Gate + Reuse Gate para a UI.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, cancelamento coberto em todos os estados, timeline persistida, Critical/High = 0.
