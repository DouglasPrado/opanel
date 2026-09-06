---
milestone: "M11"
name: "Governance, Instance Administration & Quotas"
type: "milestone"
status: "pending"
---

# M11 — Governance, Instance Administration & Quotas

## Identity

| Campo | Valor |
|---|---|
| **ID** | M11 |
| **Nome** | Governance, Instance Administration & Quotas |
| **Objetivo** | Transformar a plataforma de um painel operado por uma pessoa em um produto **multiusuário governável**: convites, ciclo de vida de membership, transferência de ownership, MFA, tokens de automação, permissões por Environment, quotas e a área de administração da instalação. |
| **Resultado observável** | Um OWNER convida membros com papéis distintos, transfere a propriedade do Team para um ADMIN de forma atômica e reautenticada, emite um token de automação com escopo, e vê no Audit Log tudo o que aconteceu. Quotas impedem que um erro de configuração consuma o cluster. |

## Why

M01 entregou identidade e autorização — o suficiente para uma instalação de um operador. M11 entrega **governança**: o que acontece quando várias pessoas com papéis diferentes compartilham a mesma instalação.

Ele é também pré-requisito de M12: o MCP precisa de OAuth, scopes, service accounts e resource boundaries, e todos nascem aqui.

Por dependência, M11 só precisa de M01 e M03 — ele pode ser paralelizado bem antes da sua posição no roadmap (ver `DEPENDENCIES.md` §5).

## Scope

- Convites com token expirável, uso único e revogação no reenvio.
- Ciclo de vida de membership: `INVITED → ACTIVE → SUSPENDED → REMOVED`.
- **Transferência de ownership**: atômica, apenas para ADMIN ativo, com step-up e auditoria.
- Recuperação excepcional de ownership por `INSTANCE_ADMIN`.
- MFA TOTP, integrando-se ao step-up de `M03-04`.
- Gestão de sessões com revogação remota.
- API tokens, service accounts e deploy tokens com escopo, hash e expiração.
- Permissões por Environment, com produção como boundary adicional.
- `Plan`, `TeamEntitlement`, `TeamQuota` e `UsageCounter`.
- Enforcement de quotas com os quatro níveis: warning, soft, hard e safety.
- UI de Audit Log com filtros e correlação.
- Área de administração da instalação: instance roles, configurações globais, providers.
- Dashboard de segurança.
- Rate limiting em autenticação, API, webhooks e endpoints caros.

## Out of Scope

| Deixado para | O quê |
|---|---|
| M12 | OAuth do MCP, presets de agente, approvals — que **consomem** o que M11 entrega. |
| M13 | Suíte consolidada de segurança e testes de abuso sob carga. |
| Backlog | SSO enterprise (OIDC/SAML), SCIM, billing completo, políticas organizacionais avançadas. |

## Dependencies

- **Hard:** M01 (identidade e RBAC), M03 (step-up).
- **Soft:** nenhuma. É a maior oportunidade de paralelização do roadmap.

## User-visible Outcome

O OWNER convida a equipe, define quem opera produção, transfere a propriedade quando sai, exige MFA dos administradores, cria um token para o CI, e consegue responder “quem fez isso?” consultando o Audit Log. O INSTANCE_ADMIN administra a instalação sem virar dono de todos os Teams.

## Technical Outcome

- Invariante de OWNER único preservada sob concorrência, agora exercitada pela transferência.
- Credenciais de automação separadas de sessões humanas.
- Quotas como proteção operacional, não apenas billing.
- Audit Log consultável e correlacionável.

## Architecture Impact

| Categoria | Impacto |
|---|---|
| Entities | `TeamInvitation`, `OwnershipTransfer`, `MfaCredential`, `ApiToken`, `ServiceAccount`, `EnvironmentPermission`, `Plan`, `TeamEntitlement`, `TeamQuota`, `UsageCounter`, `RateLimitPolicy`. |
| Commands | `InviteMember`, `AcceptInvitation`, `ChangeMemberRole`, `SuspendMember`, `TransferOwnership`, `RecoverOwnership`, `EnrollMfa`, `CreateApiToken`, `RevokeApiToken`, `SetTeamQuota`. |
| Queries | `AuditSearch`, `TeamUsage`, `SecurityOverview`. |
| Events | `team.owner.transferred.v1`, `member.role.changed`, `token.created`, `quota.exceeded`. |
| UI | Members, Ownership, Security, API tokens, Audit, Instance. |

## Security

Este Milestone é quase inteiramente sobre segurança:

