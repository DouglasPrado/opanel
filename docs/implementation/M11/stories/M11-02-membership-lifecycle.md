# M11-02 — Membership lifecycle: role change, suspend, remove

## Objective
Administrar quem pertence ao Team e com qual papel, preservando o histórico e garantindo que a perda de acesso seja imediata.

## Outcome
ADMIN altera papéis, suspende e remove membros; a suspensão tira o acesso na requisição seguinte; a auditoria permanece após a remoção.

## References
- `docs/architecture/04-identity-teams-security.md` §5 (roles e membership), §5.2 (lifecycle), §6.2 (matriz)
- `docs/architecture/10-ui-use-cases.md` §20.1 (members)
- `docs/annexes/C-threat-model-security-hardening.md` §7.2

## Preconditions
`M11-01` done.

## Scope
- Alteração de papel entre ADMIN, DEVELOPER e VIEWER.
- Suspensão e reativação.
- Remoção preservando a auditoria.
- Regras de proteção do OWNER: não pode ser removido, suspenso nem rebaixado sem transferência.
- Reavaliação de autorização a cada requisição: a sessão **não** concede acesso permanente.

## Out of Scope
- Transferência de ownership (`M11-03`).
- Permissões por Environment (`M11-08`).
- Convites (`M11-01`).

## Domain Impact
**Invariantes:** exatamente um OWNER ativo; OWNER não pode se auto-remover nem se rebaixar; `REMOVED` preserva histórico.

## Application Layer
- **Commands:** `ChangeMemberRole`, `SuspendMember`, `ReactivateMember`, `RemoveMember`.
- **Policies:** OWNER e ADMIN gerenciam membros; ADMIN **não** altera o OWNER.

## Security Requirements
- **Membership suspenso perde acesso imediatamente** (doc 04 §8.2): a autorização é revalidada a cada requisição; a sessão não é um passe permanente (Anexo C §7.2).
- ADMIN **não** pode alterar o papel do OWNER nem promover ninguém a OWNER.
- OWNER não pode ser removido nem suspenso sem que a ownership seja transferida — remover deixaria o Team sem dono.
- Se o OWNER for suspenso por procedimento de segurança, o Team entra em `OWNERSHIP_RECOVERY_REQUIRED` (doc 04 §3.2).
- Remoção preserva auditoria (doc 04 §5.2).
- Toda alteração gera AuditLog com papel anterior e novo.

## Observability Requirements
Lista de membros com papel, status e última atividade (privacy-aware). Histórico de alterações por membro.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| ADMIN tentando alterar o OWNER | Rejeitado. |
| Remover o OWNER | Rejeitado; exige transferência antes. |
| Suspender o OWNER | Team entra em `OWNERSHIP_RECOVERY_REQUIRED`. |
| Membro suspenso com sessão ativa | Próxima requisição negada. |
| Remover o último ADMIN | Permitido, mas avisado: reduz a capacidade de transferência futura. |
| Alteração concorrente de papel | Serializada; resultado final válido. |

## Acceptance Criteria
1. Papéis ADMIN, DEVELOPER e VIEWER são alteráveis por quem tem permissão.
2. ADMIN **não** consegue alterar o papel do OWNER nem promover a OWNER.
3. Remover o OWNER é rejeitado; a transferência é obrigatória antes.
4. Suspender o OWNER coloca o Team em `OWNERSHIP_RECOVERY_REQUIRED`.
5. Membro suspenso é negado na **requisição seguinte**, provado por teste com sessão ativa.
6. Remoção preserva a auditoria.
7. Remover o último ADMIN é permitido com aviso sobre a transferência futura.
8. Alterações concorrentes de papel são serializadas e produzem estado final válido.
9. Toda alteração gera AuditLog com papel anterior e novo.
10. A matriz do doc 04 §6.2 está coberta por teste.
11. Negativo cross-team passa.

## Required Tests
- **unit**: transições de status; proteções do OWNER.
- **integration (concorrente)**: alteração simultânea de papel; suspensão com sessão ativa.
- **policy**: matriz completa; ADMIN não altera OWNER; negativo cross-team.
- **security**: revalidação de autorização por requisição.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, perda de acesso imediata provada, proteções do OWNER verificadas, Critical/High = 0.
