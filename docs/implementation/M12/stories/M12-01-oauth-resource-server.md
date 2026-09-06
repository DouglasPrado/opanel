# M12-01 — OAuth resource server for MCP

## Objective
Proteger o endpoint MCP com OAuth seguindo a autorização vigente do protocolo, com PKCE, resource indicators e validação estrita de audience.

## Outcome
Um host MCP descobre os metadados de autorização, obtém consentimento do usuário e recebe um access token **vinculado ao recurso MCP**.

## References
- `docs/annexes/F-mcp-platform-agents.md` §5.1 (OAuth para MCP remoto), §4.2 (fluxo de conexão)
- `docs/annexes/C-threat-model-security-hardening.md` §13 (OAuth/callback), §7.1
- `docs/architecture/04-identity-teams-security.md` §9 (identidades de automação)

## Preconditions
M11 aceito (`M11-07` entregou tokens e escopos).

## Scope
- Protected Resource Metadata para discovery.
- Authorization Code com **PKCE S256** obrigatório.
- **Resource indicators** e audience binding: o token vale para o recurso MCP, não genericamente.
- Validação estrita de issuer e audience na verificação.
- `OAuthGrant`: subject, clientId, resource, scopes, issuedAt, expiresAt, revokedAt, metadados de refresh.
- Escopos do Anexo F §5.4 registrados e validados.
- Consentimento explícito com Team, boundary e scopes escolhidos.
- Revogação com efeito rápido.

## Out of Scope
- Registro de clientes (`M12-02`).
- Gateway (`M12-03`).
- SSO empresarial (backlog).

## Security Requirements
- **PKCE S256 obrigatório** (Anexo F §5.1).
- **Access token nunca aceito por query string** e **não repassado a APIs downstream** (Anexo F §5.1, regra explícita).
- Audience binding estrito: um token emitido para outro recurso é rejeitado.
- Escopo é **teto**, não concessão: `scopes ∩ RBAC` é a permissão efetiva (`M12-05`).
- Redirect com allowlist rígida, `state`/nonce e proteção contra open redirect.
- Grant revogado **não** pode ser reutilizado, nem com refresh token antigo (Anexo F §13.1).
- Expiração obrigatória; refresh com rotação quando suportado.
- Consentimento registra exatamente o que foi concedido.
- Tokens armazenados apenas como hash, como em `M11-07`.

## Observability Requirements
Grants ativos por usuário e cliente; `mcp_protocol_version_total` e denials por `insufficient_scope`.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Token sem PKCE | Fluxo rejeitado. |
| Token de outra audience | Rejeitado. |
| Token em query string | Rejeitado. |
| Grant revogado com refresh antigo | Rejeitado. |
| Scope insuficiente | `INSUFFICIENT_SCOPE` estruturado, orientando novo consentimento. |
| Redirect fora da allowlist | Rejeitado. |
| Token expirado | Rejeitado; refresh quando disponível. |

## Acceptance Criteria
1. Protected Resource Metadata está disponível para discovery.
2. **PKCE S256 é obrigatório**; fluxo sem ele é rejeitado.
3. O token é vinculado ao recurso MCP; token de outra audience é rejeitado, provado por teste.
4. **Token em query string é rejeitado**.
5. O token **não** é repassado a APIs downstream, verificado por teste.
6. Grant revogado não pode ser reutilizado, nem com refresh antigo.
7. Escopo insuficiente retorna `INSUFFICIENT_SCOPE` estruturado.
8. Redirect usa allowlist rígida, `state`/nonce e é protegido contra open redirect.
9. Os escopos do Anexo F §5.4 estão registrados e são validados.
10. O consentimento registra Team, boundary e scopes concedidos.
11. Tokens são armazenados apenas como hash.
12. Expiração é obrigatória; após a revogação, **nenhuma chamada subsequente é aceita** — a verificação consulta o estado da concessão, sem cache de decisão.

## Required Tests
- **security**: PKCE ausente; audience errada; token em query string; redirect fora da allowlist; refresh após revogação.
- **contract**: discovery de metadata; `insufficient_scope`.
- **integration**: expiração; revogação com efeito rápido.

## Quality Gates
Local Quality Gate + `bin/security`. **Story crítica: exige plan mode.**

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, PKCE e audience binding provados, revogação efetiva, Critical/High = 0.
