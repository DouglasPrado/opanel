# M01-01 — User, Session and password authentication

## Objective
Criar a identidade humana da instalação e a autenticação baseline: e-mail + senha forte, com sessões revogáveis server-side.

## Outcome
Um usuário se cadastra, autentica, vê suas sessões e consegue revogar uma delas. A sessão revogada deixa de conceder acesso imediatamente.

## References
- `docs/architecture/04-identity-teams-security.md` §8 (autenticação e sessões)
- `docs/architecture/09-data-model-apis-contracts.md` §3.1 (User), §15.2 (Session)
- `docs/annexes/B-nfr-slos.md` §13 (Passwords, TLS, MFA)
- `docs/annexes/C-threat-model-security-hardening.md` §7.1 (autenticação)
- `docs/decisions/ADR-0002-identifier-strategy.md`

## Preconditions
M00 aceito. **`ADR-0002` precisa estar `Accepted`** — esta é a primeira Story a criar tabela e a convenção de identificador é irreversível na prática.

## Scope
- `User`: id, email (citext UNIQUE), displayName, status (`ACTIVE`, `SUSPENDED`, `DELETED_PENDING`), emailVerifiedAt, timestamps.
- Hash de senha com **Argon2id** e parâmetros versionados, para permitir rehash futuro sem invalidar contas.
- `Session`: userId, sessionId/tokenHash, expiresAt, revokedAt, mfaLevel (campo presente, ainda sempre `password`), lastSeenAt, device metadata.
- Cadastro, login, logout e listagem/revogação de sessões próprias.
- Cookie de sessão `Secure`, `HttpOnly`, `SameSite` apropriado; proteção CSRF já ativa desde `M00-04`.
- Rate limit em login e em recuperação de conta.
- Expiração absoluta **e** por inatividade.

## Out of Scope
- MFA/TOTP e passkeys (`M11-05`).
- Step-up authentication (`M03-04`).
- OIDC/SAML (backlog pós-core).
- Recuperação de senha por e-mail — entra em `M11` junto do fluxo de convites; em M01 a redefinição é operação de INSTANCE_ADMIN.
- Team e ownership (`M01-02`).

## Domain Impact
**Entidades:** `User`, `Session`.
**Validações:** e-mail normalizado e único; senha com política mínima; `status` controla se a autenticação é permitida.
**Transições:** `User.status` `ACTIVE → SUSPENDED → ACTIVE`; `DELETED_PENDING` é terminal para autenticação.
**Regra de reuso de e-mail:** e-mail de conta em retenção não pode ser reutilizado silenciosamente (doc 09 §3.1).

## Application Layer
- **Commands:** `RegisterUser`, `AuthenticateUser`, `RevokeSession`.
- **Queries:** `UserSessions`.
- **Policies:** ainda não há RBAC (`M01-04`); nesta Story a autorização é “o dono da sessão”.

## API Impact
Rotas de sessão servidas por Inertia. Nenhum endpoint REST criado só para a UI. O envelope de erro do doc 09 §28 é usado desde aqui: `code`, `message`, `requestId`.

## UI Impact
Telas de sign in, sign up e lista de sessões, usando componentes do inventário de `M00-05`. Nenhum componente novo sem passar pelo Reuse Gate.

## Security Requirements
- Senha armazenada **somente** com Argon2id; nunca criptografia reversível (Anexo C §7.1).
- Token de sessão persistido apenas como hash; o valor bruto nunca é gravado.
- Falha de login não revela se o e-mail existe.
- Rate limit em login, com alerta para comportamento anômalo.
- Revogação de sessão é server-side e imediata; a sessão não concede acesso permanente.
- Mudança de senha invalida as demais sessões conforme política.
- Nenhum log registra senha, token bruto ou cookie.

## Observability Requirements
- Login bem-sucedido, login falho e revogação de sessão geram log com `request_id`, `actor_id` e resultado — e viram AuditLog em `M01-05`.
- Nenhum desses logs contém credencial.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| E-mail já cadastrado | Oferecer sign in/recovery sem confirmar existência da conta ao anônimo (doc 10 UC-001). |
| Senha fraca | Rejeitar com política explícita, sem vazar a regra completa em erro genérico. |
| Sessão expirada | Rejeitar; UI redireciona ao login preservando o destino. |
| Sessão revogada em outro device | Próxima requisição é rejeitada, não apenas a próxima navegação. |
| Brute force | Rate limit e backoff; o log registra o padrão. |

## Acceptance Criteria
1. Um usuário se cadastra e autentica com e-mail e senha.
2. A senha é armazenada com Argon2id e parâmetros versionados; nenhum teste consegue recuperar a senha do banco.
3. O token de sessão é persistido apenas como hash.
4. Uma sessão revogada é rejeitada na **próxima requisição**, não apenas na próxima navegação.
5. O usuário lista suas sessões com device metadata e `lastSeenAt`, e revoga individualmente.
6. Login com e-mail inexistente e login com senha errada são indistinguíveis na resposta.
7. Rate limit bloqueia tentativas repetidas de login, provado por teste.
8. Sessão expira por tempo absoluto e por inatividade, provado com relógio controlado.
9. Cookie de sessão é `Secure`, `HttpOnly` e com `SameSite` apropriado.
10. Nenhum log contém senha, token bruto ou cookie, provado por teste.
11. Todos os identificadores seguem `ADR-0002`.

## Required Tests
- **unit**: política de senha; geração/validação de token; expiração com relógio controlado.
- **integration**: cadastro, login, revogação com efeito imediato, rate limit.
- **request**: envelope de erro com `requestId`; cookie com atributos corretos.
- **security**: senha irrecuperável do banco; ausência de credencial em log; resposta indistinguível para e-mail inexistente vs senha errada.

## Quality Gates
Local Quality Gate (Ruby/Rails, Database, React/TypeScript) + `bin/security` + `bin/fitness` (AF-06 passa a avaliar código real).

## Definition of Done
Os 11 Acceptance Criteria satisfeitos com PostgreSQL real, testes de segurança verdes, `ADR-0002` aceito e aplicado, Critical/High = 0.
