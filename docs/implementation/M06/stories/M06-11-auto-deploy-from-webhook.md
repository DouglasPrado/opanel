# M06-11 — Auto-deploy from Git push

## Objective
Fechar o ciclo `git push → produção`, transformando o trigger verificado de `M05-04` em build e deployment, com as proteções de concorrência de `M06-10`.

## Outcome
Um push na branch configurada gera build e deploy automaticamente, respeitando `watchPaths`; um delivery duplicado não gera trabalho duplicado.

## References
- `docs/architecture/02-build-deploy.md` §5 (trigger Push), §3.2 (watch paths), §16 (webhook delivery id idempotente)
- `docs/architecture/10-ui-use-cases.md` UC-016
- `docs/annexes/A-implementation-roadmap.md` §9 (não criar auto-deploy antes de Operation idempotente)

## Preconditions
`M06-10` done. `M05-04` entregou a verificação e a dedup do webhook.

## Scope
- Consumo do trigger idempotente de `M05-04`.
- `autoDeploy` por Service (flag registrada em `M05-02`).
- `watchPaths`: se o commit não toca os caminhos observados, **não** disparar deploy.
- Coalescing de commits em rajada, conforme a política de supersession de `M06-10`.
- Registro do actor como `webhook`, com a identidade do delivery.
- Política opcional de cancelar/superar deploys ainda não iniciados quando um commit mais novo chega (doc 02 §16).

## Out of Scope
- Verificação de assinatura e dedup (`M05-04`).
- Preview environments por Pull Request (backlog).
- Deploy automático em produção sem gate — a policy de Environment (`M11-08`) decide; o default para `PRODUCTION` é **não** habilitar auto-deploy.

## Application Layer
- **Commands:** `ProcessDeploymentTrigger`.
- **Policies:** o auto-deploy respeita a permissão configurada para o Service/Environment; um webhook não ganha mais autoridade do que a configuração concede.

## Security Requirements
- O auto-deploy só é possível a partir de um webhook **verificado** (`M05-04`). Um webhook forjado não dispara nada — teste obrigatório.
- O actor registrado é o webhook, não um usuário — a atribuição precisa ser honesta na auditoria.
- Auto-deploy em `PRODUCTION` é **desabilitado por padrão**; habilitá-lo é decisão explícita e auditada.
- Um commit que altera a configuração de build não escapa das validações: o `buildConfigHash` muda e o build é refeito.
- Rate limit de deploys por Service protege contra rajada anômala (Anexo C §19, “Deploy spam”).

## Observability Requirements
Timeline mostrando: delivery recebido → trigger criado → build → deployment. Métrica de deploys por gatilho e de triggers ignorados por `watchPaths`.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Webhook duplicado | Nenhum deploy redundante fora da política. |
| Webhook fora de ordem | O commit mais novo prevalece; o antigo não sobrescreve. |
| Commit não toca `watchPaths` | Nenhum build/deploy; registrado como ignorado, com o motivo. |
| Rajada de commits | Coalescing; o último vence. |
| Build falha | Nenhum deployment; a release atual permanece. |
| Auto-deploy desabilitado | Trigger registrado e ignorado, com o motivo visível. |
| Webhook forjado | Rejeitado em `M05-04`; nada é disparado. |

## Acceptance Criteria
1. Um push verificado na branch configurada dispara build e deployment quando `autoDeploy` está habilitado.
2. Webhook duplicado **não** gera deploys redundantes, provado por teste.
3. Webhook fora de ordem não faz um commit antigo sobrescrever um mais novo.
4. Commit que não toca `watchPaths` não dispara build/deploy, e o motivo é registrado.
5. Rajada de commits é coalescida; o último vence.
6. Build falho não gera deployment; a release atual permanece.
7. Auto-deploy em `PRODUCTION` é desabilitado por padrão e habilitá-lo é auditado.
8. Um webhook forjado não dispara nada, provado por teste.
9. O actor registrado é o webhook, com a identidade do delivery.
10. Rate limit de deploys por Service é aplicado.
11. A timeline liga delivery → trigger → build → deployment.

## Required Tests
- **integration**: duplicado; fora de ordem; `watchPaths`; rajada; auto-deploy desabilitado.
- **security**: webhook forjado não dispara; rate limit.
- **E2E**: `git push` → build → deploy → `HEALTHY`.
- **policy**: auto-deploy em produção desabilitado por padrão.

## Quality Gates
Local Quality Gate + E2E + `bin/security`.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, E2E de push a healthy verde, duplicado e fora de ordem cobertos, Critical/High = 0.
