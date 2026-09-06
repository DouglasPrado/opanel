# M02-11 — Realtime updates over SSE with cursor-based reconnection

## Objective
Fazer a UI refletir o Control Plane em tempo quase real sem polling agressivo do Docker, entregando **eventos de produto sanitizados** — nunca payloads brutos do runtime.

## Outcome
A UI recebe atualização de operação e de status em ≤ 2 s após a persistência; a reconexão retoma por cursor; o polling de baixa frequência continua como fallback.

## References
- `docs/architecture/07-internal-control-plane.md` §18 (WebSocket/SSE e atualizações da UI)
- `docs/annexes/B-nfr-slos.md` §4 (atualização de status ≤ 2 s)
- `docs/annexes/D-test-strategy.md` §12 (realtime, logs e terminal)
- `docs/architecture/10-ui-use-cases.md` §24 (Operations Center)

## Preconditions
`M02-10` done.

## Scope
- Endpoint SSE entregando eventos de produto derivados do Control Plane.
- **Cursor / last-event-id**: reconexão retoma de onde parou, sem lacuna silenciosa.
- Eventos sanitizados: status de Operation, mudança de status de recurso, drift detectado, health degradado/recuperado.
- Fallback de polling de baixa frequência quando o stream não está disponível.
- Backpressure: cliente lento não derruba o worker nem faz a memória crescer sem limite.
- Limite de conexões por usuário/Team.
- Tolerância a evento duplicado no cliente: o estado da UI é idempotente.

## Out of Scope
- WebSocket bidirecional (só é necessário para terminal, `M09-14`).
- Streaming de logs (`M01-20` já entregou o seu caminho).
- Notificações externas (`M09-11`).

## API Impact
O navegador recebe **eventos de produto**, não payloads crus do Docker (doc 07 §18, regra explícita). O envelope é versionado.

## UI Impact
Operations Center e páginas de recurso atualizam ao vivo. Quando o stream cai, a UI **diz** que está em fallback, com o timestamp da última atualização — não finge estar ao vivo.

## Security Requirements
- Autorização avaliada **na abertura e continuamente**: perder membership durante a conexão encerra o stream.
- O stream só entrega eventos dos recursos que o usuário pode ler; nenhum vazamento cross-team, mesmo por inferência de contagem.
- Eventos passam por redaction; nenhum valor sensível trafega.
- Limite de conexões e backpressure como controle de abuso (Anexo C §19).

## Observability Requirements
- Métrica: conexões ativas, eventos entregues, reconexões, eventos perdidos por cursor inválido.
- Log de abertura/encerramento com `actor_id` e `request_id`.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Conexão cai | Reconexão por cursor; a UI indica a lacuna se o cursor expirou. |
| Cursor expirado | A UI faz uma leitura completa e diz que houve recarga, em vez de mostrar dado incompleto. |
| Cliente lento | Backpressure; conexão encerrada com motivo se necessário, sem derrubar o worker. |
| Membership revogado durante o stream | Stream encerrado imediatamente. |
| Evento duplicado | Estado da UI idempotente; nenhuma ação duplicada. |
| Stream indisponível | Fallback de polling com indicação explícita. |

## Acceptance Criteria
1. A UI recebe atualização em ≤ 2 s após a persistência, em condições normais.
2. A reconexão retoma por cursor sem lacuna silenciosa.
3. Cursor expirado provoca recarga completa **explicada** ao usuário.
4. O stream entrega apenas eventos de produto sanitizados; nenhum payload cru do Docker.
5. Nenhum evento de recurso fora do escopo do usuário é entregue, provado por teste cross-team.
6. Perder membership durante a conexão encerra o stream imediatamente.
7. Cliente lento não derruba o worker nem faz a memória crescer sem limite, provado por teste de backpressure.
8. O limite de conexões por usuário/Team é aplicado.
9. Evento duplicado não produz efeito duplicado na UI.
10. Sem o stream, o fallback de polling funciona e a UI indica que está em fallback.
11. Nenhum valor sensível trafega no stream, provado com valor plantado.

## Required Tests
- **unit (frontend)**: idempotência do estado ao receber evento duplicado.
- **integration**: reconexão por cursor; cursor expirado; backpressure; limite de conexões; revogação de membership durante o stream.
- **contract**: envelope de evento versionado.
- **policy**: nenhum evento cross-team entregue.
- **security**: redaction no stream.

## Quality Gates
Local Quality Gate + testes de realtime do Anexo D §12.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, reconexão por cursor e backpressure provados, isolamento cross-team verificado, Critical/High = 0.
