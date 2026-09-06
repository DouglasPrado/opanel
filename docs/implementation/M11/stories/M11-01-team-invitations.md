# M11-01 — Team invitations

## Objective
Permitir trazer pessoas para o Team com um convite expirável, de uso único, e sem jamais conceder OWNER diretamente.

## Outcome
OWNER/ADMIN convida por e-mail e papel; o convidado aceita e vira membro ativo; o reenvio invalida o token anterior.

## References
- `docs/architecture/04-identity-teams-security.md` §5.2 (lifecycle do membership; convites expiram e são de uso único)
- `docs/architecture/09-data-model-apis-contracts.md` §3.2 (TeamInvitation)
- `docs/architecture/10-ui-use-cases.md` UC-041, §20.2

## Preconditions
M01 e M03 aceitos.

## Scope
- `TeamInvitation`: teamId, email, role, `tokenHash`, expiresAt, acceptedAt, invitedBy.
- Papéis convidáveis: ADMIN, DEVELOPER, VIEWER. **OWNER não é convidável.**
- Token expirável, de uso único, persistido apenas como hash.
- Reenvio **revoga** o token anterior.
- Aceite criando ou vinculando o usuário e ativando o membership.
- Uma invitation ativa por team/email.

## Out of Scope
- Ciclo de vida pós-aceite (`M11-02`).
- Transferência de ownership (`M11-03`).
- SSO e provisionamento automático (backlog).

## Domain Impact
**Invariante:** `OWNER` **nunca** é obtido por convite; a única via é a transferência de `M11-03` (doc 10 §20.2, regra explícita).

## Application Layer
- **Commands:** `InviteMember`, `ResendInvitation`, `RevokeInvitation`, `AcceptInvitation`.
- **Policies:** convidar exige OWNER ou ADMIN.

## Security Requirements
- Token **apenas como hash**; o valor bruto existe só no link enviado.
- Uso único e expiração curta o suficiente para limitar a janela de um link vazado.
- **Reenviar revoga o anterior** (doc 04 §5.2, regra explícita): dois links válidos dobram a superfície.
- Convidar como OWNER é **impossível**, verificado por teste.
- O aceite valida que o e-mail do convite corresponde ao usuário autenticado, ou vincula corretamente na criação.
- O convite não revela informação do Team a quem não aceitou.
- Rate limit no envio de convites, para não virar vetor de spam a partir do domínio da plataforma.
- Convidar, reenviar, revogar e aceitar geram AuditLog.

## Observability Requirements
Convites pendentes com data de expiração; convites expirados visíveis. Métrica de convites por resultado.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Convite expirado | Rejeitado; reenviar gera novo token e invalida o anterior. |
| Token reutilizado | Rejeitado. |
| E-mail já é membro ativo | Oferecer alterar papel em vez de convidar (doc 10 UC-041). |
| Tentativa de convidar como OWNER | Rejeitada. |
| Aceite por usuário diferente do e-mail convidado | Rejeitado ou vinculado conforme a política, nunca ambíguo. |
| Muitos convites em sequência | Rate limit. |

## Acceptance Criteria
1. OWNER/ADMIN convida informando e-mail e papel não-OWNER.
2. **Convidar como OWNER é impossível**, provado por teste.
3. O token é persistido apenas como hash.
4. O convite expira e é de uso único.
5. Reenviar **revoga** o token anterior, provado por teste.
6. E-mail que já é membro ativo leva a oferecer alteração de papel.
7. Existe no máximo uma invitation ativa por team/email.
8. Aceite por usuário diferente do convidado tem comportamento definido e não ambíguo.
9. O convite não revela informação do Team antes do aceite.
10. Rate limit no envio é aplicado.
11. Convidar, reenviar, revogar e aceitar geram AuditLog; negativo cross-team passa.

## Required Tests
- **unit**: geração e hash do token; expiração; papéis convidáveis.
- **integration**: reenvio revogando; token reutilizado; uma invitation ativa por email.
- **security**: convite como OWNER rejeitado; token só em hash; rate limit; ausência de vazamento pré-aceite.
- **policy**: negativo cross-team.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, impossibilidade de convidar OWNER provada, reenvio revogando verificado, Critical/High = 0.
