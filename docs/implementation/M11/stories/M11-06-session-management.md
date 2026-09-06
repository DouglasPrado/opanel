# M11-06 — Session management and remote revocation

## Objective
Dar ao usuário visibilidade e controle sobre onde sua conta está autenticada, e garantir que a revogação tenha efeito imediato.

## Outcome
O usuário lista suas sessões com device e última atividade, revoga individualmente ou todas, e a sessão revogada para de funcionar na requisição seguinte.

## References
- `docs/architecture/04-identity-teams-security.md` §8.2 (sessões), §8.3
- `docs/architecture/10-ui-use-cases.md` §21.1 (active sessions)
- `docs/annexes/C-threat-model-security-hardening.md` §7.1

## Preconditions
`M11-05` done.

## Scope
- Lista de sessões com device metadata, IP aproximado, criação e última atividade.
- Revogação individual e “revogar todas as outras”.
- Revogação com efeito **imediato** na requisição seguinte.
- Invalidação de sessões após mudança de senha, MFA ou recuperação, conforme política.
- Recuperação de senha por e-mail, com token expirável e de uso único.
- `mfaLevel` registrado na sessão, alimentando o step-up.

## Out of Scope
- Sessões de API tokens (`M11-07`) — identidade separada.
- Detecção de anomalia de login (backlog).
- Sessões de agentes MCP (`M12-04`).

## Application Layer
- **Commands:** `RevokeSession`, `RevokeAllOtherSessions`, `RequestPasswordReset`, `ResetPassword`.
- **Queries:** `MySessions`.

## Security Requirements
- **Revogação imediata**: a autorização é revalidada a cada requisição; a sessão não é um passe permanente (Anexo C §7.1).
- Token de recuperação de senha: expirável, de uso único, apenas hash persistido, e a resposta **não** revela se o e-mail existe.
- Mudança de senha invalida as demais sessões conforme a política.
- Alterar MFA invalida sessões conforme a política.
- O device metadata exibido respeita privacidade e não expõe mais do que o necessário.
- Rate limit na recuperação de senha.
- Revogação e reset geram AuditLog.

## Observability Requirements
Sessões ativas por usuário; revogações registradas. Uma sequência anormal de resets é sinal relevante.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Sessão revogada em outro device | Próxima requisição negada. |
| Token de reset reutilizado | Rejeitado. |
| Token de reset expirado | Rejeitado; novo pedido necessário. |
| E-mail inexistente no reset | Resposta indistinguível de e-mail existente. |
| Revogar a própria sessão atual | Permitido, com logout imediato e aviso. |
| Muitos pedidos de reset | Rate limit. |

## Acceptance Criteria
1. O usuário lista suas sessões com device, última atividade e criação.
2. A revogação individual e a de “todas as outras” funcionam.
3. Sessão revogada é negada na **requisição seguinte**, provado por teste.
4. Mudança de senha invalida as demais sessões conforme a política.
5. Alterar MFA invalida sessões conforme a política.
6. O token de reset é expirável, de uso único e persistido apenas como hash.
7. A resposta do reset **não** revela se o e-mail existe.
8. Rate limit é aplicado na recuperação de senha.
9. Revogar a própria sessão faz logout imediato com aviso.
10. `mfaLevel` é registrado na sessão e alimenta o step-up.
11. Revogação e reset geram AuditLog.
12. O device metadata exibido respeita privacidade.

## Required Tests
- **integration**: revogação com efeito imediato; reset com token expirado/reutilizado; invalidação por mudança de senha.
- **security**: resposta indistinguível no reset; token só em hash; rate limit.
- **unit**: cálculo de `mfaLevel`.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, revogação imediata provada, enumeração de e-mail impedida, Critical/High = 0.
