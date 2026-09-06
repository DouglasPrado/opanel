# M11-12 — Instance administration area

## Objective
Dar ao `INSTANCE_ADMIN` um lugar para administrar a **instalação** — papéis de instância, configurações globais e providers — sem confundir isso com ser dono de todos os Teams.

## Outcome
A área de instância permite conceder e revogar papéis de instância, configurar providers globais e ver o estado da instalação, com auditoria completa.

## References
- `docs/architecture/04-identity-teams-security.md` §7 (INSTANCE_ADMIN × TEAM_OWNER), §17
- `docs/architecture/09-data-model-apis-contracts.md` §3.3 (InstanceRole)
- `docs/architecture/10-ui-use-cases.md` §22 (Providers e Instance Administration), §3.1
- `docs/annexes/F-mcp-platform-agents.md` §7.9 (`instance.status`)

## Preconditions
`M11-04` e `M11-08` done.

## Scope
- Rota `/instance/*` acessível apenas a papéis de instância.
- Concessão e revogação de `INSTANCE_ADMIN`, `INSTANCE_OPERATOR` e `INSTANCE_AUDITOR`.
- Configurações globais: domínio da plataforma, e-mail, política de segurança, feature flags.
- Providers globais: DNS, Load Balancer, Registry, Backup Storage — com metadata, teste e reconexão.
- Visão de todos os clusters e do estado da instalação.
- Regra explícita na UI: `INSTANCE_ADMIN` **não** é dono dos Teams e não acessa recursos de produto por esse papel.

## Out of Scope
- Acesso a dados de produto dos Teams — o papel administra infraestrutura, não conteúdo.
- Billing.
- Upgrade da plataforma (`M14-03`).

## Application Layer
- **Commands:** `GrantInstanceRole`, `RevokeInstanceRole`, `UpdateInstanceSettings`.
- **Queries:** `InstanceStatus`, `GlobalProviders`.
- **Policies:** exclusivamente papéis de instância.

## Security Requirements
- **`INSTANCE_ADMIN` não é `TEAM_OWNER`** (doc 04 §7, regra explícita): o papel administra a instalação, e a UI deixa isso claro. Ele **não** ganha acesso automático a Projects, secrets ou logs dos Teams.
- Conceder papel de instância exige `INSTANCE_ADMIN` + step-up e é auditado com destaque.
- Revogar o **último** `INSTANCE_ADMIN` ativo é bloqueado (`M01-03`).
- Credenciais de provider aparecem apenas como metadata, com ações de rotate/reconnect (doc 10 §22, regra explícita).
- Alterar política de segurança global é auditado e pode afetar todos os Teams — o impacto é mostrado antes.
- Feature flags perigosas (`terminal.enabled`, `mcp.enabled`) são controladas aqui, com aviso.

## Observability Requirements
`InstanceStatus`: versão, clusters, providers, readiness agregada, papéis de instância ativos. Histórico de alterações globais.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Revogar o último `INSTANCE_ADMIN` | Bloqueado. |
| Provider global indisponível | Estado degradado visível; Teams afetados listados. |
| Alteração de política global | Impacto mostrado antes; auditado. |
| Usuário de Team tentando acessar `/instance/*` | Negado, sem vazar informação da instalação. |
| Credencial de provider exibida | Impossível: apenas metadata. |
| Feature flag perigosa habilitada | Aviso explícito e auditoria. |

## Acceptance Criteria
1. A área `/instance/*` é acessível apenas a papéis de instância.
2. A UI declara que `INSTANCE_ADMIN` **não** é dono dos Teams.
3. `INSTANCE_ADMIN` **não** obtém acesso automático a Projects, secrets ou logs dos Teams, provado por teste.
4. Conceder papel de instância exige `INSTANCE_ADMIN` + step-up e é auditado.
5. Revogar o último `INSTANCE_ADMIN` ativo é bloqueado.
6. Providers globais mostram apenas metadata, com rotate/reconnect; **nenhuma credencial é exibida**.
7. Provider indisponível mostra estado degradado e lista os Teams afetados.
8. Alterar política global mostra o impacto **antes** e é auditado.
9. Feature flags perigosas são controladas aqui, com aviso explícito.
10. Usuário de Team acessando `/instance/*` é negado sem vazar informação.
11. `InstanceStatus` mostra versão, clusters, providers, readiness e papéis ativos.
12. Todas as alterações globais geram AuditLog.

## Required Tests
- **policy**: acesso restrito; `INSTANCE_ADMIN` sem acesso a dados de produto; usuário de Team negado.
- **integration**: revogação do último admin bloqueada; provider indisponível; impacto de política global.
- **security**: credencial nunca exibida; step-up para papéis de instância.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, separação entre instância e Team provada, credenciais protegidas, Critical/High = 0.
