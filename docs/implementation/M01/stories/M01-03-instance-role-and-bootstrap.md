# M01-03 — InstanceRole and first-installation bootstrap

## Objective
Separar a administração da **instalação** da propriedade de um **Team**, e implementar o bootstrap que concede os dois papéis ao primeiro usuário — e apenas a ele.

## Outcome
Uma instalação vazia, ao receber o primeiro cadastro, cria User + Team + membership OWNER + `INSTANCE_ADMIN`. Qualquer Team criado depois concede apenas `TEAM_OWNER` daquele Team.

## References
- `docs/architecture/04-identity-teams-security.md` §3.1 (primeira instalação), §7 (INSTANCE_ADMIN x TEAM_OWNER), §20 (decisões consolidadas)
- `docs/architecture/09-data-model-apis-contracts.md` §3.3 (InstanceRole)
- `docs/architecture/10-ui-use-cases.md` UC-001

## Preconditions
`M01-02` done.

## Scope
- `InstanceRole`: userId, role (`INSTANCE_ADMIN`, `INSTANCE_OPERATOR`, `INSTANCE_AUDITOR`), createdAt, revokedAt.
- Detecção de instalação vazia e fluxo de bootstrap **idempotente e à prova de corrida**: só o primeiro cadastro concede `INSTANCE_ADMIN`.
- Criação de Team posterior concede `TEAM_OWNER` daquele Team e **nada mais**.
- Regra explícita: transferir `TEAM_OWNER` não transfere `INSTANCE_ADMIN`.

## Out of Scope
- Área de administração da instância (`M11-12`).
- Concessão/revogação de InstanceRole pela UI (`M11-12`).
- Recovery Key (M03) — o onboarding completo do doc 10 §5.1 só fecha em M03.
- MFA obrigatória para papéis privilegiados (`M11-05`).

## Domain Impact
**Entidades:** `InstanceRole`.
**Validações:** um usuário pode ter no máximo um registro ativo por role; `revokedAt` encerra o papel.
**Invariante crítica:** a instalação precisa ter **pelo menos um** `INSTANCE_ADMIN` ativo; a revogação do último é bloqueada.

## Application Layer
- **Commands:** `BootstrapInstallation` (executado dentro do fluxo de primeiro cadastro), `GrantInstanceRole`, `RevokeInstanceRole`.
- **Queries:** `InstallationBootstrapState`.

## Security Requirements
- Somente o bootstrap concede `INSTANCE_ADMIN` automaticamente (doc 04 §3.1). Não existe caminho alternativo de auto-promoção.
- O bootstrap é **atômico**: ou cria User + Team + OWNER + INSTANCE_ADMIN, ou nada.
- Duas requisições simultâneas de primeiro cadastro não podem gerar dois `INSTANCE_ADMIN` de bootstrap.
- Revogar o último `INSTANCE_ADMIN` ativo é bloqueado — evita instalação sem administrador.
- O evento de bootstrap é auditado com destaque (`M01-05`).

## Observability Requirements
O bootstrap gera log e AuditLog explícitos: `installation.bootstrapped`, com o usuário, o Team criado e os papéis concedidos.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Dois primeiros cadastros simultâneos | Constraint/lock garante um único bootstrap; o segundo vira cadastro normal sem `INSTANCE_ADMIN`. |
| Bootstrap interrompido no meio | Transação atômica: nada é gravado parcialmente. |
| Tentativa de revogar o último INSTANCE_ADMIN | Rejeitada com erro estável. |
| Criação de Team após o bootstrap | Concede apenas `TEAM_OWNER`; verificado por teste. |

## Acceptance Criteria
1. Uma instalação vazia, ao receber o primeiro cadastro, cria User, Team, membership `OWNER` e `INSTANCE_ADMIN` em uma única transação.
2. Duas requisições simultâneas de primeiro cadastro produzem **um** bootstrap, comprovado por teste concorrente.
3. Um Team criado após o bootstrap concede `TEAM_OWNER` daquele Team e **não** concede `INSTANCE_ADMIN`.
4. Transferir `TEAM_OWNER` não altera `INSTANCE_ADMIN` — regra documentada e coberta por teste (a transferência em si é de `M11-03`).
5. Revogar o último `INSTANCE_ADMIN` ativo é bloqueado.
6. Um usuário sem `INSTANCE_ADMIN` não consegue conceder InstanceRole a ninguém.
7. O bootstrap é auditado com actor, Team e papéis concedidos.
8. Interromper o bootstrap no meio não deixa estado parcial.

## Required Tests
- **unit**: invariantes de InstanceRole.
- **integration**: bootstrap atômico; **teste concorrente** de duplo bootstrap; bloqueio da revogação do último admin; interrupção no meio da transação.
- **policy**: usuário comum não concede InstanceRole.
- **security**: nenhum caminho de auto-promoção a `INSTANCE_ADMIN`.

## Quality Gates
Local Quality Gate (Ruby/Rails + Database).

## Definition of Done
Os 8 Acceptance Criteria satisfeitos, teste concorrente de bootstrap verde, atomicidade provada, Critical/High = 0.
