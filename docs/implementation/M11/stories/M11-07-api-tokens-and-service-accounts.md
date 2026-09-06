# M11-07 — API tokens, service accounts and deploy tokens

## Objective
Separar credenciais de automação de sessões humanas, com escopo, expiração e revogação — para que um pipeline nunca reutilize a sessão de uma pessoa.

## Outcome
O Team emite tokens com escopo definido; o valor aparece **uma única vez**; o banco guarda apenas o hash; revogar tem efeito imediato.

## References
- `docs/architecture/04-identity-teams-security.md` §9 (API tokens e identidades de automação)
- `docs/architecture/09-data-model-apis-contracts.md` §15.3 (ApiToken)
- `docs/annexes/B-nfr-slos.md` §13 (armazenar somente hash; mostrar token completo uma vez)
- `docs/annexes/C-threat-model-security-hardening.md` T-token vazado

## Preconditions
`M11-05` done.

## Scope
- Tipos do doc 04 §9: Personal Access Token, Service Account, Deploy Token, Webhook Secret e Registry Credential — cada um com seu propósito.
- `ApiToken`: teamId/userId, name, `tokenHash`, scopes, expiresAt, lastUsedAt, revokedAt, prefixo visível.
- Exibição do valor **apenas** no momento da criação.
- Escopos validados contra uma lista conhecida.
- Expiração recomendada e revogação imediata.
- Prefixo/últimos caracteres para identificação sem guardar plaintext.
- Criar token privilegiado exige step-up.

## Out of Scope
- OAuth do MCP (`M12-01`) — mecanismo distinto que reutiliza os escopos.
- Rotação automática de token.
- Federação de identidade.

## Application Layer
- **Commands:** `CreateApiToken`, `RevokeApiToken`, `CreateServiceAccount`.
- **Queries:** `TokensForTeam`.
- **Policies:** criar token privilegiado exige step-up (doc 04 §8.3).

## Security Requirements
- **Somente hash no banco** (Anexo B §13, regra explícita); o valor é exibido uma única vez.
- Prefixo e últimos caracteres permitem identificar sem guardar plaintext (doc 04 §9).
- Token expirado ou revogado é **rejeitado mesmo existindo fisicamente** (doc 04 §9, regra explícita).
- Escopos mínimos e validados; um escopo desconhecido é rejeitado.
- Um token **não** pode ter escopo maior que o do ator que o criou.
- `lastUsedAt` registrado, para detectar tokens ociosos e para investigação após vazamento.
- Criar token privilegiado exige step-up.
- Comparação de token em tempo constante.
- Rate limit por token.
- Criação e revogação geram AuditLog.

## Observability Requirements
Tokens ativos com escopo, criação, expiração e último uso. Tokens sem uso recente sinalizados. Uso de token revogado registrado — é sinal de vazamento.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Token revogado usado | Rejeitado e **registrado** como sinal. |
| Token expirado | Rejeitado. |
| Escopo desconhecido | Rejeitado na criação. |
| Escopo maior que o do criador | Rejeitado. |
| Token exibido novamente | Impossível: só o hash existe. |
| Token vazado | Revogação imediata; `lastUsedAt` e audit permitem reconstruir o uso (RB-20). |

## Acceptance Criteria
1. Os tipos de credencial do doc 04 §9 existem com propósitos distintos.
2. O valor do token é exibido **uma única vez**; o banco guarda apenas o hash, provado por inspeção.
3. Não existe caminho para exibir o token novamente.
4. Prefixo e últimos caracteres permitem identificação sem plaintext.
5. Token expirado ou revogado é rejeitado **mesmo existindo fisicamente**.
6. Uso de token revogado é registrado como sinal.
7. Escopo desconhecido é rejeitado na criação.
8. Um token **não** pode ter escopo maior que o do ator que o criou, provado por teste.
9. Criar token privilegiado exige step-up.
10. A comparação de token é em tempo constante.
11. `lastUsedAt` é registrado; tokens ociosos são sinalizados.
12. Rate limit por token é aplicado.
13. Criação e revogação geram AuditLog; negativo cross-team passa.

## Required Tests
- **security**: apenas hash no banco; ausência de reexibição; escopo maior que o criador; comparação em tempo constante; uso de token revogado registrado.
- **integration**: expiração; revogação imediata; `lastUsedAt`.
- **policy**: step-up para token privilegiado; negativo cross-team.

## Quality Gates
Local Quality Gate + `bin/security`. **Story crítica: exige plan mode.**

## Definition of Done
Os 13 Acceptance Criteria satisfeitos, token apenas em hash e escopo limitado ao criador provados, Critical/High = 0.