- **Exatamente um OWNER ativo por Team**, garantido no banco e sob concorrência (doc 04 §3.2).
- Transferência **apenas** para ADMIN ativo, atômica, com reautenticação e auditoria (doc 04 §4).
- ADMIN **nunca** pode promover alguém a OWNER (doc 04 §6.2).
- Transferir `TEAM_OWNER` **não** transfere `INSTANCE_ADMIN` (doc 04 §7).
- Convites expiram, são de uso único, e o reenvio revoga o token anterior.
- Membership suspenso perde acesso **imediatamente**.
- MFA obrigatório para `INSTANCE_ADMIN` e `TEAM_OWNER` em ambientes production-ready (Anexo B §13).
- Tokens armazenados apenas como hash; exibidos em plaintext **uma única vez**; com escopo e expiração.
- Produção como boundary adicional: um DEVELOPER com deploy em homologação **não** herda acesso a secrets de produção (doc 04 §11.1).
- Quotas como proteção operacional contra abuso acidental (doc 04 §13).
- Rate limit em login, recuperação, webhooks e endpoints caros (Anexo C §19).
- Audit Log nunca contém plaintext sensível.
- Ameaças cobertas: T04 (RBAC bypass/IDOR), conta de OWNER comprometida, token vazado, dois transfers concorrentes.

## Observability

- Todo evento obrigatório do doc 04 §10.1 auditado.
- Audit Log com filtros por ator, ação, recurso, período e resultado, e correlação por `requestId`/`operationId`.
- `UsageCounter` por Team, com proximidade do limite visível **antes** de o limite ser atingido.
- Dashboard de segurança com adoção de MFA, tokens ativos e eventos sensíveis recentes.

## Testing

| Classe | Exigência |
|---|---|
| Unit | Invariantes de ownership; escopo de token; cálculo de quota; níveis de enforcement. |
| Integration | **Duas transferências concorrentes**; convite expirado/reutilizado; sessão revogada; quota sob concorrência. |
| Policy | Matriz completa de roles × escopos; produção como boundary; negativos cross-team. |
| Contract | Envelope de erro para `QUOTA_EXCEEDED` e `FORBIDDEN`. |
| E2E | Convidar → aceitar → alterar papel → transferir ownership → revogar token. |
| Security | ADMIN não promove a OWNER; token só em hash; MFA obrigatório; rate limit; audit sem plaintext. |

## Acceptance Criteria

1. Convites expiram, são de uso único, e o reenvio revoga o token anterior.
2. Membership suspenso perde acesso na requisição seguinte.
3. OWNER transfere a propriedade **apenas** para um ADMIN ativo.
4. A transferência é atômica: o novo vira OWNER e o antigo vira ADMIN na mesma transação.
5. **Duas transferências concorrentes** não produzem estado inválido.
6. ADMIN **não** consegue tornar a si mesmo nem outro membro OWNER.
7. OWNER não consegue sair nem se remover sem transferir.
8. Transferir `TEAM_OWNER` **não** altera `INSTANCE_ADMIN`.
9. Recuperação excepcional de ownership existe, é restrita a `INSTANCE_ADMIN` e é marcada como `OWNERSHIP_RECOVERY`.
10. MFA pode ser exigida para papéis privilegiados e integra-se ao step-up.
11. Tokens são armazenados apenas como hash e exibidos em plaintext uma única vez.
12. Token expirado ou revogado é rejeitado mesmo existindo fisicamente.
13. Um usuário sem `vault.reveal` **não** obtém plaintext pela API, em nenhuma rota.
14. Produção aplica restrições adicionais mesmo a DEVELOPER e ADMIN conforme policy.
15. Quotas bloqueiam nos níveis definidos e a proximidade do limite é visível antes.
16. Audit Log registra os eventos obrigatórios com metadata redigida.
17. Rate limit protege login, recuperação de conta, webhooks e endpoints caros.

## Exit Gate

- [ ] Stories `required` `done`; 17 Acceptance Criteria com evidência.
- [ ] **Teste concorrente de transferência de ownership** verde.
- [ ] Teste de ADMIN tentando promover a OWNER verde (negativo).
- [ ] Teste de token só em hash e exibido uma vez verde.
- [ ] Teste de produção como boundary adicional verde.
- [ ] Teste de quota sob concorrência verde.
- [ ] Matriz completa de RBAC verde, incluindo negativos cross-team.
- [ ] `bin/fitness`, `bin/security` verdes; Critical = 0, High = 0.
- [ ] `MILESTONE_REPORT.md` com `Status: READY_FOR_REVIEW`.
