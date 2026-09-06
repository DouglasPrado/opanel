# M03-04 — Step-up authentication for high-impact actions

## Objective
Exigir comprovação de identidade **recente** antes de ações de alto impacto, mesmo quando o usuário já está autenticado.

## Outcome
Existe um mecanismo de reautenticação com validade curta; as ações críticas o exigem; a UI conduz o fluxo sem perder o contexto da operação.

## References
- `docs/architecture/04-identity-teams-security.md` §8.3 (step-up authentication)
- `docs/annexes/C-threat-model-security-hardening.md` §7.2 (ações privilegiadas), §12 (reveal)
- `docs/architecture/10-ui-use-cases.md` §26 (ações destrutivas e confirmações)

## Preconditions
M02 aceito. Independente das demais Stories de M03.

## Scope
- Mecanismo de step-up: reautenticação por senha, com **contrato preparado** para aceitar MFA/passkey quando `M11-05` existir.
- Validade curta e configurável do step-up, por ação e por sessão.
- Marcação declarativa de quais ações exigem step-up; a exigência é **do backend**, não da UI.
- Lista inicial (doc 04 §8.3): rotacionar/gerar Recovery Key, revelar secret sensível, transferir ownership, excluir Cluster/Team/recurso persistente de produção, criar token de API privilegiado, alterar MFA/credenciais críticas.
- UI que conduz o step-up preservando o contexto da operação pendente.

## Out of Scope
- MFA/TOTP em si (`M11-05`) — aqui apenas o contrato que o aceitará.
- Transferência de ownership (`M11-03`) e tokens de API (`M11-07`) — declaram a exigência quando existirem.
- Reautenticação contínua / risco adaptativo — sem requisito.

## Application Layer
- **Commands:** `RequestStepUp`, `VerifyStepUp`.
- Middleware/Policy: uma ação marcada como step-up **falha** se o token de step-up estiver ausente ou expirado, mesmo com sessão válida.

## Security Requirements
- A exigência é avaliada **no backend**. Esconder o botão na UI não é controle (Anexo C §7.2).
- Step-up expirado exige nova comprovação; não há renovação silenciosa.
- O comprovante de step-up é vinculado à sessão e **não** é transferível entre sessões ou usuários.
- Falha de step-up é auditada como `DENIED`.
- Rate limit no step-up, com o mesmo cuidado do login: falha não revela informação útil.
- A senha usada no step-up nunca é logada nem reutilizada como token.

## Observability Requirements
AuditLog para step-up bem-sucedido e falho, com actor, ação alvo e resultado — sem credencial.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Step-up ausente em ação que o exige | Ação rejeitada pelo backend, mesmo com sessão válida. |
| Step-up expirado | Exigido novamente; a operação pendente é preservada. |
| Comprovante de outra sessão | Rejeitado. |
| Tentativas repetidas | Rate limit; auditado. |
| Sessão revogada durante o fluxo | Step-up e operação invalidados. |
| Ação nova esquecendo de declarar step-up | Detectada por teste: a lista de ações críticas é verificada contra a marcação. |

## Acceptance Criteria
1. Existe um mecanismo de step-up com validade curta e configurável.
2. Ações marcadas como críticas são rejeitadas **no backend** sem step-up válido, mesmo com sessão ativa.
3. Step-up expirado exige nova comprovação, preservando a operação pendente.
4. O comprovante é vinculado à sessão e não é transferível, provado por teste.
5. Rate limit é aplicado e a falha não revela informação útil.
6. Falha e sucesso de step-up geram AuditLog.
7. A senha usada no step-up não é logada nem vira token reutilizável.
8. Revogar a sessão invalida o step-up.
9. O contrato aceita um segundo fator adicional sem alteração de assinatura, preparado para `M11-05`.
10. Um teste verifica que toda ação da lista crítica está marcada como exigindo step-up.

## Required Tests
- **unit**: validade e expiração; vinculação à sessão.
- **integration**: ação crítica sem step-up rejeitada; expiração; revogação de sessão; rate limit.
- **policy/security**: comprovante de outra sessão rejeitado; lista de ações críticas verificada.
- **E2E**: fluxo de step-up preservando o contexto.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 10 Acceptance Criteria satisfeitos, exigência avaliada no backend comprovada, cobertura da lista crítica verificada, Critical/High = 0.
