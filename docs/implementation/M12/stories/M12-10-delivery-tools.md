# M12-10 — Delivery tools (rollout phase F3)

## Objective
Permitir que o agente execute o ciclo de entrega — deploy, rollback, promoção, domínios e binding de secrets — com a política de produção e os approvals aplicados.

## Outcome
O agente promove uma release para produção; a policy exige aprovação; após o consentimento humano, a Operation executa e ele acompanha até o estado terminal.

## References
- `docs/annexes/F-mcp-platform-agents.md` §7.3 (deploy, rollback, scale), §7.4 (releases.promote), §7.5 (domains e TLS), §7.6 (secrets), §21 (fase F3), §16.2 (jornada de promoção)
- `docs/architecture/02-build-deploy.md` §15 (promoção reutiliza o mesmo digest)

## Preconditions
`M12-09` done. M06 e M07 aceitos.

## Scope
- `services.deploy`, `services.redeploy`, `services.rollback`, `releases.promote`.
- `domains.add/verify/remove`, `certificates.status/renew`, `routes.list/update`.
- `secrets.promote_version`, `secrets.rotate`, `secrets.unbind`.
- Aplicação da política de produção: R2/R3 conforme o ambiente e a configuração.
- **Gate da fase F3**: approvals e production policy funcionando.

## Out of Scope
- Operações de cluster (`M12-11`).
- Reveal e exec (`M12-12`).
- Criação de release fora do fluxo normal.

## Application Layer
Reuso integral dos Commands de M06 e M07. Nenhuma lógica de deploy vive no MCP.

## Security Requirements
- **Deploy e rollback preservam artifact/release por digest imutável** (Anexo F §22, AC-MCP-07): o agente não pode implantar por tag mutável.
- **Promoção não rebuilda** — a regra de `M06-09` vale igualmente pelo MCP.
- Ações em produção são R2/R3 e exigem approval conforme a policy.
- `secrets.promote_version` e `rotate` alteram binding **sem** revelar plaintext.
- Domínios exigem posse verificada (`M07-06`) — o agente não contorna isso.
- Erros retornam estruturados e **não induzem o agente a bypass operacional**.
- Toda ação registra ator humano, conexão, tool, approval e Operation.

## Observability Requirements
Operations iniciadas por agente identificadas; approvals exigidos por tool e ambiente; correlação `trace_id` → Operation.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Deploy em produção sem approval | `APPROVAL_REQUIRED`. |
| Promoção com digest divergente | Bloqueada por `M06-09`. |
| Domínio sem posse verificada | Bloqueado por `M07-06`. |
| Rollback com artifact coletado | Bloqueado com a razão de retenção. |
| Operação concorrente | `OPERATION_IN_PROGRESS`. |
| Provider indisponível | `DEPENDENCY_UNAVAILABLE`; sem sugerir contorno. |

## Acceptance Criteria
1. As tools de delivery do escopo existem e reutilizam os Commands de M06/M07.
2. Deploy e rollback operam **por digest imutável**.
3. Promoção pelo MCP **não** rebuilda e usa o mesmo digest, provado por teste.
4. Ações em produção exigem approval conforme a policy, retornando `APPROVAL_REQUIRED`.
5. `secrets.promote_version` e `rotate` alteram binding **sem** revelar plaintext.
6. Domínios exigem posse verificada; o agente não contorna.
7. Rollback com artifact coletado é bloqueado com a razão de retenção.
8. Operação concorrente retorna `OPERATION_IN_PROGRESS`.
9. Provider indisponível retorna `DEPENDENCY_UNAVAILABLE` **sem** sugerir contorno.
10. Toda ação registra ator humano, conexão, tool, approval e Operation.
11. Toda mutação assíncrona retorna `operationId` e é acompanhável até o estado terminal.
12. Nenhuma lógica de deploy vive no MCP.

## Required Tests
- **security**: deploy por tag rejeitado; promoção sem rebuild; produção exigindo approval; posse de domínio exigida.
- **integration**: rollback bloqueado por retenção; operação concorrente; provider indisponível.
- **E2E**: MCP-06, MCP-07, MCP-08, MCP-10 do Anexo F §15.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, promoção sem rebuild e approvals provados, Critical/High = 0.
