# M01-02 — Team, TeamMember and the single-active-OWNER constraint

## Objective
Criar o tenant principal do produto e garantir **no banco** — não apenas na aplicação — que todo Team ativo tem exatamente um OWNER ativo.

## Outcome
Team e TeamMember existem com roles; o banco rejeita Team ativo sem OWNER e rejeita dois OWNER ativos simultâneos; o OWNER não consegue se remover nem se rebaixar.

## References
- `docs/architecture/04-identity-teams-security.md` §3.2 (um único OWNER), §5 (roles e membership), §16.1 (constraint de OWNER)
- `docs/architecture/09-data-model-apis-contracts.md` §3.2 (Team e TeamMember), §18 (constraints obrigatórias)
- `docs/annexes/D-test-strategy.md` §5 (constraints e concorrência)

## Preconditions
`M01-01` done.

## Scope
- `Team`: id, name, slug (UNIQUE), ownerUserId, status, timestamps, deletedAt.
- `TeamMember`: teamId, userId, role (`OWNER`, `ADMIN`, `DEVELOPER`, `VIEWER`), status (`INVITED`, `ACTIVE`, `SUSPENDED`, `REMOVED`), invitedBy, joinedAt.
- Constraints no PostgreSQL: `UNIQUE(teamId, userId)`; **partial unique** garantindo um único membership `OWNER` + `ACTIVE` por Team; `Team.ownerUserId` coerente com esse membership.
- Criação de Team pelo usuário autenticado, que vira OWNER daquele Team.
- Regra: OWNER não pode remover a si mesmo nem reduzir o próprio papel diretamente.
- Estado `OWNERSHIP_RECOVERY_REQUIRED` no Team quando o OWNER está suspenso.

## Out of Scope
- Convite de membros (`M11-01`).
- Transferência de ownership (`M11-03`) — a **constraint** que a torna segura nasce aqui.
- Recuperação excepcional por INSTANCE_ADMIN (`M11-04`).
- INSTANCE_ADMIN e bootstrap (`M01-03`).
- Policies e autorização (`M01-04`).

## Domain Impact
**Entidades:** `Team`, `TeamMember`.
**Relacionamentos:** `User 1—N TeamMember N—1 Team`.
**Validações:** slug único entre Teams não deletados; `ownerUserId` precisa ter membership `OWNER` + `ACTIVE`.
**Transições de membership:** `INVITED → ACTIVE → SUSPENDED → ACTIVE`, `→ REMOVED` terminal. Auditoria permanece após `REMOVED`.

## Application Layer
- **Commands:** `CreateTeam`, `SuspendTeamMember`.
- **Queries:** `TeamsForUser`.
- **Policies:** entram em `M01-04`; aqui as regras são invariantes de domínio e de banco.

## Security Requirements
- A invariante de OWNER é **server-enforced e database-enforced**. A UI não é controle.
- Suspender um membership remove o acesso ao Team imediatamente; a sessão global não concede acesso permanente (Anexo C §7.2).
- Não existe caminho para promover alguém a OWNER que não seja a transferência explícita de `M11-03`. `ADMIN` nunca pode criar OWNER.

## Observability Requirements
Criação de Team, mudança de role e suspensão registram log com `team_id`, `actor_id` e resultado; viram AuditLog em `M01-05`.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Duas transações tentam criar o segundo OWNER ativo | A constraint do banco rejeita uma delas; nenhum estado inválido é gravado. |
| OWNER tenta se remover | Rejeitado com erro estável explicando que é preciso transferir ownership primeiro. |
| Slug duplicado | Validação inline com sugestão; nunca colisão silenciosa. |
| Team ficaria sem OWNER | Operação rejeitada pela constraint. |
| OWNER suspenso por segurança | Team entra em `OWNERSHIP_RECOVERY_REQUIRED` até resolução administrativa. |

## Acceptance Criteria
1. Um usuário autenticado cria um Team e recebe membership `OWNER` + `ACTIVE`.
2. O banco impede um segundo membership `OWNER` + `ACTIVE` no mesmo Team, comprovado por **teste concorrente** com duas conexões e barreira.
3. O banco impede que um Team ativo fique sem OWNER.
4. `Team.ownerUserId` é sempre coerente com o membership `OWNER` + `ACTIVE`, comprovado por constraint ou verificação transacional.
5. OWNER não consegue remover a si mesmo nem reduzir o próprio papel.
6. `UNIQUE(teamId, userId)` impede membership duplicado.
7. Slug é único entre Teams não deletados.
8. Suspender um membership remove o acesso ao Team na requisição seguinte.
9. Um membership `REMOVED` preserva o histórico de auditoria.
10. Team com OWNER suspenso fica em `OWNERSHIP_RECOVERY_REQUIRED`.

## Required Tests
- **unit**: invariantes de role e transições de membership.
- **integration (PostgreSQL real)**: cada constraint provada por caso negativo; **teste concorrente** de dois OWNER simultâneos usando o helper de barreira de `M00-07`.
- **policy**: suspensão removendo acesso imediatamente.
- **security**: impossibilidade de promover a OWNER fora do fluxo de transferência.

## Quality Gates
Local Quality Gate (Ruby/Rails + Database), com Migration Gate obrigatório para as partial unique indexes.

## Definition of Done
Os 10 Acceptance Criteria satisfeitos, constraints provadas por casos negativos **no banco**, teste concorrente verde, Critical/High = 0.
