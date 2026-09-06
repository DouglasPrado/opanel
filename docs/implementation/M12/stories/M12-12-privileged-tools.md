# M12-12 — Privileged tools (rollout phase F5)

## Objective
Liberar, com o máximo de fricção deliberada, as capacidades de maior risco — restore execute, transferência de ownership, reveal e exec — todas **desabilitadas por padrão**.

## Outcome
Cada capability privilegiada exige habilitação explícita, approval R3, step-up e auditoria; nenhuma entra em preset comum.

## References
- `docs/annexes/F-mcp-platform-agents.md` §7.3 (`runtime.exec`, `runtime.terminal_create`), §7.6 (`secrets.reveal`), §7.9 (`restore.execute`, `ownership.transfer`), §13.1 (nunca em presets comuns), §17.3 (terminal e exec), §21 (fase F5), §22 (AC-MCP-10)
- `docs/annexes/C-threat-model-security-hardening.md` §15, T10

## Preconditions
`M12-11` done. `M09-14` (terminal) e `M10-11` (restore) aceitos.

## Scope
- `restore.execute` — R3, approval humano obrigatório.
- `ownership.transfer` — R3, step-up, reutilizando `M11-03`.
- `secrets.reveal` — **desabilitada por padrão**, R3, step-up, TTL mínimo, auditada.
- `runtime.exec` e `runtime.terminal_create` — **desabilitadas por padrão** para MCP.
- `instance.status`, `instance.upgrade_plan`, `instance.upgrade_execute` — R3.
- `members.*`, `audit.search`, `providers.list/test`.
- Habilitação por conexão, explícita, auditada e revogável.
- **Gate da fase F5**: step-up, approval R3 e **revisão de segurança específica**.

## Out of Scope
- Habilitar essas capabilities por padrão em qualquer preset — proibido.
- Transferência de arquivo por exec.
- Shell do host — nunca.

## Security Requirements
Esta é a Story de maior risco do Milestone:
- **`secret:reveal` e `runtime.exec` desabilitados por padrão** (Anexo F §22, AC-MCP-10, regra explícita).
- **Nunca entram em presets comuns** (Anexo F §13.1).
- Habilitar exige ação explícita do usuário na conexão, com aviso, e é auditado.
- `runtime.exec` é o maior amplificador de risco porque aproxima o agente de código arbitrário (Anexo F §17.3): TTL curto, audit de sessão, resource boundary e **bloqueio para managers e containers do control plane**.
- Todas as ações R3 exigem approval humano com digest binding e step-up quando aplicável.
- `secrets.reveal` herda todas as restrições de `M03-09`, incluindo a política por Environment.
- `ownership.transfer` herda as invariantes de `M11-03`, incluindo a atomicidade e o alvo ADMIN.
- Revogar a conexão remove imediatamente essas capabilities.

## Observability Requirements
Uso de capability privilegiada com destaque no audit e na UI de segurança. Uma única chamada de `runtime.exec` por MCP é evento notável.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Capability não habilitada | Tool ausente do catálogo ou negada com a razão. |
| Preset comum tentando incluí-la | Rejeitado. |
| `runtime.exec` em container do control plane | Bloqueado. |
| Approval R3 ausente | `APPROVAL_REQUIRED`. |
| Step-up ausente | Negado. |
| Conexão revogada | Capability some imediatamente. |
| `restore.execute` sem plano aprovado | Bloqueado. |

## Acceptance Criteria
1. `secrets.reveal`, `runtime.exec` e `runtime.terminal_create` estão **desabilitadas por padrão**, provado por teste.
2. Nenhum preset comum as inclui; a tentativa é rejeitada.
3. Habilitar exige ação explícita na conexão, com aviso, e é auditado.
4. Todas as ações R3 exigem approval humano com digest binding.
5. Step-up é exigido quando aplicável.
6. `runtime.exec` respeita TTL curto, resource boundary e audit de sessão.
7. `runtime.exec` é **bloqueado** para managers e containers do control plane.
8. **Nenhum caminho expõe shell do host.**
9. `secrets.reveal` herda todas as restrições de `M03-09`, incluindo política por Environment.
10. `ownership.transfer` herda as invariantes de `M11-03`.
11. `restore.execute` exige plano aprovado.
12. Revogar a conexão remove as capabilities imediatamente.
13. O uso de capability privilegiada aparece com destaque no audit e na UI de segurança.

## Required Tests
- **security**: capabilities off por padrão; ausência em presets; exec bloqueado em control plane; shell do host inacessível; step-up e approval exigidos.
- **integration**: revogação removendo capability; `restore.execute` sem plano.
- **policy**: herança das restrições de `M03-09` e `M11-03`.
- **E2E**: MCP-18 e MCP-19 do Anexo F §15.

## Quality Gates
Local Quality Gate + `bin/security`. **Story crítica: exige plan mode e revisão de segurança específica no Exit Gate.**

## Definition of Done
Os 13 Acceptance Criteria satisfeitos, capabilities off por padrão provadas, exec bloqueado no control plane, Critical/High = 0.
