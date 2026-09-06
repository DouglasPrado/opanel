# M12-11 — Operations tools (rollout phase F4)

## Objective
Permitir que o agente participe da operação de infraestrutura — manutenção de nodes, backups, incidentes e planos de restore — sempre dentro dos guardrails que já existem.

## Outcome
O agente drena um worker após validar capacidade e obter aprovação, dispara um backup, opera incidentes e **gera** um plano de restore sem executá-lo.

## References
- `docs/annexes/F-mcp-platform-agents.md` §7.7 (cluster e nodes), §7.8 (incidentes), §7.9 (backup/restore), §21 (fase F4), §15 (MCP-15, MCP-16, MCP-17)
- `docs/annexes/E-operational-runbooks.md` RB-28

## Preconditions
`M12-10` done. M08, M09 e M10 aceitos para as respectivas capacidades.

## Scope
- `clusters.list/get`, `nodes.list/get`, `nodes.enrollment_create`, `nodes.drain/activate`, `nodes.promote/demote`, `nodes.remove`, `clusters.reconcile`.
- `backups.list/create`, `snapshots.create/get`.
- `restore.plan` — **gera plano, não executa**.
- `incidents.create/update/resolve`, `alerts.acknowledge`.
- Aplicação dos guardrails existentes: quorum, impacto de drain, capacidade, retenção.
- **Gate da fase F4**: chaos e DR testados antes de liberar.

## Out of Scope
- `restore.execute` (`M12-12`, fase F5).
- Exec (`M12-12`).
- `force remove` e operações de desastre.

## Application Layer
Reuso dos Commands de M08, M09 e M10.

## Security Requirements
- Operações de node são R2/R3: drain e promote exigem approval conforme a policy.
- **Os guardrails de quorum de `M08-05` valem integralmente**: o MCP não os contorna, e uma operação que comprometeria o quorum é bloqueada com o cálculo.
- O impacto do drain é apresentado ao agente e ao aprovador — as tasks bloqueadas não são escondidas.
- `nodes.enrollment_create` gera token de uso único e TTL curto; o token **não** é logado.
- `restore.plan` **não** muda estado; ele é R0/R1.
- `clusters.reconcile` dispara reconciliação/diagnóstico, **sem** comando Docker arbitrário (Anexo F §7.7, regra explícita).
- Incidentes de segurança têm acesso restrito, como em `M09-10`.

## Observability Requirements
Operações de infraestrutura iniciadas por agente identificadas com destaque no audit. Approvals exigidos por tool.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Drain que comprometeria o quorum | Bloqueado com o cálculo. |
| Drain com tasks bloqueadas | Impacto apresentado; não escondido. |
| `restore.execute` chamado nesta fase | Não existe aqui; pertence a F5. |
| Enrollment token logado | Impossível; teste guarda. |
| `clusters.reconcile` com comando arbitrário | Não existe caminho. |
| Backup em destino indisponível | `DEPENDENCY_UNAVAILABLE`. |

## Acceptance Criteria
1. As tools de operação do escopo existem e reutilizam os Commands de M08/M09/M10.
2. Drain, promote, demote e remove exigem approval conforme a policy.
3. **Guardrails de quorum são aplicados integralmente**; operação que os comprometeria é bloqueada com o cálculo, provado por teste.
4. O impacto do drain, incluindo tasks bloqueadas, é apresentado ao agente e ao aprovador.
5. `nodes.enrollment_create` gera token de uso único e TTL curto; o token **não** é logado.
6. `restore.plan` gera plano **sem** alterar estado.
7. `clusters.reconcile` dispara reconciliação/diagnóstico **sem** comando Docker arbitrário, verificado por teste.
8. `restore.execute` **não** está disponível nesta fase.
9. Incidentes de segurança têm acesso restrito.
10. Backup em destino indisponível retorna `DEPENDENCY_UNAVAILABLE`.
11. Operações de infraestrutura por agente são identificadas com destaque no audit.
12. Nenhuma lógica de operação vive no MCP.

## Required Tests
- **security**: guardrail de quorum; ausência de comando arbitrário; token não logado.
- **integration**: impacto de drain apresentado; `restore.plan` sem efeito; destino indisponível.
- **E2E**: MCP-15, MCP-16, MCP-17 do Anexo F §15.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, guardrails preservados pelo MCP, `restore.plan` sem efeito, Critical/High = 0.
