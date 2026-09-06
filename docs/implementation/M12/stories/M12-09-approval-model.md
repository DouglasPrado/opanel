# M12-09 — Server-side approval model

## Objective
Exigir aprovação humana para ações de alto impacto, ligando a aprovação ao **digest da ação** — para que mudar os argumentos invalide o consentimento.

## Outcome
Uma tool R2/R3 retorna `APPROVAL_REQUIRED` com resumo, risco, expiração e URL; o humano aprova; o agente reapresenta a ação com o `approval_id` e ela executa.

## References
- `docs/annexes/F-mcp-platform-agents.md` §6 (approvals e ações destrutivas), §6.1 (níveis de risco), §6.2 (approval server-side), §6.3 (auto-approval controlado), §13.1 (approval é single-use e ligado ao digest)
- `docs/annexes/C-threat-model-security-hardening.md` §7.2

## Preconditions
`M12-08` done.

## Scope
- `ApprovalRequest`: id, actor, connectionId, action, target, `argumentsDigest`, summary, risk, expiresAt, status, approvedBy.
- Classificação de risco R0–R3 do Anexo F §6.1.
- Fluxo: tool retorna `APPROVAL_REQUIRED` → humano aprova na UI → agente consulta `approvals.get` → reapresenta com `approval_id`.
- **Digest binding**: o approval vale para **aqueles argumentos**; alterá-los invalida.
- **Uso único** e expiração.
- Auto-approval controlado apenas para ações explicitamente delimitadas de service accounts (Anexo F §6.3).

## Out of Scope
- Tools de delivery e operações (`M12-10`, `M12-11`), que consomem este modelo.
- Escalonamento de aprovadores.
- Aprovação por múltiplas pessoas (dual control) — evolução.

## Domain Impact
**Invariantes (Anexo F §13.1):** approval é **single-use** e ligado ao digest da ação; mudar argumentos invalida a aprovação.

## Application Layer
- **Commands:** `RequestApproval`, `GrantApproval`, `DenyApproval`.
- **Queries:** `PendingApprovals`, `ApprovalById`.

## Security Requirements
- **O digest binding é o controle central.** Sem ele, um agente poderia obter aprovação para uma ação benigna e executar outra — o clássico bait-and-switch.
- Approval é **single-use**: reutilizar é rejeitado.
- Expiração obrigatória; aprovação velha não vale.
- Quem aprova precisa ter permissão para **executar** a ação; aprovar não pode ser mais fácil do que fazer.
- O resumo mostrado ao humano descreve o efeito real, com recursos afetados e risco — aprovar às cegas é o mesmo que não aprovar.
- O resumo é **sanitizado**: ele pode conter texto vindo do agente e não pode induzir o aprovador.
- **Nunca existe um switch global “agent may do anything”** (Anexo F §6.3, regra explícita).
- Auto-approval é limitado a faixas explícitas e auditado.
- Toda aprovação e negação geram AuditLog com actor humano.

## Observability Requirements
`mcp_approval_required_total` por tool e ambiente; approvals pendentes, aprovados, negados e expirados.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Argumentos alterados após aprovação | Approval **inválido**; nova aprovação necessária. Teste obrigatório. |
| Approval reutilizado | Rejeitado. |
| Approval expirado | `APPROVAL_EXPIRED`; solicitar novo. |
| Aprovador sem permissão para a ação | Aprovação recusada. |
| Resumo com conteúdo enganoso | Sanitizado. |
| Auto-approval fora da faixa | Vira approval humano normal. |
| Agente tentando aprovar a si mesmo | Impossível: aprovação é ação humana na UI. |

## Acceptance Criteria
1. `ApprovalRequest` existe com os campos do Anexo F §13, incluindo `argumentsDigest`.
2. Ações R2/R3 retornam `APPROVAL_REQUIRED` com resumo, risco, expiração e URL.
3. **Alterar os argumentos invalida o approval**, provado por teste.
4. O approval é **single-use**; reutilizar é rejeitado.
5. Approval expirado retorna `APPROVAL_EXPIRED`.
6. Quem aprova precisa ter permissão para executar a ação.
7. O resumo descreve o efeito real, com recursos afetados e risco, e é **sanitizado**.
8. **Não existe switch global de auto-approval**, verificado por teste.
9. Auto-approval é limitado a faixas explícitas de service accounts e é auditado.
10. Fora da faixa, a ação vira approval humano normal.
11. O agente **não** consegue aprovar a própria ação.
12. Aprovações e negações geram AuditLog com o actor humano.

## Required Tests
- **security**: digest binding com argumentos alterados; reutilização; expiração; agente tentando aprovar; ausência de switch global.
- **policy**: aprovador sem permissão recusado.
- **integration**: fluxo completo `APPROVAL_REQUIRED` → aprovar → executar.
- **E2E**: MCP-07 e MCP-18 do Anexo F §15.

## Quality Gates
Local Quality Gate + `bin/security`. **Story crítica: exige plan mode.**

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, digest binding provado com bait-and-switch, ausência de bypass global verificada, Critical/High = 0.
